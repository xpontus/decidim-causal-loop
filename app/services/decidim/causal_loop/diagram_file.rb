# frozen_string_literal: true

module Decidim
  module CausalLoop
    # The diagram as a file: everything needed to recreate it exactly
    # (titles, descriptions, positions, sizes, fonts, polarities, labels and
    # bends), with the nodes' IDs only as keys that the links refer to.
    #
    # Loading also accepts the older "Export JSON" files, which had only
    # titles, positions (x, y) and polarities.
    #
    # A title names one variable, so a variable in the file whose title
    # matches an existing one (as Node.title_key compares them) becomes that
    # variable, which keeps its position and look; the file's links attach to
    # it. A link between two variables that are already linked that way is
    # skipped, and reported if its polarity differs.
    class DiagramFile
      FORMAT = "decidim-causal-loop"
      VERSION = 1
      MAX_NODES = 500
      MAX_LINKS = 2000
      # In "add" mode the file is placed this far to the right of the diagram.
      ADD_GAP = 250

      class Error < StandardError; end

      def self.dump(nodes, links)
        {
          format: FORMAT,
          version: VERSION,
          exported_at: Time.current.iso8601,
          nodes: nodes.map do |n|
            { id: n.id, title: n.title, description: n.description, position_x: n.position_x,
              position_y: n.position_y, width: n.width, height: n.height, font_size: n.font_size }
          end,
          links: links.map do |l|
            { source: l.source_node_id, target: l.target_node_id, polarity: l.polarity, label: l.label,
              cp1_distance: l.cp1_distance.to_f, cp2_distance: l.cp2_distance.to_f }
          end
        }
      end

      def initialize(data)
        raise Error, "The file is not a diagram" unless data.is_a?(Hash) && data["nodes"].is_a?(Array)
        raise Error, "This file was written by a newer version" if data["format"] == FORMAT && data["version"].to_i > VERSION
        raise Error, "The file has more than #{MAX_NODES} variables" if data["nodes"].size > MAX_NODES
        raise Error, "The file has more than #{MAX_LINKS} links" if Array(data["links"]).size > MAX_LINKS

        @nodes = data["nodes"].each_with_index.map { |attrs, index| read_node(attrs, index) }
        @links = Array(data["links"]).map { |attrs| read_link(attrs) }
      end

      # Creates the file's nodes and links in the component, all or nothing.
      # With replace, the current diagram is deleted first (softly, so it can
      # be restored). Links that refer to a missing variable are skipped and
      # reported. Returns the records created, merged and deleted.
      def import!(component_id, replace:)
        ApplicationRecord.transaction do
          deleted_nodes = replace ? Node.where(decidim_component_id: component_id).to_a : []
          deleted_links = deleted_nodes.flat_map(&:soft_delete!)
          existing = Node.where(decidim_component_id: component_id).index_by { |n| Node.title_key(n.title) }
          nodes = create_nodes(component_id, existing)
          links, skipped, conflicts = create_links(component_id, nodes)
          created = nodes.values.uniq.reject { |n| existing.has_value?(n) }
          { nodes: created, links:, merged: nodes.values.uniq - created, skipped:, conflicts:, deleted_nodes:, deleted_links: }
        end
      rescue ActiveRecord::RecordInvalid => e
        raise Error, "The file has an invalid variable or link: #{e.record.errors.full_messages.to_sentence}"
      end

      private

      # Nodes without a position (hand-written files) are laid out in rows.
      def read_node(attrs, index)
        raise Error, "Variable #{index + 1} in the file is not valid" unless attrs.is_a?(Hash)

        { key: (attrs["id"] || attrs["key"]).to_s,
          title: attrs["title"].to_s.strip.truncate(255), description: attrs["description"],
          position_x: number(attrs["position_x"] || attrs["x"]) || (150 + ((index % 6) * 180)),
          position_y: number(attrs["position_y"] || attrs["y"]) || (150 + ((index / 6) * 80)),
          width: integer(attrs["width"], 130), height: integer(attrs["height"], 44),
          font_size: integer(attrs["font_size"], 13) }
      end

      def integer(value, default) = number(value)&.round || default

      def read_link(attrs)
        attrs = {} unless attrs.is_a?(Hash)
        { source: attrs["source"].to_s, target: attrs["target"].to_s, polarity: attrs["polarity"].presence || "positive",
          label: attrs["label"], cp1_distance: number(attrs["cp1_distance"]) || 0, cp2_distance: number(attrs["cp2_distance"]) || 0 }
      end

      # The diagram's node for each key in the file: an existing node with the
      # same title, or a new one.
      def create_nodes(component_id, existing)
        new_nodes = @nodes.reject { |attrs| existing.has_key?(Node.title_key(attrs[:title])) }
        offset_x, offset_y = offset_beside(existing.values, new_nodes)
        @nodes.to_h do |attrs|
          node = existing[Node.title_key(attrs[:title])] ||
                 Node.create!(attrs.except(:key).merge(position_x: attrs[:position_x] + offset_x,
                                                       position_y: attrs[:position_y] + offset_y,
                                                       decidim_component_id: component_id))
          [attrs[:key], node]
        end
      end

      def create_links(component_id, nodes)
        skipped = []
        conflicts = []
        linked = Link.where(decidim_component_id: component_id).index_by { |l| [l.source_node_id, l.target_node_id] }
        links = @links.filter_map do |attrs|
          source, target = nodes.values_at(attrs[:source], attrs[:target])
          next skipped << "A link refers to a variable that is not in the file" unless source && target

          if (link = linked[[source.id, target.id]])
            conflicts << conflict(source, target, link, attrs) if link.polarity != attrs[:polarity]
            next
          end

          linked[[source.id, target.id]] =
            Link.create!(attrs.except(:source, :target).merge(source_node_id: source.id, target_node_id: target.id,
                                                              decidim_component_id: component_id))
        end
        [links, skipped, conflicts]
      end

      def conflict(source, target, link, attrs)
        sign = ->(polarity) { polarity == "negative" ? "−" : "+" }
        "#{source.title} → #{target.title}: kept #{sign[link.polarity]}, the file has #{sign[attrs[:polarity]]}"
      end

      def number(value)
        Float(value) if value.is_a?(Numeric) || value.is_a?(String)
      rescue ArgumentError
        nil
      end

      # Moves the file's new variables so they start to the right of the
      # current diagram, level with its top.
      def offset_beside(existing, new_nodes)
        return [0, 0] if existing.empty? || new_nodes.empty?

        [existing.map(&:position_x).max + ADD_GAP - new_nodes.pluck(:position_x).min,
         existing.map(&:position_y).min - new_nodes.pluck(:position_y).min]
      end
    end
  end
end

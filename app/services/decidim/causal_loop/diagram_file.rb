# frozen_string_literal: true

module Decidim
  module CausalLoop
    # The diagram as a file: everything needed to recreate it exactly
    # (titles, descriptions, positions, sizes, fonts, polarities, labels and
    # bends), with the nodes' IDs only as keys that the links refer to.
    #
    # Loading also accepts the older "Export JSON" files, which had only
    # titles, positions (x, y) and polarities.
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
      # reported. Returns the records created and deleted.
      def import!(component_id, replace:)
        ApplicationRecord.transaction do
          existing = Node.where(decidim_component_id: component_id).to_a
          deleted_links = replace ? existing.flat_map(&:soft_delete!) : []
          nodes = create_nodes(component_id, replace ? [0, 0] : offset_beside(existing))
          links, skipped = create_links(component_id, nodes)
          { nodes: nodes.values, links:, skipped:, deleted_nodes: replace ? existing : [], deleted_links: }
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

      # The created nodes by their key in the file.
      def create_nodes(component_id, (offset_x, offset_y))
        @nodes.to_h do |attrs|
          node = Node.create!(attrs.except(:key).merge(position_x: attrs[:position_x] + offset_x,
                                                       position_y: attrs[:position_y] + offset_y,
                                                       decidim_component_id: component_id))
          [attrs[:key], node]
        end
      end

      def create_links(component_id, nodes)
        skipped = []
        links = @links.filter_map do |attrs|
          source, target = nodes.values_at(attrs[:source], attrs[:target])
          next skipped << "A link refers to a variable that is not in the file" unless source && target

          Link.create!(attrs.except(:source, :target).merge(source_node_id: source.id, target_node_id: target.id,
                                                            decidim_component_id: component_id))
        end
        [links, skipped]
      end

      def number(value)
        Float(value) if value.is_a?(Numeric) || value.is_a?(String)
      rescue ArgumentError
        nil
      end

      # Moves the file's diagram so it starts to the right of the current
      # one, level with its top.
      def offset_beside(existing)
        return [0, 0] if existing.empty? || @nodes.empty?

        [existing.map(&:position_x).max + ADD_GAP - @nodes.pluck(:position_x).min,
         existing.map(&:position_y).min - @nodes.pluck(:position_y).min]
      end
    end
  end
end

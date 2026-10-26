# frozen_string_literal: true

module Decidim
  module CausalLoop
    # The system archetypes shipped with the module (config/archetypes.yml),
    # for the editor's archetypes panel and the AI assistant. They are read
    # once and never changed through a diagram.
    module Archetypes
      PATH = File.expand_path("../../../../config/archetypes.yml", __dir__)

      module_function

      def all = data[:archetypes]

      def leverage_points = data[:leverage_points]

      def find(key) = all.find { |a| a[:key] == key.to_s }

      # Archetypes with their links as objects, as the editor and the AI read
      # them.
      def catalogue
        { archetypes: all, leverage_points: }
      end

      def data
        @data ||= load_file
      end

      def load_file
        raw = YAML.safe_load_file(PATH)
        {
          archetypes: raw.fetch("archetypes").map { |a| archetype(a) }.freeze,
          leverage_points: raw.fetch("leverage_points").map(&:symbolize_keys).freeze
        }.freeze
      end

      def archetype(raw)
        links = raw.fetch("links").map do |from, to, polarity, delay|
          raise ArgumentError, "#{raw["code"]}: unknown variable in link #{from} -> #{to}" unless (raw["nodes"] & [from, to]).size == 2
          raise ArgumentError, "#{raw["code"]}: bad polarity #{polarity}" unless %w(positive negative).include?(polarity)

          { from:, to:, polarity:, delay: delay == "delay" }
        end
        raw.except("links").symbolize_keys.merge(links:, loops: loops(raw["nodes"], links))
      end

      # The archetype's own feedback loops, found the same way as a diagram's.
      def loops(titles, links)
        nodes = titles.each_with_index.map { |title, i| Node.new(id: i + 1, title:) }
        ids = titles.each_with_index.to_h { |title, i| [title, i + 1] }
        records = links.each_with_index.map do |l, i|
          Link.new(id: i + 1, source_node_id: ids[l[:from]], target_node_id: ids[l[:to]], polarity: l[:polarity])
        end
        LoopFinder.report(nodes, records)[:loops].map { |l| { name: l[:name], type: l[:type], nodes: l[:nodes] } }
      end
    end
  end
end

# frozen_string_literal: true

module Decidim
  module CausalLoop
    # Finds the feedback loops of a diagram: every elementary cycle, following
    # the links' direction and visiting each node at most once.
    #
    # A loop is reinforcing (R) when it has an even number of negative links
    # and balancing (B) when the number is odd. Links are followed one by one,
    # so two parallel links between the same nodes give two loops.
    #
    # Cycles are found by depth-first search from each node in turn, only
    # through nodes later in the order, so each cycle is found once, from its
    # first node. The number of cycles can grow exponentially with dense
    # diagrams, so the search stops at MAX_LOOPS and reports that it did.
    class LoopFinder
      MAX_LOOPS = 200

      Result = Struct.new(:loops, :truncated, keyword_init: true)

      # The loops with names (R1, R2, B1, ...) and node titles, as used by the
      # AI assistant's find_loops tool and the editor's loops panel.
      def self.report(nodes, links)
        result = new(nodes, links).call
        titles = nodes.to_h { |n| [n.id, n.title] }
        counters = Hash.new(0)
        loops = result.loops.map do |l|
          { name: "#{l[:type]}#{counters[l[:type]] += 1}", type: l[:type],
            nodes: l[:node_ids].map { |id| titles[id] }, node_ids: l[:node_ids],
            link_ids: l[:link_ids], negative_links: l[:negative_links] }
        end
        { loops:, reinforcing: counters["R"], balancing: counters["B"], truncated: result.truncated }
      end

      def initialize(nodes, links)
        @nodes = nodes.sort_by(&:id)
        @order = @nodes.each_with_index.to_h { |node, index| [node.id, index] }
        @outgoing = links.select { |l| @order.has_key?(l.source_node_id) && @order.has_key?(l.target_node_id) }
                         .group_by(&:source_node_id)
      end

      def call
        @loops = []
        @truncated = false
        @nodes.each do |start|
          search(start.id, start.id, [start.id], [])
          break if @truncated
        end
        Result.new(loops: @loops.sort_by { |l| [l[:node_ids].size, l[:node_ids]] }, truncated: @truncated)
      end

      private

      def search(start_id, current_id, path, link_path)
        Array(@outgoing[current_id]).each do |link|
          break if @truncated

          target_id = link.target_node_id
          next if @order[target_id] < @order[start_id]

          if target_id == start_id
            record(path, link_path + [link])
          elsif path.exclude?(target_id)
            search(start_id, target_id, path + [target_id], link_path + [link])
          end
        end
      end

      def record(node_ids, links)
        if @loops.size >= MAX_LOOPS
          @truncated = true
          return
        end

        negative = links.count { |l| l.polarity == "negative" }
        @loops << { type: negative.even? ? "R" : "B", node_ids:, link_ids: links.map(&:id), negative_links: negative }
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe LoopFinder do
    let(:node_class) { Struct.new(:id, :title) }
    let(:link_class) { Struct.new(:id, :source_node_id, :target_node_id, :polarity) }
    let(:nodes) { titles.each_with_index.map { |title, i| node_class.new(i + 1, title) } }
    let(:titles) { ["Tourists", "Island Income", "Infrastructure", "Crowding", "Attractiveness"] }

    def links(*specs)
      specs.each_with_index.map do |(from, to, polarity), i|
        link_class.new(100 + i, titles.index(from) + 1, titles.index(to) + 1, polarity)
      end
    end

    def report(link_list) = described_class.report(nodes, link_list)

    it "finds the reinforcing and the balancing loop of the island tourism model" do
      result = report(links(
                        ["Tourists", "Island Income", "positive"],
                        ["Island Income", "Infrastructure", "positive"],
                        %w(Infrastructure Tourists positive),
                        %w(Tourists Crowding positive),
                        %w(Crowding Attractiveness negative),
                        %w(Attractiveness Tourists positive)
                      ))

      expect(result[:loops].map { |l| [l[:name], l[:nodes]] }).to contain_exactly(
        ["R1", ["Tourists", "Island Income", "Infrastructure"]],
        ["B1", %w(Tourists Crowding Attractiveness)]
      )
      expect(result).to include(reinforcing: 1, balancing: 1, truncated: false)
    end

    it "counts negative links: an even number reinforces, an odd number balances" do
      result = report(links(%w(Tourists Crowding negative), %w(Crowding Tourists negative)))

      expect(result[:loops].sole).to include(type: "R", negative_links: 2)
    end

    it "finds a link from a node to itself" do
      expect(report(links(%w(Tourists Tourists negative)))[:loops].sole).to include(type: "B", nodes: ["Tourists"])
    end

    it "treats parallel links as separate loops" do
      result = report(links(%w(Tourists Crowding positive), %w(Tourists Crowding negative), %w(Crowding Tourists positive)))

      expect(result[:loops].map { |l| l[:type] }).to contain_exactly("R", "B")
    end

    it "finds nothing in a diagram without cycles" do
      expect(report(links(%w(Tourists Crowding positive), %w(Crowding Attractiveness negative)))[:loops]).to be_empty
    end

    it "stops at the limit and says so" do
      stub_const("#{described_class}::MAX_LOOPS", 2)
      every_pair = titles.permutation(2).map { |a, b| [a, b, "positive"] }

      result = report(links(*every_pair))
      expect(result[:loops].size).to eq(2)
      expect(result[:truncated]).to be(true)
    end
  end
end

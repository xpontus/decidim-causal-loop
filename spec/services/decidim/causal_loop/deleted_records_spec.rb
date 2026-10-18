# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe DeletedRecords do
    let(:component) { create(:causal_loop_component) }
    let!(:fishing) { Node.create!(title: "Fishing", decidim_component_id: component.id) }
    let!(:mining) { Node.create!(title: "Mining", decidim_component_id: component.id) }
    let!(:tourism) { Node.create!(title: "Tourism", decidim_component_id: component.id) }
    let!(:fishing_mining) do
      Link.create!(source_node_id: fishing.id, target_node_id: mining.id, polarity: "positive", decidim_component_id: component.id)
    end
    let!(:mining_tourism) do
      Link.create!(source_node_id: mining.id, target_node_id: tourism.id, polarity: "positive", decidim_component_id: component.id)
    end

    describe ".purge!" do
      it "removes only records deleted before the cutoff, with the links of purged nodes" do
        mining_tourism.soft_delete!(2.days.ago)
        fishing.soft_delete!(40.days.ago)
        tourism.soft_delete!(1.day.ago)

        expect(described_class.purge!).to eq(links: 1, nodes: 1)
        expect(Node.with_deleted.pluck(:title)).to contain_exactly("Mining", "Tourism")
        expect(Link.with_deleted.pluck(:id)).to eq([mining_tourism.id])
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe "Seeds" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, organization:) }
    let!(:participant) { create(:user, :confirmed, organization:, email: "user@example.org") }

    before { create(:user, :admin, :confirmed, organization:, email: "admin@example.org") }

    it "seeds a published example diagram with one reinforcing and one balancing loop" do
      Decidim.find_component_manifest(:causal_loop).seed!(participatory_space)

      component = participatory_space.components.find_by!(manifest_name: "causal_loop")
      nodes = Node.where(decidim_component_id: component.id).to_a
      links = Link.where(decidim_component_id: component.id).to_a

      expect(component).to be_published
      expect(nodes.map(&:title)).to include("Participation", "Trust in the process")
      expect(LoopFinder.report(nodes, links)).to include(reinforcing: 1, balancing: 1)
      expect(Editor.where(decidim_component_id: component.id).pluck(:decidim_user_id)).to eq([participant.id])
    end
  end
end

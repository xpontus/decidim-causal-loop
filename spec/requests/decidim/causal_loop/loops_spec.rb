# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe "Loops" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
    let(:component) { create(:causal_loop_component, :published, participatory_space:) }

    before { host! organization.host }

    it "lists the diagram's loops for anyone who can see it" do
      tourists = Node.create!(title: "Tourists", decidim_component_id: component.id)
      crowding = Node.create!(title: "Crowding", decidim_component_id: component.id)
      Link.create!(source_node_id: tourists.id, target_node_id: crowding.id, polarity: "positive", decidim_component_id: component.id)
      Link.create!(source_node_id: crowding.id, target_node_id: tourists.id, polarity: "negative", decidim_component_id: component.id)

      get Decidim::EngineRouter.main_proxy(component).loops_path

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["loops"].sole).to include("name" => "B1", "nodes" => %w(Tourists Crowding))
    end
  end
end

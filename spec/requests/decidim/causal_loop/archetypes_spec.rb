# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe "Archetypes" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
    let(:component) { create(:causal_loop_component, :published, participatory_space:) }

    before { host! organization.host }

    it "lists the archetypes for anyone who can see the diagram" do
      get Decidim::EngineRouter.main_proxy(component).archetypes_path

      expect(response).to have_http_status(:ok)
      fixes = response.parsed_body["archetypes"].find { |a| a["code"] == "FL3" }
      expect(fixes).to include("name" => "Fixes that fail", "nodes" => ["Problem symptom", "Fix", "Unintended consequence"])
      expect(fixes["links"]).to include({ "from" => "Fix", "to" => "Unintended consequence", "polarity" => "positive", "delay" => true })
      expect(response.parsed_body["leverage_points"].size).to eq(10)
    end
  end
end

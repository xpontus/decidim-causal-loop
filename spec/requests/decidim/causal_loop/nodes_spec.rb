# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe "Nodes" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
    let(:component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:other_component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:user) { create(:user, :confirmed, organization:) }
    let(:nodes_path) { Decidim::EngineRouter.main_proxy(component).nodes_path }
    let!(:fishing) { Node.create!(title: "Fishing", decidim_component_id: component.id) }
    let!(:mining) { Node.create!(title: "Mining", decidim_component_id: component.id) }
    let!(:elsewhere) { Node.create!(title: "Elsewhere", decidim_component_id: other_component.id) }
    let!(:fishing_mining) do
      Link.create!(source_node_id: fishing.id, target_node_id: mining.id, polarity: "positive", decidim_component_id: component.id)
    end

    before { host! organization.host }

    def json_request(method, path, params = {})
      send(method, path, params: params.to_json, headers: { "CONTENT_TYPE" => "application/json" })
    end

    context "when the user is an editor" do
      before do
        Editor.create!(decidim_component_id: component.id, decidim_user_id: user.id)
        login_as user, scope: :user
      end

      it "deletes a node and its links, and says which" do
        json_request(:delete, "#{nodes_path}/#{fishing.id}")

        expect(response.parsed_body).to eq("deleted" => { "nodes" => [fishing.id], "links" => [fishing_mining.id] })
        expect(Node.pluck(:title)).to contain_exactly("Mining", "Elsewhere")
        expect(Link.count).to eq(0)
        expect(Node.with_deleted.find(fishing.id)).to be_deleted
      end

      it "cannot update a deleted node" do
        fishing.soft_delete!
        json_request(:patch, "#{nodes_path}/#{fishing.id}", node: { title: "Fish" })

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when the user cannot edit" do
      before { login_as user, scope: :user }

      it "is forbidden" do
        json_request(:delete, "#{nodes_path}/#{fishing.id}")

        expect(response).to have_http_status(:forbidden)
        expect(Node.count).to eq(3)
      end
    end
  end
end

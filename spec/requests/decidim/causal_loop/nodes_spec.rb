# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe "Nodes" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
    let(:component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:other_component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:user) { create(:user, :confirmed, organization:) }
    let(:destroy_many_path) { "#{Decidim::EngineRouter.main_proxy(component).nodes_path}/destroy_many" }
    let!(:fishing) { Node.create!(title: "Fishing", decidim_component_id: component.id) }
    let!(:mining) { Node.create!(title: "Mining", decidim_component_id: component.id) }
    let!(:elsewhere) { Node.create!(title: "Elsewhere", decidim_component_id: other_component.id) }

    before do
      host! organization.host
      Link.create!(source_node_id: fishing.id, target_node_id: mining.id, polarity: "positive", decidim_component_id: component.id)
    end

    def destroy_many(ids)
      delete destroy_many_path, params: { node_ids: ids }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    context "when the user is an editor" do
      before do
        Editor.create!(decidim_component_id: component.id, decidim_user_id: user.id)
        login_as user, scope: :user
      end

      it "deletes the given nodes and their links, but only in this component" do
        destroy_many([fishing.id, elsewhere.id])

        expect(response).to have_http_status(:ok)
        expect(Node.pluck(:title)).to contain_exactly("Mining", "Elsewhere")
        expect(Link.count).to eq(0)
      end
    end

    context "when the user cannot edit" do
      before { login_as user, scope: :user }

      it "is forbidden" do
        destroy_many([fishing.id])

        expect(response).to have_http_status(:forbidden)
        expect(Node.count).to eq(3)
      end
    end
  end
end

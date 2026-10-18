# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe "Restoring deleted nodes and links" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
    let(:component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:other_component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:user) { create(:user, :confirmed, organization:) }
    let(:restore_path) { Decidim::EngineRouter.main_proxy(component).restore_path }
    let!(:fishing) { Node.create!(title: "Fishing", decidim_component_id: component.id) }
    let!(:mining) { Node.create!(title: "Mining", decidim_component_id: component.id) }
    let!(:fishing_mining) do
      Link.create!(source_node_id: fishing.id, target_node_id: mining.id, polarity: "positive", decidim_component_id: component.id)
    end
    let!(:mining_fishing) do
      Link.create!(source_node_id: mining.id, target_node_id: fishing.id, polarity: "negative", decidim_component_id: component.id)
    end

    before { host! organization.host }

    def restore(node_ids: [], link_ids: [])
      post restore_path, params: { node_ids:, link_ids: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    context "when the user is an editor" do
      before do
        Editor.create!(decidim_component_id: component.id, decidim_user_id: user.id)
        login_as user, scope: :user
      end

      it "brings a node and its links back with the same IDs" do
        links = fishing.soft_delete!
        restore(node_ids: [fishing.id], link_ids: links.map(&:id))

        expect(response.parsed_body["restored"])
          .to eq("nodes" => [fishing.id], "links" => [fishing_mining.id, mining_fishing.id])
        expect(Node.pluck(:id)).to contain_exactly(fishing.id, mining.id)
        expect(Link.pluck(:id)).to contain_exactly(fishing_mining.id, mining_fishing.id)
      end

      it "leaves a link deleted earlier, on its own, deleted" do
        mining_fishing.soft_delete!
        links = fishing.soft_delete!
        restore(node_ids: [fishing.id], link_ids: links.map(&:id))

        expect(Link.pluck(:id)).to eq([fishing_mining.id])
      end

      it "refuses to restore a link whose node is still deleted, and restores nothing" do
        fishing.soft_delete!
        restore(link_ids: [fishing_mining.id])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Link.count).to eq(0)
      end

      it "ignores records of other components" do
        elsewhere = Node.create!(title: "Elsewhere", decidim_component_id: other_component.id)
        elsewhere.soft_delete!
        restore(node_ids: [elsewhere.id])

        expect(response.parsed_body["restored"]["nodes"]).to eq([])
        expect(Node.find_by(id: elsewhere.id)).to be_nil
      end
    end

    context "when the user cannot edit" do
      before { login_as user, scope: :user }

      it "is forbidden" do
        fishing.soft_delete!
        restore(node_ids: [fishing.id])

        expect(response).to have_http_status(:forbidden)
        expect(Node.find_by(id: fishing.id)).to be_nil
      end
    end
  end
end

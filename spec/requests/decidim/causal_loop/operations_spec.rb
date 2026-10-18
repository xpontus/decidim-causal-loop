# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe "Batch operations" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
    let(:component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:other_component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:user) { create(:user, :confirmed, organization:) }
    let(:operations_path) { Decidim::EngineRouter.main_proxy(component).operations_path }
    let!(:fishing) { Node.create!(title: "Fishing", position_x: 0, position_y: 0, decidim_component_id: component.id) }
    let!(:mining) { Node.create!(title: "Mining", decidim_component_id: component.id) }
    let!(:fishing_mining) do
      Link.create!(source_node_id: fishing.id, target_node_id: mining.id, polarity: "positive", decidim_component_id: component.id)
    end

    before { host! organization.host }

    def apply(*operations)
      post operations_path, params: { operations: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    context "when the user is an editor" do
      before do
        Editor.create!(decidim_component_id: component.id, decidim_user_id: user.id)
        login_as user, scope: :user
      end

      it "applies updates, deletes and restores in order" do
        apply({ op: "update", type: "node", id: fishing.id, attrs: { title: "Fish", position_x: 50, deleted_at: nil } },
              { op: "update", type: "link", id: fishing_mining.id, attrs: { polarity: "negative", cp1_distance: 12 } },
              { op: "delete", type: "link", id: fishing_mining.id },
              { op: "delete", type: "node", id: mining.id },
              { op: "restore", type: "node", id: mining.id },
              { op: "restore", type: "link", id: fishing_mining.id })

        expect(response).to have_http_status(:no_content)
        expect(fishing.reload).to have_attributes(title: "Fish", position_x: 50)
        expect(fishing_mining.reload).to have_attributes(polarity: "negative", cp1_distance: 12, deleted_at: nil)
        expect(Node.count).to eq(2)
      end

      it "restores a node with only the links deleted along with it" do
        other = Link.create!(source_node_id: mining.id, target_node_id: fishing.id, polarity: "negative", decidim_component_id: component.id)
        other.soft_delete!
        apply({ op: "delete", type: "link", id: fishing_mining.id }, { op: "delete", type: "node", id: fishing.id })
        apply({ op: "restore", type: "node", id: fishing.id }, { op: "restore", type: "link", id: fishing_mining.id })

        expect(Node.pluck(:id)).to contain_exactly(fishing.id, mining.id)
        expect(Link.pluck(:id)).to eq([fishing_mining.id])
      end

      it "refuses to restore a link whose node is still deleted" do
        fishing.soft_delete!
        apply({ op: "restore", type: "link", id: fishing_mining.id })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Link.count).to eq(0)
      end

      it "applies nothing if one operation fails" do
        apply({ op: "update", type: "node", id: fishing.id, attrs: { title: "Fish" } },
              { op: "update", type: "link", id: fishing_mining.id, attrs: { polarity: "sideways" } })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(fishing.reload.title).to eq("Fishing")
      end

      it "reports records that are gone, and records of other components, as a changed diagram" do
        elsewhere = Node.create!(title: "Elsewhere", decidim_component_id: other_component.id)
        mining.soft_delete!

        apply({ op: "delete", type: "node", id: fishing.id }, { op: "update", type: "node", id: mining.id, attrs: { title: "Mines" } })
        expect(response).to have_http_status(:not_found)
        apply({ op: "delete", type: "node", id: elsewhere.id })
        expect(response).to have_http_status(:not_found)
        apply({ op: "restore", type: "node", id: 0 })
        expect(response).to have_http_status(:not_found)
        expect(Node.pluck(:title)).to contain_exactly("Fishing", "Elsewhere")
      end
    end

    context "when the user cannot edit" do
      before { login_as user, scope: :user }

      it "is forbidden" do
        apply({ op: "delete", type: "node", id: fishing.id })

        expect(response).to have_http_status(:forbidden)
        expect(Node.count).to eq(2)
      end
    end
  end
end

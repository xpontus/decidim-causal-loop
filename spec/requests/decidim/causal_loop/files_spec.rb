# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe "Saving and loading diagram files" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
    let(:component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:user) { create(:user, :confirmed, organization:) }
    let(:router) { Decidim::EngineRouter.main_proxy(component) }
    let!(:fishing) { Node.create!(title: "Fishing", decidim_component_id: component.id) }

    before { host! organization.host }

    def load_file(diagram, mode: "replace")
      post router.import_path, params: { diagram:, mode: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    it "lets anyone who can see the diagram download it" do
      get router.file_path

      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.parsed_body).to include("format" => DiagramFile::FORMAT, "nodes" => [include("title" => "Fishing")])
    end

    context "when the user is an editor" do
      before do
        Editor.create!(decidim_component_id: component.id, decidim_user_id: user.id)
        login_as user, scope: :user
      end

      it "loads a file and answers with what changed" do
        load_file({ nodes: [{ id: 1, title: "Tourists" }, { id: 2, title: "Crowding" }],
                    links: [{ source: 1, target: 2, polarity: "negative" }] })

        body = response.parsed_body
        expect(body["nodes"].pluck("title")).to eq(%w(Tourists Crowding))
        expect(body["links"].first).to include("polarity" => "negative", "source_node_id" => body["nodes"][0]["id"])
        expect(body["deleted_nodes"]).to eq([fishing.id])
        expect(Node.where(decidim_component_id: component.id).pluck(:title)).to eq(%w(Tourists Crowding))
      end

      it "explains a file it cannot load" do
        load_file({ title: "not a diagram" })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["errors"]).to eq(["The file is not a diagram"])
      end
    end

    context "when the user cannot edit" do
      before { login_as user, scope: :user }

      it "is forbidden" do
        load_file({ nodes: [] })

        expect(response).to have_http_status(:forbidden)
        expect(Node.pluck(:title)).to eq(["Fishing"])
      end
    end
  end
end

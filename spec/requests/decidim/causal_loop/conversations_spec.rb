# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe "AI agent conversations" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
    let(:component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:user) { create(:user, :confirmed, organization:) }
    let(:agent_path) { Decidim::EngineRouter.main_proxy(component).agent_path }
    let(:params) { { message: "Create a node called Stress" } }

    before { host! organization.host }

    def post_message
      post agent_path, params: params.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    context "when the user is not signed in" do
      it "does not reach the agent" do
        expect_any_instance_of(ConversationsController).not_to receive(:build_agent) # rubocop:disable RSpec/AnyInstance

        post_message

        expect(response).not_to have_http_status(:ok)
        expect(Node.count).to eq(0)
      end
    end

    context "when the user is signed in without edit permission" do
      before { login_as user, scope: :user }

      it "returns forbidden without building an agent" do
        expect_any_instance_of(ConversationsController).not_to receive(:build_agent) # rubocop:disable RSpec/AnyInstance

        post_message

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to eq("Not authorized")
        expect(Node.count).to eq(0)
      end
    end

    context "when the user is an explicit editor" do
      before do
        Editor.create!(decidim_component_id: component.id, decidim_user_id: user.id)
        login_as user, scope: :user
      end

      it "passes the permission check" do
        # Stub provider selection so the spec never calls a real AI provider;
        # with no agent the request stops after authorization with a 503.
        allow_any_instance_of(ConversationsController).to receive(:build_agent).and_return(nil) # rubocop:disable RSpec/AnyInstance

        post_message

        expect(response).to have_http_status(:service_unavailable)
      end
    end
  end
end

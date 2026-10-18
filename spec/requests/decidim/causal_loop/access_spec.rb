# frozen_string_literal: true

require "spec_helper"

# Who can reach a diagram, by its page and by every endpoint that reads it,
# in the cases a Decidim site has: unpublished components, private spaces
# and components in the trash.
module Decidim::CausalLoop
  describe "Access to a diagram" do
    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
    let(:component) { create(:causal_loop_component, :published, participatory_space:) }
    let(:router) { Decidim::EngineRouter.main_proxy(component) }
    let(:participant) { create(:user, :confirmed, organization:) }
    let(:admin) { create(:user, :admin, :confirmed, organization:) }
    let!(:secret) { Node.create!(title: "Secret variable", decidim_component_id: component.id) }

    before { host! organization.host }

    def readable?
      [router.root_path, router.file_path, router.loops_path].all? do |path|
        get path
        response.successful? || (return false)
      end
      get router.file_path
      response.body.include?("Secret variable")
    end

    def editable?
      post router.operations_path, params: { operations: [{ op: "update", type: "node", id: secret.id, attrs: { title: "Changed" } }] }.to_json,
                                   headers: { "CONTENT_TYPE" => "application/json" }
      secret.reload.title == "Changed"
    end

    context "when the component is published" do
      it "is readable by visitors" do
        expect(readable?).to be(true)
      end

      it "is readable but not editable by participants" do
        login_as participant, scope: :user
        expect(readable?).to be(true)
        expect(editable?).to be(false)
      end
    end

    context "when the component is not published" do
      let(:component) { create(:causal_loop_component, :unpublished, participatory_space:) }

      it "is hidden from visitors and participants" do
        expect(readable?).to be(false)
        login_as participant, scope: :user
        expect(readable?).to be(false)
      end

      it "is hidden even from a participant granted edit access" do
        Editor.create!(decidim_component_id: component.id, decidim_user_id: participant.id)
        login_as participant, scope: :user

        expect(readable?).to be(false)
        expect(editable?).to be(false)
      end

      it "can be prepared by admins" do
        login_as admin, scope: :user
        expect(readable?).to be(true)
        expect(editable?).to be(true)
      end
    end

    context "when the space is private" do
      let(:participatory_space) { create(:participatory_process, :with_steps, :private, :published, organization:) }

      it "is hidden from people outside the space" do
        login_as participant, scope: :user
        expect(readable?).to be(false)
      end

      it "is readable by members of the space" do
        create(:participatory_space_private_user, user: participant, privatable_to: participatory_space)
        login_as participant, scope: :user
        expect(readable?).to be(true)
      end
    end

    context "when the component is in the trash" do
      before do
        Editor.create!(decidim_component_id: component.id, decidim_user_id: participant.id)
        component.destroy!
      end

      it "is hidden from everyone, its editors included" do
        login_as participant, scope: :user

        expect(readable?).to be(false)
        expect(editable?).to be(false)
      end

      it "is hidden from admins too, outside the admin's trash" do
        login_as admin, scope: :user
        expect(readable?).to be(false)
      end

      it "keeps the diagram, so restoring the component brings it back" do
        component.restore
        expect(readable?).to be(true)
      end
    end
  end
end

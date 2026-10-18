# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe Permissions do
    subject { described_class.new(user, permission_action, component:).permissions.allowed? }

    let(:organization) { create(:organization) }
    let(:participatory_space) { create(:participatory_process, organization:) }
    let(:component) { create(:causal_loop_component, participatory_space:) }
    let(:permission_action) { Decidim::PermissionAction.new(scope: :public, action: :edit, subject: :diagram) }

    shared_examples "can edit" do
      it { is_expected.to be(true) }
    end

    # Permission classes never refuse; they leave the action unset, and
    # Decidim refuses what no class allowed.
    shared_examples "cannot edit" do
      it_behaves_like "permission is not set"
    end

    context "without a user" do
      let(:user) { nil }

      it_behaves_like "cannot edit"
    end

    context "with a participant" do
      let(:user) { create(:user, :confirmed, organization:) }

      it_behaves_like "cannot edit"
    end

    context "with an organization admin" do
      let(:user) { create(:user, :admin, :confirmed, organization:) }

      it_behaves_like "can edit"
    end

    context "with an admin of another organization" do
      let(:user) { create(:user, :admin, :confirmed) }

      it_behaves_like "cannot edit"
    end

    context "with an admin of the space" do
      let(:user) { create(:process_admin, :confirmed, participatory_process: participatory_space) }

      it_behaves_like "can edit"
    end

    context "with an admin of another space" do
      let(:user) { create(:process_admin, :confirmed, participatory_process: create(:participatory_process, organization:)) }

      it_behaves_like "cannot edit"
    end

    context "with a collaborator of the space" do
      let(:user) { create(:process_collaborator, :confirmed, participatory_process: participatory_space) }

      it_behaves_like "cannot edit"
    end

    context "with an editor granted on this component" do
      let(:user) { create(:user, :confirmed, organization:) }

      before { Editor.create!(decidim_component_id: component.id, decidim_user_id: user.id) }

      it_behaves_like "can edit"
    end

    context "with an editor granted on another component" do
      let(:user) { create(:user, :confirmed, organization:) }

      before do
        other = create(:causal_loop_component, participatory_space:)
        Editor.create!(decidim_component_id: other.id, decidim_user_id: user.id)
      end

      it_behaves_like "cannot edit"
    end

    context "when asked about something else" do
      let(:user) { create(:user, :admin, :confirmed, organization:) }
      let(:permission_action) { Decidim::PermissionAction.new(scope: :public, action: :delete, subject: :diagram) }

      it_behaves_like "permission is not set"
    end
  end
end

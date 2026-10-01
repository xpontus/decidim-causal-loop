# frozen_string_literal: true

module Decidim
  module CausalLoop
    class Permissions < Decidim::DefaultPermissions
      def permissions
        return permission_action if permission_action.scope != :public

        allow! if edit_diagram?

        permission_action
      end

      private

      def edit_diagram?
        permission_action.subject == :diagram &&
          permission_action.action == :edit &&
          user.present? &&
          (organization_admin? || space_admin? || explicit_editor?)
      end

      # Organization admins can always edit, so a newly created component is not
      # locked to everyone -- including the admin who just added it.
      def organization_admin?
        user.admin? && user.organization == component.organization
      end

      # Admins of the participatory space holding this component. Not every space
      # type is roleable, hence the respond_to? guard.
      def space_admin?
        space = component.participatory_space
        return false unless space.respond_to?(:user_roles)

        space.user_roles(:admin).exists?(user: user)
      end

      # Participants explicitly granted edit access for this component.
      def explicit_editor?
        Editor.exists?(decidim_component_id: component.id, decidim_user_id: user.id)
      end

      def component
        context.fetch(:component)
      end
    end
  end
end

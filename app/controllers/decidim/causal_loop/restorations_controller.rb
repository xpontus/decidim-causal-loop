# frozen_string_literal: true

module Decidim
  module CausalLoop
    # Undo of a delete: brings back soft-deleted nodes and links with their
    # original IDs.
    class RestorationsController < CausalLoop::ApplicationController
      before_action :authenticate_user!
      before_action :require_edit_permission!

      def create
        restored = DeletedRecords.restore!(current_component.id,
                                           node_ids: Array(params[:node_ids]).map(&:to_i),
                                           link_ids: Array(params[:link_ids]).map(&:to_i))
        render json: { restored: { nodes: restored[:nodes].map(&:id), links: restored[:links].map(&:id) } }
      rescue DeletedRecords::Error => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end

      private

      def require_edit_permission!
        return if allowed_to?(:edit, :diagram, component: current_component)

        render json: { errors: ["Not authorized"] }, status: :forbidden
      end
    end
  end
end

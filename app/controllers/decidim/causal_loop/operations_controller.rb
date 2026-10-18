# frozen_string_literal: true

module Decidim
  module CausalLoop
    # Applies an ordered list of changes in one transaction, so an editor's
    # undo or redo of a multi-part step (auto-layout, deleting a selection,
    # an AI assistant reply) happens completely or not at all.
    #
    # Each operation is { op: "update" | "delete" | "restore",
    # type: "node" | "link", id:, attrs: } (attrs only for update). Records
    # are never created here: with soft delete, redoing a creation is a
    # restore.
    class OperationsController < CausalLoop::ApplicationController
      before_action :authenticate_user!
      before_action :require_edit_permission!

      NODE_ATTRIBUTES = %w(title description position_x position_y width height font_size).freeze
      LINK_ATTRIBUTES = %w(polarity label cp1_distance cp2_distance).freeze

      def create
        ApplicationRecord.transaction { operations.each { |operation| apply(operation) } }
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { errors: ["The diagram has changed since"] }, status: :not_found
      rescue ActiveRecord::RecordInvalid, DeletedRecords::Error, ArgumentError => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end

      private

      def operations
        Array(params.permit(operations: [:op, :type, :id, { attrs: {} }])[:operations])
      end

      def apply(operation)
        model = { "node" => Node, "link" => Link }.fetch(operation[:type]) { raise ArgumentError, "Unknown type #{operation[:type]}" }
        id = operation[:id].to_i

        case operation[:op]
        when "update"
          allowed = model == Node ? NODE_ATTRIBUTES : LINK_ATTRIBUTES
          find(model, id).update!(operation.fetch(:attrs, {}).to_h.slice(*allowed))
        when "delete"
          find(model, id).soft_delete!
        when "restore"
          find(model.with_deleted, id) # purged for good, or never existed
          key = model == Node ? :node_ids : :link_ids
          DeletedRecords.restore!(current_component.id, key => [id])
        else
          raise ArgumentError, "Unknown operation #{operation[:op]}"
        end
      end

      def find(scope, id) = scope.find_by!(decidim_component_id: current_component.id, id:)

      def require_edit_permission!
        return if allowed_to?(:edit, :diagram, component: current_component)

        render json: { errors: ["Not authorized"] }, status: :forbidden
      end
    end
  end
end

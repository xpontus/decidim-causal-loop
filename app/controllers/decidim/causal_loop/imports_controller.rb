# frozen_string_literal: true

module Decidim
  module CausalLoop
    # Loads a diagram file, replacing the diagram or adding to it. Answers
    # with what was created and deleted, so the editor can draw it and undo
    # it as one step.
    class ImportsController < CausalLoop::ApplicationController
      before_action :authenticate_user!
      before_action :require_edit_permission!

      def create
        file = DiagramFile.new(params.to_unsafe_h["diagram"])
        result = file.import!(current_component.id, replace: params[:mode] == "replace")
        render json: {
          nodes: result[:nodes].map(&:editor_json),
          links: result[:links].map(&:editor_json),
          deleted_nodes: result[:deleted_nodes].map(&:id),
          deleted_links: result[:deleted_links].map(&:id),
          skipped: result[:skipped]
        }
      rescue DiagramFile::Error => e
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

# frozen_string_literal: true

module Decidim
  module CausalLoop
    class LinksController < CausalLoop::ApplicationController
      before_action :authenticate_user!
      before_action :require_edit_permission!

      def create
        @link = Link.new(link_params.merge(decidim_component_id: current_component.id))
        unless nodes_belong_to_component?(@link.source_node_id, @link.target_node_id)
          render json: { errors: ["Nodes do not belong to this component"] }, status: :unprocessable_entity and return
        end
        if @link.save
          render json: link_json(@link), status: :created
        else
          render json: { errors: @link.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        @link = Link.find_by!(decidim_component_id: current_component.id, id: params[:id])
        if @link.update(link_params)
          render json: link_json(@link)
        else
          render json: { errors: @link.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @link = Link.find_by!(decidim_component_id: current_component.id, id: params[:id])
        @link.destroy
        head :no_content
      end

      private

      def require_edit_permission!
        unless allowed_to?(:edit, :diagram, component: current_component)
          render json: { errors: ["Not authorized"] }, status: :forbidden
        end
      end

      def link_params
        params.require(:link).permit(:source_node_id, :target_node_id, :polarity, :label,
                                     :cp1_distance, :cp2_distance)
      end

      def nodes_belong_to_component?(source_id, target_id)
        scope = Node.where(decidim_component_id: current_component.id)
        scope.exists?(id: source_id) && scope.exists?(id: target_id)
      end

      def link_json(link)
        { id: link.id, source_node_id: link.source_node_id,
          target_node_id: link.target_node_id, polarity: link.polarity,
          label: link.label,
          cp1_distance: link.cp1_distance.to_f,
          cp2_distance: link.cp2_distance&.to_f }
      end
    end
  end
end

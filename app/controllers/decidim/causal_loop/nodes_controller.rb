# frozen_string_literal: true

module Decidim
  module CausalLoop
    class NodesController < CausalLoop::ApplicationController
      before_action :authenticate_user!
      before_action :require_edit_permission!

      def create
        @node = Node.new(node_params.merge(decidim_component_id: current_component.id))
        if @node.save
          render json: @node.editor_json, status: :created
        else
          render json: { errors: @node.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        @node = Node.find_by!(decidim_component_id: current_component.id, id: params[:id])
        if @node.update(node_params)
          render json: @node.editor_json
        else
          render json: { errors: @node.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        node = Node.find_by!(decidim_component_id: current_component.id, id: params[:id])
        links = node.soft_delete!
        render json: { deleted: { nodes: [node.id], links: links.map(&:id) } }
      end

      private

      def require_edit_permission!
        unless allowed_to?(:edit, :diagram, component: current_component)
          render json: { errors: ["Not authorized"] }, status: :forbidden
        end
      end

      def node_params
        params.require(:node).permit(:title, :description, :position_x, :position_y,
                                     :width, :height, :font_size)
      end
    end
  end
end

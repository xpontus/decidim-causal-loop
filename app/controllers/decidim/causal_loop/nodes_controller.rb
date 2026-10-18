# frozen_string_literal: true

module Decidim
  module CausalLoop
    class NodesController < CausalLoop::ApplicationController
      before_action :authenticate_user!
      before_action :require_edit_permission!

      def create
        @node = Node.new(node_params.merge(decidim_component_id: current_component.id))
        if @node.save
          render json: node_json(@node), status: :created
        else
          render json: { errors: @node.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        @node = Node.find_by!(decidim_component_id: current_component.id, id: params[:id])
        if @node.update(node_params)
          render json: node_json(@node)
        else
          render json: { errors: @node.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        node = Node.find_by!(decidim_component_id: current_component.id, id: params[:id])
        links = node.soft_delete!
        render json: { deleted: { nodes: [node.id], links: links.map(&:id) } }
      end

      # Deletes the given nodes and their links in one request. Used when the
      # user confirms clearing the diagram after the AI assistant asked to.
      # Like `destroy`, it answers with everything deleted, for undo.
      def destroy_many
        ids = Array(params[:node_ids]).map(&:to_i)
        nodes = Node.where(decidim_component_id: current_component.id, id: ids).to_a
        time = Time.current
        links = Node.transaction { nodes.flat_map { |n| n.soft_delete!(time) } }
        render json: { deleted: { nodes: nodes.map(&:id), links: links.map(&:id).uniq } }
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

      def node_json(node)
        { id: node.id, title: node.title, description: node.description,
          position_x: node.position_x, position_y: node.position_y,
          width: node.width, height: node.height, font_size: node.font_size }
      end
    end
  end
end

# frozen_string_literal: true

module Decidim
  module CausalLoop
    class DiagramsController < CausalLoop::ApplicationController
      def index
        @nodes    = Node.where(decidim_component_id: current_component.id)
        @links    = Link.where(decidim_component_id: current_component.id)
        @editable = allowed_to?(:edit, :diagram, component: current_component)
      end
    end
  end
end

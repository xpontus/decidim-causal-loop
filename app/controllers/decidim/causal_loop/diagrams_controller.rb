# frozen_string_literal: true

module Decidim
  module CausalLoop
    class DiagramsController < CausalLoop::ApplicationController
      def index
        @nodes = Node.where(decidim_component_id: current_component.id)
        @links = Link.where(decidim_component_id: current_component.id)
        @editable = allowed_to?(:edit, :diagram, component: current_component)
      end

      # The diagram's feedback loops, for the editor's loops panel. Visible to
      # everyone who can see the diagram.
      def loops
        render json: LoopFinder.report(Node.where(decidim_component_id: current_component.id).to_a,
                                       Link.where(decidim_component_id: current_component.id).to_a)
      end

      # The whole diagram as a file that "Load file" can read back.
      def file
        name = translated_attribute(current_component.name).parameterize.presence || "causal-loop-diagram"
        data = DiagramFile.dump(Node.where(decidim_component_id: current_component.id).order(:id),
                                Link.where(decidim_component_id: current_component.id).order(:id))
        send_data JSON.pretty_generate(data), filename: "#{name}.json", type: :json
      end
    end
  end
end

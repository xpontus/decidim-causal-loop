# frozen_string_literal: true

module Decidim
  module CausalLoop
    class Node < ApplicationRecord
      include SoftDeletable

      self.table_name = "decidim_causal_loop_nodes"

      belongs_to :component, foreign_key: :decidim_component_id, class_name: "Decidim::Component"

      has_many :outgoing_links, class_name: "Decidim::CausalLoop::Link", foreign_key: :source_node_id, dependent: :destroy
      has_many :incoming_links, class_name: "Decidim::CausalLoop::Link", foreign_key: :target_node_id, dependent: :destroy

      validates :title, presence: true

      # The node as the editor's JavaScript expects it.
      def editor_json
        { id:, title:, description:, position_x:, position_y:, width:, height:, font_size: }
      end

      # Marks the node deleted together with its links, and returns those
      # links, so that undo knows exactly which ones to restore. Links that
      # were deleted earlier, on their own, stay deleted.
      def soft_delete!(time = Time.current)
        transaction do
          links = Link.where(decidim_component_id:).where("source_node_id = :id OR target_node_id = :id", id:).to_a
          links.each { |link| link.soft_delete!(time) }
          update_columns(deleted_at: time, updated_at: time) # rubocop:disable Rails/SkipsModelValidations -- a deletion mark needs no validation
          links
        end
      end
    end
  end
end

# frozen_string_literal: true

module Decidim
  module CausalLoop
    class Link < ApplicationRecord
      include SoftDeletable

      self.table_name = "decidim_causal_loop_links"

      belongs_to :component, foreign_key: :decidim_component_id, class_name: "Decidim::Component"
      belongs_to :source_node, class_name: "Decidim::CausalLoop::Node"
      belongs_to :target_node, class_name: "Decidim::CausalLoop::Node"

      validates :polarity, inclusion: { in: %w(positive negative) }

      # The link as the editor's JavaScript expects it.
      def editor_json
        { id:, source_node_id:, target_node_id:, polarity:, label:,
          cp1_distance: cp1_distance.to_f, cp2_distance: cp2_distance&.to_f }
      end

      def soft_delete!(time = Time.current)
        update_columns(deleted_at: time, updated_at: time) # rubocop:disable Rails/SkipsModelValidations -- a deletion mark needs no validation
      end
    end
  end
end

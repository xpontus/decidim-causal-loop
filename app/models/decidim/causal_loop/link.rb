# frozen_string_literal: true

module Decidim
  module CausalLoop
    class Link < ApplicationRecord
      self.table_name = "decidim_causal_loop_links"

      belongs_to :component, foreign_key: :decidim_component_id, class_name: "Decidim::Component"
      belongs_to :source_node, class_name: "Decidim::CausalLoop::Node"
      belongs_to :target_node, class_name: "Decidim::CausalLoop::Node"

      validates :polarity, inclusion: { in: %w(positive negative) }
    end
  end
end

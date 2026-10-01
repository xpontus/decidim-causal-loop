# frozen_string_literal: true

module Decidim
  module CausalLoop
    class Node < ApplicationRecord
      self.table_name = "decidim_causal_loop_nodes"

      belongs_to :component, foreign_key: :decidim_component_id, class_name: "Decidim::Component"

      has_many :outgoing_links, class_name: "Decidim::CausalLoop::Link", foreign_key: :source_node_id, dependent: :destroy
      has_many :incoming_links, class_name: "Decidim::CausalLoop::Link", foreign_key: :target_node_id, dependent: :destroy

      validates :title, presence: true
    end
  end
end

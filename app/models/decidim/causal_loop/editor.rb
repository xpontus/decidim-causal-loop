# frozen_string_literal: true

module Decidim
  module CausalLoop
    class Editor < ApplicationRecord
      self.table_name = "decidim_causal_loop_editors"

      belongs_to :component, foreign_key: :decidim_component_id,
                             class_name:  "Decidim::Component"
      belongs_to :user,      foreign_key: :decidim_user_id,
                             class_name:  "Decidim::User"

      validates :decidim_user_id, uniqueness: { scope: :decidim_component_id }
    end
  end
end

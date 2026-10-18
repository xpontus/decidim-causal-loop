# frozen_string_literal: true

module Decidim
  module CausalLoop
    # Deleting a node or link only marks it, so that undo can bring it back
    # with the same ID and every older step in the editor's history still
    # refers to the right record. The default scope hides marked rows from
    # every read; restoring and purging go through `with_deleted`.
    module SoftDeletable
      extend ActiveSupport::Concern

      included do
        default_scope { where(deleted_at: nil) }
        scope :with_deleted, -> { unscope(where: :deleted_at) }
        scope :only_deleted, -> { with_deleted.where.not(deleted_at: nil) }
      end

      def deleted? = deleted_at.present?
    end
  end
end

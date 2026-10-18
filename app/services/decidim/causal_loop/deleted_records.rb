# frozen_string_literal: true

module Decidim
  module CausalLoop
    # Brings soft-deleted nodes and links back (undo of a delete), and
    # removes them for good once they are old enough that no editor's undo
    # history can still need them.
    module DeletedRecords
      class Error < StandardError; end

      PURGE_AFTER = 30.days

      # Restores the given nodes and links of one component, all or nothing.
      # A link can only come back if both its nodes are live afterwards.
      # Records are restored exactly as they were, so they skip validation.
      # rubocop:disable Rails/SkipsModelValidations
      def self.restore!(component_id, node_ids: [], link_ids: [])
        now = Time.current
        ApplicationRecord.transaction do
          Node.only_deleted.where(decidim_component_id: component_id, id: node_ids)
              .update_all(deleted_at: nil, updated_at: now)
          links = Link.only_deleted.where(decidim_component_id: component_id, id: link_ids).to_a
          live = Node.where(decidim_component_id: component_id,
                            id: links.flat_map { |l| [l.source_node_id, l.target_node_id] }).pluck(:id)
          orphan = links.find { |l| live.exclude?(l.source_node_id) || live.exclude?(l.target_node_id) }
          raise Error, "Link #{orphan.id} cannot be restored without its nodes" if orphan

          Link.with_deleted.where(id: links.map(&:id)).update_all(deleted_at: nil, updated_at: now)
          { nodes: Node.where(decidim_component_id: component_id, id: node_ids).to_a,
            links: Link.where(id: links.map(&:id)).to_a }
        end
      end
      # rubocop:enable Rails/SkipsModelValidations

      # Hard-deletes everything soft-deleted before the cutoff. Links go
      # first, including deleted links of purged nodes, because of the
      # foreign keys.
      def self.purge!(before: PURGE_AFTER.ago)
        ApplicationRecord.transaction do
          node_ids = Node.only_deleted.where(deleted_at: ...before).pluck(:id)
          links = Link.only_deleted.where(deleted_at: ...before)
                      .or(Link.with_deleted.where(source_node_id: node_ids))
                      .or(Link.with_deleted.where(target_node_id: node_ids))
          { links: links.delete_all, nodes: Node.with_deleted.where(id: node_ids).delete_all }
        end
      end
    end
  end
end

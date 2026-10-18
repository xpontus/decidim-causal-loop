# frozen_string_literal: true

class AddDeletedAtToCausalLoopNodesAndLinks < ActiveRecord::Migration[7.0]
  def change
    add_column :decidim_causal_loop_nodes, :deleted_at, :datetime
    add_column :decidim_causal_loop_links, :deleted_at, :datetime
    add_index :decidim_causal_loop_nodes, :deleted_at
    add_index :decidim_causal_loop_links, :deleted_at
  end
end

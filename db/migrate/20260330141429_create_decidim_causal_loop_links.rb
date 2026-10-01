# frozen_string_literal: true

class CreateDecidimCausalLoopLinks < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_causal_loop_links do |t|
      t.references :decidim_component, null: false, index: true
      t.references :source_node, null: false, foreign_key: { to_table: :decidim_causal_loop_nodes }
      t.references :target_node, null: false, foreign_key: { to_table: :decidim_causal_loop_nodes }
      t.string :polarity, null: false, default: "positive"
      t.string :label
      t.timestamps
    end
  end
end

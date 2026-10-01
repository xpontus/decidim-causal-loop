# frozen_string_literal: true

class AddSizeToCausalLoopNodes < ActiveRecord::Migration[7.0]
  def change
    add_column :decidim_causal_loop_nodes, :width,     :integer, default: 130, null: false
    add_column :decidim_causal_loop_nodes, :height,    :integer, default: 44,  null: false
    add_column :decidim_causal_loop_nodes, :font_size, :integer, default: 13,  null: false
  end
end

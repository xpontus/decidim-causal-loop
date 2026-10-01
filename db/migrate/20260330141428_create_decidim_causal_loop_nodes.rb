# frozen_string_literal: true

class CreateDecidimCausalLoopNodes < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_causal_loop_nodes do |t|
      t.references :decidim_component, null: false, index: true
      t.string :title, null: false
      t.text :description
      t.float :position_x, default: 0.0
      t.float :position_y, default: 0.0
      t.timestamps
    end
  end
end

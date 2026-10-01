# frozen_string_literal: true

class AddControlPointToCausalLoopLinks < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_causal_loop_links, :control_point_distance, :float, default: 0.0
  end
end

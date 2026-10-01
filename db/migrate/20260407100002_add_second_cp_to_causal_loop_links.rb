# frozen_string_literal: true

class AddSecondCpToCausalLoopLinks < ActiveRecord::Migration[7.0]
  def change
    rename_column :decidim_causal_loop_links, :control_point_distance, :cp1_distance
    add_column    :decidim_causal_loop_links, :cp2_distance, :float
  end
end

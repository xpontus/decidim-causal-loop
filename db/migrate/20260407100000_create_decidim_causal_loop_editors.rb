# frozen_string_literal: true

class CreateDecidimCausalLoopEditors < ActiveRecord::Migration[7.0]
  def change
    create_table :decidim_causal_loop_editors do |t|
      t.references :decidim_component, null: false, index: true
      t.references :decidim_user,      null: false, index: true
      t.timestamps
    end

    add_index :decidim_causal_loop_editors,
              [:decidim_component_id, :decidim_user_id],
              unique: true,
              name: "idx_causal_loop_editors_unique"
  end
end

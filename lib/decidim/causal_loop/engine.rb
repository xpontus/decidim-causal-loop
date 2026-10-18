# frozen_string_literal: true

require "rails"
require "decidim/core"

module Decidim
  module CausalLoop
    # This is the engine that runs on the public interface of causal_loop.
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::CausalLoop

      routes do
        resources :nodes,         only: [:create, :update, :destroy] do
          delete :destroy_many, on: :collection
        end
        resources :links,         only: [:create, :update, :destroy]
        post "restore", to: "restorations#create", as: :restore
        post "agent", to: "conversations#create", as: :agent
        get "loops", to: "diagrams#loops", as: :loops
        root to: "diagrams#index"
      end

      initializer "CausalLoop.shakapacker.assets_path" do
        Decidim.register_assets_path File.expand_path("app/packs", root)
      end

      initializer "CausalLoop.data_migrate", after: "decidim_core.data_migrate" do
        DataMigrate.configure do |config|
          config.data_migrations_path << root.join("db/data").to_s
        end
      end
    end
  end
end

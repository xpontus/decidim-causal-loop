# frozen_string_literal: true

module Decidim
  module CausalLoop
    # This is the engine that runs on the public interface of `CausalLoop`.
    class AdminEngine < ::Rails::Engine
      isolate_namespace Decidim::CausalLoop::Admin

      paths["db/migrate"] = nil
      paths["lib/tasks"] = nil

      routes do
        resources :diagrams, only: [:index]
        resources :editors,  only: [:index, :create, :destroy]
        root to: "diagrams#index"
      end

      def load_seed
        nil
      end
    end
  end
end

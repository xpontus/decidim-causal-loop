# frozen_string_literal: true

module Decidim
  module CausalLoop
    # This is the engine that runs on the public interface of `CausalLoop`.
    class AdminEngine < ::Rails::Engine
      isolate_namespace Decidim::CausalLoop::Admin

      paths["db/migrate"] = nil
      paths["lib/tasks"] = nil

      routes do
        resources :editors, only: [:index, :create, :destroy]
        # The diagram itself is edited on the public page; what admins manage
        # here is who may edit it.
        root to: "editors#index"
      end

      def load_seed
        nil
      end
    end
  end
end

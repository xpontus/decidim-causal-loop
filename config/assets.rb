# frozen_string_literal: true

base_path = File.expand_path("..", __dir__)

Decidim::Shakapacker.register_path("#{base_path}/app/packs")
Decidim::Shakapacker.register_entrypoints(
  decidim_causal_loop: "#{base_path}/app/packs/entrypoints/decidim_causal_loop.js"
)
Decidim::Shakapacker.register_stylesheet_import("stylesheets/decidim/causal_loop/causal_loop")

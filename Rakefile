# frozen_string_literal: true

require "json"
require "decidim/dev/common_rake"

# Decidim's generator compiles assets while it creates the database, before
# any module-specific step can run, and this module imports `cytoscape`, which
# host apps do not have. So the app is generated without touching the
# database, the module's npm dependencies and migrations are installed, and
# only then is the database created.
def install_module(path)
  dependencies = JSON.parse(File.read("package.json"))["dependencies"].slice("cytoscape")

  Dir.chdir(path) do
    sh "npm", "install", *dependencies.map { |name, version| "#{name}@#{version}" }
    sh "bin/rails", "decidim_causal_loop:install:migrations"
    system("bin/rails", "db:environment:set", "db:drop", err: File::NULL)
    sh "bin/rails", "db:create", "db:migrate", "db:test:prepare"
  end
end

desc "Generates a dummy app for testing"
task :test_app do
  generate_decidim_app(
    "spec/decidim_dummy_app",
    "--app_name", "#{base_app_name}_test_app",
    "--path", "../..",
    "--skip_gemfile",
    "--skip_spring",
    "--demo",
    "--force_ssl", "false",
    "--locales", "en,ca,es"
  )
  install_module("spec/decidim_dummy_app")
end

desc "Generates a development app."
task development_app: "decidim:generate_external_development_app"

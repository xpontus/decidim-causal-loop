# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)

require "decidim/causal_loop/version"

Gem::Specification.new do |s|
  s.version = Decidim::CausalLoop.version
  s.authors = ["Pontus Svenson"]
  s.email = ["xpontus@gmail.com"]
  s.license = "AGPL-3.0-or-later"
  s.homepage = "https://decidim.org"
  s.metadata = {
    "bug_tracker_uri" => "https://github.com/decidim/decidim/issues",
    "documentation_uri" => "https://docs.decidim.org/",
    "funding_uri" => "https://opencollective.com/decidim",
    "homepage_uri" => "https://decidim.org",
    "source_code_uri" => "https://github.com/decidim/decidim"
  }
  s.required_ruby_version = "~> 3.3.11"

  s.name = "decidim-causal_loop"
  s.summary = "A decidim causal_loop module"
  s.description = "."

  s.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").select do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w(app/ config/ db/ lib/ LICENSE Rakefile README.md))
    end
  end

  s.add_dependency "anthropic", "~> 1.25"
  s.add_dependency "decidim-core", Decidim::CausalLoop.version
end

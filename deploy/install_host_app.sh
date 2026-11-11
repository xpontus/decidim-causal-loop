#!/usr/bin/env bash
# Generates a Decidim host application next to this module and configures it
# for a small production instance: the causal loop module, no e-mail, Puma on
# the loopback interface behind a reverse proxy.
#
# Run from anywhere, with Ruby 3.3 and Node 22 on PATH, for example:
#   mise exec ruby@3.3.11 node@22.14.0 -- deploy/install_host_app.sh [APP_NAME]
#
# It touches no database and no secrets; see deploy/README.md for the rest.
set -euo pipefail

DECIDIM_VERSION=0.31.3
MODULE_DIR=$(cd "$(dirname "$0")/.." && pwd)
PARENT=$(dirname "$MODULE_DIR")
APP_NAME=${1:-decidim_app}
APP_DIR="$PARENT/$APP_NAME"
FILES="$MODULE_DIR/deploy/files"

die() { echo "install_host_app: $*" >&2; exit 1; }

[ "$(basename "$MODULE_DIR")" = decidim-module-causal_loop ] ||
  die "the module must be cloned as decidim-module-causal_loop (the host app's Gemfile refers to it by that path)"
[ ! -e "$APP_DIR" ] || die "$APP_DIR already exists; move it away or pass another name"
ruby -e 'exit(RUBY_VERSION.start_with?("3.3.") ? 0 : 1)' ||
  die "Ruby 3.3 required, found $(ruby -v)"
node -e 'process.exit(process.versions.node.split(".")[0] === "22" ? 0 : 1)' ||
  die "Node 22 required, found $(node --version)"
command -v npm >/dev/null || die "npm not found"

echo "== Decidim $DECIDIM_VERSION generator"
gem list -i decidim -v "$DECIDIM_VERSION" >/dev/null ||
  gem install decidim -v "$DECIDIM_VERSION" --no-document
cd "$PARENT"
decidim "_${DECIDIM_VERSION}_" "$APP_NAME"

cd "$APP_DIR"
echo "== Adding the causal loop module"
cat >>Gemfile <<'EOF'

gem "decidim-causal_loop", path: "../decidim-module-causal_loop"
EOF
bundle install
npm install "cytoscape@^3.30.0"

echo "== Production configuration"
cp "$FILES"/config/initializers/*.rb config/initializers/
cp "$FILES"/config/puma.rb config/puma.rb
cp "$FILES"/config/cable.yml config/cable.yml

echo "== Module migrations"
bin/rails decidim_causal_loop:install:migrations
# shellcheck disable=SC2010,SC2012  # migration file names are plain
stray=$(ls db/migrate | sed -E 's/^[0-9]+_[^.]*//' | grep -v '^\.decidim' || true)
[ -z "$stray" ] || die "db/migrate has migrations without a .decidim* suffix: $stray"
# shellcheck disable=SC2010,SC2012
echo "   $(ls db/migrate | wc -l | tr -d ' ') migrations, $(ls db/migrate | grep -c causal_loop) from the module"

echo "== Done: $APP_DIR"
echo "   Next: the environment file and database (deploy/README.md, 'Database and first start')."

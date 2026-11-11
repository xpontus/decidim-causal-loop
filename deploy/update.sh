#!/usr/bin/env bash
# Deploys the current main branch of the module to a running instance:
# pull, install gems and migrations, back up the database, migrate, rebuild
# the assets, restart. Stops at the first error.
#
#   mise exec ruby@3.3.11 node@22.14.0 -- deploy/update.sh [APP_NAME]
set -euo pipefail

MODULE_DIR=$(cd "$(dirname "$0")/.." && pwd)
PARENT=$(dirname "$MODULE_DIR")
APP_DIR="$PARENT/${1:-decidim_app}"
ENV_FILE="$PARENT/decidim.env"
BACKUPS="$PARENT/backups"
UNIT=${DECIDIM_UNIT:-decidim}

die() { echo "update: $*" >&2; exit 1; }

cd "$MODULE_DIR"
[ -z "$(git status --porcelain)" ] || die "the module checkout has local changes; code is never edited on the server"
git fetch --quiet origin
git checkout --quiet main
git pull --quiet --ff-only origin main
commit=$(git rev-parse --short HEAD)
echo "== Module at $commit: $(git log -1 --format=%s)"

cd "$APP_DIR"
set -a
# shellcheck disable=SC1090  # the env file lives outside the repo
. "$ENV_FILE"
set +a
bundle install --quiet
bin/rails decidim_causal_loop:install:migrations

umask 077   # dumps hold user data and password hashes
mkdir -p "$BACKUPS"
dump="$BACKUPS/$(date +%Y-%m-%dT%H%M%S)_before_$commit.dump"
pg_dump --format=custom --file="$dump" "$DATABASE_URL?host=$DATABASE_HOST"
echo "== Database backed up to $dump"

bin/rails db:migrate
bin/rails assets:precompile
systemctl --user restart "$UNIT"
echo "== Restarted $UNIT on $commit; check: systemctl --user status $UNIT"

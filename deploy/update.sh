#!/usr/bin/env bash
# Deploys a branch of the module (default: main) to a running instance:
# fetch from origin, check it out, install gems and migrations, back up the
# database, migrate, rebuild the assets, restart. Stops at the first error.
#
#   mise exec ruby@3.3.11 node@22.14.0 -- deploy/update.sh [BRANCH [APP_NAME]]
#
# origin is whatever the checkout was cloned from: GitHub, or a bare
# repository on the server that a development machine pushes to.
set -euo pipefail

MODULE_DIR=$(cd "$(dirname "$0")/.." && pwd)
PARENT=$(dirname "$MODULE_DIR")
BRANCH=${1:-main}
APP_DIR="$PARENT/${2:-decidim_app}"
ENV_FILE="$PARENT/decidim.env"
BACKUPS="$PARENT/backups"
UNIT=${DECIDIM_UNIT:-decidim}

die() { echo "update: $*" >&2; exit 1; }

cd "$MODULE_DIR"
[ -z "$(git status --porcelain)" ] || die "the module checkout has local changes; code is never edited on the server"
git fetch --quiet origin
# The checkout only follows origin and is never edited, so a reset (rather
# than a fast-forward) also handles branches that were rewritten or switched.
git checkout --quiet -B "$BRANCH" "origin/$BRANCH"
commit=$(git rev-parse --short HEAD)
echo "== Module at $commit ($BRANCH): $(git log -1 --format=%s)"

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

#!/usr/bin/env bash
# Writes the environment file ../decidim.env (next to the module and the host
# app) with a newly generated SECRET_KEY_BASE. The file holds secrets: it is
# created with mode 600, is never committed, and is never copied off the server.
# Refuses to overwrite an existing file.
#
#   deploy/make_env.sh [DATABASE_NAME]
set -euo pipefail

PARENT=$(cd "$(dirname "$0")/../.." && pwd)
ENV_FILE="$PARENT/decidim.env"
DB_NAME=${1:-decidim_production}

[ ! -e "$ENV_FILE" ] || { echo "make_env: $ENV_FILE exists; not overwriting" >&2; exit 1; }
command -v openssl >/dev/null || { echo "make_env: openssl not found" >&2; exit 1; }

umask 077
cat >"$ENV_FILE" <<CONF
# Decidim production environment. Secrets: mode 600, never in git.
RAILS_ENV=production
SECRET_KEY_BASE=$(openssl rand -hex 64)

# PostgreSQL over the local socket with peer authentication: the database role
# has the same name as the user running Puma, and no password is needed.
DATABASE_URL=postgresql:///$DB_NAME
DATABASE_HOST=/var/run/postgresql

RAILS_LOG_TO_STDOUT=1
RAILS_MAX_THREADS=5
DECIDIM_DEFAULT_LOCALE=en
DECIDIM_AVAILABLE_LOCALES=en

# AI assistant (see the module README). With none of these set, and no Ollama
# reachable, the assistant answers 503 and the rest works normally.
# CAUSAL_LOOP_AI_PROVIDER=ollama
# ANTHROPIC_API_KEY=
# CAUSAL_LOOP_OPENAI_MODEL=
CONF
echo "Wrote $ENV_FILE"

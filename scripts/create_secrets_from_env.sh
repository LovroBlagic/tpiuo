#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"

REDDIT_SECRET_CLIENT_ID="${REDDIT_SECRET_CLIENT_ID:-reddit-client-id}"
REDDIT_SECRET_CLIENT_SECRET="${REDDIT_SECRET_CLIENT_SECRET:-reddit-client-secret}"
REDDIT_SECRET_USERNAME="${REDDIT_SECRET_USERNAME:-reddit-username}"
REDDIT_SECRET_PASSWORD="${REDDIT_SECRET_PASSWORD:-reddit-password}"
REDDIT_SECRET_USER_AGENT="${REDDIT_SECRET_USER_AGENT:-reddit-user-agent}"

: "${REDDIT_CLIENT_ID:?Set REDDIT_CLIENT_ID}"
: "${REDDIT_CLIENT_SECRET:?Set REDDIT_CLIENT_SECRET}"
: "${REDDIT_USERNAME:?Set REDDIT_USERNAME}"
: "${REDDIT_PASSWORD:?Set REDDIT_PASSWORD}"
: "${REDDIT_USER_AGENT:?Set REDDIT_USER_AGENT}"

gcloud config set project "$PROJECT_ID" >/dev/null
gcloud services enable secretmanager.googleapis.com >/dev/null

upsert_secret () {
  local name="$1"
  local value="$2"
  if ! gcloud secrets describe "$name" >/dev/null 2>&1; then
    gcloud secrets create "$name" --replication-policy="automatic" >/dev/null
  fi
  printf "%s" "$value" | gcloud secrets versions add "$name" --data-file=- >/dev/null
  echo "updated secret: $name"
}

upsert_secret "$REDDIT_SECRET_CLIENT_ID" "$REDDIT_CLIENT_ID"
upsert_secret "$REDDIT_SECRET_CLIENT_SECRET" "$REDDIT_CLIENT_SECRET"
upsert_secret "$REDDIT_SECRET_USERNAME" "$REDDIT_USERNAME"
upsert_secret "$REDDIT_SECRET_PASSWORD" "$REDDIT_PASSWORD"
upsert_secret "$REDDIT_SECRET_USER_AGENT" "$REDDIT_USER_AGENT"

echo "✅ Secrets uploaded."

#!/usr/bin/env bash
set -euo pipefail

# ====== REQUIRED ENV VARS ======
: "${PROJECT_ID:?Set PROJECT_ID}"
: "${GCP_REGION:?Set GCP_REGION (e.g., europe-west1)}"
: "${PUBSUB_TOPIC:?Set PUBSUB_TOPIC}"
: "${PUBSUB_SUBSCRIPTION:?Set PUBSUB_SUBSCRIPTION}"

# Secret names (override if you want)
REDDIT_SECRET_CLIENT_ID="${REDDIT_SECRET_CLIENT_ID:-reddit-client-id}"
REDDIT_SECRET_CLIENT_SECRET="${REDDIT_SECRET_CLIENT_SECRET:-reddit-client-secret}"
REDDIT_SECRET_USERNAME="${REDDIT_SECRET_USERNAME:-reddit-username}"
REDDIT_SECRET_PASSWORD="${REDDIT_SECRET_PASSWORD:-reddit-password}"
REDDIT_SECRET_USER_AGENT="${REDDIT_SECRET_USER_AGENT:-reddit-user-agent}"

REPO_NAME="${REPO_NAME:-reddit-images}"
PRODUCER_IMAGE="${PRODUCER_IMAGE:-reddit-producer}"
CONSUMER_IMAGE="${CONSUMER_IMAGE:-reddit-consumer}"

PRODUCER_JOB_NAME="${PRODUCER_JOB_NAME:-reddit-producer-job}"
CONSUMER_SERVICE_NAME="${CONSUMER_SERVICE_NAME:-reddit-consumer-svc}"

TAG="${TAG:-latest}"

echo "==> Using project: $PROJECT_ID"
gcloud config set project "$PROJECT_ID" >/dev/null

echo "==> Enabling required APIs..."
gcloud services enable run.googleapis.com pubsub.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com >/dev/null

echo "==> Creating Pub/Sub topic + subscription (if missing)..."
gcloud pubsub topics create "$PUBSUB_TOPIC" >/dev/null 2>&1 || true
gcloud pubsub subscriptions create "$PUBSUB_SUBSCRIPTION" --topic="$PUBSUB_TOPIC" >/dev/null 2>&1 || true

echo "==> Creating Artifact Registry repo (if missing)..."
gcloud artifacts repositories create "$REPO_NAME" \
  --repository-format=docker \
  --location="$GCP_REGION" \
  --description="Docker images for Reddit Pub/Sub pipeline" >/dev/null 2>&1 || true

echo "==> Configuring Docker auth for Artifact Registry..."
gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" -q >/dev/null

PRODUCER_IMAGE_URL="${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${PRODUCER_IMAGE}:${TAG}"
CONSUMER_IMAGE_URL="${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${CONSUMER_IMAGE}:${TAG}"

echo "==> Building & pushing producer image: $PRODUCER_IMAGE_URL"
docker build -t "$PRODUCER_IMAGE_URL" ./producer
docker push "$PRODUCER_IMAGE_URL"

echo "==> Building & pushing consumer image: $CONSUMER_IMAGE_URL"
docker build -t "$CONSUMER_IMAGE_URL" ./consumer
docker push "$CONSUMER_IMAGE_URL"

echo "==> Creating Service Account for Cloud Run (if missing)..."
gcloud iam service-accounts create cr-deploy-sa \
  --description="Service Account for Cloud Run Service and Job deployment" \
  --display-name="CR Deploy SA" >/dev/null 2>&1 || true

echo "==> Granting roles to SA..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:cr-deploy-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/run.admin" >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:cr-deploy-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/pubsub.editor" >/dev/null

echo "==> Ensuring Reddit secrets exist (values must be added separately if missing)..."
create_secret_if_missing () {
  local name="$1"
  if ! gcloud secrets describe "$name" >/dev/null 2>&1; then
    echo "   - creating secret: $name"
    gcloud secrets create "$name" --replication-policy="automatic" >/dev/null
    echo "     Add a value with: gcloud secrets versions add $name --data-file=-"
  fi
}
create_secret_if_missing "$REDDIT_SECRET_CLIENT_ID"
create_secret_if_missing "$REDDIT_SECRET_CLIENT_SECRET"
create_secret_if_missing "$REDDIT_SECRET_USERNAME"
create_secret_if_missing "$REDDIT_SECRET_PASSWORD"
create_secret_if_missing "$REDDIT_SECRET_USER_AGENT"

echo "==> Deploying consumer Cloud Run service..."
gcloud run deploy "$CONSUMER_SERVICE_NAME" \
  --image "$CONSUMER_IMAGE_URL" \
  --region "$GCP_REGION" \
  --platform managed \
  --allow-unauthenticated \
  --service-account "cr-deploy-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --set-env-vars "PROJECT_ID=${PROJECT_ID},PUBSUB_TOPIC=${PUBSUB_TOPIC},PUBSUB_SUBSCRIPTION=${PUBSUB_SUBSCRIPTION}" >/dev/null

CONSUMER_URL="$(gcloud run services describe "$CONSUMER_SERVICE_NAME" --region "$GCP_REGION" --format='value(status.url)')"
echo "==> Consumer URL: $CONSUMER_URL"
PUSH_ENDPOINT="${CONSUMER_URL}/pubsub/push"

echo "==> Creating Pub/Sub PUSH subscription to consumer endpoint (if missing)..."
PUSH_SUB_NAME="${PUBSUB_TOPIC}-push-to-${CONSUMER_SERVICE_NAME}"
gcloud pubsub subscriptions create "$PUSH_SUB_NAME" \
  --topic="$PUBSUB_TOPIC" \
  --push-endpoint="$PUSH_ENDPOINT" \
  --push-auth-service-account="cr-deploy-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --ack-deadline=30 >/dev/null 2>&1 || true

echo "==> Deploying producer Cloud Run Job..."
gcloud run jobs deploy "$PRODUCER_JOB_NAME" \
  --image "$PRODUCER_IMAGE_URL" \
  --region "$GCP_REGION" \
  --service-account "cr-deploy-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --set-env-vars "PROJECT_ID=${PROJECT_ID},PUBSUB_TOPIC=${PUBSUB_TOPIC},REDDIT_SUBREDDIT=dataengineering,REDDIT_LIMIT=10,EXIT_AFTER_PUBLISH=true" \
  --set-secrets "REDDIT_CLIENT_ID=${REDDIT_SECRET_CLIENT_ID}:latest,REDDIT_CLIENT_SECRET=${REDDIT_SECRET_CLIENT_SECRET}:latest,REDDIT_USERNAME=${REDDIT_SECRET_USERNAME}:latest,REDDIT_PASSWORD=${REDDIT_SECRET_PASSWORD}:latest,REDDIT_USER_AGENT=${REDDIT_SECRET_USER_AGENT}:latest" >/dev/null

echo ""
echo "✅ Deploy complete."
echo "Next:"
echo "  1) Ensure secrets have values (Secret Manager) OR run: bash scripts/create_secrets_from_env.sh"
echo "  2) Run the producer job:"
echo "     gcloud run jobs execute "$PRODUCER_JOB_NAME" --region "$GCP_REGION""
echo "  3) Watch logs in Cloud Run for $CONSUMER_SERVICE_NAME"

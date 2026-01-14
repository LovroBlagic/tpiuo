# Reddit → Pub/Sub → Cloud Run (Producer Job + Consumer Service)

This repo implements the **tasks at the end of the lab instructions**: a Reddit *producer* that fetches posts and publishes them to a Pub/Sub topic, and a Cloud Run *consumer* service (Flask) that receives Pub/Sub push messages and logs them.

## What you get
- `producer/producer.py` — fetches **Top 10** posts (All time) from **r/dataengineering** via **plain HTTP** (OAuth2) and publishes **full post objects** to Pub/Sub, one message per post, then (optionally) idles in an infinite loop.
- `consumer/app.py` — Flask service with:
  - `GET /listening` healthcheck
  - `POST /pubsub/push` Pub/Sub push endpoint (decodes message, prints JSON)
- Dockerfiles for both apps
- `scripts/deploy_gcp.sh` — creates Pub/Sub topic/subscription, Artifact Registry repo, builds/pushes images, deploys Cloud Run service + job, and creates a **push subscription** to your consumer endpoint.

---

## Prerequisites
- GCP project + billing enabled (free trial ok)
- `gcloud` installed (or use Cloud Shell)
- Docker installed
- Reddit API credentials (create Reddit app of type **script**)

### Required env vars
Export these in your shell before running locally or before deploying:

```bash
# GCP
export PROJECT_ID="your-project-id"
export GCP_REGION="europe-west1"
export PUBSUB_TOPIC="reddit-topic-yourid"
export PUBSUB_SUBSCRIPTION="reddit-topic-yourid-sub"  # naming convention from the lab

# Reddit (store as Secret Manager in GCP; export locally for testing)
export REDDIT_CLIENT_ID="..."
export REDDIT_CLIENT_SECRET="..."
export REDDIT_USERNAME="..."
export REDDIT_PASSWORD="..."
export REDDIT_USER_AGENT="lab1-reddit-producer/1.0 by <your-username>"

# Behavior
export EXIT_AFTER_PUBLISH="false"   # set true for Cloud Run Job to finish
```

> **Important:** In GCP, create secrets in Secret Manager and attach them as env vars to Cloud Run. See `scripts/create_secrets_from_env.sh` and `scripts/deploy_gcp.sh`.

---

## Local run (quick test without GCP Pub/Sub)
You can test the Reddit fetch logic locally:

```bash
cd producer
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python producer.py
```

To fully test Pub/Sub locally you’d need the Pub/Sub emulator; the lab focuses on using real Pub/Sub in GCP.

---

## Deploy to GCP
1) Upload secrets from your local env to Secret Manager:

```bash
bash scripts/create_secrets_from_env.sh
```

2) Deploy everything:

```bash
bash scripts/deploy_gcp.sh
```

After deploy:
- Open Cloud Run consumer logs to see messages arriving.
- Execute the producer job:
  ```bash
  gcloud run jobs execute "$PRODUCER_JOB_NAME" --region "$GCP_REGION"
  ```


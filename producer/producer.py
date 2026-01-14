import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

import requests
from google.cloud import pubsub_v1


REDDIT_TOKEN_URL = "https://www.reddit.com/api/v1/access_token"
REDDIT_API_BASE = "https://oauth.reddit.com"


def env(name: str, default: Optional[str] = None, required: bool = False) -> str:
    val = os.getenv(name, default)
    if required and (val is None or val == ""):
        raise RuntimeError(f"Missing required environment variable: {name}")
    return val


def get_reddit_token() -> str:
    """
    OAuth2 password grant for 'script' apps.
    Uses plain HTTP requests (requests lib), as required by the lab.
    """
    client_id = env("REDDIT_CLIENT_ID", required=True)
    client_secret = env("REDDIT_CLIENT_SECRET", required=True)
    username = env("REDDIT_USERNAME", required=True)
    password = env("REDDIT_PASSWORD", required=True)
    user_agent = env("REDDIT_USER_AGENT", "lab1-reddit-producer/1.0", required=True)

    auth = requests.auth.HTTPBasicAuth(client_id, client_secret)
    data = {"grant_type": "password", "username": username, "password": password}
    headers = {"User-Agent": user_agent}

    resp = requests.post(REDDIT_TOKEN_URL, auth=auth, data=data, headers=headers, timeout=30)
    resp.raise_for_status()
    token = resp.json().get("access_token")
    if not token:
        raise RuntimeError(f"Could not get access_token from Reddit. Response: {resp.text[:300]}")
    return token


def fetch_top_posts(subreddit: str = "dataengineering", limit: int = 10) -> List[Dict[str, Any]]:
    """
    Fetch Top posts of All Time from r/<subreddit>.
    Returns a list of 'children[i].data' dicts (full post objects).
    """
    token = get_reddit_token()
    user_agent = env("REDDIT_USER_AGENT", "lab1-reddit-producer/1.0", required=True)

    url = f"{REDDIT_API_BASE}/r/{subreddit}/top"
    params = {"t": "all", "limit": str(limit)}
    headers = {"Authorization": f"bearer {token}", "User-Agent": user_agent}

    resp = requests.get(url, params=params, headers=headers, timeout=30)
    resp.raise_for_status()
    payload = resp.json()

    children = payload.get("data", {}).get("children", [])
    posts = [c.get("data", {}) for c in children]  # keep ALL fields per post
    return posts


def publish_posts(posts: List[Dict[str, Any]]) -> None:
    project_id = env("PROJECT_ID", required=True)
    topic_name = env("PUBSUB_TOPIC", required=True)

    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)

    futures = []
    for i, post in enumerate(posts, start=1):
        msg = json.dumps(post, ensure_ascii=False).encode("utf-8")
        attributes = {
            "source": "reddit",
            "subreddit": str(post.get("subreddit", "dataengineering")),
            "kind": "post",
        }
        futures.append(publisher.publish(topic_path, msg, **attributes))
        print(f"[producer] published {i}/{len(posts)} id={post.get('id')} title={post.get('title')!r}")

    for f in futures:
        f.result(timeout=60)

    print(f"[producer] done: published {len(posts)} messages to {topic_name}.")


def main() -> None:
    subreddit = env("REDDIT_SUBREDDIT", "dataengineering")
    limit = int(env("REDDIT_LIMIT", "10"))
    exit_after = env("EXIT_AFTER_PUBLISH", "false").lower() in ("1", "true", "yes")

    print(f"[producer] fetching Top {limit} (all time) from r/{subreddit} ...")
    posts = fetch_top_posts(subreddit=subreddit, limit=limit)

    if not posts:
        print("[producer] WARNING: got 0 posts from Reddit API.")
    else:
        publish_posts(posts)

    # Lab instruction: infinite loop after sending 10 messages.
    # For Cloud Run Job you usually want to exit; control via EXIT_AFTER_PUBLISH.
    if exit_after:
        print("[producer] EXIT_AFTER_PUBLISH=true -> exiting.")
        return

    print("[producer] entering infinite idle loop (sleeping). Set EXIT_AFTER_PUBLISH=true to exit.")
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[producer] ERROR: {e}", file=sys.stderr)
        raise

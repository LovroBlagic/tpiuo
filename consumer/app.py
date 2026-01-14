import base64
import json
import os
from datetime import datetime, timezone

from flask import Flask, request

app = Flask(__name__)


@app.get("/listening")
def listening_check():
    return "Consumer service is listening", 200


@app.post("/pubsub/push")
def pubsub_push():
    """
    Pub/Sub push subscription POSTs a JSON envelope:
    {
      "message": {"data": "base64...", "attributes": {...}, "messageId": "...", ...},
      "subscription": "..."
    }
    Returning 200 acknowledges the message.
    """
    envelope = request.get_json(silent=True) or {}
    message = envelope.get("message", {}) or {}
    data_b64 = message.get("data", "")
    attrs = message.get("attributes", {}) or {}

    if not data_b64:
        print("[consumer] WARNING: no message.data found in push envelope.")
        return ("no data", 200)

    try:
        payload_bytes = base64.b64decode(data_b64)
        payload_str = payload_bytes.decode("utf-8", errors="replace")
        post = json.loads(payload_str)
    except Exception as e:
        print(f"[consumer] ERROR decoding message: {e}")
        return ("bad message", 200)

    now = datetime.now(timezone.utc).isoformat()
    print(f"\n[consumer] {now} received reddit post")
    print(f"  attributes: {attrs}")
    print(f"  id: {post.get('id')}")
    print(f"  title: {post.get('title')}")
    print(f"  author: {post.get('author')}")
    print(f"  score: {post.get('score')}")
    print(f"  created_utc: {post.get('created_utc')}")
    print(f"  permalink: {post.get('permalink')}")

    return ("ok", 200)


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)

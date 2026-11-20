"""Check the Windows deployment with real services and synthetic data."""

import argparse
import json
from uuid import uuid4

import httpx
import redis


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--via-frontend", action="store_true")
    args = parser.parse_args()
    api = "http://127.0.0.1:15174/api" if args.via_frontend else "http://127.0.0.1:18010"
    user_id = f"windows-smoke-{uuid4().hex[:12]}"
    working_memory = redis.Redis(
        host="127.0.0.1", port=16380, decode_responses=True, socket_timeout=5
    )
    assert working_memory.ping(), "Redis PING failed"

    with httpx.Client(timeout=120, trust_env=False) as http:
        def request(method: str, path: str, **kwargs):
            response = http.request(method, f"{api}{path}", **kwargs)
            response.raise_for_status()
            return response.json()

        heartbeat = http.get("http://127.0.0.1:18011/api/v2/heartbeat")
        heartbeat.raise_for_status()
        assert "nanosecond heartbeat" in heartbeat.json()
        assert request("GET", "/health")["status"] == "ok"
        skills = request("GET", "/skills")
        assert skills["count"] and not skills["errors"], skills

        title = "本地部署验证专用订阅定价"
        imported = request("POST", "/knowledge/add", json={"documents": [{
            "title": title,
            "content": "仅用于本地测试的订阅定价：验证版每月 99 元，购买前可试用 7 天。",
        }]})
        assert imported["added_chunks"] == 1, imported
        retrieved = request("POST", "/search", params={"query": title, "top_k": 5})
        hits = [item["title"] for item in retrieved["results"] if not item.get("fallback")]
        assert title in hits, retrieved

        first = request("POST", "/chat", json={"user_id": user_id, "message": "你好！请简短问好。"})
        second = request("POST", "/chat", json={
            "user_id": user_id,
            "conv_id": first["conv_id"],
            "message": "谢谢，也请介绍你能提供什么帮助。",
        })
        assert first["response"] and second["response"], (first, second)
        assert first["conv_id"] == second["conv_id"], (first, second)
        trace = request("GET", f"/trace/tool/{second['request_id']}")
        assert trace["found"], trace

        key = f"wm:{user_id}:{first['conv_id']}"
        rows = [json.loads(value) for value in working_memory.lrange(key, 0, -1)]
        assert [row["role"] for row in rows] == ["assistant", "user"] * 2, rows
        assert rows[2]["content"] == first["response"] and rows[0]["content"] == second["response"]

        metrics = http.get(f"{api}/metrics")
        metrics.raise_for_status()
        assert "chat_latency_ms" in metrics.text

    print(json.dumps({
        "api": api,
        "skills_count": skills["count"],
        "knowledge_chunks": imported["total_chunks"],
        "retrieved_titles": hits,
        "trace_request_id": second["request_id"],
        "redis_key": key,
        "redis_messages": len(rows),
        "metrics_ok": True,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

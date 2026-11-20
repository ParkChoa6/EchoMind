"""Small, display-safe previews of real knowledge-base results."""


def source_preview(item: object) -> dict[str, str] | None:
    if not isinstance(item, dict) or item.get("fallback"):
        return None
    content = item.get("content")
    if not isinstance(content, str) or not content.strip():
        return None
    title = str(item.get("title") or "未命名文档").strip() or "未命名文档"
    return {"title": title[:500], "snippet": content.strip()[:500]}

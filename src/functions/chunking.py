"""Pure helpers (no Azure imports) so they can be tested anywhere."""
from urllib.parse import unquote, urlparse

CHUNK_CHARS = 1500  # ~350 tokens. Smaller chunks = sharper search results.


def chunk(text: str, size: int = CHUNK_CHARS) -> list[str]:
    """Split on blank lines, then pack paragraphs into chunks of up to `size` chars."""
    paras = [p.strip() for p in text.split("\n\n") if p.strip()]
    pieces = [p[i:i + size] for p in paras for i in range(0, len(p), size)]  # hard-split huge paragraphs

    chunks, current = [], ""
    for piece in pieces:
        if current and len(current) + len(piece) + 2 > size:
            chunks.append(current)
            current = ""
        current = f"{current}\n\n{piece}" if current else piece
    if current:
        chunks.append(current)
    return chunks


def parse_blob_url(url: str) -> tuple[str, str]:
    """https://<acct>.blob.core.windows.net/runbooks/payments-api/latency.md
    -> ("payments-api/latency.md", "payments-api")

    The first folder inside the container is the service name.
    Files at the container root belong to "general".
    """
    path = unquote(urlparse(url).path).lstrip("/")  # runbooks/payments-api/latency.md
    _, _, source = path.partition("/")              # payments-api/latency.md
    service = source.split("/")[0] if "/" in source else "general"
    return source, service

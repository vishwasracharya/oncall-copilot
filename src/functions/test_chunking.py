"""Run: python test_chunking.py"""
from chunking import chunk, parse_blob_url

# chunking
assert chunk("") == []
assert chunk("a\n\nb") == ["a\n\nb"]                       # small paragraphs are packed together
assert chunk("aaaa\n\nbbbb", size=6) == ["aaaa", "bbbb"]   # ...until the size limit
assert chunk("x" * 25, size=10) == ["x" * 10, "x" * 10, "x" * 5]  # huge paragraph is hard-split
assert all(len(c) <= 10 for c in chunk("one two\n\n" * 20, size=10))

# blob url -> (source, service)
base = "https://st.blob.core.windows.net/runbooks/"
assert parse_blob_url(base + "payments-api/high-latency.md") == ("payments-api/high-latency.md", "payments-api")
assert parse_blob_url(base + "readme.md") == ("readme.md", "general")
assert parse_blob_url(base + "auth%20service/login.md") == ("auth service/login.md", "auth service")

print("all good")

"""On-Call Copilot - Phase 1

ingest : Service Bus message (a BlobCreated event from Event Grid)
         -> download runbook -> chunk -> embed -> store in PostgreSQL (pgvector)
ask    : HTTP POST {"question": "...", "service": "optional"}
         -> embed question -> vector search -> answer with Azure OpenAI
"""
import json
import logging
import os
from functools import cache

import azure.functions as func
import psycopg
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.storage.blob import BlobClient
from openai import OpenAI

from chunking import chunk, parse_blob_url

app = func.FunctionApp()

TOP_K = 5
MAX_QUESTION_CHARS = 2000

SYSTEM_PROMPT = """You are an on-call assistant for software engineers.
Answer ONLY from the runbook excerpts provided. Cite them like [1], [2].
If the excerpts do not cover the question, say so plainly. Do not guess.
Format: one line with the most likely cause, then numbered steps."""

SCHEMA = """
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE IF NOT EXISTS chunks (
    id        bigserial PRIMARY KEY,
    source    text NOT NULL,          -- e.g. payments-api/high-latency.md
    service   text NOT NULL,          -- e.g. payments-api (used as a metadata filter)
    chunk_no  int  NOT NULL,
    content   text NOT NULL,
    embedding vector(1536) NOT NULL,  -- text-embedding-3-small size
    UNIQUE (source, chunk_no)
);
CREATE INDEX IF NOT EXISTS chunks_embedding_idx ON chunks USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS chunks_service_idx ON chunks (service);
"""


# ---------- clients (created once per instance) ----------

@cache
def credential() -> DefaultAzureCredential:
    return DefaultAzureCredential()  # the Function's managed identity in Azure, your `az login` locally


@cache
def llm() -> OpenAI:
    token = get_bearer_token_provider(credential(), "https://cognitiveservices.azure.com/.default")
    endpoint = os.environ["AZURE_OPENAI_ENDPOINT"].rstrip("/")
    return OpenAI(base_url=f"{endpoint}/openai/v1/", api_key=token)  # no API key anywhere


_schema_ready = False


def connect() -> psycopg.Connection:
    # ponytail: new connection per call. Pooling is a Phase 3 exam topic ("connection optimization").
    global _schema_ready
    conn = psycopg.connect(os.environ["PG_CONN"], autocommit=True)
    if not _schema_ready:
        conn.execute(SCHEMA)
        _schema_ready = True
    return conn


def embed(texts: list[str]) -> list[list[float]]:
    resp = llm().embeddings.create(model=os.environ["EMBEDDING_DEPLOYMENT"], input=texts)
    return [d.embedding for d in resp.data]


# ---------- ingest ----------

@app.service_bus_queue_trigger(arg_name="msg", queue_name="ingest", connection="ServiceBusConnection")
def ingest(msg: func.ServiceBusMessage) -> None:
    # Any exception here = Service Bus retries the message; after 5 failures it goes to the dead-letter queue.
    event = json.loads(msg.get_body())
    url = event["data"]["url"]
    source, service = parse_blob_url(url)

    text = BlobClient.from_blob_url(url, credential=credential()).download_blob().readall().decode("utf-8")
    pieces = chunk(text)
    vectors = embed(pieces) if pieces else []

    with connect() as conn, conn.transaction():
        conn.execute("DELETE FROM chunks WHERE source = %s", (source,))  # re-upload replaces old chunks
        with conn.cursor() as cur:
            cur.executemany(
                "INSERT INTO chunks (source, service, chunk_no, content, embedding) VALUES (%s, %s, %s, %s, %s::vector)",
                [(source, service, i, p, str(v)) for i, (p, v) in enumerate(zip(pieces, vectors))],
            )
    logging.info("Ingested %s (%s): %d chunks", source, service, len(pieces))


# ---------- ask ----------

def bad_request(message: str) -> func.HttpResponse:
    return func.HttpResponse(json.dumps({"error": message}), status_code=400, mimetype="application/json")


@app.route(route="ask", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def ask(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except ValueError:
        return bad_request("Body must be JSON.")

    question = body.get("question") if isinstance(body, dict) else None
    service = body.get("service") if isinstance(body, dict) else None
    if not isinstance(question, str) or not question.strip() or len(question) > MAX_QUESTION_CHARS:
        return bad_request(f'"question" must be a non-empty string up to {MAX_QUESTION_CHARS} chars.')
    if service is not None and not isinstance(service, str):
        return bad_request('"service" must be a string.')

    [qvec] = embed([question])
    with connect() as conn:
        rows = conn.execute(
            """
            SELECT source, content, 1 - (embedding <=> %(q)s::vector) AS score
            FROM chunks
            WHERE %(svc)s::text IS NULL OR service = %(svc)s
            ORDER BY embedding <=> %(q)s::vector
            LIMIT %(k)s
            """,
            {"q": str(qvec), "svc": service, "k": TOP_K},
        ).fetchall()

    if not rows:
        answer = "No matching runbooks. Upload Markdown files to the 'runbooks' container, or check the service name."
    else:
        excerpts = "\n\n---\n\n".join(f"[{i}] {src}\n{content}" for i, (src, content, _) in enumerate(rows, 1))
        resp = llm().responses.create(
            model=os.environ["CHAT_DEPLOYMENT"],
            instructions=SYSTEM_PROMPT,
            input=f"Runbook excerpts:\n\n{excerpts}\n\nQuestion: {question}",
            reasoning={"effort": "low"},
        )
        answer = resp.output_text

    sources = [{"ref": i, "source": src, "score": round(score, 3)} for i, (src, _, score) in enumerate(rows, 1)]
    return func.HttpResponse(json.dumps({"answer": answer, "sources": sources}), mimetype="application/json")

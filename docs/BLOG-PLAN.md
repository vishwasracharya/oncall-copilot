# Blog plan

One post per phase, plus a few short ones on single topics. Each post uses a diagram from `docs/diagrams/` and links back to this repo.

## Series: "Building an On-Call Copilot on Azure"

| # | Title idea | Main point | When |
|---|---|---|---|
| 0 | Why I'm learning for AI-200 by building one real app | Pick a project where every service has a job | Now |
| 1 | RAG in 6 hops: Blob → Event Grid → Service Bus → Functions → pgvector | Event-driven ingestion, with diagram + code | After Phase 1 runs |
| 2 | From alert to Slack message: Cosmos DB change feed in practice | Change feed, vector search in Cosmos DB, Redis caching | After Phase 2 |
| 3 | Same code, three hosts: Functions vs Container Apps vs AKS | KEDA scaling on queue length, the trade-offs | After Phase 3 |
| 4 | Zero secrets: Key Vault, managed identity and OpenTelemetry | Remove every password, trace one request end to end | After Phase 4 |
| 5 | What I'd tell myself before the AI-200 exam | Recap, links to each post | After the exam |

## Short posts (pick from the journey log)

- What the dead-letter queue taught me (experiment 1 in `phase-1.md`)
- Event Grid filters: the cheapest code is the code that never runs
- HNSW vs no index in pgvector: real numbers from this project
- `disableLocalAuth: true`: running Azure OpenAI with no API keys at all

## Reusable for every post

- Banner + 1–2 figures (diagrams from `docs/diagrams/`, exported as PNG from draw.io)
- A "Try it yourself" link to the README quick start
- One honest "what broke" section, taken from `JOURNEY.md`

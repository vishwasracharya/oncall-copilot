# Journey log

A short entry each time I work on this. These notes become the blog posts later.

**Template**

```
## YYYY-MM-DD · Phase N · <one-line title>
Built:
Broke:
Learned:
Exam topic:
```

---

## 2026-11-14 · Phase 0 · Picking the project

Built: Picked the idea, wrote the Phase 1 code and Bicep, and drew the diagrams.
Broke: Nothing yet. It hasn't been deployed.
Learned: AI-200 is mostly backend engineering (containers, data, messaging, security), not prompt engineering. An on-call assistant gives every service a real job.
Exam topic: All four domains, planned across 4 phases.

## 2026-11-14 · Phase 1 · First deploy: Azure said no (three times)

Built: Pushed the repo. Ran the first Bicep deployment. Storage, Event Grid, Service Bus, Functions and the Azure OpenAI account were created.
Broke:
- PostgreSQL B1ms failed with `SkuNotAvailable` in eastus2, centralindia and westus3, even though `az postgres flexible-server list-skus` listed B1ms in westus3.
- Azure OpenAI writes were blocked with `715-123420` ("unusual activity") after several retries in a short time.
- A server that fails to provision gets stuck and can't be deleted right away, and its name can't be reused in another region.
Learned:
- SKU availability depends on the region AND your subscription. New pay-as-you-go subscriptions may need a support request for PostgreSQL region access.
- Retrying a blocked deployment again and again can trigger fraud checks. Stop and open a ticket instead.
- Template fixes: a `pgLocation` parameter, a region-based Postgres name, and `openAiExists` so an existing OpenAI account is referenced instead of rewritten.
Exam topic: Bicep parameters and `existing` resources; Azure Database for PostgreSQL provisioning.
Next: Wait for the two support requests (PostgreSQL region access, OpenAI unusual-activity review), then redeploy.

## 2026-11-22 · Phase 1 · It answers! 🎉

Built: Full Phase 1 deployed. First question: "Payments API latency is above 2 seconds. What should I check?" The answer gave the right likely cause and steps, cited the payments runbook (score 0.68) and ranked the auth runbook far lower (0.38).
Broke:
- PostgreSQL: support enabled region access for East US 2, but Standard_B1ms still failed with `SkuNotAvailable`. Standard_B2s worked, so only that one size was blocked.
- Azure OpenAI's "unusual activity" flag (`715-123420`) cleared on its own after about a week. The free support request was closed as "needs a paid technical plan".
- Bicep: the pgvector setting needs `source: 'user-override'`, not `'user-defined'`. The Bicep checker can't catch this; it only fails at deploy time.
- `func publish` without a `local.settings.json` can't detect the language, so you have to pass `--python`.
Learned:
- Runbooks uploaded before the code was published waited safely in the Service Bus queue and were processed as soon as `ingest` existed. That's decoupling, seen for real.
- When a SKU is blocked, test a neighbouring size to narrow down the cause before waiting on support.
Exam topic: Service Bus as a buffer, Functions triggers, pgvector RAG, Bicep parameters.
Next: Run the hands-on experiments in `phase-1.md` (dead-letter queue, Event Grid filter, KQL).

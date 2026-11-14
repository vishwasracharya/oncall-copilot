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

# Payments API: high latency

**Alert:** p95 latency above 2 seconds for 5 minutes.

## Most likely causes

1. Database connection pool exhausted (most common, especially after a deploy)
2. Slow calls to the external card processor
3. A noisy batch job running at peak hours

## Check

1. Open the dashboard and compare latency with the database connection count. If connections are flat at the pool maximum (50), the pool is exhausted.
2. Check card processor response times. Anything above 800 ms points to the processor, not to us.
3. Check whether the nightly reconciliation job started early: `kubectl get jobs -n payments`.

## Fix

- **Pool exhausted:** restart the pods one at a time (`kubectl rollout restart deployment/payments-api -n payments`), then look for a recent deploy that leaks connections.
- **Processor slow:** turn on the `processor-fallback` feature flag and post in #payments-incidents.
- **Batch job:** pause it with `kubectl patch cronjob reconcile -n payments -p '{"spec":{"suspend":true}}'`.

## Escalate

If latency is still above 2 seconds after 20 minutes, page the Payments on-call lead.

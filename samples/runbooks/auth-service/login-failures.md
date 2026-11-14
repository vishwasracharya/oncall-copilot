# Auth service: spike in login failures

**Alert:** login failure rate above 10% for 5 minutes.

## Most likely causes

1. Expired signing certificate or client secret with the identity provider
2. Identity provider outage
3. Credential-stuffing attack (many failures from few IPs)

## Check

1. Search the logs for `invalid_client` or `AADSTS7000222`. Either one means a secret or certificate has expired.
2. Check the identity provider status page.
3. Group failures by source IP. If 5 or fewer IPs cause most of the failures, treat it as an attack.

## Fix

- **Expired secret:** rotate it in Key Vault; the service picks up the new value within 5 minutes.
- **Provider outage:** nothing to fix on our side; post a status update and watch.
- **Attack:** block the IPs at the WAF and turn on stricter rate limiting.

## Escalate

Tell the Security on-call immediately if you suspect an attack.

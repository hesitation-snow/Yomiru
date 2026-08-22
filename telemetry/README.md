# Yomiru anonymous telemetry

This Cloudflare Worker records a single anonymous first-activation event for a Yomiru installation.

It accepts only:

- a randomly generated installation identifier;
- app version, build number and platform;
- operating-system version, CPU architecture, locale and device model.

It does not accept account identifiers, login credentials, session keys, book or reading data, IP addresses, or location. The short IP-derived rate-limit key is hashed and retained only in Cloudflare Cache for five minutes; it is never written to D1.

## Deploy

The existing `yomiru-telemetry` Worker uses the `yomiru-telemetry` D1 database and the `telemetry.yutro.uk` custom domain. It requires the Worker secrets `DISCORD_WEBHOOK_URL`, `TELEMETRY_PEPPER`, and `STATS_TOKEN`. Set only missing secrets before deploying:

```bash
npx wrangler secret put DISCORD_WEBHOOK_URL
npx wrangler secret put TELEMETRY_PEPPER
npx wrangler secret put STATS_TOKEN
npx wrangler deploy
```

Never commit `.dev.vars`, Wrangler state, API tokens, or the Discord webhook.

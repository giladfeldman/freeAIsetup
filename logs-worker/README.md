# Setup log box (Cloudflare Worker + KV, free plan)

When a setup fails, the student is asked: "Send this setup report to your teacher?" On yes, the setup
report and log are sent here and the student sees a 6-letter code to tell the teacher.

- Address: `https://freeaisetup-logs.giladfel.workers.dev/upload` (POST only, write-only; nothing can be read through it).
- Before sending, the setup replaces the home folder with `~`, and the user name and computer name with `<name>`.
- Each log is deleted automatically after 180 days. Up to 1.5 MB per log.
- Cost: none. Free plan limits (100,000 requests and 1,000 stored logs a day); above that, uploads fail.
- Keys look like `2026-11-09/windows/failed/AB3XYZ` (day / platform / result / code).

Reading logs (teacher's Cloudflare login), from this folder:

```powershell
npx wrangler kv key list --binding LOGS --remote --prefix 2026-11-09/
npx wrangler kv key get "2026-11-09/mac/failed/AB3XYZ" --binding LOGS --remote
npx wrangler kv key delete "2026-11-09/mac/failed/AB3XYZ" --binding LOGS --remote
```

Deploy after a change: `npx wrangler deploy`.

## Admin alerts (email)

Each failed report also sends the teacher an alert email (admin email standard): priority, what failed,
the report key, and a button that opens a Claude Code session on it. The same failure is emailed at most
once per 24 hours (later ones are counted), at most 10 alert emails a day. A digest of everything arrives
on the 1st and 15th of each month, even when quiet (it proves the alerts still work). Code: `src/alerts.js`;
tests: `npm test` (no network).

Uploads that send the header `x-freeaisetup-env: local` (tests) are stored but not emailed. Students'
setups send no such header, so their reports count as production.

Settings (Cloudflare secrets, set once with `npx wrangler secret put <NAME>`): `ADMIN_NOTIFY_EMAIL`,
`SES_FROM`, `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY` (a send-only Amazon SES user, EU region
`SES_REGION`), `ADMIN_EMAIL_SESSION_FOLDER` (this project's folder on the teacher's computer),
`ADMIN_LOG_URL`. If a setting is missing or SES refuses, reports are still stored and the failure is recorded in `alerts/meta`
(the next digest shows it, once sending works again).
Alert status: `npx wrangler kv key get alerts/meta --binding LOGS --remote`.

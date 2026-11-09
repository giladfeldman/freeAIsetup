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

# Setup log box (Cloudflare Worker + KV, free plan)

When a setup fails, the student is asked: "Send this setup report to your teacher?" On yes, the setup
report and log are sent here and the student sees a 6-letter code to tell the teacher. Every way a setup can
stop asks this: a failed check, a stop in step 1 (old Windows, full disk, no internet, no winget), an
unexpected error, and a stop in the one-line installers themselves (no download, a failed signature or
checksum, a managed computer that forbids scripts). Ctrl+C (the student's own choice) only says how to re-run.
Installer reports carry the version `installer` when no release could be read, and `zip` from
`install-windows.cmd`.

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

## Count of successful installs

`POST /count?platform=<windows|mac|linux|codespace>&version=<pack version>` with header `x-freeaisetup: 1`
and no body. The setup sends it once per user account when a full setup ends with everything working (a
marker file, `install-counted` next to the installed pack, remembers it; `MS_NO_COUNT=1` switches it off).
It carries no name, computer details or log, and the worker stores neither the address nor the country:
one empty key per install, `stats/<environment>/<day>/<platform>/<random 8 letters>`, version in its
metadata, deleted after 400 days. One key per install (not a counter that is read and rewritten) means two
installs at the same moment cannot overwrite each other. The fortnight digest shows the period's count by
platform. Count by hand:

```powershell
npx wrangler kv key list --binding LOGS --remote --prefix stats/production/2026-11-
```

## Testing without the real log box

The setups and installers read `MS_LOG_URL` (another log box address) and `MS_LOG_ENV` (sent as
`x-freeaisetup-env`; tests send `local`). `tests/fake_logbox.py` is a local stand-in; `tests/exit-paths.ps1`
(Windows) and `tests/run-tests.ps1 -Only exits` (Mac/Linux, Docker) check that every stop offers the report
and that a success is counted once. Test hooks in the setups: `MS_TEST_FAIL_AT=precheck`,
`MS_TEST_CRASH=main|tools` (and `unbound` on Mac).

## Admin alerts (email)

Each failed report also sends the teacher an alert email (admin email standard): priority, what failed,
the report key, and a button that opens a Claude Code session on it. The same failure is emailed at most
once per 24 hours (later ones are counted), at most 10 alert emails a day. A digest of everything arrives
on the 1st and 15th of each month, even when quiet (it proves the alerts still work). Code: `src/alerts.js`;
tests: `npm test` (no network). The deploy's own confirming upload (version `DEPLOY-CHECK`) is emailed
like a student's, and its text says it is the deploy check.

Uploads that send the header `x-freeaisetup-env: local` (tests) are stored but not emailed, and their
install counts go under `stats/local/`, outside the digest. Students'
setups send no such header, so their reports count as production.

Settings (Cloudflare secrets, set once with `npx wrangler secret put <NAME>`): `ADMIN_NOTIFY_EMAIL`,
`SES_FROM`, `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY` (a send-only Amazon SES user, EU region
`SES_REGION`), `ADMIN_EMAIL_SESSION_FOLDER` (this project's folder on the teacher's computer),
`ADMIN_LOG_URL`. If a setting is missing or SES refuses, reports are still stored and the failure is recorded in `alerts/meta`
(the next digest shows it, once sending works again).
Alert status: `npx wrangler kv key get alerts/meta --binding LOGS --remote`.

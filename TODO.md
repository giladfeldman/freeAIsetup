# freeAIsetup — open issues

Open work for this project, one line per item: severity, urgency, value, size, then the issue and where it was found.

## Guide

- [ ] [HIGH · now · val:high · S · sonnet-medium] Document OpenCode free-model usage limits and a fallback order (GLM/DeepSeek/MiMo hit 'Free usage limit reached'; Nemotron still worked) (src: hackathon-2 test 2026-11-08: 12 parallel opencode runs exhausted free limit) ^d-98e4c9
- [ ] [MED · soon · val:med · S · sonnet-medium] Update guide Part 3 to OpenCode desktop 2.2.6 UI: 'Add project' (not 'Open folder'), models show a 'Free' tag (not '-free'), auto-accept switch in Settings > Preferences (src: Lectures/03-Hackathon-2-Build-simulations/TEST-RESULTS.md section 5) ^d-db5234
- [ ] [HIGH · now · val:high · S · sonnet-medium] Tell students who see the installer's code printed on screen that the line was run without its ending '| iex' (top comment of install.ps1 + walkthrough troubleshooting note); check install.sh/Mac for the same failure (src: archive/2026-11-12-08-20-studenterrorlog.txt is install.ps1 verbatim (diff identical)) ^d-4a5d64

## Windows setup

- [ ] [HIGH · soon · val:med · M · opus-medium] Quarto has no non-GitHub source when GitHub is blocked (quarto.org/download/latest redirects to GitHub; PyPI quarto-cli is an sdist that downloads from GitHub); try conda-forge mirror (Tsinghua) (src: VM case H1-github-blocked 2026-11-09) ^d-e4a52e
- [x] [HIGH · soon · val:med · M · opus-medium] pymupdf import fails (DLL load failed: _extra) in the GitHub-blocked VM case; find the missing runtime DLL (likely MSVC C++ runtime) and supply it without admin (src: VM case H1-github-blocked 2026-11-09) ^d-39f03c (fixed 2026-11-09: 6da99b1; VM exp7-msvc.ps1: copy next to pymupdf -> import ok)
- [ ] [HIGH · soon · val:high · S · sonnet-medium] Add 'gh release create' with metascience-setup.zip to the release steps so releases/latest/download link stays current (src: first Release created by hand for v2026.11.8.6 on 2026-11-09) ^d-d2924e
- [ ] [HIGH · soon · val:high · M · opus-medium] Windows: install current R next to an R older than 4.5 (winget --no-upgrade keeps the old R; packages then fail) (src: class 2026-11-09 Mac with R 4.0.0; same gap in setup-windows.ps1 Find-Tool R) ^d-872f0e
- [ ] [HIGH · now · val:high · M · opus-medium] Report installer-stage failures to the log box too: install.ps1 stops (no download, failed signature/checksum, group policy) and never reaches setup-windows.ps1, so nothing is uploaded (src: archive/2026-11-12-08-20-studenterrorlog.txt (student 2026-11-12; KV held 0 student logs)) ^d-be2fdc
- [ ] [HIGH · soon · val:high · M · opus-medium] Check the log box against the EU directive: student setup logs sit in Cloudflare KV (freeaisetup-logs), whose storage region is not pinned to the EU on the free plan as far as known; confirm, then move or document (src: logs-worker/wrangler.toml (KV namespace 68e18a10, no jurisdiction set)) ^d-d375f9
- [ ] [HIGH · now · val:high · M · opus-medium] Offer the log upload on every failing exit, not only after a full run: Precheck/pkg_manager failures exit 1 before the offer (setup-windows.ps1:777, setup-mac.sh:563-564), and a crash mid-run never reaches it; test each exit path (src: setup-windows.ps1:777, setup-mac.sh:563) ^d-03d284

## Codespaces

- [ ] [HIGH · now · val:high · M · opus-medium] Verify a real GitHub Codespace finishes setup (15 min after create: OpenCode/RStudio not running, MetaScience empty; local devcontainer passed) (src: video filming 2026-11-09, codespace zany-space-carnival (deleted)) ^d-ad15b4
- [x] [HIGH · soon · val:high · S · opus-medium] Make RStudio Server start automatically in a new Codespace (was not running after creation; manual start script worked) (src: video agent Codespace filming 2026-11-10, release 2026.11.10.2) ^d-e4e367 (fixed 2026-11-10: release 2026.11.10.4 (commit before 36fb198): fresh Codespace legendary-waddle 2026-11-10 first start - start.log shows rserver behind relay, opencode web running; built-in browser: RStudio first visit loads R 4.6.2 in /workspaces/MetaScience, OpenCode web lists GLM-5.3-Flash Free and answered 'ready')
- [x] [MED · later · val:med · M · opus-medium] Real fix for RStudio first-visit redirect to localhost:8787 in Codespaces (rewrite Location via small proxy, or RStudio option) (src: .devcontainer/start.sh; agent curl trace 2026-11-10) ^d-644df4 (fixed 2026-11-10: release 2026.11.10.4 (commit before 36fb198): fresh Codespace legendary-waddle 2026-11-10 first start - start.log shows rserver behind relay, opencode web running; built-in browser: RStudio first visit loads R 4.6.2 in /workspaces/MetaScience, OpenCode web lists GLM-5.3-Flash Free and answered 'ready')
- [x] [HIGH · soon · val:high · M · opus-medium] Fix OpenCode web in Codespaces: GET /provider?directory=/workspaces/MetaScience returns 400 through the port proxy, model list empty (src: .devcontainer/start.sh opencode web; video agent 2026-11-10) ^d-a3c2a5 (fixed 2026-11-10: release 2026.11.10.4 (commit before 36fb198): fresh Codespace legendary-waddle 2026-11-10 first start - start.log shows rserver behind relay, opencode web running; built-in browser: RStudio first visit loads R 4.6.2 in /workspaces/MetaScience, OpenCode web lists GLM-5.3-Flash Free and answered 'ready')
- [x] [HIGH · soon · val:high · M · opus-medium] RStudio in Codespaces: second visit also fails (1 of 2 worked) - needs Location rewrite proxy; revise START-HERE 'tap the globe again' text (src: d-644df4 follow-up; video agent 2026-11-10 10:52) ^d-6da8a7 (fixed 2026-11-10: release 2026.11.10.4 (commit before 36fb198): fresh Codespace legendary-waddle 2026-11-10 first start - start.log shows rserver behind relay, opencode web running; built-in browser: RStudio first visit loads R 4.6.2 in /workspaces/MetaScience, OpenCode web lists GLM-5.3-Flash Free and answered 'ready')

## Setup scripts

- [ ] [HIGH · now · val:high · M · opus-medium] Mac setup fails on Intel Macs: Homebrew installer now aborts on x86_64 (Apple Silicon only); add a non-Homebrew path or a clear early message (src: QEMU macOS 15.8.2 x86_64 run 2026-11-09; student-setup/tests/mac/04-log-apple-silicon-only.png; Homebrew install.sh lines 170-172) ^d-cce4b1

## Mac setup

- [ ] [LOW · later · val:med · S · sonnet-medium] Step 5 R packages: check each package loads (requireNamespace), not only that its folder exists (src: emulator run 2 2026-11-09 (cli/vroom missing after VM reset)) ^d-3d6237

## Windows

- [ ] [HIGH · soon · val:high · M · opus-medium] Find why the Windows Python check crashed with 0xC000070A on its first run (VM take 3, release 2026.11.10.2; re-run passed) (src: video agent take 3 film-log, setup-videos/windows/vm-film) ^d-8fb1bf

# freeAIsetup

One-step setup of a free AI research toolkit for students. No accounts and no payment needed. Built for
meta-science courses and workshops (University of Innsbruck, Hong Kong).

It installs, on Windows, Mac and Linux:
- OpenCode (an AI coding and research assistant) with free AI models
- R and RStudio, Python (via uv), Quarto, Git and Node.js
- a course folder with a real end-to-end check that uses every tool

The setup never upgrades or removes software you already have, and never changes security settings.

## Quick start

**Windows:** open PowerShell (Start menu, type `PowerShell`, press Enter), paste this line, press Enter:

```powershell
irm https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/install.ps1 | iex
```

**Mac:** open Terminal (press ⌘ Space, type `Terminal`, press Enter), paste this line, press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/install.sh | bash
```

**iPad, Chromebook, or any computer where you cannot install programs:** sign in to your own free
GitHub account, then press this button and then **Create codespace**. Everything runs in your browser.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/giladfeldman/freeAIsetup?quickstart=1)

The Codespace is a small cloud computer that GitHub builds in **your** account from the recipe in this
repository. It is free for about 60 hours a month, switches off after 30 minutes without use, and is
deleted if not opened for 30 days, so download what you hand in. Nobody else can see it.

Then follow the student guide: `guide/walkthrough.docx`. The same files are also in
`metascience-setup.zip` on the [latest release](https://github.com/giladfeldman/freeAIsetup/releases/latest).

## Video walkthroughs

Each video shows the whole setup from start to finish. Full-quality copies are on OSF:
[osf.io/yq9h5](https://osf.io/yq9h5/).

**Windows** (2:53) · [full quality on OSF](https://osf.io/yq9h5/files/6jskr)

https://github.com/user-attachments/assets/9b398de2-0615-4476-854c-4658a5ac16e7

**Mac** (2:50) · [full quality on OSF](https://osf.io/8xwg3)

https://github.com/user-attachments/assets/9605692e-bb17-4338-9d5f-c33bf67d1b87

**Codespace: in the browser, for iPad or Chromebook** (5:13) · [full quality on OSF](https://osf.io/yq9h5/files/ghe3s)

https://github.com/user-attachments/assets/c0e45b3b-1174-4725-b04a-9fc2bdf258c4

## Updates

The installed pack can keep itself up to date. The setup asks once; you can say no.
- A short daily check downloads only the files that changed and installs any newly added tools.
- Every release is signed. The pack refuses any update whose signature does not match the key it carries,
  and it never touches files you changed.
- To update by hand: `install-windows.cmd -Update` (Windows) or `bash setup-mac.sh --update` (Mac).
- To go back to the previous version: `-Rollback` / `--rollback`. To switch the daily check off:
  `-NoAutoUpdate` / `--no-auto-update`.

## Money

Everything is free, for students and teacher. Every service used charges only through a payment method, credits or a
billing account on the user's own account there; a free account without one gets an error or a wait at its limit,
never a bill. Students should never enter a card anywhere, and use a separate free account where they already pay
for a service (or, for Codespaces, set a $0 budget with "Stop usage"). The setup only uses free models; on
OpenRouter, OpenCode is limited to the `:free` models.

## Privacy

If the setup fails, it asks whether to send the setup report to the teacher. Only on yes, the report and
log go to the teacher's private log box (user name, computer name and home folder removed; deleted after
180 days). See `logs-worker/README.md`.

The free AI models may use what you type to train their models. **Never paste identifiable participant data
or anything confidential into them.**

## Status

Under active development for courses starting November 2026. More documentation will follow.

## License

GNU Affero General Public License v3.0 (AGPL-3.0); see [LICENSE](LICENSE). You may use, change and share this kit; if you share a changed version, or run it as a service for others, you must publish your changes under the same license.

Copyright (C) 2026 Gilad Feldman.

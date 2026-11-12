# freeAIsetup

One-step setup of a free AI research toolkit for students. No accounts and no payment needed. Built for
meta-science courses and workshops (University of Innsbruck, Hong Kong).

It installs, on Windows, Mac and Linux:
- OpenCode (an AI coding and research assistant) with free AI models
- R and RStudio, Python (via uv), Quarto, Git and Node.js
- a course folder with a real end-to-end check that uses every tool

The setup never upgrades or removes software you already have, and never changes security settings.
(Next to an R older than 4.5, which the course packages no longer support, it installs the current R for the
student's account and keeps the old one.)
The AI assistant is always installed; R, RStudio, Quarto, the Python course packages and Node.js are optional (the
setup asks once, and installs all of them when you press Enter).

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

## Choosing parts, disk space, and removing the setup

- **Parts:** the setup asks once which optional parts to install and remembers the answer. To choose again:
  `install-windows.cmd -Choose` (Windows) or `bash setup-mac.sh --choose` (Mac). Without asking:
  `-Components r,quarto` / `--components=r,quarto` (any of `r`, `rstudio`, `quarto`, `python`, `node`, `all`, `none`).
- **Disk space:** before installing, the setup adds up what the chosen parts that are not on the computer yet need,
  says how much it will use, stops if that plus 2 GB for the downloads is not free, and warns when less than 3 GB
  would be left. The sizes were measured on one Windows 11 computer; Mac sizes are not yet measured.
- **Removing it:** `install-windows.cmd -Uninstall` (Windows) or `bash setup-mac.sh --uninstall` (Mac), run from the
  installed pack. The setup keeps a record of what it installed itself (since November 2026); the uninstall removes
  some or all of that record and nothing else, so software that was on the computer before is never touched. The
  course folder is kept unless the student types DELETE.

## Money

Everything is free, for students and teacher. Every service used charges only through a payment method, credits or a
billing account on the user's own account there; a free account without one gets an error or a wait at its limit,
never a bill. Students should never enter a card anywhere, and use a separate free account where they already pay
for a service (or, for Codespaces, set a $0 budget with "Stop usage"). The setup only uses free models; on
OpenRouter, OpenCode is limited to the `:free` models.

## Privacy

The setup sends two kinds of messages to the teacher's private log box (a small Cloudflare service, see
`logs-worker/README.md`). Neither contains personal identifiers or personal information.

- **A count of successful installs.** When a setup finishes with everything working, it sends one message
  that says only "an install succeeded", with the platform (Windows, Mac, Linux or Codespace) and the version
  of this pack. No name, no e-mail, no computer name, no files, no log. It is sent once per user account (a
  small marker file on the computer remembers it), so re-running the setup is not counted twice. The log box
  does not store the internet address the message came from. This tells us how widely the setup is used.
  To switch it off, set the environment variable `MS_NO_COUNT=1` before running the setup.
- **Error reports, only with your yes.** If the setup or the installer stops with a problem, it asks whether
  to send the setup report to the teacher. Only on yes, the report and log go to the log box, with the user
  name, computer name and home folder removed. They are used only to find and fix setup problems, and are
  deleted automatically after 180 days. The log box also records the country the report came from (from the
  network, not an address), which helps with network blocks in some countries.

Nothing is sent without one of these two events, and nothing about your course work is ever sent.

The free AI models may use what you type to train their models. **Never paste identifiable participant data
or anything confidential into them.**

## Status

Under active development for courses starting November 2026. More documentation will follow.

<!-- license-citation:start -->
## License and citation

Copyright (C) 2026 Gilad Feldman.

This software is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0-only). You may use, study, modify and share it, including for commercial purposes, provided that the complete source code of any modified version is published under the same licence - including when the modified version is offered as a hosted online service.

**Commercial licences** without these conditions are available from the author: Gilad Feldman (https://orcid.org/0000-0003-2812-6599).

**How to cite.** If you use this software in research, please cite it. GitHub's *Cite this repository* button (from [CITATION.cff](CITATION.cff)) gives APA and BibTeX. In APA style:

> Feldman, G. (2026). *freeAIsetup* [Computer software]. https://github.com/giladfeldman/freeAIsetup

<!-- license-citation:end -->

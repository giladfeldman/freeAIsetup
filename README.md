# freeAIsetup

One-step setup of a free AI research toolkit for students. No accounts and no payment needed. Built for
meta-science courses and workshops (University of Innsbruck, Hong Kong).

It installs, on Windows, Mac and Linux:
- OpenCode (an AI coding and research assistant) with free AI models
- R and RStudio, Python (via uv), Quarto, Git and Node.js
- a course folder with a real end-to-end check that uses every tool
- optionally: the website tools (GitHub CLI, Vercel, Neon, Railway) so the AI can publish a tool as a website on
  free plans, and Codex or Claude Code for students who already pay for ChatGPT or Claude

The setup never upgrades or removes software you already have (one exception: a VS Code add-on the course uses that is older than the tested version is updated), and never changes security settings.
(Next to an R older than 4.5, which the course packages no longer support, it installs the current R (on
Windows for the student's account only) and keeps the old one. On a Mac the new R becomes the one that starts; the old one stays
in the R framework and can still be chosen.)
The AI assistant is always installed; R, RStudio, Quarto, the Python course packages, Node.js and VS Code are optional (the
setup asks once, and installs all of them when you press Enter). Then it explains three more optional parts and asks
about each one, accepting only a typed yes or no: the website tools (recommended yes), Codex and Claude Code
(recommended no, unless the student already has a ChatGPT or paid Claude plan). Unattended runs (`-Yes`, a new
Codespace) install the website tools and not Codex or Claude Code.

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

When the Codespace opens, it shows a short **Start here** page. Tap its first line, **Open the start page**: the
start page opens in its own tab (also during the first 15-25 minute setup, which it reports), with big buttons: open OpenCode in your course folder, open
RStudio, connect a free OpenRouter account by signing in (no key to copy), restart OpenCode, and see whether the AI
is ready. OpenCode's built-in free AI counts its free use per internet address, and a Codespace shares its address
with many others, so it can run out early. Once you have connected your own free account, OpenCode then switches to
a free model on that account by itself and says so in the chat. Never press **Subscribe**.

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

The installed pack updates only when you ask it to. Nothing of this setup runs on its own on your computer: no
scheduled task, no background check, no program that starts with the computer.
- An update downloads only the files that changed and installs any newly added tools.
- Setups from before 24 November 2026 added a daily update check (Windows: a task in Task Scheduler; Mac: an item
  under Login Items, shown as "bash"; Linux: a crontab line). The next run of the setup, an update or any uninstall
  removes it; so does the check itself the next time it starts, without installing anything.
- Every release is signed. The pack refuses any update whose signature does not match the key it carries,
  and it never touches files you changed.
- On Windows, a program the setup downloads straight from its maker (VS Code, R, RStudio, Quarto, Git, uv,
  OpenCode) is used only if Windows confirms it is signed by that maker; otherwise the step stops with a
  warning. On a Mac and Linux, OpenCode is used only if its download has the checksum the release was tested
  with, and uv only if it matches the checksum its source publishes; macOS's own check of each other download is
  written to the setup log, but does not yet stop the install.
- A Codespace brings its copy of the setup up to date each time it starts (only if nothing in that copy was
  changed in the Codespace), so fixes to its start page reach Codespaces made before a release.
- To update by hand: `install-windows.cmd -Update` (Windows) or `bash setup-mac.sh --update` (Mac).
- To go back to the previous version: `-Rollback` / `--rollback`. A previous version from before 24 November 2026 is
  not restored, because it would add the daily update check again; the updater says so and changes nothing. (`-NoAutoUpdate` / `--no-auto-update` are still
  accepted and do nothing: there is no automatic check to switch off.)

## Choosing parts, disk space, and removing the setup

- **Parts:** the setup asks once which optional parts to install and remembers the answer. To choose again:
  `install-windows.cmd -Choose` (Windows) or `bash setup-mac.sh --choose` (Mac). Without asking:
  `-Components r,quarto` (`-Parts` works too) / `--components=r,quarto` (`--parts=` works too) (any of `r`, `rstudio`, `quarto`, `python`, `node`, `vscode`, `web`, `codex`, `claude`, `all`, `none`).
- **VS Code** (on Windows and Mac, chosen by default): the code editor, with OpenCode's own add-on (a button at the
  top right of an open file starts OpenCode in a terminal next to the code, with the same free models), Microsoft's
  Python add-on and, when R is chosen, the R add-on (with the R package `languageserver` it needs). A VS Code that is
  already there is kept as it is and never upgraded. A `code` command counts as VS Code only if it says so (another editor, such as Cursor, also installs a `code` command; it is not taken for VS Code, and VS Code is installed next to it). Its add-ons are checked: a missing one is added, one older than
  the version the release was tested with is updated (the one exception to "never upgrades"), the rest are left alone.
  The uninstall removes only the add-ons the setup added, never one the student had, even one it updated. If VS Code
  is too old for the tested add-ons, the setup warns and says how to update VS Code. An update of the pack never adds
  VS Code to an older setup; `-Choose` / `--choose` does.
- **Disk space:** before installing, the setup adds up what the chosen parts that are not on the computer yet need,
  says how much it will use, stops if that plus 2 GB for the downloads is not free, and warns when less than 3 GB
  would be left. The sizes were measured on one Windows 11 computer; Mac sizes are not yet measured.
- **Removing it:** `install-windows.cmd -Uninstall` (Windows) or `bash setup-mac.sh --uninstall` (Mac), run from the
  installed pack. The setup keeps a record of what it installed itself (since November 2026); the uninstall removes
  some or all of that record and nothing else, so software that was on the computer before is never touched. The
  course folder is kept unless the student types DELETE; with `-Uninstall -Yes -RemoveCourse` (Windows) or
  `--uninstall --yes --remove-course` (Mac) it is deleted too, without asking. A folder the setup created and added
  to the PATH is removed once it is empty; the sign-in folders of the website tools, Codex and Claude Code are
  removed only when the setup installed that tool and the folder did not exist before.
- **Opened inside the zip (Windows):** if `install-windows.cmd` is double-clicked inside `metascience-setup.zip`
  without unpacking it, it finds the zip (Downloads, Desktop, Documents, OneDrive), unpacks it into a new folder next
  to it (never over an existing one) and starts the setup from there; if it cannot find the zip, it explains how to
  unpack it.
- **Node.js on Linux** (and on Intel Macs) comes from nodejs.org (the current 22.x, checksum-checked, in the
  student's own folder): Ubuntu's own Node.js is too old for the website tools, Codex and Claude Code. A Node.js
  already on the computer is kept as it is; when it is too old for these tools, the step says so.

## Money

Everything is free, for students and teacher. Every service used charges only through a payment method, credits or a
billing account on the user's own account there; a free account without one gets an error or a wait at its limit,
never a bill. Students should never enter a card anywhere, and use a separate free account where they already pay
for a service (or, for Codespaces, set a $0 budget with "Stop usage"). The setup only uses free models; on
OpenRouter, OpenCode is limited to the `:free` models. The optional website tools work with free plans (Vercel
Hobby, Neon Free, Railway's trial and Free plan), which pause at their limits. Codex and Claude Code are only for
students who already pay for ChatGPT or Claude; nobody needs them, and the setup recommends no. A Claude plan is used
only in Anthropic's own Claude Code: Anthropic does not allow other tools to offer Claude plan sign-in without its
approval, and OpenCode removed its earlier Claude sign-in in March 2026.

## Privacy

The setup sends two kinds of messages to the teacher's private log box (a small Cloudflare service, see
`logs-worker/README.md`). Neither contains personal identifiers or personal information. Both are stored
only in the EU (a Cloudflare store restricted to the EU); the alert e-mails to the teacher go through Amazon's
e-mail service in Ireland. The small program that receives the messages runs on Cloudflare's worldwide network.

- **The result of each setup run.** At the end of every setup run (and when the one-line installer stops), it
  sends one short message: the platform (Windows, Mac, Linux or Codespace), the pack version, the operating
  system's name and version (for example "Windows 11 Home 26100"), the processor type, whether it worked, how
  far it got, whether it was a first install, a re-run or an update, which optional parts were chosen, how many
  minutes it took, and the name of each step that failed or warned with its short reason (the user name,
  computer name and home folder removed from it, and so are a login inside an address, e-mail addresses and the
  folder names of other accounts; the log box removes those once more when the result arrives). No name, no e-mail, no computer name, no files, no log, and no
  number that would link two runs of the same computer. The log box stores neither the internet address nor the
  country. These messages are kept for 400 days and tell us which parts work on which computers.
  To switch them off, set the environment variable `MS_NO_COUNT=1` before running the setup.
- **Error reports, only with your yes.** If the setup or the installer stops with a problem, it asks whether
  to send the setup report to the teacher. Only on yes, the report and log go to the log box, with the user
  name, computer name and home folder removed (of your VS Code add-ons, only the course's are named; your own
  are only counted). They are used only to find and fix setup problems, and are
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

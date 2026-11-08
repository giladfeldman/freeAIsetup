# freeAIsetup

One-step setup of a free AI research toolkit for students. No accounts and no payment needed. Built for
meta-science courses and workshops (University of Innsbruck, Hong Kong).

It installs, on Windows, Mac and Linux:
- OpenCode (an AI coding and research assistant) with free AI models
- R and RStudio, Python (via uv), Quarto, Git and Node.js
- a course folder with a real end-to-end check that uses every tool

The setup never upgrades or removes software you already have, and never changes security settings.

## Quick start

1. Download `metascience-setup.zip` from the [latest release](https://github.com/giladfeldman/freeAIsetup/releases/latest) and unzip it.
2. **Windows:** double-click `install-windows.cmd`.
   **Mac:** in Terminal, type `bash `, drag `setup-mac.sh` into the window, and press Enter.
3. Follow the student guide: `guide/walkthrough.docx`.

## Updates

The installed pack can keep itself up to date. The setup asks once; you can say no.
- A short daily check downloads only the files that changed and installs any newly added tools.
- Every release is signed. The pack refuses any update whose signature does not match the key it carries,
  and it never touches files you changed.
- To update by hand: `install-windows.cmd -Update` (Windows) or `bash setup-mac.sh --update` (Mac).
- To go back to the previous version: `-Rollback` / `--rollback`. To switch the daily check off:
  `-NoAutoUpdate` / `--no-auto-update`.

## Privacy

The free AI models may use what you type to train their models. **Never paste identifiable participant data
or anything confidential into them.**

## Status

Under active development for courses starting November 2026. More documentation will follow.

## License

GNU Affero General Public License v3.0 (AGPL-3.0); see [LICENSE](LICENSE). You may use, change and share this kit; if you share a changed version, or run it as a service for others, you must publish your changes under the same license.

Copyright (C) 2026 Gilad Feldman.

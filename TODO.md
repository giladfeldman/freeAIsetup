# freeAIsetup — open issues

Open work for this project, one line per item: severity, urgency, value, size, then the issue and where it was found.

## Guide

- [ ] [HIGH · now · val:high · S · sonnet-medium] Document OpenCode free-model usage limits and a fallback order (GLM/DeepSeek/MiMo hit 'Free usage limit reached'; Nemotron still worked) (src: hackathon-2 test 2026-11-08: 12 parallel opencode runs exhausted free limit) ^d-98e4c9

## Windows setup

- [ ] [HIGH · soon · val:med · M · opus-medium] Quarto has no non-GitHub source when GitHub is blocked (quarto.org/download/latest redirects to GitHub; PyPI quarto-cli is an sdist that downloads from GitHub); try conda-forge mirror (Tsinghua) (src: VM case H1-github-blocked 2026-11-09) ^d-e4a52e
- [ ] [HIGH · soon · val:med · M · opus-medium] pymupdf import fails (DLL load failed: _extra) in the GitHub-blocked VM case; find the missing runtime DLL (likely MSVC C++ runtime) and supply it without admin (src: VM case H1-github-blocked 2026-11-09) ^d-39f03c

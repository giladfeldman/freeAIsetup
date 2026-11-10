---
title: "Setting up your AI research assistant"
subtitle: "Meta-science and open science course — step-by-step guide for students"
---

# What you will have at the end

- **OpenCode**: an AI assistant that can read your course files, write code, run it, and save results. It comes with free AI models. **You do not need an account or a credit card for it.**
- **R, RStudio and Python**: the analysis tools the AI uses, and that you can use yourself.
- **Quarto**: turns analyses into reports.
- A course folder called **MetaScience** in your home folder, with the course rules for the AI (`AGENTS.md`).

The setup takes **20-40 minutes**, most of it waiting. You only need to do something at a few points, marked with a hand: ✋.

## Money: everything here is free, and stays free

Nothing in this course costs money, and nothing can charge you **unless you yourself add a payment method**.
Every service used here charges only after you add a credit card, buy credits, link a billing account or
subscribe. When a free allowance runs out, you get an error message or a wait until the next day, **never a bill**.

- **Never enter a credit card, bank details or PayPal** anywhere for this course: not in OpenCode, OpenRouter,
  Groq, Google AI Studio or GitHub. Nobody from the course will ever ask you to.
- **Never click** "Upgrade", "Subscribe", "Buy credits", "Add credits", "Auto-recharge", "Go", "Extra usage" or
  "Set up billing".
- Seeing **"$0.00"**, "credits" or a dollar price next to a model on these websites is normal. It shows what the
  service *would* cost for paying customers. On a free account with no card it stays at $0.
- In OpenRouter, use only models whose name ends in **`:free`** (the setup only picks those).
- GitHub Codespaces: without a payment method on your GitHub account, a Codespace simply stops when the free
  monthly hours are used up. Do not add one.
- If a page ever asks you for payment to continue, stop and tell your teacher.

**Before you start:**

1. Plug in your laptop. Connect to the university Wi-Fi.
2. Have 8 GB of free disk space.
3. Know your laptop password (the one you use to log in).

# Part 1 — Run the setup

You copy **one line** into a window and press Enter. Nothing to download or unzip first.

*Why not a downloaded file?* Windows (Smart App Control) and macOS (Gatekeeper) block setup files that a web browser downloaded. The line below downloads the setup files itself, checks that they are the genuine, signed course files, and starts the setup.

## Windows

1. Click **Start**, type `PowerShell`, and click **Windows PowerShell**. (Not "Run as administrator".) A blue or black window opens.
2. Copy this line (select it, then Ctrl+C):

   ```
   irm https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/install.ps1 | iex
   ```

3. **Right-click** inside the PowerShell window (this pastes the line), then press **Enter**.
4. It says *"downloading the setup files"*, then *"downloaded and checked. Starting the setup"*, and shows the steps. Leave the window open.
   - ✋ **If it says *"Smart App Control is ON"*:** this Windows protection blocks parts of R and Python that the course needs. Windows Security opens by itself. Click **Smart App Control settings**, choose **Off**, confirm (Windows asks for the computer's administrator password; on a laptop owned by your employer or school, ask its IT), then go back to the PowerShell window and press **Enter**. Your normal virus protection stays on. Windows may not let you switch it back on later without a reset; if you do not want that, type **Q** and ask your teacher about the browser-only option.
   - ✋ Windows may ask *"Do you want to allow this app to make changes to your device?"* If you know your computer's admin password, click **Yes**. If you do not, click **No**: the setup then installs that tool just for your account.
5. ✋ It asks *"Keep this course pack up to date automatically?"* Press **Enter** (yes).
6. ✋ Near the end it asks *"Connect a free OpenRouter account as a backup for the AI?"* Type **y** and press Enter (or **n** to do it later, Part 3). Press Enter again at *"connect now?"*. A browser page opens: sign in with Google or GitHub and press **Allow**. The setup receives the key by itself; nothing to copy. At *"other free services too?"* press Enter (no).

## Mac

1. Open **Terminal**: press **⌘ + Space**, type `Terminal`, press Enter. A white or black window with a blinking cursor opens.
2. Copy this line (select it, then ⌘ + C):

   ```
   curl -fsSL https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/install.sh | bash
   ```

3. Click in the Terminal window, paste with **⌘ + V**, and press **Enter**.
4. ✋ When asked for a **Password**, type your Mac login password and press Enter. **Nothing appears while you type**, which is normal.
5. ✋ If a window asks to install *"command line developer tools"*, click **Install**, then **Agree**. This alone can take 10–40 minutes; the setup continues by itself afterwards. If the screen goes dark or locks meanwhile, log in again: the setup keeps running underneath.
   - ✋ If macOS asks whether *"Terminal"* may access your **Downloads** folder, click **Allow**.
   - A notice *"Background Items Added: bash"* may appear. That is the daily update check; you can ignore it.
6. ✋ It asks *"Keep this course pack up to date automatically?"* Press **Enter** (yes).
7. ✋ Near the end it asks *"Connect a free OpenRouter account as a backup for the AI?"* Type **y** and press Enter (or **n** to do it later, Part 3). Press Enter again at *"connect now?"*. A browser page opens: sign in with Google or GitHub and press **Allow**. The setup receives the key by itself; nothing to copy. At *"other free services too?"* press Enter (no).

## If GitHub is blocked (for example in mainland China)

Use these lines instead. They fetch the same signed files from jsDelivr, a public mirror:

- **Windows:** `irm https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@main/install.ps1 | iex`
- **Mac:** `curl -fsSL https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@main/install.sh | bash`

## What success looks like

At the end you see a table like this:

```
  OK    git                    git version 2.xx
  OK    uv                     uv 0.xx
  OK    Rscript                R version 4.x
  OK    quarto                 1.xx
  OK    opencode               1.19.5
  OK    AI step                free model read the article and wrote check/out/extract.csv
  OK    Python step            AI answer verified; course packages load
  OK    R step                 statcheck re-checked the reported t-test
  OK    Report step            Quarto + R rendered check/report.html
  OK    MCP tools              6 configured, all switched off

ALL CHECKS PASSED. Your computer is ready for the course.
```

This check gave the AI a real (fictional) article abstract. The AI extracted four facts. Python checked the AI's answer, R re-checked the reported t-test with **statcheck**, and Quarto made a small report. These are the same steps you will use in the course.

## If something says FAIL

1. **Run the setup again** (paste the same line again). It skips everything that already works and repairs the rest. Most problems (slow Wi-Fi, a busy server) go away on the second run.
2. **Let the AI setup helper look at it.** When something fails, the setup asks *"Start the AI setup helper?"* Press Enter. OpenCode starts in the same window with a free AI model. It reads the setup log, explains in plain words what went wrong, and suggests fixes one step at a time.
   - ✋ Before the helper runs any command, it shows you the command and asks. Choose **Allow** only if its explanation makes sense to you. If you are unsure, choose **Reject** and ask the teacher.
   - The helper never removes or upgrades software you already have, never changes security settings, and never asks for passwords or accounts.
   - To stop it, type `/exit` and press Enter. If it cannot fix the problem, it writes a note for the teacher in the folder **`MetaScience-help`** in your home folder.
3. If it still fails, show the teacher the file **`setup-report.txt`** in your MetaScience folder.
4. **"AI step" FAIL only?** The free AI may be busy. Everything else is fine. Try later with the check command below.

To start the AI helper again later:

- **Windows:** in PowerShell, paste: `& "$env:LOCALAPPDATA\MetaScience\pack\install-windows.cmd" -Fix`
- **Mac:** in Terminal, paste: `bash "$HOME/Library/Application Support/MetaScience/pack/setup-mac.sh" --fix`

**Software you already have is safe.** If R, Git or another tool is already on the computer (also when another user account installed it), the setup uses it as it is. It never upgrades or removes it.

To re-run only the check:

- **Windows:** in PowerShell, paste: `& "$env:LOCALAPPDATA\MetaScience\pack\install-windows.cmd" -Check`
- **Mac:** in Terminal, paste: `bash "$HOME/Library/Application Support/MetaScience/pack/setup-mac.sh" --check`

## Messages you may see, and what to do

| The setup says | What it means | What to do |
|---|---|---|
| *"Smart App Control blocked …"* or *"Windows protected your PC"* | You double-clicked a downloaded setup file. | Close it and use the one-line method in Part 1 instead. The setup then tells you whether Smart App Control needs to be switched off. |
| *"An Application Control policy has blocked this file"* in R or Python | Smart App Control is on and blocks a package file. | Switch it off (Windows Security > App & browser control > Smart App Control settings > Off), then run the setup line again. |
| *"This computer is managed by an organisation …"* | A school or company laptop that blocks scripts. | Use your own laptop, or ask the teacher. Do not try to get around the block. |
| *"Blocked site — github.com cannot be reached from this network"* (or another site) | Your network blocks that site. This is common in China and on some school or hotel Wi-Fi. | The setup switches to mirror sites where it can (Python, R packages, OpenCode). For the rest, connect to a phone hotspot or your VPN and run the setup again. |
| *"Proxy — Windows is set to send internet traffic through …, but nothing answers there"* | Windows/Mac is told to use a VPN or proxy app that is not running. | Start your VPN app (for example Clash or v2rayN) and run the setup again, or switch off *"Use a proxy server"* in the Windows proxy settings. |
| *"Internet access — no download site can be reached"* | No site could be reached. | Check the Wi-Fi. On a café, hotel or university network, open a web page first; you may need to log in there. |
| *"AI step … the free models refuse this network or region"* | The free AI is not offered from where you are. | Turn on your VPN and run the check again. Everything else is installed and works. |

**Using a VPN:** if your VPN app has a *TUN* or *global* mode, turn it on during the setup. Then every program uses the VPN, not only the web browser.

# Part 2 — First steps in OpenCode

1. Open **OpenCode** from the Start menu (Windows) or the Applications folder (Mac).
2. ✋ Mac only, the first time: if macOS says the app *"is downloaded from the internet"*, click **Open**.
3. Choose **Open folder** and select the **MetaScience** folder in your home folder:
   - **Windows:** `C:\Users\<your name>\MetaScience`
   - **Mac:** your home folder → `MetaScience`
4. The model shown at the bottom should end in **`-free`**. If not, click the model name and choose **GLM 5.3 Flash Free**.
5. Try your first task. Type:

   > Read check/sample-abstract.txt and tell me, with an exact quote for each, whether the study was preregistered, whether data are open, and what the sample size was.

6. Then try one that uses the tools:

   > Write an R script in analysis/ that reads check/out/extract.csv and prints it as a table. Run it and show me the output.

**Rules the AI follows** are in `AGENTS.md`. Read them. They match the course rules: never invent numbers or citations, quote the source, log what it did in `log/ai-log.md`.

# Part 3 — Optional: more free AI services

The built-in free models are enough for the course. If they are busy, you can add more free services. Each one needs a free sign-up. **Use your university email address, and never add a card (see "Money" above).**

| Service | Free allowance (Nov 2026) | Card needed? | Notes |
|---|---|---|---|
| OpenRouter | 50 requests per day on `:free` models | No | Many models in one place |
| Groq | 1,000 requests per day; 8,000 tokens per minute | No | Very fast; send excerpts, not whole papers |
| Google AI Studio (Gemini) | Free tier; limits shown in AI Studio | No | You must be 18+. Never link a billing account. On the free tier your prompts may be used by Google, so never paste personal or confidential data. |

To add keys:

- **Windows:** in PowerShell, paste: `& "$env:LOCALAPPDATA\MetaScience\pack\install-windows.cmd" -Keys`
- **Mac:** in Terminal, paste: `bash "$HOME/Library/Application Support/MetaScience/pack/setup-mac.sh" --keys`

**OpenRouter (recommended, one click):** the setup opens OpenRouter's page. Sign in with Google or GitHub and press **Allow**; the key arrives by itself. In a Codespace, OpenRouter shows a short code instead: copy it and paste it into the terminal. If OpenRouter later says it blocks free models for your account, open https://openrouter.ai/settings/privacy and allow free models.

**Other services (optional):** answer **y** to *"other free services too?"*. For each one the setup opens the sign-up page and waits. Create a key, copy it, paste it into the window (it stays hidden), and press Enter. Press Enter without pasting to skip a service.

The setup then tests each key. A key that does not answer is shown as a WARN, never as a failure of the setup.

Keys are saved only on your laptop, in your user folder (`.config/metascience/keys`). They are never inside the course folder, so you will not share them by accident.

# Part 4 — Optional: MCP tools (extra abilities for the AI)

MCP tools give the AI extra abilities. They are installed in the course settings but **switched off**, so the AI does not use them unless you decide it should. The list is in `MCP-TOOLS.txt` in your course folder.

| Tool | What it lets the AI do |
|---|---|
| `fetch` | read a web page as text |
| `markitdown` | turn a PDF, Word or Excel file into text it can read |
| `papers` | search arXiv, PubMed, Crossref, OpenAlex, Semantic Scholar, and download open papers |
| `zotero` | read your Zotero library (Zotero must be open) |
| `browser` | control a web browser: open journal pages, click, download |
| `r` | run R code inside R or RStudio |

To switch one on, open `opencode.json` in the MetaScience folder. Find the tool's name, change `"enabled": false` to `"enabled": true`, save, and restart OpenCode.

# Privacy rules

- Put only **published, public papers and course materials** into any AI.
- Never paste personal data: names of participants, grades, health information, or other people's emails.
- The free models chosen as defaults keep no data and do not train on it, but other free models may. Treat everything you type as public.

# Bonus: AI you already get as a student

These are **not required**. They are offers some of you may want to use.

**University of Innsbruck students**

- **Academic AI** (`uibk.academic-ai.at`, log in with your university account): the university's own AI chat with top models (GPT-5.x, Claude, Gemini, Mistral). It includes a **€20 monthly budget** paid by the university, and is the university's recommended, data-protection-compliant option. It is browser-only for students.
- **Microsoft Copilot** is included in the university's Microsoft 365 account.

**Any verified student**

- **GitHub Copilot for students:** free for students verified through GitHub Education (`education.github.com`). OpenCode can connect to it: in OpenCode type `/connect` and choose GitHub Copilot.

Offers change often. The teacher keeps this list updated.

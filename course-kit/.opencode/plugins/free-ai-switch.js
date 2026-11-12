// MetaScience course: switch to your own free AI account when OpenCode's free models are used up.
//
// OpenCode's built-in free models count usage per internet address (one shared count for all of them, per day).
// On a shared address (a GitHub Codespace, a big office network) that count is often used up early, and OpenCode then
// keeps retrying and offers a paid subscription. This add-on notices that refusal, stops the retrying and continues
// the same request with a free model from the student's own free account (OpenRouter, Groq, ...), saying so in the chat.
// When the free models are likely available again, new messages go back to them by themselves.
//
// Reads:  ~/.config/metascience/free-ai-fallback.json  (written by the course setup: free models that answered its test)
// Writes: ~/.local/state/metascience/free-ai-state.json (what happened, read by the Codespace start page)
// Never chooses a paid model: it only uses what the setup tested and listed, and each entry must be marked free.
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

const HOME = os.homedir()
const FALLBACK_FILE = process.env.MS_FREE_AI_FALLBACK || path.join(HOME, ".config", "metascience", "free-ai-fallback.json")
const STATE_FILE = process.env.MS_FREE_AI_STATE || path.join(HOME, ".local", "state", "metascience", "free-ai-state.json")
const FREE_LIMIT = /free usage (exceeded|limit)|FreeUsageLimitError/i
// a backup account that is itself out of free requests (OpenRouter: "free-models-per-day", 429 rate limits)
const BACKUP_LIMIT = /rate.?limit|free-models-per|quota|too many requests|429/i
const RECHECK_MS = 3 * 3600_000 // try the built-in free models again after at most 3 hours (some limits are hourly)

function readJSON(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"))
  } catch {
    return fallback
  }
}

function writeState(state) {
  try {
    fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true })
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 1))
  } catch {}
}

function nextUtcMidnight(now) {
  return Math.ceil((now + 1) / 86_400_000) * 86_400_000
}

// only entries the setup tested, marked free, and not from OpenCode's own (address-counted) free models
function fallbacks() {
  const list = readJSON(FALLBACK_FILE, [])
  return (Array.isArray(list) ? list : []).filter(
    (m) =>
      m &&
      m.free === true &&
      typeof m.providerID === "string" &&
      typeof m.modelID === "string" &&
      m.providerID !== "opencode" &&
      !/anthropic|claude/i.test(m.providerID + "/" + m.modelID) &&
      (m.providerID !== "openrouter" || m.modelID.endsWith(":free")),
  )
}

export const FreeAiSwitch = async ({ client }) => {
  let state = readJSON(STATE_FILE, {})
  const switching = new Set() // sessions being moved right now (the abort itself raises events)

  const limited = () => (state.limitedUntil || 0) > Date.now()
  const exhausted = (m) => (state.exhausted || {})[`${m.providerID}/${m.modelID}`] > Date.now()
  const pick = () => fallbacks().find((m) => !exhausted(m))

  function save(patch) {
    state = { ...state, ...patch, updated: new Date().toISOString() }
    writeState(state)
  }

  const moves = new Map() // session -> times it was moved recently: never an endless abort / re-prompt loop
  async function moveOn(sessionID, reason) {
    if (switching.has(sessionID)) return
    const now = Date.now()
    const recent = (moves.get(sessionID) || []).filter((t) => now - t < 600_000)
    if (recent.length >= 4) {
      save({ lastEvent: `${reason}; stopped switching this chat (4 switches in 10 minutes)` })
      return
    }
    moves.set(sessionID, [...recent, now])
    switching.add(sessionID)
    try {
      const to = pick()
      try {
        await client.session.abort({ path: { id: sessionID } })
      } catch {}
      if (!to) {
        save({ lastEvent: `${reason}; no free backup account is connected or all are used up` })
        return
      }
      save({ lastEvent: `${reason}; switched to ${to.name || to.modelID}`, using: to })
      const until = new Date(state.limitedUntil || Date.now()).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
      const text =
        `[Automatic note from the course setup] ${reason}. ` +
        `Continuing with ${to.name || to.providerID + "/" + to.modelID} from your own free account ` +
        `(free, no payment). The built-in free models are tried again after ${until}. ` +
        `Never press "Subscribe": the course needs no payment. Please continue with my last request.`
      await client.session.promptAsync({
        path: { id: sessionID },
        body: { model: { providerID: to.providerID, modelID: to.modelID }, parts: [{ type: "text", text }] },
      })
    } catch (e) {
      save({ lastEvent: `switch failed: ${String(e && e.message ? e.message : e).slice(0, 200)}` })
    } finally {
      setTimeout(() => switching.delete(sessionID), 5000)
    }
  }

  return {
    // every new message: while the built-in free models are used up, send it to the backup instead
    "chat.message": async (_input, output) => {
      const m = output.message && output.message.model
      if (!m) return
      if (m.providerID === "opencode" && limited()) {
        const to = pick()
        if (to) output.message.model = { ...m, providerID: to.providerID, modelID: to.modelID }
      } else if (m.providerID !== "opencode" && exhausted(m)) {
        const to = pick()
        if (to) output.message.model = { ...m, providerID: to.providerID, modelID: to.modelID }
      }
    },
    event: async ({ event }) => {
      if (!event || event.type !== "session.status") return
      const p = event.properties || {}
      const st = p.status || {}
      if (st.type !== "retry" || !p.sessionID) return
      const msg = String(st.message || "")
      if (FREE_LIMIT.test(msg) || (st.action && st.action.reason === "free_tier_limit")) {
        const now = Date.now()
        save({ limitedUntil: Math.min(nextUtcMidnight(now), now + RECHECK_MS), limitedSince: new Date(now).toISOString() })
        await moveOn(p.sessionID, "OpenCode's built-in free models are used up on this internet connection")
        return
      }
      // the backup itself is out of free requests: mark it used up until tomorrow and take the next one
      const using = state.using
      if (using && BACKUP_LIMIT.test(msg) && (st.attempt || 0) >= 2) {
        const now = Date.now()
        save({ exhausted: { ...(state.exhausted || {}), [`${using.providerID}/${using.modelID}`]: nextUtcMidnight(now) } })
        await moveOn(p.sessionID, `${using.name || using.modelID} has no free requests left today`)
      }
    },
  }
}

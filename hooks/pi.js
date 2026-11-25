// PlugLight: розширення для Pi Coding Agent (~/.pi/agent/extensions/pluglight.js)
// та Oh My Pi (~/.omp/agent/extensions/pluglight.js).
// Слухає події життєвого циклу агента й передає стан у /usr/local/bin/pluglight.
import { spawn } from "node:child_process"

const BIN = process.env.PLUGLIGHT_BIN ?? "/usr/local/bin/pluglight"

export default function (pi) {
  const fallbackId = `pi_${process.pid}`
  const pending = new Set()

  const sidOf = (event, ctx) =>
    event?.session_id ??
    event?.sessionId ??
    ctx?.sessionManager?.getSessionId?.() ??
    fallbackId

  const isSubagent = (ctx) => ctx?.agent?.kind === "sub"

  const send = (sid, state) => {
    if (!sid) return
    try {
      const p = spawn(BIN, ["hook", state, "pi"], { stdio: ["pipe", "ignore", "ignore"] })
      pending.add(p)
      p.on("error", () => pending.delete(p))
      p.on("close", () => pending.delete(p))
      p.stdin.end(JSON.stringify({ session_id: String(sid) }))
    } catch {}
  }

  pi.on("agent_start", async (event, ctx) => {
    if (!isSubagent(ctx)) send(sidOf(event, ctx), "busy")
  })

  pi.on("tool_execution_start", async (event, ctx) => {
    if (!isSubagent(ctx)) send(sidOf(event, ctx), "busy")
  })

  // Pi Coding Agent: діалоги розширень (select/confirm/input/editor/custom).
  pi.on("ui_prompt_start", async (event, ctx) => {
    if (!isSubagent(ctx)) send(sidOf(event, ctx), "waiting")
  })
  pi.on("ui_prompt_end", async (event, ctx) => {
    if (!isSubagent(ctx)) send(sidOf(event, ctx), "busy")
  })

  // Oh My Pi (OMP): запит дозволу на інструмент або перегляд плану.
  pi.on("tool_approval_requested", async (event, ctx) => {
    if (!isSubagent(ctx)) send(sidOf(event, ctx), "waiting")
  })
  pi.on("tool_approval_resolved", async (event, ctx) => {
    if (!isSubagent(ctx)) send(sidOf(event, ctx), "busy")
  })
  pi.on("plan_review_requested", async (event, ctx) => {
    if (!isSubagent(ctx)) send(sidOf(event, ctx), "waiting")
  })
  pi.on("plan_review_resolved", async (event, ctx) => {
    if (!isSubagent(ctx)) send(sidOf(event, ctx), "busy")
  })

  // Pi Coding Agent: фінальне завершення ходу після всіх повторів і стискань.
  pi.on("agent_settled", async (event, ctx) => {
    if (isSubagent(ctx)) return
    send(sidOf(event, ctx), event?.aborted ? "idle" : "done")
  })

  // Oh My Pi (OMP): завершення циклу агента (коли willContinue відсутній).
  pi.on("agent_end", async (event, ctx) => {
    if (isSubagent(ctx) || event?.willContinue) return
    const msgs = Array.isArray(event?.messages) ? event.messages : []
    const last = msgs[msgs.length - 1]
    const reason = last?.stopReason
    if (reason === "aborted") send(sidOf(event, ctx), "idle")
    else if (reason === "error") send(sidOf(event, ctx), "error")
    else send(sidOf(event, ctx), "done")
  })

  pi.on("session_shutdown", async (event, ctx) => {
    if (!isSubagent(ctx)) send(sidOf(event, ctx), "idle")
    await Promise.allSettled(
      [...pending].map((p) => new Promise((r) => p.once("close", r)))
    )
  })
}

// PlugLight: плагін Kilo Code (CLI та VS Code). Події сесії стають станами у /tmp/pluglight.
// Ставиться у ~/.config/kilo/plugin/pluglight.js; інший шлях до бінарника задає PLUGLIGHT_BIN.
const BIN = process.env.PLUGLIGHT_BIN ?? "/usr/local/bin/pluglight"

const server = async ({ $ }) => {
  const children = new Set()
  const failed = new Set()
  const asking = new Set()
  const pending = new Set()

  const send = (sessionID, state) => {
    if (!sessionID || children.has(sessionID)) return
    try {
      const json = JSON.stringify({ session_id: sessionID })
      const run = $`printf '%s' ${json} | ${BIN} hook ${state} kilo`.quiet().nothrow()
      pending.add(run)
      run.then(() => {}, () => {}).finally(() => pending.delete(run))
    } catch {}
  }

  return {
    "chat.message": async (input) => {
      failed.delete(input.sessionID)
      asking.delete(input.sessionID)
      send(input.sessionID, "busy")
    },
    "tool.execute.before": async (input) => {
      if (!asking.has(input.sessionID)) send(input.sessionID, "busy")
    },
    dispose: async () => {
      await Promise.allSettled([...pending])
    },
    event: async ({ event }) => {
      const p = event.properties ?? {}
      const id = p.sessionID ?? p.info?.id
      switch (event.type) {
        case "session.created":
          if (p.info?.parentID) children.add(id)
          break
        case "session.deleted":
          send(id, "idle")
          children.delete(id); failed.delete(id); asking.delete(id)
          break
        case "permission.asked":
        case "question.asked":
          asking.add(id)
          send(id, "waiting")
          break
        case "permission.replied":
        case "question.replied":
        case "question.rejected":
          asking.delete(id)
          send(id, "busy")
          break
        case "session.error": {
          const kind = p.error?.name
          if (kind === "ContextOverflowError") break
          failed.add(id)
          asking.delete(id)
          send(id, kind === "MessageAbortedError" ? "idle" : "error")
          break
        }
        case "session.idle":
        case "session.status":
          if (event.type === "session.idle" || p.status?.type === "idle") {
            asking.delete(id)
            if (!failed.has(id)) send(id, "done")
          } else if (!asking.has(id)) {
            send(id, "busy")
          }
          break
      }
    },
  }
}

export default { id: "pluglight", server }

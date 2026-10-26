// PlugLight: плагін OpenCode. Кожна подія сесії стає станом у /tmp/pluglight, звідки його бере помічник.
// Ставиться у ~/.config/opencode/plugins/pluglight.js; інший шлях до бінарника задає PLUGLIGHT_BIN.
//
// Подія OpenCode                                  → стан
//   chat.message (запит користувача)              → busy
//   session.status busy / retry                   → busy
//   tool.execute.before                           → busy
//   permission.asked, question.asked              → waiting
//   permission.replied, question.replied/rejected → busy
//   session.error                                 → error (MessageAbortedError — це Esc, тоді idle)
//   session.status idle, session.idle             → done, якщо в цьому ході не було помилки
//   session.deleted                               → idle
//
// У файлі має бути рівно один експорт: OpenCode вважає плагіном кожен експорт файлу.
const BIN = process.env.PLUGLIGHT_BIN ?? "/usr/local/bin/pluglight"

export const PlugLight = async ({ $ }) => {
  const children = new Set()   // сесії підагентів: їхній idle — не кінець ходу, тому про них мовчимо
  const failed = new Set()     // сесії, де цей хід уже закінчився помилкою чи перериванням
  const asking = new Set()     // сесії, що чекають відповіді: busy не має затерти waiting
  const pending = new Set()    // команди в дорозі: dispose дочекається їх, щоб «готово» не загубилось при виході

  // Стан світлодіода не вартий зламаної сесії: не чекаємо на бінарник і ковтаємо будь-яку помилку.
  // $ у Bun лінива — команда запускається лише тоді, коли до неї приєднали then або await.
  const send = (sessionID, state) => {
    if (!sessionID || children.has(sessionID)) return
    try {
      const json = JSON.stringify({ session_id: sessionID })
      const run = $`printf '%s' ${json} | ${BIN} hook ${state} opencode`.quiet().nothrow()
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
          if (kind === "ContextOverflowError") break   // далі йде автостискання, хід триває
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

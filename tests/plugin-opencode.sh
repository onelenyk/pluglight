#!/bin/sh
# Перевіряє плагін OpenCode справжнім Bun: події агента мають ставати станами у тимчасовій теці.
# Без bun тест пропускається — репозиторій від нього не залежить.
set -e
command -v bun >/dev/null 2>&1 || { echo "skip плагін OpenCode: немає bun"; exit 0; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS=$(mktemp "${TMPDIR:-/tmp}/pluglight-plugin.XXXXXX")
trap 'rm -f "$JS"' EXIT

cat > "$JS" <<'EOF'
import { $ } from "bun"
import { mkdtempSync, readFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const root = process.env.PLUGLIGHT_ROOT
const dir = mkdtempSync(join(tmpdir(), "pl-plugin-"))
process.env.PLUGLIGHT_DIR = dir
process.env.PLUGLIGHT_BIN = join(root, "build/pluglight")
const { PlugLight } = await import(join(root, "hooks/opencode.js"))
const hooks = await PlugLight({ $ })

let fail = 0
const state = (sid) => { try { return readFileSync(join(dir, sid), "utf8").trim() } catch { return "none" } }
const check = (name, got, want) => {
  if (got === want) console.log(`ok   ${name}`)
  else { console.log(`FAIL ${name}: «${got}» != «${want}»`); fail = 1 }
}
const wait = () => Bun.sleep(200)

// Основна послідовність ходу.
await hooks["chat.message"]({ sessionID: "ses_main" }); await wait()
check("запит → busy", state("ses_main"), "busy")
await hooks.event({ event: { type: "permission.asked", properties: { sessionID: "ses_main", permission: "bash" } } }); await wait()
check("дозвіл → waiting", state("ses_main"), "waiting")
await hooks.event({ event: { type: "permission.replied", properties: { sessionID: "ses_main", requestID: "r1" } } }); await wait()
check("дозвіл надано → busy", state("ses_main"), "busy")
await hooks["tool.execute.before"]({ sessionID: "ses_main", tool: "bash" }); await wait()
check("інструмент → busy", state("ses_main"), "busy")
await hooks.event({ event: { type: "session.status", properties: { sessionID: "ses_main", status: { type: "idle" } } } }); await wait()
check("кінець ходу → done", state("ses_main"), "done")

// Помилка і переривання.
await hooks.event({ event: { type: "session.error", properties: { sessionID: "ses_err", error: { name: "ApiError" } } } }); await wait()
check("помилка → error", state("ses_err"), "error")
await hooks.event({ event: { type: "session.error", properties: { sessionID: "ses_esc", error: { name: "MessageAbortedError" } } } }); await wait()
check("Esc → сесію прибрано", state("ses_esc"), "none")

// Підагент не має перебивати стан батька.
await hooks.event({ event: { type: "session.created", properties: { sessionID: "ses_child", info: { parentID: "ses_main" } } } }); await wait()
await hooks["chat.message"]({ sessionID: "ses_child" }); await wait()
check("підагент ігнорується", state("ses_child"), "none")

// busy не має затирати waiting, поки на питання не відповіли.
await hooks["chat.message"]({ sessionID: "ses_wait" }); await wait()
await hooks.event({ event: { type: "question.asked", properties: { sessionID: "ses_wait", questions: [{ question: "?" }] } } }); await wait()
await hooks.event({ event: { type: "session.status", properties: { sessionID: "ses_wait", status: { type: "busy" } } } }); await wait()
check("питання не затирається busy", state("ses_wait"), "waiting")

// Закриття сесії і вихід: черга команд доходить до кінця.
await hooks.event({ event: { type: "session.deleted", properties: { sessionID: "ses_main" } } }); await wait()
check("сесію закрито → прибрано", state("ses_main"), "none")
await hooks.dispose()

// --- Плагін Kilo Code (hooks/kilo.js) ---
const kiloMod = (await import(join(root, "hooks/kilo.js"))).default
check("kilo: id === pluglight", kiloMod.id, "pluglight")
const khooks = await kiloMod.server({ $ })
await khooks["chat.message"]({ sessionID: "kilo_1" }); await wait()
check("kilo: запит → busy", state("kilo_1"), "busy")
await khooks.event({ event: { type: "permission.asked", properties: { sessionID: "kilo_1" } } }); await wait()
check("kilo: дозвіл → waiting", state("kilo_1"), "waiting")
await khooks.event({ event: { type: "session.idle", properties: { sessionID: "kilo_1" } } }); await wait()
check("kilo: кінець ходу → done", state("kilo_1"), "done")
await khooks.event({ event: { type: "session.deleted", properties: { sessionID: "kilo_1" } } }); await wait()
check("kilo: сесію закрито → прибрано", state("kilo_1"), "none")
await khooks.dispose()

// --- Розширення Pi Coding Agent та Oh My Pi (hooks/pi.js) ---
const piExt = (await import(join(root, "hooks/pi.js"))).default
const handlers = {}
piExt({ on: (ev, fn) => { handlers[ev] = fn } })
const piCtx = { sessionManager: { getSessionId: () => "pi_ses1" }, agent: { kind: "main" } }
const subCtx = { sessionManager: { getSessionId: () => "pi_sub" }, agent: { kind: "sub" } }

await handlers.agent_start({}, piCtx); await wait()
check("pi: agent_start → busy", state("pi_ses1"), "busy")
await handlers.ui_prompt_start({}, piCtx); await wait()
check("pi: ui_prompt_start → waiting", state("pi_ses1"), "waiting")
await handlers.ui_prompt_end({}, piCtx); await wait()
check("pi: ui_prompt_end → busy", state("pi_ses1"), "busy")
await handlers.agent_settled({ aborted: false }, piCtx); await wait()
check("pi: agent_settled → done", state("pi_ses1"), "done")
await handlers.agent_settled({ aborted: true }, piCtx); await wait()
check("pi: agent_settled (aborted) → прибрано", state("pi_ses1"), "none")

// Oh My Pi події дозволів та завершення
await handlers.tool_approval_requested({ sessionId: "omp_1" }, piCtx); await wait()
check("omp: tool_approval_requested → waiting", state("omp_1"), "waiting")
await handlers.tool_approval_resolved({ sessionId: "omp_1" }, piCtx); await wait()
check("omp: tool_approval_resolved → busy", state("omp_1"), "busy")
await handlers.agent_end({ messages: [{ stopReason: "error" }] }, { sessionManager: { getSessionId: () => "omp_1" }, agent: { kind: "main" } }); await wait()
check("omp: agent_end (error) → error", state("omp_1"), "error")
await handlers.agent_start({}, subCtx); await wait()
check("omp: підагент ігнорується", state("pi_sub"), "none")
await handlers.session_shutdown({ session_id: "omp_1" }, piCtx); await wait()
check("omp: session_shutdown → прибрано", state("omp_1"), "none")

console.log(fail ? "PLUGIN FAIL" : "OK   плагіни OpenCode, Kilo Code, Pi та Oh My Pi")
process.exit(fail)
EOF
PLUGLIGHT_ROOT="$ROOT" bun "$JS"

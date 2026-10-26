#!/bin/sh
# Перевіряє плагін OpenCode справжнім Bun: події агента мають ставати станами у тимчасовій теці.
# Без bun тест пропускається — репозиторій від нього не залежить.
set -e
command -v bun >/dev/null 2>&1 || { echo "skip плагін OpenCode: немає bun"; exit 0; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS=$(mktemp -t pluglight-plugin)
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
console.log(fail ? "PLUGIN FAIL" : "OK   плагін OpenCode")
process.exit(fail)
EOF
PLUGLIGHT_ROOT="$ROOT" bun "$JS"

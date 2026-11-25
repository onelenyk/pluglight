#!/bin/sh
# Перевіряє встановлювач хуків на тимчасовому HOME: кожен агент, злиття з чужими хуками,
# повторний запуск без дублювання, remove і відмову чіпати зламаний JSON.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H=$(mktemp -d)
trap 'rm -rf "$H"' EXIT
export HOME="$H"
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# Питання до JSON ставимо через python3 — так само, як сам встановлювач, без jq.
q() { python3 -c "import json,sys
d = json.load(open(sys.argv[1]))
print(eval(sys.argv[2], {'d': d, 'json': json}))" "$1" "$2"; }
yes_() { [ "$(q "$1" "$2")" = True ] && ok "$3" || bad "$3"; }
eq_() { [ "$(q "$1" "$2")" = "$3" ] && ok "$4" || bad "$4 (маємо «$(q "$1" "$2")»)"; }

# --- Claude Code: злиття з чужим хуком, повторний запуск, remove ---
mkdir -p "$H/.claude"
printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo mine"}]}]}, "model": "opus"}\n' \
  > "$H/.claude/settings.json"
sh "$ROOT/install-hooks.sh" claude >/dev/null
eq_ "$H/.claude/settings.json" "d['model']" "opus" "claude: чужі ключі лишились"
eq_ "$H/.claude/settings.json" "sum(len(g['hooks']) for g in d['hooks']['Stop'])" "2" "claude: свій хук дописано поруч із чужим"
eq_ "$H/.claude/settings.json" "len(d['hooks'])" "13" "claude: усі події на місці"

sh "$ROOT/install-hooks.sh" claude >/dev/null
eq_ "$H/.claude/settings.json" "len(d['hooks']['UserPromptSubmit'])" "1" "claude: повторний запуск не дублює"
eq_ "$H/.claude/settings.json" "sum(len(g['hooks']) for g in d['hooks']['Stop'])" "2" "claude: чужий хук не задвоївся"
ls "$H/.claude/"settings.json.bak-pluglight-* >/dev/null 2>&1 && ok "claude: старий файл збережено" || bad "claude: немає бекапу"

# Записи старої назви проєкту (magsafe-light) теж прибираються.
python3 - "$H/.claude/settings.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["hooks"]["Stop"].append({"hooks": [{"type": "command", "command": "magsafe-light hook done"}]})
json.dump(d, open(p, "w"))
EOF
sh "$ROOT/install-hooks.sh" claude >/dev/null
eq_ "$H/.claude/settings.json" "sum('magsafe-light' in str(e) for e in d['hooks']['Stop'])" "0" "claude: записи magsafe-light прибрано"

sh "$ROOT/install-hooks.sh" claude remove >/dev/null
yes_ "$H/.claude/settings.json" "'pluglight hook' not in json.dumps(d)" "claude: remove прибрав свої записи"
eq_ "$H/.claude/settings.json" "d['hooks']['Stop'][0]['hooks'][0]['command']" "echo mine" "claude: чужий хук після remove"

# --- Codex CLI ---
mkdir -p "$H/.codex"
sh "$ROOT/install-hooks.sh" codex >/dev/null

yes_ "$H/.codex/hooks.json" "any('pluglight hook done codex' in h['command'] for g in d['hooks']['Stop'] for h in g['hooks'])" "codex: Stop → done"
yes_ "$H/.codex/hooks.json" "any('pluglight hook waiting codex' in h['command'] for g in d['hooks']['PermissionRequest'] for h in g['hooks'])" "codex: PermissionRequest → waiting"

# --- Gemini CLI: хук мусить друкувати JSON, тому в команді є echo '{}' ---
mkdir -p "$H/.gemini"
sh "$ROOT/install-hooks.sh" gemini >/dev/null
yes_ "$H/.gemini/settings.json" "all(h['command'].rstrip().endswith(\"echo '{}'\") for groups in d['hooks'].values() for g in groups for h in g['hooks'])" "gemini: кожен хук повертає {}"
yes_ "$H/.gemini/settings.json" "all(h.get('timeout') == 5000 for groups in d['hooks'].values() for g in groups for h in g['hooks'])" "gemini: timeout у мілісекундах"

# --- Cursor: свій формат, stop вирішує стан за подією ---
mkdir -p "$H/.cursor"
sh "$ROOT/install-hooks.sh" cursor >/dev/null
eq_ "$H/.cursor/hooks.json" "d['version']" "1" "cursor: version збережено"
yes_ "$H/.cursor/hooks.json" "'pluglight hook stop cursor' in d['hooks']['stop'][0]['command']" "cursor: stop → псевдостан stop"

# --- Antigravity: власний ключ, чужі ключі не чіпаємо ---
mkdir -p "$H/.gemini/config"
printf '{"other": {"keep": true}}\n' > "$H/.gemini/config/hooks.json"
sh "$ROOT/install-hooks.sh" antigravity >/dev/null
yes_ "$H/.gemini/config/hooks.json" "d['other']['keep'] is True" "antigravity: чужі ключі лишились"
yes_ "$H/.gemini/config/hooks.json" "'pluglight' in d and 'Stop' in d['pluglight'] and 'PreToolUse' in d['pluglight']" "antigravity: блок pluglight додано"
sh "$ROOT/install-hooks.sh" antigravity remove >/dev/null
yes_ "$H/.gemini/config/hooks.json" "'pluglight' not in d and d['other']['keep'] is True" "antigravity: remove прибирає лише своє"

# --- Windsurf (Cascade), Crush, Factory Droid, Auggie ---
mkdir -p "$H/.codeium/windsurf"
sh "$ROOT/install-hooks.sh" windsurf >/dev/null
yes_ "$H/.codeium/windsurf/hooks.json" "any('pluglight hook done windsurf' in h['command'] for h in d['hooks']['post_cascade_response'])" "windsurf: post_cascade_response → done"

mkdir -p "$H/.config/crush"
sh "$ROOT/install-hooks.sh" crush >/dev/null
yes_ "$H/.config/crush/crush.json" "any('pluglight hook done crush' in h['command'] for h in d['hooks']['TurnEnd'])" "crush: TurnEnd → done"
yes_ "$H/.config/crush/crush.json" "any('pluglight hook waiting crush' in h['command'] for h in d['hooks']['PermissionRequest'])" "crush: PermissionRequest → waiting"

mkdir -p "$H/.factory"
sh "$ROOT/install-hooks.sh" droid >/dev/null
yes_ "$H/.factory/settings.json" "any('pluglight hook done droid' in h['command'] for g in d['hooks']['Stop'] for h in g['hooks'])" "droid: Stop → done"

mkdir -p "$H/.augment"
sh "$ROOT/install-hooks.sh" auggie >/dev/null
yes_ "$H/.augment/settings.json" "any('pluglight hook stop auggie' in h['command'] for g in d['hooks']['Stop'] for h in g['hooks'])" "auggie: Stop → stop"

# --- Copilot CLI, Kiro, Goose, OpenCode, Kilo Code, Pi, Oh My Pi: окремі файли ---
mkdir -p "$H/.copilot/hooks"
sh "$ROOT/install-hooks.sh" copilot >/dev/null
yes_ "$H/.copilot/hooks/pluglight.json" "any('pluglight hook done copilot' in e['bash'] for e in d['hooks']['agentStop'])" "copilot: agentStop → done"

mkdir -p "$H/.kiro"
sh "$ROOT/install-hooks.sh" kiro >/dev/null
yes_ "$H/.kiro/hooks/pluglight.json" "d['version'] == 'v1' and any('pluglight hook done kiro' in h['action']['command'] for h in d['hooks'])" "kiro: v1 hooks встановлено"
sh "$ROOT/install-hooks.sh" kiro remove >/dev/null
[ ! -f "$H/.kiro/hooks/pluglight.json" ] && ok "kiro: remove видалив файл" || bad "kiro: файл лишився"

mkdir -p "$H/.config/goose"
sh "$ROOT/install-hooks.sh" goose >/dev/null
yes_ "$H/.agents/plugins/pluglight/hooks/hooks.json" "any('pluglight hook done goose' in h['command'] for g in d['hooks']['Stop'] for h in g['hooks'])" "goose: плагін Open Plugins встановлено"
yes_ "$H/.agents/plugins/pluglight/plugin.json" "d['name'] == 'pluglight'" "goose: plugin.json створено"
sh "$ROOT/install-hooks.sh" goose remove >/dev/null
[ ! -d "$H/.agents/plugins/pluglight" ] && ok "goose: remove видалив плагін" || bad "goose: плагін лишився"

mkdir -p "$H/.config/opencode/plugins"
sh "$ROOT/install-hooks.sh" opencode >/dev/null
grep -q 'export const PlugLight' "$H/.config/opencode/plugins/pluglight.js" && ok "opencode: плагін покладено" || bad "opencode: плагіна немає"
sh "$ROOT/install-hooks.sh" opencode remove >/dev/null
[ ! -f "$H/.config/opencode/plugins/pluglight.js" ] && ok "opencode: remove видалив плагін" || bad "opencode: плагін лишився"

mkdir -p "$H/.config/kilo"
sh "$ROOT/install-hooks.sh" kilo >/dev/null
grep -q 'export default { id: "pluglight"' "$H/.config/kilo/plugin/pluglight.js" && ok "kilo: плагін покладено" || bad "kilo: плагіна немає"
sh "$ROOT/install-hooks.sh" kilo remove >/dev/null
[ ! -f "$H/.config/kilo/plugin/pluglight.js" ] && ok "kilo: remove видалив плагін" || bad "kilo: плагін лишився"

mkdir -p "$H/.pi"
sh "$ROOT/install-hooks.sh" pi >/dev/null
grep -q 'pi.on("agent_start"' "$H/.pi/agent/extensions/pluglight.js" && ok "pi: розширення покладено" || bad "pi: розширення немає"
sh "$ROOT/install-hooks.sh" pi remove >/dev/null
[ ! -f "$H/.pi/agent/extensions/pluglight.js" ] && ok "pi: remove видалив розширення" || bad "pi: розширення лишилось"

mkdir -p "$H/.omp"
sh "$ROOT/install-hooks.sh" omp >/dev/null
grep -q 'pi.on("tool_approval_requested"' "$H/.omp/agent/extensions/pluglight.js" && ok "omp: розширення покладено" || bad "omp: розширення немає"
sh "$ROOT/install-hooks.sh" omp remove >/dev/null
[ ! -f "$H/.omp/agent/extensions/pluglight.js" ] && ok "omp: remove видалив розширення" || bad "omp: розширення лишилось"

# --- Cline: виконувані скрипти хуків без затирання чужих ---
mkdir -p "$H/.cline/hooks" "$H/Documents/Cline"
printf '#!/bin/sh\necho custom\n' > "$H/.cline/hooks/PreToolUse"
chmod +x "$H/.cline/hooks/PreToolUse"
sh "$ROOT/install-hooks.sh" cline >/dev/null
[ -x "$H/.cline/hooks/TaskStart" ] && [ -x "$H/Documents/Cline/Hooks/TaskComplete" ] && ok "cline: скрипти встановлено в обидві теки" || bad "cline: скрипти не встановлено"
grep -q 'custom' "$H/.cline/hooks/PreToolUse" && ok "cline: чужий скрипт не перезаписано" || bad "cline: чужий скрипт затерто"
sh "$ROOT/install-hooks.sh" cline remove >/dev/null
[ ! -f "$H/.cline/hooks/TaskStart" ] && [ ! -f "$H/Documents/Cline/Hooks/TaskComplete" ] && ok "cline: remove видалив свої скрипти" || bad "cline: скрипти лишились"
grep -q 'custom' "$H/.cline/hooks/PreToolUse" && ok "cline: чужий скрипт лишився після remove" || bad "cline: чужий скрипт видалено"

# --- all: не створює теки агентів, яких на макі немає ---
rm -rf "$H/.claude" "$H/.codex" "$H/.gemini" "$H/.cursor" "$H/.codeium" "$H/.copilot" "$H/.config" "$H/.kiro" "$H/.factory" "$H/.augment" "$H/.agents" "$H/.pi" "$H/.omp" "$H/.cline" "$H/Documents"
mkdir -p "$H/.codex" "$H/.gemini/antigravity-ide"
sh "$ROOT/install-hooks.sh" all >/dev/null
[ -f "$H/.codex/hooks.json" ] && ok "all: наявний Codex підключено" || bad "all: Codex пропущено"
[ -f "$H/.gemini/config/hooks.json" ] && ok "all: Antigravity IDE підключено" || bad "all: Antigravity IDE пропущено"
[ ! -d "$H/.cursor" ] && ok "all: відсутній Cursor не створюється" || bad "all: створив теку Cursor"

# --- all: агент є, а теки під його файл ще немає (Copilot CLI створює лише ~/.copilot) ---
rm -rf "$H/.codex" "$H/.gemini"
mkdir -p "$H/.copilot"
sh "$ROOT/install-hooks.sh" all >/dev/null
[ -f "$H/.copilot/hooks/pluglight.json" ] && ok "all: Copilot без теки hooks підключено" || bad "all: Copilot пропущено"

# --- зламаний JSON не чіпаємо ---
mkdir -p "$H/.codex"
printf '{ broken\n' > "$H/.codex/hooks.json"
before=$(cat "$H/.codex/hooks.json")
if sh "$ROOT/install-hooks.sh" codex >/dev/null 2>&1; then bad "зламаний JSON: скрипт мовчки встиг"; else ok "зламаний JSON: помилка"; fi
[ "$(cat "$H/.codex/hooks.json")" = "$before" ] && ok "зламаний JSON: файл не змінено" || bad "зламаний JSON: файл зіпсовано"

# --- невідомий агент ---
if sh "$ROOT/install-hooks.sh" nosuch >/dev/null 2>&1; then bad "невідомий агент мав бути відхилений"; else ok "невідомий агент відхилено"; fi

exit $fail

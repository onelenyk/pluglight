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
yes_ "$H/.gemini/config/hooks.json" "'pluglight' in d and 'Stop' in d['pluglight']" "antigravity: блок pluglight додано"
sh "$ROOT/install-hooks.sh" antigravity remove >/dev/null
yes_ "$H/.gemini/config/hooks.json" "'pluglight' not in d and d['other']['keep'] is True" "antigravity: remove прибирає лише своє"

# --- Copilot CLI і OpenCode: окремі файли ---
mkdir -p "$H/.copilot/hooks"
sh "$ROOT/install-hooks.sh" copilot >/dev/null
yes_ "$H/.copilot/hooks/pluglight.json" "any('pluglight hook done copilot' in e['bash'] for e in d['hooks']['agentStop'])" "copilot: agentStop → done"

mkdir -p "$H/.config/opencode/plugins"
sh "$ROOT/install-hooks.sh" opencode >/dev/null
grep -q 'export const PlugLight' "$H/.config/opencode/plugins/pluglight.js" && ok "opencode: плагін покладено" || bad "opencode: плагіна немає"
sh "$ROOT/install-hooks.sh" opencode remove >/dev/null
[ ! -f "$H/.config/opencode/plugins/pluglight.js" ] && ok "opencode: remove видалив плагін" || bad "opencode: плагін лишився"

# --- all: не створює теки агентів, яких на макі немає ---
rm -rf "$H/.claude" "$H/.codex" "$H/.gemini" "$H/.cursor" "$H/.copilot" "$H/.config"
mkdir -p "$H/.codex"
sh "$ROOT/install-hooks.sh" all >/dev/null
[ -f "$H/.codex/hooks.json" ] && ok "all: наявний Codex підключено" || bad "all: Codex пропущено"
[ ! -d "$H/.cursor" ] && ok "all: відсутній Cursor не створюється" || bad "all: створив теку Cursor"

# --- all: агент є, а теки під його файл ще немає (Copilot CLI створює лише ~/.copilot) ---
rm -rf "$H/.codex"
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

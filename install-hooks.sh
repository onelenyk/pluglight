#!/bin/sh
# Дописує хуки pluglight до налаштувань агента, не чіпаючи чужих хуків.
#   ./install-hooks.sh claude            встановити для одного агента
#   ./install-hooks.sh claude remove     прибрати свої записи
#   ./install-hooks.sh all               усі агенти, чиї налаштування вже є на цьому макі
#   ./install-hooks.sh all remove        прибрати з усіх
# Агенти: claude, codex, qwen, gemini, cursor, antigravity, copilot, opencode.
# Повторний запуск замінює свої записи, а не дублює. Стару версію файлу зберігає поруч
# як *.bak-pluglight-<час>. Для дописування в наявні налаштування потрібен python3.
set -e
cd "$(dirname "$0")"
MODE="${2:-install}"

# hooks — дописати записи в "hooks" файлу (формат Claude Code; його ж повторюють Codex, Qwen,
# Gemini і Cursor); key — власний ключ у спільному файлі (Antigravity); file — окремий файл
# агента, який перезаписуємо цілком (Copilot CLI, плагін OpenCode).
setup_agent() {
  DIR=
  case "$1" in
    claude)      FILE="$HOME/.claude/settings.json";                 HOW=hooks ;;
    codex)       FILE="$HOME/.codex/hooks.json";                     HOW=hooks ;;
    qwen)        FILE="$HOME/.qwen/settings.json";                   HOW=hooks ;;
    gemini)      FILE="$HOME/.gemini/settings.json";                 HOW=hooks ;;
    cursor)      FILE="$HOME/.cursor/hooks.json";                    HOW=hooks ;;
    antigravity) FILE="$HOME/.gemini/config/hooks.json";             HOW=key ;;
    copilot)     FILE="$HOME/.copilot/hooks/pluglight.json";         DIR="$HOME/.copilot";         HOW=file ;;
    opencode)    FILE="$HOME/.config/opencode/plugins/pluglight.js"; DIR="$HOME/.config/opencode"; HOW=file ;;
    *) return 1 ;;
  esac
  [ -n "$DIR" ] || DIR=$(dirname "$FILE")
  case "$1" in
    opencode) SRC="hooks/opencode.js" ;;
    *)        SRC="hooks/$1.json" ;;
  esac
}

one() {
  setup_agent "$1" || { echo "Usage: install-hooks.sh <agent|all> [remove]" >&2; exit 1; }
  if [ "$HOW" = file ]; then
    if [ "$MODE" = remove ]; then
      if [ -f "$FILE" ]; then rm -f "$FILE"; echo "Removed $FILE"; fi
    else
      mkdir -p "$(dirname "$FILE")"
      [ -f "$FILE" ] && cp "$FILE" "$FILE.bak-pluglight-$(date +%Y%m%d%H%M%S)"
      cp "$SRC" "$FILE"
      echo "Hooks added to $FILE. Restart the agent."
    fi
    return 0
  fi
  if [ "$MODE" = remove ] && [ ! -f "$FILE" ]; then return 0; fi
  mkdir -p "$(dirname "$FILE")"
  [ -s "$FILE" ] && cp "$FILE" "$FILE.bak-pluglight-$(date +%Y%m%d%H%M%S)"

  python3 - "$FILE" "$SRC" "$MODE" "$HOW" <<'EOF'
import json, os, sys
path, src, mode, how = sys.argv[1:]
try:
    cfg = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
    add = json.load(open(src))
except ValueError as e:
    sys.exit(f"{path}: not valid JSON, nothing changed ({e})")
# pluglight — наша назва; magsafe-light — стара назва проєкту (до 0.3.0): її записи теж прибираємо.
# Порівнюємо весь запис: у Claude-форматі команда лежить у вкладеному "hooks", у Cursor і Copilot — поруч.
mine = lambda entry: any(m in json.dumps(entry) for m in ("pluglight hook", "magsafe-light hook"))
if how == "key":
    if mode == "remove":
        cfg.pop("pluglight", None)
    else:
        cfg["pluglight"] = add["pluglight"]
else:
    hooks = cfg.setdefault("hooks", {})
    for event in list(hooks):
        hooks[event] = [g for g in hooks[event] if not mine(g)]
        if not hooks[event]:
            del hooks[event]
    if mode != "remove":
        for event, groups in add.get("hooks", {}).items():
            hooks.setdefault(event, []).extend(groups)
        for key, value in add.items():
            if key != "hooks":
                cfg.setdefault(key, value)
    if not hooks:
        cfg.pop("hooks", None)
with open(path + ".tmp", "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(path + ".tmp", path)
EOF
  if [ "$MODE" = remove ]; then echo "Hooks removed from $FILE"; else echo "Hooks added to $FILE. Restart the agent."; fi
}

if [ "$1" = all ]; then
  for a in claude codex qwen gemini cursor antigravity copilot opencode; do
    setup_agent "$a"
    [ "$MODE" = remove ] || [ -d "$DIR" ] || continue
    one "$a"
  done
else
  one "$1"
fi

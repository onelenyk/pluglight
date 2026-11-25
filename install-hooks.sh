#!/bin/sh
# Дописує хуки pluglight до налаштувань агента, не чіпаючи чужих хуків.
#   ./install-hooks.sh claude            встановити для одного агента
#   ./install-hooks.sh claude remove     прибрати свої записи
#   ./install-hooks.sh all               усі агенти, чиї налаштування вже є на цьому макі
#   ./install-hooks.sh all remove        прибрати з усіх
# Агенти: claude, codex, qwen, gemini, cursor, antigravity, windsurf, copilot, opencode,
#         kiro, crush, droid, auggie, goose, pi, omp, cline.
# Повторний запуск замінює свої записи, а не дублює. Стару версію файлу зберігає поруч
# як *.bak-pluglight-<час>. Для дописування в наявні налаштування потрібен python3.
set -e
cd "$(dirname "$0")"
MODE="${2:-install}"
ALL_AGENTS="claude codex qwen gemini cursor antigravity windsurf copilot opencode kilo kiro crush droid auggie goose pi omp cline"

# hooks — дописати записи в "hooks" файлу (формат Claude Code; його ж повторюють Codex, Qwen,
# Gemini, Cursor, Windsurf, Crush, Droid і Auggie); key — власний ключ у спільному файлі
# (Antigravity); file — окремий файл агента або плагіна, який перезаписуємо цілком
# (Copilot CLI, Kiro, OpenCode, Kilo Code, Pi, Oh My Pi); goose — плагін Open Plugins;
# cline — скрипти хуків у ~/.cline/hooks/ та ~/Documents/Cline/Hooks/.
setup_agent() {
  DIR=
  case "$1" in
    claude)      FILE="$HOME/.claude/settings.json";                              HOW=hooks ;;
    codex)       FILE="$HOME/.codex/hooks.json";                                  HOW=hooks ;;
    qwen)        FILE="$HOME/.qwen/settings.json";                                HOW=hooks ;;
    gemini)      FILE="$HOME/.gemini/settings.json";                              HOW=hooks ;;
    cursor)      FILE="$HOME/.cursor/hooks.json";                                 HOW=hooks ;;
    antigravity) FILE="$HOME/.gemini/config/hooks.json";                          HOW=key ;;
    windsurf)    FILE="$HOME/.codeium/windsurf/hooks.json";                       HOW=hooks ;;
    copilot)     FILE="$HOME/.copilot/hooks/pluglight.json";                      DIR="$HOME/.copilot";                HOW=file ;;
    opencode)    FILE="$HOME/.config/opencode/plugins/pluglight.js";              DIR="$HOME/.config/opencode";        HOW=file ;;
    kilo)        FILE="$HOME/.config/kilo/plugin/pluglight.js";                   DIR="$HOME/.config/kilo";            HOW=file ;;
    kiro)        FILE="$HOME/.kiro/hooks/pluglight.json";                         DIR="$HOME/.kiro";                   HOW=file ;;
    crush)       FILE="$HOME/.config/crush/crush.json";                           HOW=hooks ;;
    droid)       FILE="$HOME/.factory/settings.json";                             HOW=hooks ;;
    auggie)      FILE="$HOME/.augment/settings.json";                             HOW=hooks ;;
    goose)       FILE="$HOME/.agents/plugins/pluglight/hooks/hooks.json";         DIR="$HOME/.config/goose";           HOW=goose ;;
    pi)          FILE="$HOME/.pi/agent/extensions/pluglight.js";                  DIR="$HOME/.pi";                     HOW=file ;;
    omp)         FILE="$HOME/.omp/agent/extensions/pluglight.js";                 DIR="$HOME/.omp";                    HOW=file ;;
    cline)       FILE="$HOME/.cline/hooks";                                       DIR="$HOME/.cline";                  HOW=cline ;;
    *) return 1 ;;
  esac
  [ -n "$DIR" ] || DIR=$(dirname "$FILE")
  case "$1" in
    opencode) SRC="hooks/opencode.js" ;;
    kilo)     SRC="hooks/kilo.js" ;;
    pi|omp)   SRC="hooks/pi.js" ;;
    cline)    SRC="" ;;
    *)        SRC="hooks/$1.json" ;;
  esac
}

install_cline_dir() {
  target_dir="$1"
  if [ "$MODE" = remove ]; then
    [ -d "$target_dir" ] || return 0
    for ev in TaskStart TaskResume UserPromptSubmit PreToolUse PostToolUse Notification TaskComplete TaskError TaskCancel SessionShutdown; do
      f="$target_dir/$ev"
      if [ -f "$f" ] && grep -q "pluglight hook" "$f" 2>/dev/null; then
        rm -f "$f"
      fi
    done
    return 0
  fi
  mkdir -p "$target_dir"
  for pair in "TaskStart:busy" "TaskResume:busy" "UserPromptSubmit:busy" "PostToolUse:busy" "Notification:waiting" "TaskComplete:done" "TaskError:error" "TaskCancel:idle" "SessionShutdown:idle"; do
    ev=${pair%%:*}; st=${pair#*:}
    f="$target_dir/$ev"
    if [ -f "$f" ] && ! grep -q "pluglight hook" "$f" 2>/dev/null; then
      continue
    fi
    cat > "$f" <<SCRIPT
#!/bin/sh
# PlugLight hook for Cline ($ev -> $st)
/usr/local/bin/pluglight hook $st cline 2>/dev/null || true
echo '{"cancel":false}'
SCRIPT
    chmod +x "$f"
  done
}

one() {
  setup_agent "$1" || { echo "Usage: install-hooks.sh <agent|all> [remove]" >&2; exit 1; }
  if [ "$HOW" = cline ]; then
    install_cline_dir "$HOME/.cline/hooks"
    if [ "$MODE" = remove ] || [ -d "$HOME/Documents/Cline" ]; then
      install_cline_dir "$HOME/Documents/Cline/Hooks"
    fi
    if [ "$MODE" = remove ]; then echo "Hooks removed from $FILE"; else echo "Hooks added to $FILE. Restart the agent."; fi
    return 0
  fi
  if [ "$HOW" = goose ]; then
    PDIR="$(dirname "$(dirname "$FILE")")"
    if [ "$MODE" = remove ]; then
      if [ -d "$PDIR" ]; then rm -rf "$PDIR"; echo "Removed $PDIR"; fi
    else
      mkdir -p "$(dirname "$FILE")"
      [ -f "$FILE" ] && cp "$FILE" "$FILE.bak-pluglight-$(date +%Y%m%d%H%M%S)"
      cp "$SRC" "$FILE"
      cat > "$PDIR/plugin.json" <<'JSON'
{
  "name": "pluglight",
  "version": "1.0.0",
  "description": "PlugLight MagSafe LED status indicator for Goose"
}
JSON
      echo "Hooks added to $FILE. Restart the agent."
    fi
    return 0
  fi
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
# Порівнюємо весь запис: у Claude-форматі команда лежить у вкладеному "hooks", у Cursor, Windsurf, Crush і Copilot — поруч.
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

agent_present() {
  case "$1" in
    antigravity) [ -d "$HOME/.gemini/config" ] || [ -d "$HOME/.gemini/antigravity" ] || [ -d "$HOME/.gemini/antigravity-cli" ] || [ -d "$HOME/.gemini/antigravity-ide" ] ;;
    goose)       [ -d "$HOME/.config/goose" ] || [ -d "$HOME/Library/Application Support/Block/goose" ] ;;
    cline)       [ -d "$HOME/.cline" ] || [ -d "$HOME/Documents/Cline" ] ;;
    kilo)        [ -d "$HOME/.config/kilo" ] || [ -d "$HOME/.kilocode" ] ;;
    *)           setup_agent "$1" && [ -d "$DIR" ] ;;
  esac
}

if [ "$1" = all ]; then
  for a in $ALL_AGENTS; do
    [ "$MODE" = remove ] || agent_present "$a" || continue
    one "$a"
  done
else
  one "$1"
fi

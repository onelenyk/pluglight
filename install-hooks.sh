#!/bin/sh
# Дописує хуки pluglight до налаштувань агента, не чіпаючи чужих хуків.
#   ./install-hooks.sh claude          встановити (повторний запуск замінює свої записи, а не дублює)
#   ./install-hooks.sh claude remove   прибрати свої записи
# Стару версію файлу зберігає поруч як *.bak-pluglight-<час>. Потрібен python3.
set -e
cd "$(dirname "$0")"
case "$1" in
  claude) FILE="$HOME/.claude/settings.json" ;;
  *) echo "Вкажи агента: claude" >&2; exit 1 ;;
esac
SRC="hooks/$1.json"
MODE="${2:-install}"

mkdir -p "$(dirname "$FILE")"
[ -f "$FILE" ] && cp "$FILE" "$FILE.bak-pluglight-$(date +%Y%m%d%H%M%S)"

python3 - "$FILE" "$SRC" "$MODE" <<'EOF'
import json, os, sys
path, src, mode = sys.argv[1:]
cfg = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
hooks = cfg.setdefault("hooks", {})
# magsafe-light — стара назва проєкту (до 0.3.0): її хуки теж прибираємо.
mine = lambda group: any(m in h.get("command", "") for h in group.get("hooks", [])
                         for m in ("pluglight hook", "magsafe-light hook"))
for event in list(hooks):
    hooks[event] = [g for g in hooks[event] if not mine(g)]
    if not hooks[event]:
        del hooks[event]
if mode != "remove":
    for event, groups in json.load(open(src))["hooks"].items():
        hooks.setdefault(event, []).extend(groups)
if not hooks:
    del cfg["hooks"]
with open(path + ".tmp", "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(path + ".tmp", path)
EOF

[ "$MODE" = remove ] && echo "Хуки прибрано з $FILE" || echo "Хуки додано в $FILE. Перезапусти агента."

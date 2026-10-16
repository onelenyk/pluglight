#!/bin/sh
# Наскрізна перевірка зі справжнім Claude Code: запускає його в tmux у тимчасовій теці, просить
# виконати команду (з'являється запит дозволу), схвалює її, виходить — і записує, що показував світлодіод.
# Потрібні: встановлені помічник і хуки (`./install-hooks.sh claude`), tmux, claude з входом в акаунт.
# Стежить лише за своєю сесією (інші сесії Claude на цьому маку не заважають) і чекає
# послідовність станів: busy → waiting → busy → done → сесію прибрано.
set -e
S=magsafe-light-e2e
# Повний шлях і власний сокет: уже запущений tmux-сервер міг мати старий PATH.
CLAUDE=$(command -v claude)
tmux() { command tmux -L $S "$@"; }
WORK=$(mktemp -d)
LOG=$(mktemp)
trap 'tmux kill-session -t $S 2>/dev/null; kill $REC 2>/dev/null; rm -rf "$WORK" "$WORK.id" "$LOG"' EXIT

DIR="${MAGSAFE_LIGHT_DIR:-/tmp/magsafe-light}"
pane() { tmux capture-pane -p -t $S; }
# Стан нової сесії: вміст файлу, якого не було до запуску; «gone», коли він зник.
BEFORE=" $(ls "$DIR" 2>/dev/null | tr '\n' ' ') "
mine() {
  for f in $(ls "$DIR" 2>/dev/null); do
    case "$BEFORE" in *" $f "*) ;; *) echo "$f" > "$WORK.id"; cat "$DIR/$f"; return ;; esac
  done
  [ -s "$WORK.id" ] && echo gone || echo none
}
until_state() { # <стан> <секунд>
  i=0; until [ "$(mine)" = "$1" ]; do i=$((i + 1)); [ $i -gt $(($2 * 5)) ] && { echo "не дочекались стану $1"; pane | tail -20; exit 1; }; sleep 0.2; done
}
wait_for() { # <що шукати> <секунд>
  i=0; while ! pane | grep -Eq "$1"; do i=$((i + 1)); [ $i -gt $(($2 * 5)) ] && { echo "не дочекались «$1»"; pane | tail -20; exit 1; }; sleep 0.2; done
}

# Записувач: кожні 0.2 с дивиться на стан своєї сесії і пише лише зміни.
( last=; while :; do
    cur=$(mine)
    [ "$cur" != "$last" ] && echo "$(date +%T) $cur" >> "$LOG" && last=$cur
    sleep 0.2
  done ) >/dev/null 2>&1 & REC=$!

tmux new-session -d -s $S -x 160 -y 45 "cd '$WORK' && '$CLAUDE' --model haiku --permission-mode default"
# Діалог довіри до нової теки: за замовчуванням вибрано «No, exit».
wait_for "trust this folder|❯" 30
pane | grep -q "trust this folder" && { tmux send-keys -t $S Down; sleep 0.3; tmux send-keys -t $S Enter; }
wait_for "❯" 30
sleep 1
tmux send-keys -t $S "Run exactly this shell command with the Bash tool: touch hello.txt"; sleep 0.5; tmux send-keys -t $S Enter
wait_for "Do you want to proceed" 60
sleep 2
tmux send-keys -t $S Enter
i=0; while [ ! -f "$WORK/hello.txt" ]; do i=$((i + 1)); [ $i -gt 300 ] && { echo "файл не створено"; exit 1; }; sleep 0.2; done
until_state done 60
sleep 1
tmux send-keys -t $S "/exit"; sleep 0.5; tmux send-keys -t $S Enter
until_state gone 20
sleep 0.5

echo "Стани сесії:"
cat "$LOG"
got=$(cut -d' ' -f2- "$LOG" | tr '\n' '|')
want="none|busy|waiting|busy|done|gone|"
[ "$got" = "$want" ] && echo "ok   послідовність станів збігається" || { echo "FAIL чекали: $want"; exit 1; }

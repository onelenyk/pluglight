#!/bin/sh
# Перевіряє логіку станів без запису в SMC: хуки, пріоритет, прострочення, idle.
set -e
BIN="$(cd "$(dirname "$0")/.." && pwd)/build/pluglight"
export PLUGLIGHT_DIR="$(mktemp -d)"
trap 'rm -rf "$PLUGLIGHT_DIR"' EXIT
fail=0

expect() {
  got=$("$BIN" status | sed -n 's/^LED: //p')
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: чекали «$2», маємо «$got»"; fail=1; fi
}
event() { printf '{"session_id":"%s","hook_event_name":"x"}' "$1" | "$BIN" hook "$2"; }

expect "немає сесій" "macOS"
event aaa busy;          expect "працює" "orange"
event bbb done;          expect "працює важливіше за готово" "orange"
event bbb waiting;       expect "чекає" "orange, slow blink"
event aaa error;         expect "помилка найважливіша" "orange, fast blink"
event aaa idle;          expect "idle прибирає сесію" "orange, slow blink"
event bbb notification;  expect "notification = чекає" "orange, slow blink"
event bbb done;          expect "готово" "green"

touch -t 202001010000 "$PLUGLIGHT_DIR/bbb"
expect "старе «готово» прострочується" "macOS"

printf '{ "sessionId" : "x/../y" }' | "$BIN" hook busy
[ -f "$PLUGLIGHT_DIR/xy" ] && echo "ok   небезпечні символи в імені сесії відкидаються" \
  || { echo "FAIL ім'я сесії"; fail=1; }

echo 'не json' | "$BIN" hook busy
[ -f "$PLUGLIGHT_DIR/default" ] && echo "ok   без session_id — сесія default" || { echo "FAIL default"; fail=1; }

"$BIN" hook nonsense </dev/null && echo "ok   невідомий стан хук мовчки ігнорує" || { echo "FAIL hook exit"; fail=1; }

"$BIN" clear; expect "clear" "macOS"

PLUGLIGHT_PROBE_KEY=ZZZZ "$BIN" probe >/dev/null && { echo "FAIL probe знайшов неіснуючий ключ"; fail=1; } \
  || echo "ok   probe: мак без MagSafe розпізнається"
exit $fail

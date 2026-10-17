#!/bin/sh
# Перевіряє логіку станів без запису в SMC: хуки, пріоритет, прострочення, idle.
set -e
BIN="$(cd "$(dirname "$0")/.." && pwd)/build/pluglight"
export PLUGLIGHT_DIR="$(mktemp -d)"
trap 'rm -rf "$PLUGLIGHT_DIR"' EXIT
fail=0

expect() {
  got=$("$BIN" status | sed -n 's/^Світлодіод: //p')
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: чекали «$2», маємо «$got»"; fail=1; fi
}
event() { printf '{"session_id":"%s","hook_event_name":"x"}' "$1" | "$BIN" hook "$2"; }

expect "немає сесій" "керує macOS"
event aaa busy;          expect "працює" "помаранчевий"
event bbb done;          expect "працює важливіше за готово" "помаранчевий"
event bbb waiting;       expect "чекає" "помаранчевий, повільно блимає"
event aaa error;         expect "помилка найважливіша" "помаранчевий, швидко блимає"
event aaa idle;          expect "idle прибирає сесію" "помаранчевий, повільно блимає"
event bbb notification;  expect "notification = чекає" "помаранчевий, повільно блимає"
event bbb done;          expect "готово" "зелений"

touch -t 202001010000 "$PLUGLIGHT_DIR/bbb"
expect "старе «готово» прострочується" "керує macOS"

printf '{ "sessionId" : "x/../y" }' | "$BIN" hook busy
[ -f "$PLUGLIGHT_DIR/xy" ] && echo "ok   небезпечні символи в імені сесії відкидаються" \
  || { echo "FAIL ім'я сесії"; fail=1; }

echo 'не json' | "$BIN" hook busy
[ -f "$PLUGLIGHT_DIR/default" ] && echo "ok   без session_id — сесія default" || { echo "FAIL default"; fail=1; }

"$BIN" hook nonsense </dev/null && echo "ok   невідомий стан хук мовчки ігнорує" || { echo "FAIL hook exit"; fail=1; }

"$BIN" clear; expect "clear" "керує macOS"
exit $fail

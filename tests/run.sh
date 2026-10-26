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

# Інші агенти кладуть id сесії в інші поля: OpenCode — sessionId, Cursor і Gemini — conversation_id,
# Antigravity — trajectory_id.
for pair in "sessionId:oc-1" "conversation_id:cur-1" "trajectory_id:agy-1"; do
  key=${pair%%:*}; sid=${pair#*:}
  printf '{"%s":"%s"}' "$key" "$sid" | "$BIN" hook busy
  [ -f "$PLUGLIGHT_DIR/$sid" ] && echo "ok   $key → сесія $sid" || { echo "FAIL $key"; fail=1; }
done

# OpenCode з oh-my-openagent запускає хуки Claude Code зі своїм id (ses_...) і без Stop:
# таку сесію веде плагін OpenCode, тож хук із міткою claude її пропускає.
printf '{"session_id":"ses_abc"}' | "$BIN" hook busy claude
[ ! -f "$PLUGLIGHT_DIR/ses_abc" ] && echo "ok   хук claude пропускає ses_-сесію" || { echo "FAIL ses_ skip"; fail=1; }
printf '{"session_id":"ses_abc"}' | "$BIN" hook busy opencode
[ -f "$PLUGLIGHT_DIR/ses_abc" ] && echo "ok   плагін OpenCode пише ту саму сесію" || { echo "FAIL ses_ write"; fail=1; }

# Псевдостан stop: стан залежить від причини в події (Cursor — status, Antigravity — terminationReason).
stop_state() { printf '%s' "$2" | "$BIN" hook stop; cat "$PLUGLIGHT_DIR/$1" 2>/dev/null || echo gone; }
[ "$(stop_state s1 '{"conversation_id":"s1","status":"completed"}')" = done ] && echo "ok   stop: completed → готово" || { echo "FAIL stop completed"; fail=1; }
[ "$(stop_state s2 '{"conversation_id":"s2","status":"error"}')" = error ] && echo "ok   stop: error → помилка" || { echo "FAIL stop error"; fail=1; }
[ "$(stop_state s3 '{"conversation_id":"s3","status":"aborted"}')" = gone ] && echo "ok   stop: aborted → сесію прибрано" || { echo "FAIL stop aborted"; fail=1; }
[ "$(stop_state s4 '{"trajectory_id":"s4","terminationReason":"max_steps_exceeded"}')" = error ] && echo "ok   stop: ліміт кроків → помилка" || { echo "FAIL stop limit"; fail=1; }
[ "$(stop_state s5 '{"trajectory_id":"s5","terminationReason":"complete","fullyIdle":false}')" = busy ] && echo "ok   stop: фонові задачі → працює" || { echo "FAIL stop fullyIdle"; fail=1; }

"$BIN" clear; expect "clear" "macOS"

PLUGLIGHT_PROBE_KEY=ZZZZ "$BIN" probe >/dev/null && { echo "FAIL probe знайшов неіснуючий ключ"; fail=1; } \
  || echo "ok   probe: мак без MagSafe розпізнається"
exit $fail

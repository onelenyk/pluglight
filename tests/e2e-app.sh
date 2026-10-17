#!/bin/sh
# Наскрізна перевірка програми: справжні кліки по меню через System Events (потрібен дозвіл
# Accessibility для терміналу). Помічник має бути встановлений. Тест перезапускає програму
# українською (назви пунктів нижче — з uk.lproj), а наприкінці запускає її знову як зазвичай.
# Хуки Claude Code тест прибирає і ставить назад; «Запускати при вході» вмикає і повертає як було.
set -e
DIR=/tmp/pluglight
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

as() { osascript -e "tell application \"System Events\" to tell process \"PlugLight\"" -e "$1" -e "end tell"; }
items() { as 'click menu bar item 1 of menu bar 1
delay 0.3
set r to {}
repeat with i in menu items of menu 1 of menu bar item 1 of menu bar 1
  set end of r to (name of i as text) & "=" & (value of attribute "AXMenuItemMarkChar" of i as text)
end repeat
key code 53
return r'; }
click() { as "click menu bar item 1 of menu bar 1
delay 0.3
click menu item \"$1\" of menu 1 of menu bar item 1 of menu bar 1" >/dev/null; }
dismiss_alert() { sleep 0.5; as 'click button 1 of window 1' >/dev/null; }
mark() { items | tr ',' '\n' | sed -n "s/^ *$1=//p"; }

osascript -e 'quit app "PlugLight"' 2>/dev/null || true
sleep 1
open -a "PlugLight" --args -AppleLanguages '(uk)'
sleep 3
pgrep -q PlugLight || { echo "Програма не запустилась"; exit 1; }

all=$(items)
while IFS= read -r name; do
  [ -n "$name" ] || continue
  echo "$all" | grep -qF "$name=" && ok "у меню є «$name»" || bad "немає «$name»"
done <<EOF
Увімкнено
Тест світлодіода
Хуки Claude Code
Помічник
Оновлення
Запускати при вході
Про PlugLight
Вийти
EOF
echo "$all" | grep -q "Помічник не встановлено" && bad "програма не бачить помічника" || ok "помічник встановлений"

# Увімкнено: вимикання зупиняє пульс, і помічник віддає світлодіод macOS.
[ "$(mark Увімкнено)" = "✓" ] || click "Увімкнено"
click "Увімкнено"; sleep 1
[ ! -f $DIR/.app ] && ok "вимкнено: пульсу немає" || bad "вимкнено, а пульс є"
[ "$(mark Увімкнено)" != "✓" ] && ok "вимкнено: галочки немає" || bad "галочка лишилась"
click "Увімкнено"; sleep 1.5
[ -n "$(find $DIR/.app -mtime -5s 2>/dev/null)" ] && ok "увімкнено: пульс свіжий" || bad "увімкнено, а пульсу немає"

# Тест світлодіода: сесія test проходить стани.
click "Тест світлодіода"; sleep 1
[ "$(cat $DIR/test 2>/dev/null)" = busy ] && ok "тест: busy" || bad "тест не почався"
sleep 3; [ "$(cat $DIR/test 2>/dev/null)" = waiting ] && ok "тест: waiting" || bad "тест: немає waiting"
sleep 3.5; grep -qx orange-fast /var/run/pluglight.state && ok "помічник показує помилку" || bad "помічник не перемкнув світлодіод на помилку"
sleep 5.5; [ ! -f $DIR/test ] && ok "тест: сесію прибрано" || bad "тест: сесія лишилась"

# Хуки Claude Code: прибрати й поставити назад.
had=$(mark "Хуки Claude Code")
click "Хуки Claude Code"; dismiss_alert
[ "$(mark "Хуки Claude Code")" != "$had" ] && ok "хуки перемкнулись" || bad "хуки не перемкнулись"
click "Хуки Claude Code"; dismiss_alert
[ "$(mark "Хуки Claude Code")" = "$had" ] && ok "хуки повернулись як було" || bad "хуки не повернулись"

# Запускати при вході.
was=$(mark "Запускати при вході")
click "Запускати при вході"; sleep 1
if as 'exists window 1' | grep -q true; then
  bad "запуск при вході: $(as 'value of static text 2 of window 1' 2>/dev/null)"; dismiss_alert
else
  [ "$(mark "Запускати при вході")" != "$was" ] && ok "запуск при вході перемкнувся" || bad "запуск при вході не перемкнувся"
  click "Запускати при вході"; sleep 1
  [ "$(mark "Запускати при вході")" = "$was" ] && ok "запуск при вході повернувся як було" || bad "не повернувся"
fi

# Про програму.
click "Про PlugLight"; sleep 1
as 'exists window 1' | grep -q true && ok "вікно «Про програму» відкрилось" || bad "вікна «Про програму» немає"
as 'click button 1 of window 1' >/dev/null 2>&1 || true

# Вийти: процес зникає, пульс прибрано, світлодіод віддано macOS.
click "Вийти"; sleep 1.5
! pgrep -q PlugLight && ok "програма закрилась" || bad "програма не закрилась"
[ ! -f $DIR/.app ] && ok "після виходу пульсу немає" || bad "після виходу пульс лишився"
open -a "PlugLight"
exit $fail

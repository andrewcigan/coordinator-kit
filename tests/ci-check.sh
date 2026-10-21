#!/bin/bash
# Проверка на чистой машине (GitHub Actions, Mac и Windows): установка в ~/AI и запуск хуков
# теми командами, что записаны в настройках, — так, как их запускает Claude Code.
# На своём компьютере не запускать: ставит набор по-настоящему.
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$(cd "$HERE/.." && pwd)
. "$HERE/lib.sh"

case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) win=1 ;; *) win=0 ;; esac
CH=$HOME
[ "$win" = 1 ] && CH=$(cygpath -u "$USERPROFILE")
ROOT="$CH/AI"

# Команда хука из settings.json: строка с меткой → значение "command" без экранирования кавычек.
command_of() {
  grep "$2" "$1" | head -n 1 \
    | sed -E 's/^[[:space:]]*"command"[[:space:]]*:[[:space:]]*"(.*)"[[:space:]]*,?[[:space:]]*$/\1/' \
    | sed 's/\\"/"/g'
}
os_path() { if [ "$win" = 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
json_path() { local p; p=$(os_path "$1"); printf '%s' "${p//\\/\\\\}"; }

out=$(bash "$KIT/install.sh" "$(os_path "$ROOT")" 2>&1); code=$?
printf '%s\n' "$out"
expect_code 0 "$code" "установка на чистой машине: код 0"
expect_has "$out" "ГОТОВО" "установка: отчёт"
expect_has "$out" "Хук значков: подключён" "хук значков подключён"

S="$CH/.claude/settings.json"
cat "$S"
expect_json "$(cat "$S")" "~/.claude/settings.json — правильный JSON"
cmd=$(command_of "$S" coordinator-status-icon)
printf 'команда хука значков: %s\n' "$cmd"
out=$(printf '%s' '{"session_id":"s","prompt":"да","session_title":"❓ Проверка"}' | bash -c "$cmd"); code=$?
expect_code 0 "$code" "хук значков по команде из настроек: код 0"
expect_has "$out" 'take the ❓ off' "хук значков по команде из настроек: просит снять ❓"
out=$(printf '%s' '{"prompt":"да","session_title":"Без значка"}' | bash -c "$cmd")
expect_empty "$out" "хук значков: без значка молчит"

P="$ROOT/.claude/settings.json"
cat "$P"
gcmd=$(command_of "$P" guard.sh)
printf 'команда сторожа: %s\n' "$gcmd"
guard() {
  local code=0
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$(json_path "$2")" \
    | CLAUDE_PROJECT_DIR="$(os_path "$ROOT")" bash -c "$gcmd" >/dev/null 2>&1 || code=$?
  expect_code "$1" "$code" "сторож по команде из настроек: $3"
}
guard 2 "$ROOT/infra/vpn-bot/bot.py" "рабочий файл — нельзя"
guard 0 "$ROOT/infra/vpn-bot/PROJECT.md" "паспорт — можно"
guard 0 "$ROOT/PROJECTS.md" "список проектов — можно"

# Повтор установки — без дублей
bash "$KIT/install.sh" "$(os_path "$ROOT")" >/dev/null 2>&1
expect_code 1 "$(grep -c coordinator-status-icon "$S")" "повтор: хук значков один"
expect_code 1 "$(grep -c guard.sh "$P")" "повтор: сторож один"

finish

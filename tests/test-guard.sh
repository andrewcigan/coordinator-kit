#!/bin/bash
# Тесты сторожа координатора на временной главной папке. Запуск: bash tests/test-guard.sh
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/../template/.claude/hooks/guard.sh"
. "$HERE/lib.sh"

TMP=$(mktemp -d)
ROOT="$TMP/My AI"   # пробел в пути — нарочно
mkdir -p "$ROOT/.claude/hooks" "$ROOT/infra"
cp "$SRC" "$ROOT/.claude/hooks/guard.sh"
GUARD="$ROOT/.claude/hooks/guard.sh"

# check <ожидаемый код> <корень сессии> <путь файла> <описание> [инструмент]
check() {
  local tool=${5:-Write} key=file_path err code
  [ "$tool" = NotebookEdit ] && key=notebook_path
  err=$(printf '{"tool_name":"%s","tool_input":{"%s":"%s","content":"x"},"cwd":"%s"}' \
    "$tool" "$key" "$3" "$2" | CLAUDE_PROJECT_DIR="$2" bash "$GUARD" 2>&1 >/dev/null)
  code=$?
  expect_code "$1" "$code" "$4"
  [ "$1" = 2 ] && expect_has "$err" "оординатор" "$4: понятная причина"
  return 0
}

# Координатор (сессия в корне): рабочие файлы — нельзя
check 2 "$ROOT" "$ROOT/infra/vpn-bot/bot.py" "рабочий файл проекта"
check 2 "$ROOT" "$ROOT/notes.md" "файл в корне"
check 2 "$ROOT" "$HOME/Desktop/x.txt" "файл вне главной папки"
check 2 "$ROOT" "$ROOT/infra/vpn-bot/a.ipynb" "блокнот" NotebookEdit
check 2 "$ROOT" "$ROOT/infra/vpn-bot/bot.py" "правка Edit" Edit

# Координатор: свои файлы — можно
check 0 "$ROOT" "$ROOT/infra/vpn-bot/PROJECT.md" "паспорт проекта"
check 0 "$ROOT" "$ROOT/PROJECTS.md" "список проектов"
check 0 "$ROOT" "$ROOT/directions.md" "направления"
check 0 "$ROOT" "$ROOT/CLAUDE.md" "правила"
check 0 "$ROOT" "$ROOT/.claude/skills/novoe/SKILL.md" "папка .claude"
check 0 "$ROOT" "$HOME/.claude/projects/x/memory/a.md" "память Claude"
check 0 "$ROOT" "/private/tmp/claude-501/x/scratchpad/a.md" "черновики сессии"
check 0 "$ROOT" "/tmp/claude-501/x/a.md" "черновики сессии (/tmp)"
check 0 "$ROOT" "$HOME/old-bot/PROJECT.md" "паспорт существующего проекта вне главной папки"

# Обход через «..» не проходит, честные «..» работают
check 2 "$ROOT" "$ROOT/.claude/nope/../../infra/x.py" "обход через .claude/../.."
check 2 "$ROOT" "/private/tmp/claude-501/../../$ROOT/infra/x.py" "обход через черновики/../.."
check 0 "$ROOT" "$ROOT/infra/../PROJECTS.md" "честный .. к своему файлу"
check 2 "$ROOT" "$ROOT//infra/./x.py" "двойной / и ./ — всё равно рабочий файл"

# Имена папок проектов — латиница
check 2 "$ROOT" "$ROOT/infra/Бот-записи/PROJECT.md" "кириллица в имени папки"
check 2 "$ROOT" "$ROOT/infra/VpnBot/PROJECT.md" "заглавные буквы в имени папки"
check 2 "$ROOT" "$ROOT/infra/vpn bot/PROJECT.md" "пробел в имени папки"
check 0 "$ROOT" "$ROOT/agents/telegram-bot-2/PROJECT.md" "латиница, цифры, дефис"

# Сессия в папке проекта — сторож её не касается
check 0 "$ROOT/infra/vpn-bot" "$ROOT/infra/vpn-bot/bot.py" "исполнитель в подпапке"
check 0 "$HOME" "$HOME/x.py" "сессия вне главной папки"

# Без CLAUDE_PROJECT_DIR — корень берётся из cwd
code=0
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$ROOT/infra/a.py" "$ROOT" \
  | env -u CLAUDE_PROJECT_DIR bash "$GUARD" 2>/dev/null || code=$?
expect_code 2 "$code" "без CLAUDE_PROJECT_DIR — по cwd"

# Непонятный ввод — не мешать
code=0; printf 'не JSON' | CLAUDE_PROJECT_DIR="$ROOT" bash "$GUARD" 2>/dev/null || code=$?
expect_code 0 "$code" "мусор на входе — пропустить"
code=0; printf '{"tool_name":"Write","tool_input":{}}' | CLAUDE_PROJECT_DIR="$ROOT" bash "$GUARD" 2>/dev/null || code=$?
expect_code 0 "$code" "нет пути — пропустить"

# Windows: пути в виде C:\Users\… (в JSON обратная косая удвоена)
if command -v cygpath >/dev/null 2>&1; then
  wjson() { local w; w=$(cygpath -w "$1"); printf '%s' "${w//\\/\\\\}"; }
  wroot=$(cygpath -w "$ROOT")
  wcheck() {
    local code=0
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$(wjson "$2")" \
      | CLAUDE_PROJECT_DIR="$wroot" bash "$(cygpath -m "$GUARD")" >/dev/null 2>&1 || code=$?
    expect_code "$1" "$code" "Windows: $3"
  }
  wcheck 2 "$ROOT/infra/vpn-bot/bot.py" "рабочий файл"
  wcheck 0 "$ROOT/infra/vpn-bot/PROJECT.md" "паспорт"
  wcheck 0 "$ROOT/PROJECTS.md" "список проектов"
  wcheck 2 "$ROOT/infra/Бот/PROJECT.md" "кириллица в имени папки"
fi

expect_clean_file "$SRC" "сторож: без \\r и BOM"

rm -rf "$TMP"
finish

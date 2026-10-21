#!/bin/bash
# Сторож координатора — хук PreToolUse на Edit, Write и NotebookEdit.
# Подключён в .claude/settings.json главной папки, поэтому действует только на сессию,
# начатую в самом корне главной папки, то есть на координатора. Сессии в папках проектов не трогает.
# Координатор не выполняет задачи сам: он правит только паспорта PROJECT.md, PROJECTS.md,
# directions.md, CLAUDE.md и папку .claude. Всё остальное — выход 2, причина уходит Claude.
# Заодно следит, чтобы папки проектов назывались латиницей.
# Непонятный ввод — пропустить (выход 0), чтобы не мешать работе.

export LC_ALL=C

input=$(cat 2>/dev/null) || exit 0

field() {
  printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -n 1 \
    | sed -e 's/\\\//\//g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}

# Убрать из полного пути «.», «..» и двойные «/» — по тексту, чтобы «x/../..» не обошёл проверку.
normalize() {
  local IFS=/ part
  local -a parts out=()
  read -ra parts <<<"$1"
  for part in "${parts[@]}"; do
    case "$part" in
      "" | .) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset "out[$((${#out[@]} - 1))]" ;;
      *) out+=("$part") ;;
    esac
  done
  [ ${#out[@]} -gt 0 ] && printf '/%s' "${out[@]}" || printf '/'
}

# Настоящий путь (без ярлыков) даже для файла, которого ещё нет: ищем ближайшую существующую папку.
resolve() {
  local p tail=""
  p=$(normalize "$1")
  while [ -n "$p" ] && [ "$p" != "/" ] && [ ! -d "$p" ]; do
    tail="/$(basename "$p")$tail"
    p=$(dirname "$p")
  done
  printf '%s%s' "$(cd "$p" 2>/dev/null && pwd -P)" "$tail"
}

ROOT=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P) || exit 0
session=${CLAUDE_PROJECT_DIR:-$(field cwd)}
[ -n "$session" ] || exit 0
[ "$(resolve "$session")" = "$ROOT" ] || exit 0 # не координатор

path=$(field file_path)
[ -n "$path" ] || path=$(field notebook_path)
[ -n "$path" ] || exit 0
case "$path" in /*) ;; *) path="$ROOT/$path" ;; esac
path=$(resolve "$path")
home=$(resolve "$HOME")

block() { printf '%s\n' "$1" >&2; exit 2; }

if [ "$(basename "$path")" = "PROJECT.md" ]; then
  case "$path" in
    "$ROOT"/*)
      rel=${path#"$ROOT"/}
      rel=${rel%/PROJECT.md}
      if ! printf '%s' "$rel" | grep -Eq '^[a-z0-9][a-z0-9-]*(/[a-z0-9][a-z0-9-]*)*$'; then
        block "Координатор: имя папки проекта — только латиница, строчные буквы, цифры и дефис, например vpn-bot (кириллица и пробелы в пути путают историю сессий Claude). Русское название пиши внутри PROJECT.md. Сейчас: $rel"
      fi
      ;;
  esac
  exit 0
fi

case "$path" in
  "$ROOT/CLAUDE.md" | "$ROOT/PROJECTS.md" | "$ROOT/directions.md" | "$ROOT/.claude/"* | "$home/.claude/"* | /tmp/claude-* | /private/tmp/claude-*)
    exit 0
    ;;
esac

block "Координатор не выполняет задачи сам — даже мелкие. Заведи папку проекта с PROJECT.md по скиллу novoe и запусти в ней новую сессию (start_session; не вышло — дай человеку готовую фразу). Сам правишь только PROJECT.md, PROJECTS.md, directions.md, CLAUDE.md и папку .claude. Не обходи это через терминал."

#!/bin/bash
# Сторож координатора — хук PreToolUse на Edit, Write и NotebookEdit.
# Подключён в .claude/settings.json главной папки, поэтому действует только на сессию,
# начатую в самом корне главной папки, то есть на координатора. Сессии в папках проектов не трогает.
# Координатор не выполняет задачи сам: он правит только паспорта PROJECT.md, PROJECTS.md,
# directions.md, правила в корне и папку .claude, а в новом проекте заводит журналы (создать можно,
# править чужие — нет). Всё остальное — выход 2, причина уходит Claude.
# Заодно следит, чтобы НОВЫЕ папки проектов назывались латиницей; готовые папки не трогает.
# Непонятный ввод — пропустить (выход 0), чтобы не мешать работе.

# Windows (Git Bash): в локали C русские имена файлов в путях портятся (cygpath, -d, cd) — нужна UTF-8.
if command -v cygpath >/dev/null 2>&1; then export LC_ALL=C.UTF-8; else export LC_ALL=C; fi

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
  local dir
  dir=$(cd "$p" 2>/dev/null && pwd -P)
  [ "$dir" = / ] && dir=""
  [ -n "$dir$tail" ] && printf '%s%s' "$dir" "$tail" || printf '/'
}

# Windows (Git Bash): пути приходят в виде C:\Users\… — переводим в /c/Users/…
topath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}

ROOT=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P) || exit 0
session=${CLAUDE_PROJECT_DIR:-$(field cwd)}
[ -n "$session" ] || exit 0
session=$(topath "$session")
[ "$(resolve "$session")" = "$ROOT" ] || exit 0 # не координатор

path=$(field file_path)
[ -n "$path" ] || path=$(field notebook_path)
[ -n "$path" ] || exit 0
path=$(topath "$path")
case "$path" in /*) ;; *) path="$ROOT/$path" ;; esac
path=$(resolve "$path")
home=$(resolve "$(topath "${USERPROFILE:-$HOME}")") # где Claude Code держит ~/.claude (на Windows — профиль)
tmp=$(resolve /tmp)                                  # черновики сессий; на Windows /tmp — это папка Temp

block() { printf '%s\n' "$1" >&2; exit 2; }

# Новая папка внутри главной — имя латиницей. Папка уже есть — имя не проверяем.
latin_or_block() {
  local dir rel
  dir=$(dirname "$path")
  [ -d "$dir" ] && return 0
  case "$dir" in "$ROOT"/*) ;; *) return 0 ;; esac
  rel=${dir#"$ROOT"/}
  printf '%s' "$rel" | tail -c 200 | sed 's#.*/##' | grep -Eq '^[a-z0-9][a-z0-9-]*$' && return 0
  block "Координатор: имя новой папки проекта — только латиница, строчные буквы, цифры и дефис, например vpn-bot. Русское название пиши внутри PROJECT.md. Сейчас: $rel"
}

name=$(basename "$path")
if [ "$name" = "PROJECT.md" ]; then
  latin_or_block
  exit 0
fi

# Журналы нового проекта: создать можно, менять готовые — дело сессии проекта.
case "$name" in
  "ХОД.md" | "РЕШЕНИЯ.md" | "ФИЧИ.md" | "ОБРАТНАЯ-СВЯЗЬ.md" | AGENTS.md | CLAUDE.md | .gitignore)
    case "$(dirname "$path")" in
      "$ROOT") ;;
      "$ROOT"/*)
        if [ ! -s "$path" ]; then # нет файла или он пустой
          latin_or_block
          exit 0
        fi
        ;;
    esac
    ;;
esac

case "$path" in
  "$ROOT/CLAUDE.md" | "$ROOT/AGENTS.md" | "$ROOT/PROJECTS.md" | "$ROOT/directions.md" | "$ROOT/.claude/"* | "$home/.claude/"* | "$tmp"/claude-* | /tmp/claude-* | /private/tmp/claude-*)
    exit 0
    ;;
esac

block "Координатор не выполняет задачи сам — даже мелкие. Запусти сессию в папке проекта по скиллу novoe (start_session; не вышло — дай человеку готовую фразу). Сам правишь только PROJECT.md, PROJECTS.md, directions.md, правила в корне и папку .claude; журналы заводишь только в новом проекте. Не обходи это через терминал."

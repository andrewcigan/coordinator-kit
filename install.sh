#!/bin/bash
# Установщик набора «Координатор».   bash install.sh <главная папка> [znachki]
# Mac — в Терминале или сессии Claude; Windows — в Git Bash (ставится вместе с Git for Windows).
#
# 1. Проверяет свои хуки на тестовых примерах — если что-то не так, ничего не меняет.
# 2. Кладёт шаблон в главную папку. Существующие файлы не перезаписывает: CLAUDE.md дополняет
#    между метками, .claude/settings.json дописывает, остальное пропускает и называет.
# 3. Только с «znachki»: хук-напоминание о значках в ~/.claude (с копией настроек).
#    Без него личные настройки человека не меняются вовсе.
# 4. Проверяет поставленное и печатает отчёт.
# Повторный запуск безопасен.

KIT=$(cd "$(dirname "$0")" && pwd)
MARK_BEGIN="<!-- coordinator-kit: начало -->"
MARK_END="<!-- coordinator-kit: конец -->"
MARK_VERSION="<!-- coordinator-kit: версия 2026-11-26 -->"
problems=0

say() { printf '%s\n' "$*"; }
problem() { problems=$((problems + 1)); say "ОШИБКА: $*"; }

case "$(uname -s)" in
  Darwin) os=mac ;;
  MINGW* | MSYS* | CYGWIN*) os=win ;;
  *) os=other ;;
esac

ROOT=$1
[ "$os" = win ] && [ -n "$ROOT" ] && ROOT=$(cygpath -u "$ROOT")
ROOT=${ROOT%/}
case "$ROOT" in
  "") say "Нужна главная папка: bash install.sh <папка>"; exit 2 ;;
  /*) ;;
  *) say "Главная папка — полный путь, например $HOME/AI"; exit 2 ;;
esac

# Домашняя папка, где Claude Code держит свои настройки (на Windows — профиль пользователя).
CLAUDE_HOME=$HOME
[ "$os" = win ] && [ -n "$USERPROFILE" ] && CLAUDE_HOME=$(cygpath -u "$USERPROFILE")
HOOK_DST="$CLAUDE_HOME/.claude/hooks/coordinator-status-icon.sh"

mkdir -p "$ROOT" || { say "Не могу создать $ROOT"; exit 2; }
ROOT=$(cd "$ROOT" && pwd -P)
if [ "$ROOT" = "$(cd "$CLAUDE_HOME" 2>/dev/null && pwd -P)" ] || [ "$ROOT" = "/" ]; then
  say "Главная папка не может быть домашней папкой целиком — возьмите отдельную, например $CLAUDE_HOME/AI"
  exit 2
fi

# 1. Самопроверка до любых изменений
if ! bash "$KIT/tests/test-status-icon.sh" "$KIT/user/hooks/status-icon.sh" >/dev/null 2>&1 \
  || ! bash "$KIT/tests/test-guard.sh" >/dev/null 2>&1; then
  say "ОШИБКА: хуки не прошли самопроверку — ничего не меняю. Подробности: bash $KIT/tests/run.sh"
  exit 1
fi
say "Самопроверка хуков: ок"

# Настройки главной папки: на Windows команда сторожа — с полным путём (переменная там в виде C:\…).
PATCH="$KIT/template/.claude/settings.json"
if [ "$os" = win ]; then
  PATCH=$(mktemp)
  win_root=$(cygpath -m "$ROOT")
  sed "s#\$CLAUDE_PROJECT_DIR#$win_root#" "$KIT/template/.claude/settings.json" >"$PATCH"
fi

# Главная папка внутри другой главной папки: правил координатора было бы два.
up=$(dirname "$ROOT")
while [ -n "$up" ] && [ "$up" != "/" ] && [ "$up" != "." ]; do
  if grep -qF "$MARK_BEGIN" "$up/CLAUDE.md" 2>/dev/null; then
    say "Эта папка лежит внутри папки, где координатор уже стоит: $up. Ничего не меняю: поставьте набор в неё или перенесите папку рядом."
    exit 2
  fi
  up=$(dirname "$up")
done

# Раздел набора в CLAUDE.md: метки — ровно одна пара и по порядку, иначе не трогаем.
C="$ROOT/CLAUDE.md"
had_rules=0
had_version=0
if grep -qF -e "$MARK_BEGIN" -e "$MARK_END" "$C" 2>/dev/null; then
  b=$(grep -nF "$MARK_BEGIN" "$C" | cut -d: -f1)
  e=$(grep -nF "$MARK_END" "$C" | cut -d: -f1)
  case "$b:$e" in
    *[!0-9:]* | :* | *:) bad_marks=1 ;;
    *) [ "$b" -lt "$e" ] && bad_marks=0 || bad_marks=1 ;;
  esac
  if [ "$bad_marks" = 1 ]; then
    say "ОШИБКА: метки набора в CLAUDE.md стоят не парой — ничего не меняю. Уберите старый раздел координатора и запустите снова."
    exit 1
  fi
  had_rules=1
  grep -qF "$MARK_VERSION" "$C" && had_version=1
fi
BAK="$ROOT/.claude/coordinator-kit-bak-$(date +%Y%m%d-%H%M%S)"

# Правила набора — между метками. Версию дописываем последней и только без ошибок (шаг 4).
rules_block() {
  printf '%s\n' "$MARK_BEGIN"
  cat "$KIT/template/CLAUDE.md"
  printf '%s\n' "$MARK_END"
}

backup() { mkdir -p "$BAK" && cp "$1" "$BAK/$(basename "$1")"; }

# Файл из нашего набора (любой версии) узнаём по первой строке роли.
ours() {
  case "$1" in
    */guard.sh) grep -qF "Сторож координатора" "$1" ;;
    */SKILL.md) grep -qF "Ты координатор" "$1" && grep -qF "directions.md" "$1" ;;
    *) false ;;
  esac
}

# Строки человека внутри прежнего раздела: всё, чего нет ни в старых, ни в новых правилах набора.
own_lines() {
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" 'index($0, b) { f = 1; next } index($0, e) { f = 0 } f' "$C" \
    | tr -d '\r' | grep -vF "coordinator-kit: версия" | grep -v '^[[:space:]]*$' \
    | grep -vxFf "$KIT/lib/old-rules-2026-10-22.md" | grep -vxFf "$KIT/template/CLAUDE.md"
}

# 2. Шаблон в главную папку
skipped=""
updated=""
cd "$KIT/template" || exit 1
while IFS= read -r f; do
  f=${f#./}
  dst="$ROOT/$f"
  src=$f
  case "$f" in
    */.gitkeep) mkdir -p "$(dirname "$dst")"; continue ;;
    .claude/settings.json)
      [ "$os" = other ] && { say "Эта система не Mac и не Windows: сторож координатора не подключён (правило в CLAUDE.md остаётся)"; continue; }
      src=$PATCH
      ;;
  esac
  if [ ! -e "$dst" ]; then
    mkdir -p "$(dirname "$dst")" || problem "не создал папку для $f"
    if [ "$f" = CLAUDE.md ]; then
      rules_block >"$dst" || problem "не скопировал $f"
    else
      cp "$src" "$dst" || problem "не скопировал $f"
    fi
    continue
  fi
  case "$f" in
    CLAUDE.md)
      if [ "$had_version" = 1 ]; then
        skipped="$skipped CLAUDE.md(уже есть)"
      elif [ "$had_rules" = 1 ]; then
        own=$(own_lines)
        new=$(RULES="$(rules_block)" awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
          index($0, b) && !seen { print ENVIRON["RULES"]; seen = 1; skip = 1 }
          !skip { print }
          skip && index($0, e) { skip = 0 }' "$C")
        [ -n "$own" ] && new=$(printf '%s\n\n## Мои правила координатору\n\n%s' "$new" "$own")
        case "$new" in
          *"$MARK_BEGIN"*"ты координатор"*"$MARK_END"*)
            backup "$C" && printf '%s\n' "$new" >"$C" && updated="$updated CLAUDE.md" || problem "не обновил CLAUDE.md" ;;
          *) problem "не обновил правила в CLAUDE.md" ;;
        esac
        [ -n "$own" ] && say "Ваши строки из прежнего раздела перенесены в конец CLAUDE.md"
      else
        { printf '\n'; rules_block; } >>"$dst" \
          && say "CLAUDE.md уже был — правила координатора дописаны в конец между метками" \
          || problem "не дописал CLAUDE.md"
      fi
      ;;
    .claude/settings.json)
      r=$(bash "$KIT/lib/merge-settings.sh" file "$dst" "$src" "/.claude/hooks/guard.sh" 2>&1) \
        && say ".claude/settings.json уже был — дописан: $r" || problem ".claude/settings.json: $r"
      ;;
    .claude/hooks/guard.sh | .claude/skills/novoe/SKILL.md)
      if cmp -s "$src" "$dst"; then
        skipped="$skipped $f"
      elif ! ours "$dst"; then
        problem "$f уже есть и он не из набора — не трогаю; координатор с ним не заработает"
      elif [ "$had_version" = 1 ]; then
        skipped="$skipped $f(ваша правка)"
      else
        backup "$dst" && cp "$src" "$dst" && updated="$updated $f" || problem "не обновил $f"
      fi
      ;;
    *) skipped="$skipped $f" ;;
  esac
done < <(find . -type f ! -name .DS_Store | sort)
cd - >/dev/null || true
chmod +x "$ROOT/.claude/hooks/guard.sh" 2>/dev/null

# Есть AGENTS.md — в CLAUDE.md нужна отдельная строка @AGENTS.md, иначе Claude его не прочитает.
if [ -f "$ROOT/AGENTS.md" ] && ! tr -d '\r' <"$C" | grep -qxF "@AGENTS.md"; then
  body=$(cat "$C") && printf '@AGENTS.md\n\n%s\n' "$body" >"$C" || problem "не добавил @AGENTS.md в CLAUDE.md"
fi
[ -n "$updated" ] && say "Старый набор обновлён:$updated — прежние файлы в $BAK"
say "Шаблон в $ROOT: ок${skipped:+ (уже были, не трогал:$skipped)}"

# 3. Хук значков для всех сессий на этом компьютере — только по просьбе
if [ "$2" = znachki ]; then
mkdir -p "$CLAUDE_HOME/.claude/hooks" && cp "$KIT/user/hooks/status-icon.sh" "$HOOK_DST" && chmod +x "$HOOK_DST" \
  || problem "не положил хук значков в $HOOK_DST"
if [ "$os" != other ]; then
  r=$(bash "$KIT/lib/merge-settings.sh" user "$CLAUDE_HOME/.claude/settings.json" "$HOOK_DST" 2>&1)
  case $? in
    0)
      case "$r" in
        exists*) say "Хук значков: уже подключён в ~/.claude/settings.json, не трогал" ;;
        *) say "Хук значков: подключён в ~/.claude/settings.json ($r)" ;;
      esac
      case "$r" in *disableAllHooks*) say "ВНИМАНИЕ: в ~/.claude/settings.json хуки выключены (disableAllHooks)" ;; esac
      ;;
    *) problem "хук значков не подключён: $r" ;;
  esac
else
  say "Эта система не Mac и не Windows: хук значков положен, но не подключён — значки ставит модель по правилу в CLAUDE.md"
fi
fi

# 4. Проверка поставленного
if [ "$2" = znachki ]; then
  out=$(printf '%s' '{"prompt":"да","session_title":"❓ Проверка"}' | bash "$HOOK_DST" 2>/dev/null)
  case "$out" in *'take the ❓ off'*) say "Проверка хука значков: ок" ;; *) problem "хук значков не ответил как ждали" ;; esac
fi
if [ "$os" != other ]; then
  code=0
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/proverka/x/app.py"}}' "$ROOT" \
    | CLAUDE_PROJECT_DIR="$ROOT" bash "$ROOT/.claude/hooks/guard.sh" >/dev/null 2>&1 || code=$?
  S="$ROOT/.claude/settings.json"
  want='/.claude/hooks/guard.sh'
  [ "$os" = win ] && want="$(cygpath -m "$ROOT")/.claude/hooks/guard.sh"
  if [ "$code" != 2 ]; then
    problem "сторож не блокирует рабочий файл"
  elif ! grep -qF "$want" "$S" 2>/dev/null; then
    problem "сторож не подключён в .claude/settings.json (или указывает на прежнее место папки)"
  else
    off=""
    for s in "$S" "$ROOT/.claude/settings.local.json" "$CLAUDE_HOME/.claude/settings.json"; do
      grep -Eq '"disableAllHooks"[[:space:]]*:[[:space:]]*true' "$s" 2>/dev/null && off="$s"
    done
    if [ -n "$off" ]; then
      guard_off=1
      say "ВНИМАНИЕ: сторож стоит, но не сработает — хуки выключены в $off"
    else
      say "Проверка сторожа: ок"
    fi
  fi
fi
[ "$os" = win ] && rm -f "$PATCH"

if [ "$problems" -eq 0 ] && [ "$had_version" = 0 ]; then
  body=$(awk -v b="$MARK_BEGIN" -v v="$MARK_VERSION" '{ print } index($0, b) { print v }' "$C") \
    && printf '%s\n' "$body" >"$C" || problem "не записал версию в CLAUDE.md"
fi
if [ "$problems" -eq 0 ]; then
  say "ГОТОВО${guard_off:+, но сторож выключен}. Главная папка: $ROOT"
else
  say "Есть ошибки: $problems — см. выше"
  exit 1
fi

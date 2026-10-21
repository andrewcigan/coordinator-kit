#!/bin/bash
# Установщик набора «Координатор».   bash install.sh <главная папка>
# Mac — в Терминале или сессии Claude; Windows — в Git Bash (ставится вместе с Git for Windows).
#
# 1. Проверяет свои хуки на тестовых примерах — если что-то не так, ничего не меняет.
# 2. Кладёт шаблон в главную папку. Существующие файлы не перезаписывает: CLAUDE.md дополняет
#    между метками, .claude/settings.json дописывает, остальное пропускает и называет.
# 3. Кладёт хук значков в ~/.claude/hooks и подключает его в ~/.claude/settings.json
#    (с копией; если хук значков уже есть — не трогает).
# 4. Проверяет поставленное и печатает отчёт.
# Повторный запуск безопасен.

KIT=$(cd "$(dirname "$0")" && pwd)
MARK_BEGIN="<!-- coordinator-kit: начало -->"
MARK_END="<!-- coordinator-kit: конец -->"
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

# 2. Шаблон в главную папку
skipped=""
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
      # Метки и в новом файле: повторная установка узнает свои правила и не задвоит их.
      { printf '%s\n' "$MARK_BEGIN"; cat "$src"; printf '%s\n' "$MARK_END"; } >"$dst" || problem "не скопировал $f"
    else
      cp "$src" "$dst" || problem "не скопировал $f"
    fi
    continue
  fi
  case "$f" in
    CLAUDE.md)
      if grep -qF "$MARK_BEGIN" "$dst"; then
        skipped="$skipped CLAUDE.md(уже есть)"
      else
        { printf '\n%s\n' "$MARK_BEGIN"; cat "$f"; printf '%s\n' "$MARK_END"; } >>"$dst" \
          && say "CLAUDE.md уже был — правила координатора дописаны в конец между метками" \
          || problem "не дописал CLAUDE.md"
      fi
      ;;
    .claude/settings.json)
      r=$(bash "$KIT/lib/merge-settings.sh" file "$dst" "$src" "guard.sh" 2>&1) \
        && say ".claude/settings.json уже был — дописан: $r" || problem ".claude/settings.json: $r"
      ;;
    *) skipped="$skipped $f" ;;
  esac
done < <(find . -type f ! -name .DS_Store | sort)
cd - >/dev/null || true
chmod +x "$ROOT/.claude/hooks/guard.sh" 2>/dev/null
say "Шаблон в $ROOT: ок${skipped:+ (уже были, не трогал:$skipped)}"

# 3. Хук значков для всех сессий на этом компьютере
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

# 4. Проверка поставленного
out=$(printf '%s' '{"prompt":"да","session_title":"❓ Проверка"}' | bash "$HOOK_DST" 2>/dev/null)
case "$out" in *'take the ❓ off'*) say "Проверка хука значков: ок" ;; *) problem "хук значков не ответил как ждали" ;; esac
if [ "$os" != other ]; then
  code=0
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/infra/x/app.py"}}' "$ROOT" \
    | CLAUDE_PROJECT_DIR="$ROOT" bash "$ROOT/.claude/hooks/guard.sh" >/dev/null 2>&1 || code=$?
  [ "$code" = 2 ] && say "Проверка сторожа: ок" || problem "сторож не блокирует рабочий файл"
fi
[ "$os" = win ] && rm -f "$PATCH"

if [ "$problems" -eq 0 ]; then
  say "ГОТОВО. Главная папка: $ROOT"
else
  say "Есть ошибки: $problems — см. выше"
  exit 1
fi

#!/bin/bash
# Запись в settings.json Claude Code для любой системы:
#   Mac — merge-settings.js (osascript), Windows (Git Bash) — merge-settings.ps1 (PowerShell).
# Аргументы как у них: user <settings.json> <хук значков> | file <settings.json> <заплатка.json> <метка>
# Пути — в виде bash; на Windows переводятся в вид Windows.
# COORDINATOR_KIT_PWSH=<путь к pwsh> — прогнать вариант для Windows на Mac (для тестов).

HERE=$(cd "$(dirname "$0")" && pwd)

if [ -n "$COORDINATOR_KIT_PWSH" ]; then
  exec "$COORDINATOR_KIT_PWSH" -NoProfile -File "$HERE/merge-settings.ps1" "$@"
fi

case "$(uname -s)" in
  Darwin)
    exec osascript -l JavaScript "$HERE/merge-settings.js" "$@"
    ;;
  MINGW* | MSYS* | CYGWIN*)
    mode=$1
    target=$(cygpath -w "$2")
    if [ "$mode" = user ]; then third=$(cygpath -m "$3"); else third=$(cygpath -w "$3"); fi
    if [ $# -ge 4 ]; then
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/merge-settings.ps1")" "$mode" "$target" "$third" "$4"
    fi
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/merge-settings.ps1")" "$mode" "$target" "$third"
    ;;
  *)
    echo "эта система не поддерживается для записи настроек" >&2
    exit 2
    ;;
esac

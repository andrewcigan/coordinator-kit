#!/bin/bash
# Тесты установщика и слияния настроек на поддельной домашней папке. Настоящие ~/.claude не трогаются.
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$(cd "$HERE/.." && pwd)
. "$HERE/lib.sh"

# Запись настроек — через обёртку: на Mac JavaScript, на Windows PowerShell
# (COORDINATOR_KIT_PWSH=<pwsh> — вариант для Windows на Mac).
merge() { bash "$KIT/lib/merge-settings.sh" "$@" 2>&1; }
count() { grep -o "$1" "$2" 2>/dev/null | wc -l | tr -d ' '; }
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) win=1 ;; *) win=0 ;; esac

TMP=$(mktemp -d)
export HOME="$TMP/home"
mkdir -p "$HOME"
[ "$win" = 1 ] && export USERPROFILE=$(cygpath -w "$HOME")

# --- Слияние пользовательских настроек: шесть видов файла ---
S="$TMP/s.json"
rm -f "$S"; r=$(merge user "$S" /h/status-icon.sh); expect_has "$r" created "нет файла — создан"
expect_json "$(cat "$S")" "нет файла — JSON"
expect_code 1 "$(count status-icon "$S")" "нет файла — одна запись"

r=$(merge user "$S" /h/status-icon.sh); expect_has "$r" exists "повтор — без дубля"
expect_code 1 "$(count status-icon "$S")" "повтор — всё ещё одна запись"
expect_code 0 "$(ls "$TMP" | grep -c bak-coordinator-kit)" "повтор — без лишней копии"

echo '{}' >"$S"; r=$(merge user "$S" /h/status-icon.sh); expect_has "$r" added "пустой объект — дописан"
rm -f "$TMP"/s.json.bak-coordinator-kit-*

printf '{\n  "theme": "auto",\n  "env": {"A": "1"}\n}\n' >"$S"; chmod 600 "$S"
r=$(merge user "$S" /h/status-icon.sh); expect_has "$r" added "чужие ключи — дописан"
expect_has "$(cat "$S")" 'auto' "чужие ключи — сохранены"
expect_has "$(cat "$S")" 'env' "чужие ключи — сохранены (env)"
if [ "$(uname -s)" = Darwin ] && [ -z "$COORDINATOR_KIT_PWSH" ]; then
  expect_code 600 "$(stat -f %Lp "$S")" "права файла сохранены"
fi
expect_code 1 "$(ls "$TMP" | grep -c 's.json.bak-coordinator-kit')" "копия до правки сделана"
rm -f "$TMP"/s.json.bak-coordinator-kit-*

echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"other.sh"}]}],"Stop":[]}}' >"$S"
r=$(merge user "$S" /h/status-icon.sh); expect_has "$r" added "чужой хук — дописан рядом"
expect_has "$(cat "$S")" other.sh "чужой хук — на месте"
expect_has "$(cat "$S")" '"Stop"' "другие события — на месте"

before='{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"bash /x/my-status-icon.sh"}]}]}}'
echo "$before" >"$S"; r=$(merge user "$S" /h/status-icon.sh); expect_has "$r" exists "свой хук значков уже есть — не трогать"
expect_code "$before" "$(cat "$S")" "свой хук значков — файл тот же байт в байт"

echo '{"hooks": {' >"$S"; r=$(merge user "$S" /h/status-icon.sh); code=$?
expect_code 3 "$code" "не JSON — код 3"; expect_code '{"hooks": {' "$(cat "$S")" "не JSON — файл не тронут"

echo '{"hooks":{"UserPromptSubmit":{"x":1}}}' >"$S"; r=$(merge user "$S" /h/status-icon.sh); code=$?
expect_code 3 "$code" "событие не списком — код 3"

echo '{"disableAllHooks":true}' >"$S"; r=$(merge user "$S" /h/status-icon.sh); expect_has "$r" disableAllHooks "выключенные хуки — предупреждение"

# --- Установщик: чистая машина ---
ROOT="$TMP/AI"
out=$(bash "$KIT/install.sh" "$ROOT" 2>&1); code=$?
expect_code 0 "$code" "установка: код 0"
expect_has "$out" "ГОТОВО" "установка: отчёт"
for f in CLAUDE.md directions.md PROJECTS.md .claude/settings.json .claude/hooks/guard.sh .claude/skills/novoe/SKILL.md; do
  [ -f "$ROOT/$f" ] && ok || bad "установка: есть $f"
done
for d in infra data harness agents; do
  [ -d "$ROOT/$d" ] && ok || bad "установка: есть папка $d"
  [ -e "$ROOT/$d/.gitkeep" ] && bad "установка: лишний .gitkeep в $d" || ok
done
expect_code 1 "$(count coordinator-status-icon "$HOME/.claude/settings.json")" "установка: хук значков подключён один раз"
[ -x "$HOME/.claude/hooks/coordinator-status-icon.sh" ] && ok || bad "установка: хук значков на месте"

# --- Повторная установка: ничего не задваивается, своё не перезаписывается ---
echo "моя правка" >>"$ROOT/directions.md"
out=$(bash "$KIT/install.sh" "$ROOT" 2>&1); code=$?
expect_code 0 "$code" "повтор: код 0"
expect_has "$(cat "$ROOT/directions.md")" "моя правка" "повтор: свои правки целы"
expect_code 1 "$(count coordinator-status-icon "$HOME/.claude/settings.json")" "повтор: без дубля хука"
expect_code 1 "$(count guard.sh "$ROOT/.claude/settings.json")" "повтор: без дубля сторожа"

# --- Главная папка, где уже были свои CLAUDE.md и .claude/settings.json ---
R2="$TMP/Existing"
mkdir -p "$R2/.claude"
echo "# Мои старые правила" >"$R2/CLAUDE.md"
echo '{"permissions":{"allow":["Bash(ls:*)"]},"model":"x"}' >"$R2/.claude/settings.json"
out=$(bash "$KIT/install.sh" "$R2" 2>&1); code=$?
expect_code 0 "$code" "своя папка: код 0"
expect_has "$(cat "$R2/CLAUDE.md")" "Мои старые правила" "своя папка: старые правила целы"
expect_has "$(cat "$R2/CLAUDE.md")" "coordinator-kit: начало" "своя папка: правила координатора дописаны"
s2=$(cat "$R2/.claude/settings.json")
expect_has "$s2" 'Bash(ls:*)' "своя папка: старые разрешения целы"
expect_has "$s2" 'Edit(/PROJECTS.md)' "своя папка: разрешения координатора дописаны"
expect_has "$s2" 'guard.sh' "своя папка: сторож подключён"
bash "$KIT/install.sh" "$R2" >/dev/null 2>&1
expect_code 1 "$(count 'coordinator-kit: начало' "$R2/CLAUDE.md")" "своя папка, повтор: правила не задвоены"

# --- Отказы ---
out=$(bash "$KIT/install.sh" "$HOME" 2>&1); code=$?
expect_code 2 "$code" "домашняя папка целиком — отказ"
out=$(bash "$KIT/install.sh" "AI" 2>&1); code=$?
expect_code 2 "$code" "неполный путь — отказ"

for f in "$KIT/install.sh" "$KIT/lib/merge-settings.sh" "$KIT/lib/merge-settings.js" "$KIT/lib/merge-settings.ps1"; do expect_clean_file "$f" "без \\r и BOM: $(basename "$f")"; done

rm -rf "$TMP"
finish

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
[ -e "$HOME/.claude/settings.json" ] && bad "установка: личные настройки не тронуты" || ok
bash "$KIT/install.sh" "$ROOT" znachki >/dev/null 2>&1; code=$?
expect_code 0 "$code" "установка со значками: код 0"
expect_code 1 "$(count coordinator-status-icon "$HOME/.claude/settings.json")" "установка со значками: хук подключён один раз"
[ -x "$HOME/.claude/hooks/coordinator-status-icon.sh" ] && ok || bad "установка: хук значков на месте"

# --- Повторная установка: ничего не задваивается, своё не перезаписывается ---
echo "моя правка" >>"$ROOT/directions.md"
out=$(bash "$KIT/install.sh" "$ROOT" znachki 2>&1); code=$?
expect_code 0 "$code" "повтор: код 0"
expect_has "$(cat "$ROOT/directions.md")" "моя правка" "повтор: свои правки целы"
expect_code 1 "$(count coordinator-status-icon "$HOME/.claude/settings.json")" "повтор: без дубля хука"
expect_code 1 "$(count guard.sh "$ROOT/.claude/settings.json")" "повтор: без дубля сторожа"
expect_code 1 "$(count 'coordinator-kit: начало' "$ROOT/CLAUDE.md")" "повтор: правила в CLAUDE.md один раз"
expect_code 1 "$(count 'ты координатор' "$ROOT/CLAUDE.md")" "повтор: раздел координатора один раз"

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

# --- Старый набор 22.10 в этой же папке: файлы набора заменяются новыми, прежние — копией рядом, своё цело ---
R3="$TMP/Old"
mkdir -p "$R3/.claude/hooks" "$R3/.claude/skills/novoe"
printf '# Мои строки сверху\n\n<!-- coordinator-kit: начало -->\nСТАРЫЕ ПРАВИЛА infra harness\r\nпо пятницам список\n<!-- coordinator-kit: конец -->\n\n# Мои строки снизу\n' >"$R3/CLAUDE.md"
echo "# Сторож координатора, старый" >"$R3/.claude/hooks/guard.sh"
echo "Ты координатор, старый навык, directions.md" >"$R3/.claude/skills/novoe/SKILL.md"
echo "мои направления" >"$R3/directions.md"
echo "мои проекты" >"$R3/PROJECTS.md"
out=$(bash "$KIT/install.sh" "$R3" 2>&1); code=$?
expect_code 0 "$code" "старый набор: код 0"
expect_has "$out" "обновлён" "старый набор: сказано, что обновлён"
for f in .claude/hooks/guard.sh .claude/skills/novoe/SKILL.md; do
  cmp -s "$KIT/template/$f" "$R3/$f" && ok || bad "старый набор: новый $f"
done
expect_has "$(cat "$R3/CLAUDE.md")" "ты координатор" "старый набор: новые правила"
expect_code 1 "$(sed -n '/Мои правила координатору/,$p' "$R3/CLAUDE.md" | grep -c 'по пятницам список')" "старый набор: личная строка из раздела — в конце"
expect_has "$(cat "$R3/CLAUDE.md")" "Мои строки сверху" "старый набор: строки сверху целы"
expect_has "$(cat "$R3/CLAUDE.md")" "Мои строки снизу" "старый набор: строки снизу целы"
expect_code "мои направления" "$(cat "$R3/directions.md")" "старый набор: направления целы"
expect_code "мои проекты" "$(cat "$R3/PROJECTS.md")" "старый набор: список проектов цел"
expect_code 1 "$(grep -l 'старый навык' "$R3"/.claude/coordinator-kit-bak-*/* 2>/dev/null | wc -l | tr -d ' ')" "старый набор: копия навыка"
expect_code 1 "$(grep -l 'СТАРЫЕ ПРАВИЛА' "$R3"/.claude/coordinator-kit-bak-*/* 2>/dev/null | wc -l | tr -d ' ')" "старый набор: копия правил"
bash "$KIT/install.sh" "$R3" >/dev/null 2>&1
expect_code 1 "$(ls -d "$R3"/.claude/coordinator-kit-bak-* | wc -l | tr -d ' ')" "старый набор, повтор: второй копии нет"
expect_code 1 "$(count 'coordinator-kit: начало' "$R3/CLAUDE.md")" "старый набор, повтор: правила один раз"

# Настоящие правила 22.10 с личной строкой внутри: правил нет, личная строка цела
R6="$TMP/Old2"
mkdir -p "$R6"
{ echo '<!-- coordinator-kit: начало -->'; cat "$KIT/lib/old-rules-2026-10-22.md"; echo 'присылай список по пятницам'; echo '<!-- coordinator-kit: конец -->'; } >"$R6/CLAUDE.md"
out=$(bash "$KIT/install.sh" "$R6" 2>&1); code=$?
expect_code 0 "$code" "правила 22.10: код 0"
expect_code 1 "$(count 'присылай список по пятницам' "$R6/CLAUDE.md")" "правила 22.10: личная строка цела"
expect_code 0 "$(count 'set_remote_control' "$R6/CLAUDE.md")" "правила 22.10: старых правил нет"
bash "$KIT/install.sh" "$R6" >/dev/null 2>&1
expect_code 1 "$(count 'присылай список по пятницам' "$R6/CLAUDE.md")" "правила 22.10, повтор: личная строка не задвоена"

# Метка начала есть, конца нет (человек стёр): не портим, говорим
R4="$TMP/Broken"
mkdir -p "$R4"
printf '<!-- coordinator-kit: начало -->\nстарое без конца\n' >"$R4/CLAUDE.md"
out=$(bash "$KIT/install.sh" "$R4" 2>&1); code=$?
expect_code 1 "$code" "метка без конца: ошибка, а не «готово»"
expect_has "$(cat "$R4/CLAUDE.md")" "старое без конца" "метка без конца: файл не тронут"

# Метки наоборот: не трогаем
R7="$TMP/Reversed"
mkdir -p "$R7"
printf '<!-- coordinator-kit: конец -->\nмоё\n<!-- coordinator-kit: начало -->\nтоже моё\n' >"$R7/CLAUDE.md"
out=$(bash "$KIT/install.sh" "$R7" 2>&1); code=$?
expect_code 1 "$code" "метки наоборот: ошибка"
expect_has "$(cat "$R7/CLAUDE.md")" "тоже моё" "метки наоборот: файл не тронут"

# Главная папка внутри другой главной — отказ
mkdir -p "$ROOT/AI-projects"
out=$(bash "$KIT/install.sh" "$ROOT/AI-projects" 2>&1); code=$?
expect_code 2 "$code" "внутри другой главной папки: отказ"

# AGENTS.md есть — строка @AGENTS.md появляется один раз
R8="$TMP/Agents"
mkdir -p "$R8"
echo "- мои правила" >"$R8/AGENTS.md"
bash "$KIT/install.sh" "$R8" >/dev/null 2>&1
bash "$KIT/install.sh" "$R8" >/dev/null 2>&1
expect_code 1 "$(grep -cxF '@AGENTS.md' "$R8/CLAUDE.md")" "AGENTS.md подключён одной строкой"

# Хуки выключены — не «готово» молча
R9="$TMP/NoHooks"
mkdir -p "$R9/.claude"
echo '{"disableAllHooks": true}' >"$R9/.claude/settings.json"
out=$(bash "$KIT/install.sh" "$R9" 2>&1)
expect_has "$out" "сторож выключен" "выключенные хуки: сказано в итоге"

# Чужой хук с похожим именем — сторож всё равно подключается
R10="$TMP/OtherGuard"
mkdir -p "$R10/.claude"
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"bash my-bash-guard.sh"}]}]}}' >"$R10/.claude/settings.json"
bash "$KIT/install.sh" "$R10" >/dev/null 2>&1
expect_has "$(cat "$R10/.claude/settings.json")" "/.claude/hooks/guard.sh" "чужой guard.sh: наш подключён рядом"

# Чужой навык novoe без наших меток — не затираем
R5="$TMP/Foreign"
mkdir -p "$R5/.claude/skills/novoe"
echo "мой собственный навык" >"$R5/.claude/skills/novoe/SKILL.md"
out=$(bash "$KIT/install.sh" "$R5" 2>&1); code=$?
expect_code "мой собственный навык" "$(cat "$R5/.claude/skills/novoe/SKILL.md")" "чужой навык: цел"
expect_code 1 "$code" "чужой навык: ошибка, а не «готово»"
out=$(bash "$KIT/install.sh" "$R5" 2>&1); code=$?
expect_code 1 "$code" "чужой навык, повтор: всё ещё ошибка"
expect_code "мой собственный навык" "$(cat "$R5/.claude/skills/novoe/SKILL.md")" "чужой навык, повтор: цел"

# --- Отказы ---
out=$(bash "$KIT/install.sh" "$HOME" 2>&1); code=$?
expect_code 2 "$code" "домашняя папка целиком — отказ"
out=$(bash "$KIT/install.sh" "AI" 2>&1); code=$?
expect_code 2 "$code" "неполный путь — отказ"

for f in "$KIT/install.sh" "$KIT/lib/merge-settings.sh" "$KIT/lib/merge-settings.js" "$KIT/lib/merge-settings.ps1"; do expect_clean_file "$f" "без \\r и BOM: $(basename "$f")"; done

rm -rf "$TMP"
finish

#!/bin/bash
# Тесты хука значков. Запуск: bash tests/test-status-icon.sh [путь к хуку]
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK=${1:-"$HERE/../user/hooks/status-icon.sh"}
. "$HERE/lib.sh"

run() { printf '%s' "$1" | bash "$HOOK"; }

# ❓ в начале — напоминание снять значок, с готовым названием без него
out=$(run '{"session_id":"s","prompt":"да","session_title":"❓ Проект бота"}'); code=$?
expect_code 0 "$code" "❓: код выхода 0"
expect_has "$out" '"hookEventName":"UserPromptSubmit"' "❓: формат ответа"
expect_has "$out" 'take the ❓ off' "❓: просит снять ❓"
expect_has "$out" 'title \"Проект бота\"' "❓: новое название без значка"
expect_json "$out" "❓: ответ — правильный JSON"

# ✅ в начале — работа продолжается, снять ✅
out=$(run '{"prompt":"ещё","session_title":"✅ Готовый бот"}')
expect_has "$out" 'take the ✅ off' "✅: просит снять ✅"
expect_has "$out" 'title \"Готовый бот\"' "✅: новое название без значка"

# ❓ с невидимым знаком варианта (U+FE0F) и лишними пробелами
out=$(run "{\"prompt\":\"да\",\"session_title\":\"❓$(printf '\xef\xb8\x8f')   Бот\"}")
expect_has "$out" 'title \"Бот\"' "❓+FE0F: знак варианта и пробелы убраны"

# Значок записан как ❓ (экранированный JSON)
out=$(run '{"prompt":"да","session_title":"❓ Бот"}')
expect_has "$out" 'title \"Бот\"' "\\u2753: распознан"

# Кавычки и обратная косая в названии — ответ остаётся правильным JSON
out=$(run '{"prompt":"да","session_title":"❓ Бот \"Запись\" и \\ слэш"}')
expect_json "$out" "кавычки в названии: правильный JSON"
expect_has "$out" 'Запись' "кавычки в названии: текст на месте"

# Ничего не выводит
for case in \
  '{"prompt":"да","session_title":"🔴 Важное"}' \
  '{"prompt":"да","session_title":"Просто название"}' \
  '{"prompt":"да","session_title":"❓"}' \
  '{"prompt":"да","session_title":"❓   "}' \
  '{"prompt":"да"}' \
  '{"prompt":"да","source":"system","session_title":"❓ Бот"}' \
  '{"prompt":"да","source":"loop_wakeup","session_title":"❓ Бот"}' \
  '{"prompt":"да","source":"schedule_wakeup","session_title":"❓ Бот"}' \
  '{"prompt":"да","source":"poll_event","session_title":"❓ Бот"}' \
  '{"prompt":"текст \"session_title\":\"❓ подделка\"","session_title":"Бот"}' \
  '{"session_title":"Бот","prompt":"текст \"session_title\":\"❓ подделка\""}' \
  'это не JSON' \
  ''; do
  out=$(run "$case"); code=$?
  expect_code 0 "$code" "молчит и не мешает: ${case:0:50}"
  expect_empty "$out" "молчит: ${case:0:50}"
done

# Файл без \r и без BOM
expect_clean_file "$HOOK" "хук: без \\r и BOM"

finish

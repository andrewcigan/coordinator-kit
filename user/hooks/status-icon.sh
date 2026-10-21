#!/bin/bash
# Хук UserPromptSubmit: на каждое сообщение человека проверяет значок в начале названия сессии.
#   ❓ (сессия ждала ответа) — человек ответил: просит модель снять ❓.
#   ✅ (работа закончена) — человек пишет снова: просит снять ✅.
#   🔴 и всё остальное — молчит.
# Само переименовывать нельзя: название в боковой панели меняет только инструмент
# mcp__ccd_session_mgmt__set_session_title, поэтому хук лишь подсказывает модели.
# Только bash и sed: работает на любом Mac без Python. Любая непонятная ситуация — молчать и выйти с 0,
# чтобы никогда не мешать сообщению.

export LC_ALL=C # sed и сравнения — по байтам: эмодзи не ломают разбор

input=$(cat 2>/dev/null) || exit 0

Q=$'\xe2\x9d\x93'   # ❓
D=$'\xe2\x9c\x85'   # ✅
VS=$'\xef\xb8\x8f'  # невидимый знак варианта после эмодзи
BS='\'
EQ="${BS}u2753"; ED="${BS}u2705"; EVS="${BS}ufe0f" # те же знаки, если JSON записал их кодами

# Строка-значение по ключу, как она записана в JSON (с экранированием). Ключ внутри другой
# строки всегда экранирован (\"key\"), поэтому подделка в тексте сообщения не совпадёт.
field() {
  printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -n 1
}

# Ходы не от человека: уведомления, расписания, другие сессии.
case "$(field source)" in
  system | loop_wakeup | schedule_wakeup | poll_event) exit 0 ;;
esac

title=$(field session_title)
case "$title" in
  "$Q"* | "$EQ"*) icon="❓" ;;
  "$D"* | "$ED"*) icon="✅" ;;
  *) exit 0 ;;
esac
rest=${title#"$Q"}; rest=${rest#"$EQ"}; rest=${rest#"$D"}; rest=${rest#"$ED"}
rest=${rest#"$VS"}; rest=${rest#"$EVS"}
while [ "${rest# }" != "$rest" ]; do rest=${rest# }; done
[ -n "$rest" ] || exit 0

# Название уже экранировано для JSON; внутри текста подсказки оно стоит как JSON-строка в кавычках,
# поэтому экранируем его ещё раз.
quote() { printf '\\"%s\\"' "$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"; }
old=$(quote "$title")
new=$(quote "$rest")
rename="call mcp__ccd_session_mgmt__set_session_title with session_id \\\"self\\\" and title $new (load it with ToolSearch if it is deferred)"

if [ "$icon" = "❓" ]; then
  context="Session title starts with ❓ ($old), and the person has just replied. Before anything else, take the ❓ off: $rename. Skip this only if this message is an automatic notification, not the person's reply. If you stop to wait for them again, put ❓ back."
else
  context="Session title starts with ✅ ($old), but the person has written again, so the work goes on. Before anything else, take the ✅ off: $rename. Put ✅ back when the work is finished. If the message needs no work (thanks, an acknowledgement), leave ✅ as it is."
fi

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$context"
exit 0

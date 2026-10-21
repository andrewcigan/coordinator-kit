#!/bin/bash
# Правила набора, которые можно проверить машиной (остальное — CODING_STANDARDS.md, для ревью).
# Запуск: bash tests/test-rules.sh
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$(cd "$HERE/.." && pwd)
. "$HERE/lib.sh"
cd "$KIT" || exit 1

# То, что уезжает к человеку и работает у него: установщик, запись настроек, хуки.
SHIPPED="install.sh lib/merge-settings.sh lib/merge-settings.js lib/merge-settings.ps1 user/hooks/status-icon.sh template/.claude/hooks/guard.sh"
code_lines() { grep -v -E '^[[:space:]]*(#|//)' "$1"; } # без строк-комментариев

for f in $SHIPPED; do
  [ -f "$f" ] && ok || bad "есть файл $f"

  # 1. Только то, что есть на любом Mac и в Git Bash: без Python, Node, Ruby.
  hits=$(code_lines "$f" | grep -n -E '(^|[^[:alnum:]_.-])(python3?|node|npx|ruby|pip3?)([^[:alnum:]_-]|$)')
  expect_empty "$hits" "$f: без Python/Node/Ruby"

  # 2. Навсегда ничего не удаляем. Разрешено только убрать свой временный файл: rm -f "$PATCH".
  hits=$(code_lines "$f" | grep -n -E '(^|[^[:alnum:]_])rm[[:space:]]+-[a-zA-Z]*r|Remove-Item|removeItem|unlink[[:space:]]*\(|rmdir' )
  expect_empty "$hits" "$f: без удаления папок и файлов"
  hits=$(code_lines "$f" | grep -n -E '(^|[^[:alnum:]_])rm[[:space:]]' | grep -v -F 'rm -f "$PATCH"')
  expect_empty "$hits" "$f: rm — только для своего временного файла"
done

# 3. Windows PowerShell 5.1 читает файл без BOM в кодировке ANSI: в .ps1 — только латиница.
non_ascii=$(LC_ALL=C tr -d '\000-\177' <lib/merge-settings.ps1 | wc -c | tr -d ' ')
expect_code 0 "$non_ascii" "merge-settings.ps1: только ASCII"

# 4. Все текстовые файлы — без \r и без BOM (иначе bash на Windows и Mac спотыкается).
while IFS= read -r f; do
  expect_clean_file "$f" "без \\r и BOM: $f"
done < <(find . -type f ! -path './.git/*' ! -name '*.tar.gz' ! -name '.DS_Store' | sort)

# 5. Ничего личного: ни путей автора, ни ключей, ни клиентов.
hits=$(grep -r -n -i -E '/Users/atsyhan|atsyhan\.by|infisical|sekret|ratinglab|korpopushka|amocrm|tsyhanhelper' \
  --exclude-dir=.git --exclude=test-rules.sh . 2>/dev/null)
expect_empty "$hits" "нет личного"

# 6. Одна и та же версия в фразе установки (README) и в инструкции для Claude (INSTALL.md).
tag_of() { grep -o -E 'archive/refs/tags/[^/[:space:]]+\.tar\.gz' "$1" | sort -u; }
expect_code "$(tag_of INSTALL.md)" "$(tag_of README.md)" "README и INSTALL ссылаются на одну версию"
[ "$(tag_of INSTALL.md | wc -l | tr -d ' ')" = 1 ] && ok || bad "в INSTALL.md ровно одна версия архива"

finish

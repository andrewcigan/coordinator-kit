#!/bin/bash
# Все тесты набора: bash tests/run.sh
HERE=$(cd "$(dirname "$0")" && pwd)
status=0
for t in test-rules.sh test-status-icon.sh test-guard.sh test-install.sh; do
  bash "$HERE/$t" || status=1
done
[ "$status" -eq 0 ] && echo "Все тесты прошли" || echo "Есть упавшие тесты"
exit "$status"

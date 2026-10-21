# Общие проверки для тестов: подключать через «. lib.sh».
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; [ -n "$2" ] && printf '      %s\n' "$2"; }

expect_code() { [ "$2" = "$1" ] && ok || bad "$3" "ждали код $1, получили $2"; }
expect_has() { case "$1" in *"$2"*) ok ;; *) bad "$3" "нет «$2» в: $1" ;; esac; }
expect_empty() { [ -z "$1" ] && ok || bad "$2" "ждали пусто, получили: $1"; }

# Проверка JSON без Python: JavaScript, который есть на любом Mac.
expect_json() {
  if printf '%s' "$1" | osascript -l JavaScript -e '
    ObjC.import("Foundation");
    const d = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
    JSON.parse($.NSString.alloc.initWithDataEncoding(d, $.NSUTF8StringEncoding).js); "ok"' >/dev/null 2>&1
  then ok; else bad "$2" "не JSON: $1"; fi
}

expect_clean_file() {
  if LC_ALL=C grep -q $'\r' "$1" || [ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' ')" = "efbbbf" ]; then
    bad "$2" "$1"
  else ok; fi
}

finish() {
  printf '%s: прошло %d, упало %d\n' "$(basename "$0")" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

// Аккуратно дописывает в settings.json Claude Code хуки и разрешения, не трогая чужое.
// JavaScript для macOS (osascript): работает на любом Mac без Python и Node.
//
//   osascript -l JavaScript merge-settings.js user <settings.json> <путь к хуку значков>
//   osascript -l JavaScript merge-settings.js file <settings.json> <файл-заплатка.json> <метка>
//
// user — добавить хук значков в UserPromptSubmit (метка «status-icon»: если такой хук уже есть, ничего не делать).
// file — влить заплатку: события hooks (событие пропускается, если в нём уже есть команда с меткой)
//        и permissions.allow (только недостающие правила).
// Печатает: created | added | exists (+ «; disableAllHooks», если хуки выключены).
// Коды: 0 — готово; 2 — неверный вызов; 3 — файл не JSON или другой формы (не тронут);
//       4 — запись не удалась (вернули копию).
// Перед правкой существующего файла кладёт копию <файл>.bak-coordinator-kit-<время>.

ObjC.import("Foundation");
ObjC.import("stdlib");

const fm = $.NSFileManager.defaultManager;

function quit(code, message) {
  console.log(message); // в osascript console.log пишет в stderr
  $.exit(code);
}

function readText(path) {
  const s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  return s.isNil() ? null : s.js;
}

function writeText(path, text) {
  return $(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
}

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function shapeError(where) {
  return new Error(`${where} — не того вида, что ждёт Claude Code`);
}

function hasCommand(groups, marker) {
  return groups.some((g) =>
    (isObject(g) && Array.isArray(g.hooks) ? g.hooks : []).some(
      (h) => isObject(h) && typeof h.command === "string" && h.command.includes(marker),
    ),
  );
}

function merge(settings, patch, marker) {
  let changed = false;
  if (isObject(patch.hooks)) {
    if (settings.hooks === undefined) settings.hooks = {};
    if (!isObject(settings.hooks)) throw shapeError("hooks");
    for (const event of Object.keys(patch.hooks)) {
      const current = settings.hooks[event] === undefined ? [] : settings.hooks[event];
      if (!Array.isArray(current)) throw shapeError(`hooks.${event}`);
      if (!hasCommand(current, marker)) {
        settings.hooks[event] = current.concat(patch.hooks[event]);
        changed = true;
      }
    }
  }
  if (isObject(patch.permissions) && Array.isArray(patch.permissions.allow)) {
    if (settings.permissions === undefined) settings.permissions = {};
    if (!isObject(settings.permissions)) throw shapeError("permissions");
    const allow = settings.permissions.allow === undefined ? [] : settings.permissions.allow;
    if (!Array.isArray(allow)) throw shapeError("permissions.allow");
    const missing = patch.permissions.allow.filter((rule) => !allow.includes(rule));
    if (missing.length) {
      settings.permissions.allow = allow.concat(missing);
      changed = true;
    }
  }
  return changed;
}

function stamp() {
  const d = new Date();
  const two = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${two(d.getMonth() + 1)}${two(d.getDate())}-${two(d.getHours())}${two(d.getMinutes())}${two(d.getSeconds())}`;
}

function run(argv) {
  const [mode, target] = argv;
  let patch, marker;
  if (mode === "user" && argv.length === 3) {
    patch = { hooks: { UserPromptSubmit: [{ hooks: [{ type: "command", command: `bash "${argv[2]}"`, timeout: 10 }] }] } };
    marker = "status-icon";
  } else if (mode === "file" && argv.length === 4) {
    const text = readText(argv[2]);
    if (text === null) quit(2, `нет файла-заплатки: ${argv[2]}`);
    patch = JSON.parse(text);
    marker = argv[3];
  } else {
    quit(2, "вызов: merge-settings.js user <settings.json> <хук> | file <settings.json> <заплатка.json> <метка>");
  }

  const existed = fm.fileExistsAtPath(target);
  const raw = existed ? readText(target) : "";
  if (raw === null) quit(3, `не читается: ${target}`);
  let settings;
  try {
    settings = raw.trim() ? JSON.parse(raw) : {};
  } catch (e) {
    quit(3, `не JSON, файл не тронут: ${target} (${e.message})`);
  }
  if (!isObject(settings)) quit(3, `не объект JSON, файл не тронут: ${target}`);

  let changed;
  try {
    changed = merge(settings, patch, marker);
  } catch (e) {
    quit(3, `файл не тронут: ${target}: ${e.message}`);
  }
  const note = settings.disableAllHooks === true ? "; disableAllHooks" : "";
  if (!changed) return "exists" + note;

  const dir = $(target).stringByDeletingLastPathComponent;
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
  let backup = null;
  let mode0 = null;
  if (existed) {
    if (readText(target) !== raw) quit(4, `файл поменялся во время правки, запустите ещё раз: ${target}`);
    backup = `${target}.bak-coordinator-kit-${stamp()}`;
    for (let i = 2; fm.fileExistsAtPath(backup); i += 1) backup = `${target}.bak-coordinator-kit-${stamp()}-${i}`;
    if (!fm.copyItemAtPathToPathError(target, backup, null)) quit(4, `не удалось сделать копию: ${backup}`);
    mode0 = fm.attributesOfItemAtPathError(target, null).objectForKey($.NSFilePosixPermissions);
  }
  const ok = writeText(target, JSON.stringify(settings, null, 2) + "\n");
  let valid = false;
  try {
    valid = ok && isObject(JSON.parse(readText(target)));
  } catch (e) {
    valid = false;
  }
  if (!valid) {
    if (backup) {
      fm.removeItemAtPathError(target, null);
      fm.copyItemAtPathToPathError(backup, target, null);
    }
    quit(4, `запись не удалась${backup ? ", вернул копию" : ""}: ${target}`);
  }
  if (mode0 !== null) {
    const attrs = $.NSDictionary.dictionaryWithObjectForKey(mode0, $.NSFilePosixPermissions);
    fm.setAttributesOfItemAtPathError(attrs, target, null);
  }
  return (existed ? "added" : "created") + note;
}

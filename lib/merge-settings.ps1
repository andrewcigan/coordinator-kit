# Same as merge-settings.js, for Windows (Windows PowerShell 5.1 and PowerShell 7).
# Adds hooks and permissions to a Claude Code settings.json without touching anything else.
# ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less script in the ANSI code page.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File merge-settings.ps1 user <settings.json> <status hook path>
#   powershell -NoProfile -ExecutionPolicy Bypass -File merge-settings.ps1 file <settings.json> <patch.json> <marker>
#
# Prints: created | added | exists (+ "; disableAllHooks"). Exit codes: 0 done; 2 bad call;
# 3 file is not JSON or has another shape (left untouched); 4 write failed (old text restored).
# Before changing an existing file it saves <file>.bak-coordinator-kit-<time>.

param([string]$Mode, [string]$Target, [string]$Third, [string]$Marker)

$utf8 = New-Object System.Text.UTF8Encoding($false)

function Quit([int]$code, [string]$message) {
  [Console]::Error.WriteLine($message)
  exit $code
}

# Returns the value as is (an array stays one array). Assign it to a variable before using @(...)
# or a pipeline on it: @(Get-Prop ...) would wrap the array into another array.
function Get-Prop($obj, [string]$name) {
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return $null }
  return , $p.Value
}

function Set-Prop($obj, [string]$name, $value) {
  $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
}

function Test-Object($v) { return $v -is [System.Management.Automation.PSCustomObject] }

function Test-HasCommand($groups, [string]$marker) {
  foreach ($g in @($groups)) {
    if (-not (Test-Object $g)) { continue }
    $hs = Get-Prop $g 'hooks'
    foreach ($h in @($hs)) {
      if (-not (Test-Object $h)) { continue }
      $c = Get-Prop $h 'command'
      if (($c -is [string]) -and $c.Contains($marker)) { return $true }
    }
  }
  return $false
}

if ($Mode -eq 'user' -and $Third -and -not $Marker) {
  $command = 'bash "' + $Third + '"'
  $patch = ('{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":' + (ConvertTo-Json $command) + ',"timeout":10}]}]}}') | ConvertFrom-Json
  # Any status-icon hook already connected counts as ours: two hooks would send two identical reminders.
  $Marker = 'status-icon'
} elseif ($Mode -eq 'file' -and $Third -and $Marker) {
  if (-not (Test-Path -LiteralPath $Third)) { Quit 2 "no patch file: $Third" }
  try { $patch = [IO.File]::ReadAllText($Third, $utf8) | ConvertFrom-Json } catch { Quit 2 "patch is not JSON: $Third" }
} else {
  Quit 2 'usage: merge-settings.ps1 user <settings.json> <hook> | file <settings.json> <patch.json> <marker>'
}

$existed = Test-Path -LiteralPath $Target
$raw = ''
if ($existed) {
  try { $raw = [IO.File]::ReadAllText($Target, $utf8) } catch { Quit 3 "cannot read: $Target" }
}
if ($raw.Trim()) {
  try { $settings = $raw | ConvertFrom-Json } catch { Quit 3 "not JSON, left untouched: $Target" }
  if (-not (Test-Object $settings)) { Quit 3 "not a JSON object, left untouched: $Target" }
} else {
  $settings = New-Object PSObject
}

$changed = $false
$patchHooks = Get-Prop $patch 'hooks'
if (Test-Object $patchHooks) {
  $hooks = Get-Prop $settings 'hooks'
  if ($null -eq $hooks) { $hooks = New-Object PSObject; Set-Prop $settings 'hooks' $hooks }
  if (-not (Test-Object $hooks)) { Quit 3 "left untouched: ${Target}: hooks has another shape" }
  foreach ($event in @($patchHooks.PSObject.Properties.Name)) {
    $current = Get-Prop $hooks $event
    if ($null -eq $current) { $current = @() }
    if (-not ($current -is [array])) { Quit 3 "left untouched: ${Target}: hooks.$event has another shape" }
    if (-not (Test-HasCommand $current $Marker)) {
      $add = Get-Prop $patchHooks $event
      Set-Prop $hooks $event (@($current) + @($add))
      $changed = $true
    }
  }
}
$patchPerms = Get-Prop $patch 'permissions'
if ((Test-Object $patchPerms) -and ((Get-Prop $patchPerms 'allow') -is [array])) {
  $perms = Get-Prop $settings 'permissions'
  if ($null -eq $perms) { $perms = New-Object PSObject; Set-Prop $settings 'permissions' $perms }
  if (-not (Test-Object $perms)) { Quit 3 "left untouched: ${Target}: permissions has another shape" }
  $allow = Get-Prop $perms 'allow'
  if ($null -eq $allow) { $allow = @() }
  if (-not ($allow -is [array])) { Quit 3 "left untouched: ${Target}: permissions.allow has another shape" }
  $wanted = Get-Prop $patchPerms 'allow'
  $missing = @($wanted | Where-Object { $allow -notcontains $_ })
  if ($missing.Count -gt 0) { Set-Prop $perms 'allow' (@($allow) + $missing); $changed = $true }
}

$note = ''
if ((Get-Prop $settings 'disableAllHooks') -eq $true) { $note = '; disableAllHooks' }
if (-not $changed) { Write-Output ('exists' + $note); exit 0 }

$dir = Split-Path -Parent $Target
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
if ($existed) {
  if ([IO.File]::ReadAllText($Target, $utf8) -ne $raw) { Quit 4 "file changed while merging, run again: $Target" }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backup = "$Target.bak-coordinator-kit-$stamp"
  $i = 2
  while (Test-Path -LiteralPath $backup) { $backup = "$Target.bak-coordinator-kit-$stamp-$i"; $i++ }
  try { Copy-Item -LiteralPath $Target -Destination $backup } catch { Quit 4 "cannot make a backup: $backup" }
}
$valid = $false
try {
  [IO.File]::WriteAllText($Target, ($settings | ConvertTo-Json -Depth 100) + "`n", $utf8)
  $valid = Test-Object ([IO.File]::ReadAllText($Target, $utf8) | ConvertFrom-Json)
} catch { $valid = $false }
if (-not $valid) {
  if ($existed) { [IO.File]::WriteAllText($Target, $raw, $utf8) }
  Quit 4 "write failed: $Target"
}
if ($existed) { Write-Output ('added' + $note) } else { Write-Output ('created' + $note) }
exit 0

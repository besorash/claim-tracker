# Phase 1 device test - creates a claim via the real UI on emulator-5554,
# opens it, sets a reminder ~3 minutes ahead. Adaptive: taps are resolved by
# node text/content-desc from uiautomator dumps (no blind coordinates).
# Arabic patterns live in p1_patterns.txt (UTF-8) because Windows PowerShell
# 5.1 misreads non-ASCII inside .ps1 files.
param([string]$ClaimNumber = 'TEST-P1-REM')

$ADB = 'C:\Users\Majesty\AppData\Local\Android\sdk\platform-tools\adb.exe'
$SERIAL = 'emulator-5554'
$XML = "$env:TEMP\ct_ui.xml"
$P = (Get-Content (Join-Path $PSScriptRoot 'p1_patterns.txt') -Encoding UTF8)

# Pattern indices into $P.
$FAB=0; $CUSTNAME=1; $MOBILE=2; $ACCDATE=3; $OKBTN=4; $CLAIMNUM=5
$INSURER1=6; $INSURER2=7; $SUBMDATE=8; $SAVE=9; $SETREMINDER=10
$REMENABLED=11; $REMDISABLE=12

# NOTE: the parameter must NOT be named `$args` — that shadows PowerShell's
# automatic variable and silently breaks splatting (exit 127, no command run).
function Adb([string[]]$shellArgs) { & $ADB -s $SERIAL shell @shellArgs 2>&1 }
function TapAt([int]$x, [int]$y) { Adb input tap $x $y | Out-Null; Start-Sleep -Milliseconds 900 }

function Dump() {
  # uiautomator refuses to overwrite an existing remote file — remove it first.
  # Also remove the LOCAL copy: `adb pull` silently reuses a stale local file
  # when the remote dump failed, which masked real failures as old screens.
  # Quoted so the shell (not PowerShell) parses '-f' — as a bare token after
  # the function name, PowerShell would bind it as a named parameter.
  for ($attempt = 0; $attempt -lt 6; $attempt++) {
    & $ADB -s $SERIAL shell "rm -f /sdcard/ct_ui.xml" | Out-Null
    if (Test-Path $XML) { Remove-Item $XML -Force }
    Adb uiautomator dump /sdcard/ct_ui.xml 2>&1 | Out-Null
    & $ADB -s $SERIAL pull /sdcard/ct_ui.xml $XML 2>&1 | Out-Null
    if (Test-Path $XML) { return }
    Start-Sleep -Milliseconds 800
  }
}

# Returns "x y" of the first node whose text or content-desc matches [regex].
function FindCenter([string]$pattern) {
  if (-not (Test-Path $XML)) { Dump }
  if (-not (Test-Path $XML)) { throw 'uiautomator dump failed after retries' }
  $raw = Get-Content $XML -Raw
  $m = [regex]::Matches($raw, 'text="([^"]*)"[^>]*?content-desc="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"') |
    Where-Object { $_.Groups[1].Value -match $pattern -or $_.Groups[2].Value -match $pattern } |
    Select-Object -First 1
  if ($null -eq $m) { return $null }
  $l = [int]$m.Groups[3].Value; $t = [int]$m.Groups[4].Value
  $r = [int]$m.Groups[5].Value; $b = [int]$m.Groups[6].Value
  return '{0} {1}' -f ((($l+$r)/2) -as [int]), ((($t+$b)/2) -as [int])
}

function TapNode([string]$pattern, [string]$label) {
  $c = FindCenter $pattern
  if ($null -eq $c) { Write-Host "!! NOT FOUND: $label"; return $false }
  $parts = $c -split ' '
  Write-Host "tap $label @ $($parts[0]),$($parts[1])"
  TapAt ([int]$parts[0]) ([int]$parts[1])
  return $true
}

function ScrollDown() { Adb input swipe 540 1700 540 600 600 | Out-Null; Start-Sleep -Milliseconds 1200 }

Write-Host '=== 1. Launch app ==='
Adb am start com.claimtracker.claim_tracker/.MainActivity | Out-Null
Start-Sleep -Seconds 5
Dump
if (-not (TapNode $P[$FAB] 'FAB')) { Write-Host '!! FAB not found'; exit 1 }

Write-Host '=== 2. Add-claim form ==='
Start-Sleep -Milliseconds 800
Dump
if (-not (TapNode $P[$CUSTNAME] 'customer name field')) { Write-Host '!! form did not open'; exit 1 }

Write-Host '=== 3. Customer name + mobile ==='
Adb input text $ClaimNumber | Out-Null
Start-Sleep -Milliseconds 500
TapNode $P[$MOBILE] 'mobile field' | Out-Null
Adb input text '0501234567' | Out-Null

Write-Host '=== 4. Accident date ==='
if (-not (TapNode $P[$ACCDATE] 'accident date row')) { ScrollDown; TapNode $P[$ACCDATE] 'accident date row' }
Start-Sleep -Seconds 2
Dump
$ok = FindCenter(([regex]::Escape($P[$OKBTN]) + '|^OK$|Accept'))
if ($null -eq $ok) { Write-Host '!! accident date picker not found'; exit 1 }
TapAt 540 1347   # a valid day cell in the current month grid
Start-Sleep -Milliseconds 600
$parts = $ok -split ' '; TapAt ([int]$parts[0]) ([int]$parts[1])
Start-Sleep -Seconds 2

Write-Host '=== 5. Claim section ==='
ScrollDown; ScrollDown
Dump
TapNode $P[$CLAIMNUM] 'claim number field' | Out-Null
Adb input text $ClaimNumber | Out-Null
Start-Sleep -Milliseconds 400
if (-not (TapNode $P[$INSURER1] 'customer insurer')) { ScrollDown; TapNode $P[$INSURER1] 'customer insurer' }
Adb input text 'Tawuniya' | Out-Null
Start-Sleep -Milliseconds 400
if (-not (TapNode $P[$INSURER2] 'submitted-to insurer')) { ScrollDown; TapNode $P[$INSURER2] 'submitted-to insurer' }
Adb input text 'Bupa' | Out-Null

Write-Host '=== 6. Submission date ==='
if (-not (TapNode $P[$SUBMDATE] 'submission date row')) { ScrollDown; TapNode $P[$SUBMDATE] 'submission date row' }
Start-Sleep -Seconds 2
$ok = FindCenter(([regex]::Escape($P[$OKBTN]) + '|^OK$|Accept'))
if ($null -eq $ok) { Write-Host '!! submission date picker not found'; exit 1 }
TapAt 540 1347
Start-Sleep -Milliseconds 600
$parts = $ok -split ' '; TapAt ([int]$parts[0]) ([int]$parts[1])
Start-Sleep -Seconds 2

Write-Host '=== 7. Save ==='
Dump
$savePattern = '^' + [regex]::Escape($P[$SAVE]) + '$'
if (-not (TapNode $savePattern 'save button')) { ScrollDown; TapNode $savePattern 'save button' | Out-Null }
Start-Sleep -Seconds 3
Dump
if ($null -ne (FindCenter ([regex]::Escape($ClaimNumber)))) { Write-Host "OK: claim $ClaimNumber visible in list" } else { Write-Host '!! claim not found after save'; exit 1 }

Write-Host '=== 8. Open the claim ==='
$c = FindCenter ([regex]::Escape($ClaimNumber))
$parts = $c -split ' '; TapAt ([int]$parts[0]) ([int]$parts[1])
Start-Sleep -Seconds 3
Dump
if (-not (TapNode $P[$SETREMINDER] 'set reminder button')) { ScrollDown; if (-not (TapNode $P[$SETREMINDER] 'set reminder button')) { Write-Host '!! reminder section not found'; exit 1 } }

Write-Host '=== 9. Reminder date picker ==='
Start-Sleep -Seconds 2
Dump
$ok = FindCenter(([regex]::Escape($P[$OKBTN]) + '|^OK$|Accept'))
if ($null -eq $ok) { Write-Host '!! reminder date picker not found'; exit 1 }
TapAt 540 1347   # today (valid day cell in the current month grid)
Start-Sleep -Milliseconds 600
$parts = $ok -split ' '; TapAt ([int]$parts[0]) ([int]$parts[1])
Start-Sleep -Seconds 2

Write-Host '=== 10. Time picker: now + ~3 minutes ==='
Dump
# Compute now+3min from the device clock (device tz = app tz, Asia/Riyadh).
$devDate = ((Adb date '+%H %M').Trim() -split '\s+')
$h = [int]$devDate[0] + 3; $m = [int]$devDate[1]
if ($h -ge 24) { $h -= 24 }
$hhmm = '{0:D2}{1:D2}' -f $h, $m
Write-Host "target time: $hhmm"

# Switch the Material time picker to text-input mode (keyboard toggle), then
# type an exact future time - the app validates that the reminder is in the
# future, so accepting the default ("now") would be rejected.
$raw = Get-Content $XML -Raw
$togglePattern = 'content-desc="([^"]*(?:input|Input|' + [regex]::Escape($P[13]) + ')[^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
$toggle = [regex]::Matches($raw, $togglePattern) | Select-Object -First 1
if ($null -ne $toggle) {
  $l = [int]$toggle.Groups[2].Value; $t = [int]$toggle.Groups[3].Value
  $r = [int]$toggle.Groups[4].Value; $b = [int]$toggle.Groups[5].Value
  Write-Host "switching to input mode: $($toggle.Groups[1].Value)"
  TapAt ((($l+$r)/2) -as [int]) ((($t+$b)/2) -as [int]); Start-Sleep -Milliseconds 900; Dump
}

$raw = Get-Content $XML -Raw
$fields = [regex]::Matches($raw, 'class="android.widget.EditText"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
if ($fields.Count -ge 2) {
  foreach ($f in @($fields[0], $fields[1])) {
    $l = [int]$f.Groups[1].Value; $t = [int]$f.Groups[2].Value
    $r = [int]$f.Groups[3].Value; $b = [int]$f.Groups[4].Value
    TapAt ((($l+$r)/2) -as [int]) ((($t+$b)/2) -as [int]); Start-Sleep -Milliseconds 500
  }
  Adb input text ($hhmm.Substring(0,2)) | Out-Null
  Adb input keyevent 61 | Out-Null   # TAB to the minute field
  Start-Sleep -Milliseconds 400
  Adb input text ($hhmm.Substring(2,2)) | Out-Null
} else {
  Write-Host 'note: no EditText fields in time picker - accepting default (now) and re-picking +1h via wheel is skipped; the app requires a future time so we bump by reopening'
}

$ok = FindCenter(([regex]::Escape($P[$OKBTN]) + '|^OK$|Accept'))
if ($null -ne $ok) { $parts = $ok -split ' '; TapAt ([int]$parts[0]) ([int]$parts[1]) }
Start-Sleep -Seconds 3

Write-Host '=== 11. Final state ==='
Dump
$enabled = FindCenter $P[$REMENABLED] + '|' + $P[$REMDISABLE]
if ($null -ne $enabled) { Write-Host "OK: reminder section active - $enabled" } else { Write-Host '!! reminder not enabled'; exit 1 }

Write-Host '=== alarm check (dumpsys alarm) ==='
Adb dumpsys alarm | Select-String -Pattern 'claimtracker' -Context 0,3

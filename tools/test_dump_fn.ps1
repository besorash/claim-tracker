# Isolate test of the Adb/Dump pattern used by p1_reminder_test.ps1.
$ADB = 'C:\Users\Majesty\AppData\Local\Android\sdk\platform-tools\adb.exe'
$SERIAL = 'emulator-5554'
$XML = "$env:TEMP\ct_ui_fn.xml"

function Adb([string[]]$shellArgs) { & $ADB -s $SERIAL shell @shellArgs 2>&1 }

Write-Host 'step1 rm:'
& $ADB -s $SERIAL shell "rm -f /sdcard/ct_ui.xml" | Out-Null
if (Test-Path $XML) { Remove-Item $XML -Force }
Write-Host 'step2 dump:'
Adb @('uiautomator', 'dump', '/sdcard/ct_ui.xml') 2>&1 | Out-Null
Write-Host "dump exit: $LASTEXITCODE"
Write-Host 'step3 pull:'
& $ADB -s $SERIAL pull /sdcard/ct_ui.xml $XML 2>&1 | Out-Null
Write-Host "pull exit: $LASTEXITCODE"
if (Test-Path $XML) { Write-Host ("OK size: " + (Get-Item $XML).Length) } else { Write-Host 'FAIL: no local file' }

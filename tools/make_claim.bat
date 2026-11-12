@echo off
rem Creates one claim (TEST-CLAIM-###) through the real UI on emulator-5554.
rem Usage: make_claim.bat <claim-number> [accident-day-x] [submission-day-x]
setlocal EnableExtensions
set ADB=C:\Users\Majesty\AppData\Local\Android\sdk\platform-tools\adb.exe
set CN=%~1
set ADAYX=%~2
if "%ADAYX%"=="" set ADAYX=414
set SDAYX=%~3
if "%SDAYX%"=="" set SDAYX=162

rem 1. Open the add-claim form from the dashboard.
%ADB% shell input tap 234 2012
ping -n 4 127.0.0.1 >nul

rem 2. Customer section (top of form, no scroll needed).
%ADB% shell input tap 540 420
ping -n 2 127.0.0.1 >nul
%ADB% shell input text %CN%
%ADB% shell input tap 540 598
ping -n 2 127.0.0.1 >nul
%ADB% shell input text 0501234567

rem 3. Accident date via picker (day cell + OK at RTL-left position).
%ADB% shell input tap 540 1318
ping -n 5 127.0.0.1 >nul
%ADB% shell input tap %ADAYX% 1347
ping -n 2 127.0.0.1 >nul
%ADB% shell input tap 173 1877
ping -n 5 127.0.0.1 >nul

rem 4. Scroll to the claim section.
%ADB% shell input swipe 540 1800 540 600 700
ping -n 3 127.0.0.1 >nul

rem 5. Claim number + both insurers.
%ADB% shell input tap 540 978
ping -n 2 127.0.0.1 >nul
%ADB% shell input text %CN%
%ADB% shell input tap 540 1156
ping -n 2 127.0.0.1 >nul
%ADB% shell input text Tawuniya
%ADB% shell input tap 540 1336
ping -n 2 127.0.0.1 >nul
%ADB% shell input text Bupa

rem 6. Submission date via picker.
%ADB% shell input tap 540 1508
ping -n 5 127.0.0.1 >nul
%ADB% shell input tap %SDAYX% 1347
ping -n 2 127.0.0.1 >nul
%ADB% shell input tap 173 1877
ping -n 5 127.0.0.1 >nul

rem 7. Save (RTL: save button is the wide one on the left).
%ADB% shell input tap 456 2243
ping -n 5 127.0.0.1 >nul
endlocal

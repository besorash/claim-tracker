@echo off
rem Fills the claim form (TEST-CLAIM-###) with ASCII values via `input text`.
rem Usage: fill_claim.bat <claim-number>
setlocal
set ADB=C:\Users\Majesty\AppData\Local\Android\sdk\platform-tools\adb.exe
set CN=%~1

%ADB% shell input tap 540 420
ping -n 2 127.0.0.1 >nul
%ADB% shell input text %CN%

%ADB% shell input tap 540 598
ping -n 2 127.0.0.1 >nul
%ADB% shell input text 0501234567

%ADB% shell input tap 540 1491
ping -n 2 127.0.0.1 >nul
%ADB% shell input text %CN%

%ADB% shell input tap 540 1669
ping -n 2 127.0.0.1 >nul
%ADB% shell input text Tawuniya

%ADB% shell input tap 540 1848
ping -n 2 127.0.0.1 >nul
%ADB% shell input text Bupa
endlocal

# Inspect the current uiautomator dump (texts + clickable nodes).
$x = [IO.File]::ReadAllText((Join-Path $env:TEMP 'ct_ui.xml'), [Text.Encoding]::UTF8)
Write-Host '--- texts ---'
[regex]::Matches($x, 'text="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -First 30
Write-Host '--- clickable (content-desc + bounds) ---'
[regex]::Matches($x, 'content-desc="([^"]+)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"') |
  ForEach-Object {
    $l = [int]$_.Groups[2].Value; $t = [int]$_.Groups[3].Value
    $r = [int]$_.Groups[4].Value; $b = [int]$_.Groups[5].Value
    '{0} @ center({1},{2})' -f $_.Groups[1].Value, (($l+$r)/2), (($t+$b)/2)
  } | Select-Object -First 30

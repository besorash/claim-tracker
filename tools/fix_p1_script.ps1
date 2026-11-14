# One-shot repair of p1_reminder_test.ps1 (run once, then delete).
$p = Join-Path $PSScriptRoot 'p1_reminder_test.ps1'
$lines = [IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8)
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match "FindCenter\(\[regex\]::Escape\(`$P\[`$OKBTN\]\) \+ '\|\^OK`\$\|Accept'\s*$") {
    $lines[$i] = '$ok = FindCenter(([regex]::Escape($P[$OKBTN]) + ''|^OK$|Accept''))'
  }
}
[IO.File]::WriteAllLines($p, $lines, (New-Object Text.UTF8Encoding($false)))
Write-Host 'repair done'

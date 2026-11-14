# Clickable claim cards (TEST-CLAIM-nnn) with center coords.
param([string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml')
$x = Get-Content $Xml -Raw
[regex]::Matches($x, '<node [^>]*/>') | ForEach-Object {
  $n = $_.Value
  if ($n -notmatch 'TEST-CLAIM-(\d+)') { return }
  $num = $Matches[1]
  if ($n -notmatch 'clickable="true"') { return }
  $b = [regex]::Match($n, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if (-not $b.Success) { return }
  $l=[int]$b.Groups[1].Value; $t=[int]$b.Groups[2].Value
  $r=[int]$b.Groups[3].Value; $bb=[int]$b.Groups[4].Value
  'claim-{0} at ({1},{2})' -f $num, (($l+$r)/2), (($t+$bb)/2)
}

# All nodes whose center falls within a y-band (calendar grid inspection).
param(
  [string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml',
  [int]$YMin = 900,
  [int]$YMax = 1700
)
$x = Get-Content $Xml -Raw
[regex]::Matches($x, '<node [^>]*/>') | ForEach-Object {
  $n = $_.Value
  $b = [regex]::Match($n, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if (-not $b.Success) { return }
  $l=[int]$b.Groups[1].Value; $t=[int]$b.Groups[2].Value
  $r=[int]$b.Groups[3].Value; $bb=[int]$b.Groups[4].Value
  $cy = ($t+$bb)/2
  if ($cy -lt $YMin -or $cy -gt $YMax) { return }
  $cd = ([regex]::Match($n, 'content-desc="([^"]*)"')).Groups[1].Value
  $tx = ([regex]::Match($n, ' text="([^"]*)"')).Groups[1].Value
  $cls = ([regex]::Match($n, 'class="([^"]*)"')).Groups[1].Value
  $clk = if ($n -match 'clickable="true"') { 'CLICK' } else { '' }
  '{0},{1}  "{2}" "{3}" {4} {5}' -f (($l+$r)/2), $cy, $cd, $tx, $cls, $clk
}

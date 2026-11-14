# Every node with text/hint/desc + center, in document order.
param([string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml')
$x = Get-Content $Xml -Raw
[regex]::Matches($x, '<node [^>]*>') | ForEach-Object {
  $n = $_.Value
  $text = ([regex]::Match($n, ' text="([^"]*)"')).Groups[1].Value
  $hint = ([regex]::Match($n, ' hint="([^"]*)"')).Groups[1].Value
  $cd = ([regex]::Match($n, 'content-desc="([^"]*)"')).Groups[1].Value
  if ($text -eq '' -and $hint -eq '' -and $cd -eq '') { return }
  $b = [regex]::Match($n, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if (-not $b.Success) { return }
  $l=[int]$b.Groups[1].Value; $t=[int]$b.Groups[2].Value
  $r=[int]$b.Groups[3].Value; $bb=[int]$b.Groups[4].Value
  'y={0,-5} text="{1}" hint="{2}" desc="{3}"' -f [int](($t+$bb)/2), $text, $hint, $cd
}

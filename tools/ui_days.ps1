# All nodes whose content-desc or text is 1-2 chars (date-picker day cells).
param([string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml')
$x = Get-Content $Xml -Raw
[regex]::Matches($x, '<node [^>]*/>') | ForEach-Object {
  $n = $_.Value
  $cd = ([regex]::Match($n, 'content-desc="([^"]*)"')).Groups[1].Value
  $tx = ([regex]::Match($n, ' text="([^"]*)"')).Groups[1].Value
  $val = if ($cd.Length -ge 1 -and $cd.Length -le 2) { $cd } elseif ($tx.Length -ge 1 -and $tx.Length -le 2) { $tx } else { return }
  $b = [regex]::Match($n, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if (-not $b.Success) { return }
  $l=[int]$b.Groups[1].Value; $t=[int]$b.Groups[2].Value
  $r=[int]$b.Groups[3].Value; $bb=[int]$b.Groups[4].Value
  'day="{0}" at ({1},{2})' -f $val, (($l+$r)/2), (($t+$bb)/2)
}

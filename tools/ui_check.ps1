# Dumps every node with text/hint/desc + center to a UTF-8 file (readable via read_file).
param(
  [string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml',
  [string]$Out = 'C:\Users\Majesty\AppData\Local\Temp\ui_check.txt'
)
$utf8 = New-Object System.Text.UTF8Encoding $false
$x = [System.IO.File]::ReadAllText($Xml, $utf8)
$lines = New-Object System.Collections.Generic.List[string]
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
  $cx = [int](($l+$r)/2); $cy = [int](($t+$bb)/2)
  $line = "y=$cy x=$cx text='$text' hint='$hint' desc='$cd'"
  $lines.Add($line)
}
[System.IO.File]::WriteAllLines($Out, $lines, (New-Object System.Text.UTF8Encoding $false))

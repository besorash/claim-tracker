# Dumps clickable nodes (content-desc + bounds) from a uiautomator XML file.
param([string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml')
$x = Get-Content $Xml -Raw
[regex]::Matches($x, 'content-desc="([^"]+)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"') |
  ForEach-Object {
    $desc = $_.Groups[1].Value
    $l = [int]$_.Groups[2].Value; $t = [int]$_.Groups[3].Value
    $r = [int]$_.Groups[4].Value; $b = [int]$_.Groups[5].Value
    '{0} @ center({1},{2}) bounds[{3},{4}-{5},{6}]' -f $desc, (($l+$r)/2), (($t+$b)/2), $l, $t, $r, $b
  }

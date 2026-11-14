# Decode content-desc / text / hint of all nodes to a UTF-8 file (no console mojibake).
param([string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml')
$out = New-Object System.Collections.Generic.List[string]
$x2 = [System.IO.File]::ReadAllText($Xml, [System.Text.Encoding]::UTF8)
[regex]::Matches($x2, '<node [^>]*/>') | ForEach-Object {
  $n = $_.Value
  $cd = ([regex]::Match($n, 'content-desc="([^"]*)"')).Groups[1].Value
  $tx = ([regex]::Match($n, ' text="([^"]*)"')).Groups[1].Value
  $ht = ([regex]::Match($n, ' hint="([^"]*)"')).Groups[1].Value
  if ($cd -or $tx -or $ht) {
    $b = [regex]::Match($n, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
    $cls = ([regex]::Match($n, 'class="([^"]*)"')).Groups[1].Value
    $out.Add(('{0} | {1} | text="{2}" desc="{3}" hint="{4}"' -f $cls, $b.Value, $tx, $cd, $ht))
  }
}
[System.IO.File]::WriteAllLines('tools/ui_decoded.txt', $out, [System.Text.Encoding]::UTF8)

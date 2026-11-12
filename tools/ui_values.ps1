# Dumps EditText nodes with their current text values + bounds.
param([string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml')
$x = Get-Content $Xml -Raw
[regex]::Matches($x, '<node [^>]*class="android.widget.EditText"[^>]*>') |
  ForEach-Object {
    $n = $_.Value
    $text = ([regex]::Match($n, ' text="([^"]*)"')).Groups[1].Value
    $hint = ([regex]::Match($n, ' hint="([^"]*)"')).Groups[1].Value
    $b = [regex]::Match($n, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
    if ($b.Success) {
      $l = [int]$b.Groups[1].Value; $t = [int]$b.Groups[2].Value
      $r = [int]$b.Groups[3].Value; $bb = [int]$b.Groups[4].Value
      'text="{0}" hint="{1}" @ center({2},{3})' -f $text, $hint, (($l+$r)/2), (($t+$bb)/2)
    } else {
      "text='$text' hint='$hint'"
    }
  }

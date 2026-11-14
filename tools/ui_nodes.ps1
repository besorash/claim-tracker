# Full node listing: class, text, hint, clickable, center — to locate date rows & buttons.
param([string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml')
$x = Get-Content $Xml -Raw
[regex]::Matches($x, '<node [^>]*>') | ForEach-Object {
  $n = $_.Value
  if ($n -notmatch 'class="android.widget.(Button|EditText)"' -and
      $n -notmatch 'clickable="true"') { return }
  $cls = ([regex]::Match($n, 'class="([^"]*)"')).Groups[1].Value
  $text = ([regex]::Match($n, ' text="([^"]*)"')).Groups[1].Value
  $hint = ([regex]::Match($n, ' hint="([^"]*)"')).Groups[1].Value
  $cd = ([regex]::Match($n, 'content-desc="([^"]*)"')).Groups[1].Value
  $click = ($n -match 'clickable="true"')
  $b = [regex]::Match($n, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if (-not $b.Success) { return }
  $l=[int]$b.Groups[1].Value; $t=[int]$b.Groups[2].Value
  $r=[int]$b.Groups[3].Value; $bb=[int]$b.Groups[4].Value
  '{0,-9} click={1,-5} text="{2}" hint="{3}" desc="{4}" @ ({5},{6})' -f `
    ($cls -replace 'android.widget.',''), $click, $text, $hint, $cd, (($l+$r)/2), (($t+$bb)/2)
}

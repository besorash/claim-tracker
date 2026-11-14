# Lists non-day buttons (OK/Cancel/nav) with centers, using safe string building.
param([string]$Xml = 'C:\Users\Majesty\AppData\Local\Temp\ct_ui.xml')
$x = Get-Content $Xml -Raw
[regex]::Matches($x, '<node [^>]*class="android.widget.Button"[^>]*>') | ForEach-Object {
  $n = $_.Value
  $cd = ([regex]::Match($n, 'content-desc="([^"]*)"')).Groups[1].Value
  if ($cd -match '^[0-9]+,') { return } # skip day cells "N, ..."
  $b = [regex]::Match($n, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if (-not $b.Success) { return }
  $l=[int]$b.Groups[1].Value; $t=[int]$b.Groups[2].Value
  $r=[int]$b.Groups[3].Value; $bb=[int]$b.Groups[4].Value
  $cx = [int](($l+$r)/2); $cy = [int](($t+$bb)/2)
  '(' + $cx + ',' + $cy + ')  ' + $cd
}

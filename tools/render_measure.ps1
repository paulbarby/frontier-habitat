# RENDER: mean brightness of screen boxes in two screenshots (day / night) and the ratio.
#   powershell -File tools/render_measure.ps1 day.png night.png "x0,y0,x1,y1" ["x0,y0,x1,y1" ...]
# Prints, per box: mean display luminance (0..255, Rec.709 weights on sRGB values) in each
# image and night/day, plus the same in linear light.
param([string]$dayPng, [string]$nightPng, [Parameter(ValueFromRemainingArguments = $true)][string[]]$boxes)
Add-Type -AssemblyName System.Drawing
$imgA = [System.Drawing.Bitmap]::FromFile((Resolve-Path $dayPng))
$imgB = [System.Drawing.Bitmap]::FromFile((Resolve-Path $nightPng))
function lin([double]$c) { $c = $c / 255.0; if ($c -le 0.04045) { return $c / 12.92 } else { return [Math]::Pow(($c + 0.055) / 1.055, 2.4) } }
foreach ($bx in $boxes) {
  $v = $bx.Split(',') | ForEach-Object { [int]$_ }
  $sa = 0.0; $sb = 0.0; $la = 0.0; $lb = 0.0; $n = 0
  for ($y = $v[1]; $y -le $v[3]; $y += 2) {
    for ($x = $v[0]; $x -le $v[2]; $x += 2) {
      $p = $imgA.GetPixel($x, $y); $q = $imgB.GetPixel($x, $y)
      $sa += 0.2126 * $p.R + 0.7152 * $p.G + 0.0722 * $p.B
      $sb += 0.2126 * $q.R + 0.7152 * $q.G + 0.0722 * $q.B
      $la += 0.2126 * (lin $p.R) + 0.7152 * (lin $p.G) + 0.0722 * (lin $p.B)
      $lb += 0.2126 * (lin $q.R) + 0.7152 * (lin $q.G) + 0.0722 * (lin $q.B)
      $n++
    }
  }
  "{0,-20} day {1,6:N1}  night {2,6:N1}  ratio {3,5:P0}   linear ratio {4,5:P0}" -f $bx, ($sa / $n), ($sb / $n), ($sb / $sa), ($lb / $la)
}
$imgA.Dispose(); $imgB.Dispose()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'assets\branding\admin_facile_icon.png'

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Icône source introuvable : $sourcePath"
}

$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
try {
    if ($source.Width -ne $source.Height -or $source.Width -lt 512) {
        throw "L’icône doit être carrée et mesurer au moins 512 px ($($source.Width)x$($source.Height) détectés)."
    }

    function Write-ResizedPng {
        param(
            [System.Drawing.Bitmap]$Image,
            [string]$RelativePath,
            [int]$Size
        )

        $outputPath = Join-Path $projectRoot $RelativePath
        $outputDirectory = Split-Path -Parent $outputPath
        [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

        $target = [System.Drawing.Bitmap]::new(
            $Size,
            $Size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        try {
            $target.SetResolution(96, 96)
            $graphics = [System.Drawing.Graphics]::FromImage($target)
            try {
                $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage(
                    $Image,
                    [System.Drawing.Rectangle]::new(0, 0, $Size, $Size),
                    0,
                    0,
                    $Image.Width,
                    $Image.Height,
                    [System.Drawing.GraphicsUnit]::Pixel
                )
            }
            finally {
                $graphics.Dispose()
            }
            $target.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $target.Dispose()
        }
    }

    $launcherSizes = [ordered]@{
        'mipmap-mdpi' = 48
        'mipmap-hdpi' = 72
        'mipmap-xhdpi' = 96
        'mipmap-xxhdpi' = 144
        'mipmap-xxxhdpi' = 192
    }

    foreach ($entry in $launcherSizes.GetEnumerator()) {
        Write-ResizedPng `
            -Image $source `
            -RelativePath "android\app\src\main\res\$($entry.Key)\ic_launcher.png" `
            -Size $entry.Value
    }

    Write-ResizedPng `
        -Image $source `
        -RelativePath 'android\app\src\main\res\drawable\adminfacile_brand_icon.png' `
        -Size 432
    Write-ResizedPng `
        -Image $source `
        -RelativePath 'android\app\src\main\res\drawable\adminfacile_splash.png' `
        -Size 288

    $corner = $source.GetPixel(0, 0)
    $cornerHex = '#{0:X2}{1:X2}{2:X2}' -f $corner.R, $corner.G, $corner.B
    Write-Output "Branding Android généré depuis assets/branding/admin_facile_icon.png ($($source.Width)x$($source.Height), coin $cornerHex, alpha $($corner.A))."
}
finally {
    $source.Dispose()
}

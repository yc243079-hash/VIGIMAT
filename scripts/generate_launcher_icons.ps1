Add-Type -AssemblyName System.Drawing

$sizes = @{
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png" = 48
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png" = 72
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png" = 96
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png" = 144
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" = 192
}

foreach ($item in $sizes.GetEnumerator()) {
    $path = $item.Key
    $sz = [float]$item.Value

    $bmp = [System.Drawing.Bitmap]::new([int]$sz, [int]$sz)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # Fond transparent
    $g.Clear([System.Drawing.Color]::Transparent)

    # 1. Base Squircle Tactique Sombre
    $radius = $sz * 0.22
    $bgRect = [System.Drawing.RectangleF]::new(0, 0, $sz, $sz)
    $bgBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $bgRect,
        [System.Drawing.Color]::FromArgb(255, 14, 35, 62),
        [System.Drawing.Color]::FromArgb(255, 7, 18, 33),
        90.0
    )

    $bgPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = $radius * 2
    $bgPath.AddArc(0, 0, $d, $d, 180, 90)
    $bgPath.AddArc($sz - $d, 0, $d, $d, 270, 90)
    $bgPath.AddArc($sz - $d, $sz - $d, $d, $d, 0, 90)
    $bgPath.AddArc(0, $sz - $d, $d, $d, 90, 90)
    $bgPath.CloseFigure()
    $g.FillPath($bgBrush, $bgPath)

    # Bordure de squircle
    $iconBorderPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(90, 16, 185, 129), $sz * 0.03)
    $g.DrawPath($iconBorderPen, $bgPath)

    # 2. Bouclier Hexagonal Tactique
    $shieldPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    [System.Drawing.PointF[]]$pts = @(
        [System.Drawing.PointF]::new($sz * 0.50, $sz * 0.08),
        [System.Drawing.PointF]::new($sz * 0.88, $sz * 0.22),
        [System.Drawing.PointF]::new($sz * 0.86, $sz * 0.62),
        [System.Drawing.PointF]::new($sz * 0.50, $sz * 0.92),
        [System.Drawing.PointF]::new($sz * 0.14, $sz * 0.62),
        [System.Drawing.PointF]::new($sz * 0.12, $sz * 0.22)
    )
    $shieldPath.AddPolygon($pts)

    $shieldBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $bgRect,
        [System.Drawing.Color]::FromArgb(255, 23, 56, 94),
        [System.Drawing.Color]::FromArgb(255, 11, 28, 50),
        45.0
    )
    $g.FillPath($shieldBrush, $shieldPath)

    $shieldPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(235, 16, 185, 129), $sz * 0.04)
    $shieldPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($shieldPen, $shieldPath)

    # 3. Le Grand V Aérodynamique (Blanc & Cyan)
    $vPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    [System.Drawing.PointF[]]$vPts = @(
        [System.Drawing.PointF]::new($sz * 0.25, $sz * 0.28),
        [System.Drawing.PointF]::new($sz * 0.50, $sz * 0.74),
        [System.Drawing.PointF]::new($sz * 0.75, $sz * 0.28),
        [System.Drawing.PointF]::new($sz * 0.64, $sz * 0.28),
        [System.Drawing.PointF]::new($sz * 0.50, $sz * 0.56),
        [System.Drawing.PointF]::new($sz * 0.36, $sz * 0.28)
    )
    $vPath.AddPolygon($vPts)

    $vBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $bgRect,
        [System.Drawing.Color]::FromArgb(255, 255, 255, 255),
        [System.Drawing.Color]::FromArgb(255, 6, 182, 212),
        90.0
    )
    $g.FillPath($vBrush, $vPath)

    # 4. Clé de Maintenance Centrale
    $wPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    [System.Drawing.PointF[]]$wPts = @(
        [System.Drawing.PointF]::new($sz * 0.50, $sz * 0.33),
        [System.Drawing.PointF]::new($sz * 0.58, $sz * 0.46),
        [System.Drawing.PointF]::new($sz * 0.50, $sz * 0.60),
        [System.Drawing.PointF]::new($sz * 0.42, $sz * 0.46)
    )
    $wPath.AddPolygon($wPts)
    $wBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 16, 185, 129))
    $g.FillPath($wBrush, $wPath)

    # 5. Balise Centrale Vert Radar
    $dotR = $sz * 0.045
    $dotBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 52, 211, 153))
    $g.FillEllipse($dotBrush, $sz * 0.50 - $dotR, $sz * 0.46 - $dotR, $dotR * 2, $dotR * 2)

    # 6. Trinité Mali (Vert, Or, Rouge)
    $barW = $sz * 0.055
    $barH = $sz * 0.025
    $barY = $sz * 0.14
    $g.FillRectangle([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 20, 181, 58)), $sz * 0.40, $barY, $barW, $barH)
    $g.FillRectangle([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 252, 209, 22)), $sz * 0.47, $barY, $barW, $barH)
    $g.FillRectangle([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 206, 17, 38)), $sz * 0.54, $barY, $barW, $barH)

    # Sauvegarde PNG
    $dir = Split-Path $path -Parent
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force }
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

    $g.Dispose()
    $bmp.Dispose()
    Write-Output "Généré avec succès : $path ($sz x $sz)"
}

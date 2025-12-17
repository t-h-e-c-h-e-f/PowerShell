# Run as administrator so it can install ImageMagick and create and delete the temp folder
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break
}

# Check if 'C:\temp' exists
if (!(Test-Path 'C:\temp')) {
    New-Item -ItemType Directory -Force -Path 'C:\temp'
}
Add-Type -AssemblyName System.Windows.Forms

$imageMagickPath = 'C:\Program Files\ImageMagick\magick.exe'

if (!(Test-Path -Path $imageMagickPath)) {
    Write-Host 'ImageMagick is not installed. Installing now...'
    $installerPath = 'C:\temp\ImageMagickInstaller.exe'
    $installerURL = 'https://imagemagick.org/archive/binaries/ImageMagick-7.1.1-12-Q16-x64-static.exe'
    Invoke-WebRequest -Uri $installerURL -OutFile $installerPath
    Start-Process -FilePath $installerPath -ArgumentList '/SILENT /VERYSILENT /DIR="C:\Program Files\ImageMagick"' -Wait
    Remove-Item -Path $installerPath  # delete the installer
    Write-Host 'ImageMagick has been installed.'
}

$mainForm = New-Object System.Windows.Forms.Form
$mainForm.Text = 'CritterVet SVG to PNG Converter'
$mainForm.Size = New-Object System.Drawing.Size(600,200)
$mainForm.StartPosition = 'CenterScreen'

$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Filter = 'SVG Files (*.svg)|*.svg'
$openFileDialog.Multiselect = $true

$convertButton = New-Object System.Windows.Forms.Button
$convertButton.Location = New-Object System.Drawing.Point(180,50)
$convertButton.Size = New-Object System.Drawing.Size(200,30)
$convertButton.Text = 'Select File(s) to Convert'
$convertButton.Add_Click({
    $openFileDialog.ShowDialog()
    $selectedFiles = $openFileDialog.FileNames

    foreach ($file in $selectedFiles) {
        $pngFile = [IO.Path]::ChangeExtension($file, ".png")
        Write-Host "Converting......"
        Start-Process $imageMagickPath -ArgumentList "convert `"$file`" `"$pngFile`"" -NoNewWindow -Wait
        Write-Host "`"$file`" has been converted to `"$pngFile`"."
    }
})

$mainForm.Controls.Add($convertButton)
$mainForm.Add_Shown({$mainForm.Activate()})
[void]$mainForm.ShowDialog()

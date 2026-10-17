# Installs a self-contained Android SDK + emulator for testing the web build in
# real Android Chrome. No admin rights needed for this part. Running the emulator
# additionally requires the "Windows Hypervisor Platform" Windows feature.
#
#   SDK:  %LOCALAPPDATA%\Android\Sdk
#   JDK:  %LOCALAPPDATA%\Android\jdk17   (only used by sdkmanager/avdmanager)
#   AVDs: iron_phone (Pixel 7) and iron_tablet (Pixel Tablet), Android 14 + Google Play (has Chrome)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest is very slow with the progress bar

$Root    = Join-Path $env:LOCALAPPDATA "Android"
$Sdk     = Join-Path $Root "Sdk"
$JdkDir  = Join-Path $Root "jdk17"
$Image   = "system-images;android-34;google_apis_playstore;x86_64"
$JdkUrl  = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip"
$ToolUrl = "https://dl.google.com/android/repository/commandlinetools-win-9862592_latest.zip"

New-Item -ItemType Directory -Force $Root, $Sdk | Out-Null

if (-not (Test-Path (Join-Path $JdkDir "bin\java.exe"))) {
    Write-Host "== Downloading JDK 17"
    Invoke-WebRequest $JdkUrl -OutFile "$Root\jdk.zip"
    Expand-Archive "$Root\jdk.zip" -DestinationPath "$Root\jdk_tmp" -Force
    Move-Item (Get-ChildItem "$Root\jdk_tmp" -Directory | Select-Object -First 1).FullName $JdkDir
    Remove-Item "$Root\jdk.zip", "$Root\jdk_tmp" -Recurse -Force
}
$env:JAVA_HOME = $JdkDir
$env:ANDROID_HOME = $Sdk
$env:ANDROID_SDK_ROOT = $Sdk

$SdkManager = Join-Path $Sdk "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $SdkManager)) {
    Write-Host "== Downloading Android command-line tools"
    Invoke-WebRequest $ToolUrl -OutFile "$Root\cmdline.zip"
    Expand-Archive "$Root\cmdline.zip" -DestinationPath "$Root\cmdline_tmp" -Force
    New-Item -ItemType Directory -Force "$Sdk\cmdline-tools" | Out-Null
    if (Test-Path "$Sdk\cmdline-tools\latest") { Remove-Item "$Sdk\cmdline-tools\latest" -Recurse -Force }
    Move-Item "$Root\cmdline_tmp\cmdline-tools" "$Sdk\cmdline-tools\latest"
    Remove-Item "$Root\cmdline.zip", "$Root\cmdline_tmp" -Recurse -Force
}

Write-Host "== Accepting SDK licenses"
("y`n" * 30) | & $SdkManager --licenses | Out-Null

Write-Host "== Installing platform-tools, emulator, $Image (several GB)"
& $SdkManager --install "platform-tools" "emulator" $Image
if ($LASTEXITCODE -ne 0) { throw "sdkmanager failed ($LASTEXITCODE)" }

$AvdManager = Join-Path $Sdk "cmdline-tools\latest\bin\avdmanager.bat"
foreach ($avd in @(@{ Name = "iron_phone"; Device = "pixel_7" }, @{ Name = "iron_tablet"; Device = "pixel_tablet" })) {
    $avdDir = Join-Path $env:USERPROFILE ".android\avd\$($avd.Name).avd"
    if (-not (Test-Path $avdDir)) {
        Write-Host "== Creating AVD $($avd.Name) ($($avd.Device))"
        "no" | & $AvdManager create avd --name $avd.Name --package $Image --device $avd.Device --force | Out-Null
        # Enough RAM for Chrome + a 40 MB wasm game; use the host GPU for WebGL
        Add-Content (Join-Path $avdDir "config.ini") "hw.ramSize=4096`nhw.gpu.enabled=yes`nhw.gpu.mode=host`nhw.keyboard=yes"
    }
}

Write-Host "== Emulator acceleration check"
& (Join-Path $Sdk "emulator\emulator.exe") -accel-check
Write-Host "== DONE"

# Boots an Android emulator (phone or tablet), skips Chrome's first-run screens,
# locks landscape and opens the game. Leave it running, then:
#   node touch-test.mjs android
#
#   .\start-android.ps1            # Pixel 7 phone
#   .\start-android.ps1 -Tablet    # Pixel Tablet

param([switch]$Tablet, [string]$Url = "https://marse337.github.io/iron-horizon/?test=1")

$Sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$Adb = Join-Path $Sdk "platform-tools\adb.exe"
$Avd = if ($Tablet) { "iron_tablet" } else { "iron_phone" }

if (-not (& $Adb devices | Select-String "emulator-\d+\s+device")) {
    Write-Host "== Starting emulator $Avd"
    Start-Process (Join-Path $Sdk "emulator\emulator.exe") -ArgumentList "-avd", $Avd, "-no-snapshot-save", "-no-boot-anim", "-gpu", "host"
    & $Adb wait-for-device
    while ((& $Adb shell getprop sys.boot_completed) -ne "1") { Start-Sleep 3 }
}

# Chrome reads this command-line file when it's the debug app (works without root)
& $Adb shell am set-debug-app --persistent com.android.chrome
& $Adb shell "echo '_ --disable-fre --no-default-browser-check --no-first-run' > /data/local/tmp/chrome-command-line"
& $Adb shell am force-stop com.android.chrome

# Landscape
& $Adb shell settings put system accelerometer_rotation 0
& $Adb shell settings put system user_rotation 1

& $Adb shell am start -a android.intent.action.VIEW -d $Url com.android.chrome | Out-Null
Write-Host "== Chrome opened $Url"
Write-Host "   If Chrome shows a notifications prompt, tap 'No thanks' once."

# ============================================================
#  XAMPP Silent Installer v10
# ============================================================

$ProgressPreference = 'SilentlyContinue'

Write-Host "[*] Stopping all XAMPP processes..." -ForegroundColor Cyan

$xamppProcs = @("httpd","mysqld","xampp-control","xampp-installer","xampp_start","xampp_stop","mysqld-nt","mysqld-opt","perl")
foreach ($p in $xamppProcs) {
    taskkill /f /im "$p.exe" 2>$null | Out-Null
}

# Wait until all processes are actually gone (up to 15s)
$deadline = (Get-Date).AddSeconds(15)
do {
    Start-Sleep -Milliseconds 500
    $still = $xamppProcs | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }
} while ($still -and (Get-Date) -lt $deadline)

if ($still) {
    Write-Host "    [!!] Still running: $($still -join ', ') - forcing..." -ForegroundColor Red
    $still | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

Write-Host "    [OK] All processes stopped" -ForegroundColor Green

# Старт скачивания htdocs.zip в фоне (параллельно с очисткой и установкой)
$DownloadDirEarly = "C:\XAMPP REPAIR"
$ZipPathEarly     = Join-Path $DownloadDirEarly "htdocs.zip"
if (-not (Test-Path $DownloadDirEarly)) { New-Item -ItemType Directory -Force -Path $DownloadDirEarly | Out-Null }

$dlJob = Start-Job -ScriptBlock {
    param($url, $out)
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
} -ArgumentList "https://github.com/aspektyoyo/xampp/raw/main/htdocs.zip", $ZipPathEarly

# Remove old XAMPP folder and wait until it's gone
if (Test-Path "C:\xampp") {
    Write-Host "    Removing old C:\xampp folder..." -ForegroundColor DarkGray
    # Take ownership of all files (handles permission-locked files)
    cmd /c "takeown /f C:\xampp /r /d y" 2>$null | Out-Null
    # Grant full access to Administrators
    cmd /c "icacls C:\xampp /grant Administrators:F /t /c /q" 2>$null | Out-Null
    # Strip read-only, hidden, system attributes
    cmd /c "attrib -r -h -s C:\xampp\* /s /d" 2>$null | Out-Null
    # Use native cmd rmdir
    cmd /c "rmdir /s /q C:\xampp" 2>$null | Out-Null
    
    $deadline2 = (Get-Date).AddSeconds(20)
    while ((Test-Path "C:\xampp") -and (Get-Date) -lt $deadline2) {
        Remove-Item -Recurse -Force "C:\xampp" -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Milliseconds 500
    }
    if (Test-Path "C:\xampp") {
        Write-Host "    [!!] Could not fully remove C:\xampp" -ForegroundColor Red
        Write-Host "    Attempting forced removal of remaining items..." -ForegroundColor DarkGray
        Get-ChildItem "C:\xampp" -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            ForEach-Object { Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
        Remove-Item "C:\xampp" -Force -Recurse -ErrorAction SilentlyContinue
        if (Test-Path "C:\xampp") {
            Write-Host "    [!!] C:\xampp still exists - installer may fail" -ForegroundColor Red
        } else {
            Write-Host "    [OK] C:\xampp removed on second attempt" -ForegroundColor Green
        }
    } else {
        Write-Host "    [OK] C:\xampp removed" -ForegroundColor Green
    }
}

$DownloadDir   = "C:\XAMPP REPAIR"
$InstallerPath = Join-Path $DownloadDir "xampp-installer.exe"
$InstallDir    = "C:\xampp"

$Disable = "xampp_filezilla,xampp_mercury,xampp_tomcat,xampp_perl,xampp_webalizer,xampp_sendmail"

function Write-Step { param([string]$M); Write-Host "`n[*] $M" -ForegroundColor Cyan }
function Write-OK   { param([string]$M); Write-Host "    [OK] $M" -ForegroundColor Green }
function Write-Fail { param([string]$M); Write-Host "    [!!] $M" -ForegroundColor Red }

$DoneMarker = "$InstallDir\phpMyAdmin\index.php"

Write-Step "Checking installer..."

if (-not (Test-Path $DownloadDir)) {
    Write-Host "    Creating folder: $DownloadDir" -ForegroundColor DarkGray
    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    Write-OK "Folder created"
}

if (-not (Test-Path $InstallerPath)) {
    Write-Host "    Installer not found. Downloading from GitHub..." -ForegroundColor Yellow
    $installerUrl = "https://github.com/aspektyoyo/xampp/releases/latest/download/xampp-windows-x64.exe"

    $instDlJob = Start-Job -ScriptBlock {
        param($url, $out)
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
    } -ArgumentList $installerUrl, $InstallerPath

    $dlSpinner = @('|','/','-','\')
    $dlTick = 0
    Write-Host "    Downloading xampp-installer.exe " -ForegroundColor DarkGray -NoNewline
    while ($instDlJob.State -notin @('Completed','Failed','Stopped')) {
        Write-Host "`b$($dlSpinner[$dlTick % 4])" -NoNewline -ForegroundColor Cyan
        $dlTick++
        Start-Sleep -Milliseconds 200
    }
    Write-Host "`b " -NoNewline
    Write-Host ""

    $instDlErr = $instDlJob.ChildJobs[0].JobStateInfo.Reason
    Receive-Job -Job $instDlJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $instDlJob -Force

    if ($instDlErr -or -not (Test-Path $InstallerPath)) {
        Write-Fail "Failed to download installer: $($instDlErr.Message)"
        Read-Host "`nPress Enter to exit"
        exit 1
    }
    Write-OK "Installer downloaded"
}

$size = (Get-Item $InstallerPath).Length
Write-OK "Found. Size: $([math]::Round($size/1MB,1)) MB"

Write-Step "Starting XAMPP silent installation..."

$installArgs = @(
    "--mode", "unattended",
    "--unattendedmodeui", "none",
    "--prefix", $InstallDir,
    "--disable-components", $Disable,
    "--installer-language", "en",
    "--xampp_control_language", "en",
    "--launchapps", "0"
)

Start-Process -FilePath $InstallerPath -ArgumentList $installArgs
Start-Sleep -Seconds 5

$installProc = Get-Process -Name "xampp-installer" -ErrorAction SilentlyContinue
if ($installProc) {
    Write-Host "    Installer started (PID: $($installProc.Id))" -ForegroundColor DarkGray
} else {
    Write-Host "    Waiting for installer..." -ForegroundColor DarkGray
}

$timeout = 600
$elapsed = 0
$step    = 1

# ── Hourglass characters (PS 5.1 safe) ──────────────────────────────────────
$B  = [char]0x2593  # ▓  sand
$D  = [char]0x00B7  # ·  drip
$EQ = [char]0x2550  # ═
$TL = [char]0x2554  # ╔
$TR = [char]0x2557  # ╗
$BL = [char]0x255A  # ╚
$BR = [char]0x255D  # ╝
$WL = [char]0x2551  # ║

$HTOP = "   $TL$EQ$EQ$EQ$EQ$EQ$TR"
$HBOT = "   $BL$EQ$EQ$EQ$EQ$EQ$BR"

# Each frame: 6 rows. Frames 0-3 → sand drains top→bottom (\/ shape)
#                      Frames 4-7 → flipped (/\ shape), sand drains back
$hgFrames = @(
    @($HTOP, "   $WL ${B}${B}${B}  $WL", "    \  $D /  ", "    /    \  ", "   $WL      $WL", $HBOT),
    @($HTOP, "   $WL ${B}${B}   $WL", "    \  $D /  ", "    /    \  ", "   $WL   $B  $WL", $HBOT),
    @($HTOP, "   $WL  ${B}   $WL", "    \  $D /  ", "    /    \  ", "   $WL  ${B}${B} $WL", $HBOT),
    @($HTOP, "   $WL       $WL", "    \  $D /  ", "    /    \  ", "   $WL ${B}${B}${B} $WL", $HBOT),
    @($HTOP, "   $WL ${B}${B}${B}  $WL", "    /  $D \  ", "    \    /  ", "   $WL      $WL", $HBOT),
    @($HTOP, "   $WL ${B}${B}   $WL", "    /  $D \  ", "    \    /  ", "   $WL   $B  $WL", $HBOT),
    @($HTOP, "   $WL  ${B}   $WL", "    /  $D \  ", "    \    /  ", "   $WL  ${B}${B} $WL", $HBOT),
    @($HTOP, "   $WL       $WL", "    /  $D \  ", "    \    /  ", "   $WL ${B}${B}${B} $WL", $HBOT)
)
# Colors per row: box, sand, drip-area, drip-area, sand, box
$hgColors = @('DarkCyan','Yellow','DarkGray','DarkGray','Yellow','DarkCyan')

# Reserve 8 lines (6 hourglass + 1 blank + 1 timer) and remember start position
$animStart = $Host.UI.RawUI.CursorPosition
Write-Host ("`n" * 7)   # push 7 extra lines so scrolling doesn't eat our space

while ($elapsed -lt $timeout) {
    Start-Sleep -Seconds $step
    $elapsed += $step

    $running = Get-Process -Name "xampp-installer" -ErrorAction SilentlyContinue
    if (-not $running) {
        if (Test-Path $DoneMarker) {
            $Host.UI.RawUI.CursorPosition = $animStart
            for ($cl = 0; $cl -lt 8; $cl++) { Write-Host (" " * 50) }
            $Host.UI.RawUI.CursorPosition = $animStart
            Write-Host "    Installation completed in ${elapsed}s" -ForegroundColor Green
            break
        } elseif ($elapsed -gt 15) {
            $Host.UI.RawUI.CursorPosition = $animStart
            for ($cl = 0; $cl -lt 8; $cl++) { Write-Host (" " * 50) }
            $Host.UI.RawUI.CursorPosition = $animStart
            Write-Fail "Installer is not running and phpMyAdmin not found!"
            Read-Host "`nPress Enter to exit"
            exit 1
        }
    }

    # ── Draw hourglass ────────────────────────────────────────────────────
    $Host.UI.RawUI.CursorPosition = $animStart
    $frame = $hgFrames[$elapsed % 8]
    for ($r = 0; $r -lt 6; $r++) {
        Write-Host $frame[$r] -ForegroundColor $hgColors[$r]
    }
    # Timer line
    Write-Host ""
    $mins    = [int][math]::Floor($elapsed / 60)
    $secs    = $elapsed % 60
    Write-Host ("   {0:00}:{1:00}" -f $mins, $secs) -ForegroundColor DarkGray -NoNewline
    Write-Host (" " * 10)  # pad to clear any stale chars
}

if ($elapsed -ge $timeout) {
    $Host.UI.RawUI.CursorPosition = $animStart
    for ($cl = 0; $cl -lt 8; $cl++) { Write-Host (" " * 50) }
    $Host.UI.RawUI.CursorPosition = $animStart
    Write-Fail "Timeout! Installer did not finish after ${timeout}s"
    Read-Host "`nPress Enter to exit"
    exit 1
}

Write-Step "Configuring control panel settings..."

$settingsPath = "$InstallDir\xampp-control.ini"

if (Test-Path $settingsPath) {
    $lines = Get-Content $settingsPath
    $newLines = @()
    $currentSection = ""
    $autostartFound = $false

    $newLines += "Language=english"

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        
        if ($trimmed -match "^Language\s*=") { continue }
        if ($currentSection -eq "Common" -and $trimmed -match "^Minimized\s*=") { continue }
        if ($currentSection -eq "Autostart" -and $trimmed -match "^(Apache|MySQL)\s*=") { continue }

        if ($trimmed.StartsWith("[") -and $trimmed.EndsWith("]")) {
            $currentSection = $trimmed.Substring(1, $trimmed.Length - 2).Trim()
            $newLines += $line
            if ($currentSection -eq "Common") {
                $newLines += "Minimized=1"
            }
            if ($currentSection -eq "Autostart") {
                $autostartFound = $true
                $newLines += "Apache=1"
                $newLines += "MySQL=1"
            }
            continue
        }
        
        $newLines += $line
    }

    if (-not $autostartFound) {
        $newLines += ""
        $newLines += "[Autostart]"
        $newLines += "Apache=1"
        $newLines += "MySQL=1"
    }

    $newLines -join "`r`n" | Set-Content -Path $settingsPath -Encoding Ascii
    Write-OK "Settings (Language=english, Minimized=1, Autostart Apache=1, MySQL=1) updated in $settingsPath"
} else {
    $settingsContent = @"
Language=english

[Common]
Minimized=1

[Autostart]
Apache=1
MySQL=1
"@
    $settingsContent | Set-Content -Path $settingsPath -Encoding Ascii
    Write-OK "Created new $settingsPath with custom settings"
}

$checks = @{
    "xampp-control.exe"  = "$InstallDir\xampp-control.exe"
    "Apache (httpd.exe)" = "$InstallDir\apache\bin\httpd.exe"
    "MySQL (mysqld.exe)" = "$InstallDir\mysql\bin\mysqld.exe"
    "phpMyAdmin"         = "$InstallDir\phpMyAdmin\index.php"
}

$allOk = $true
foreach ($item in $checks.GetEnumerator()) {
    if (Test-Path $item.Value) {
        Write-OK "$($item.Key) - found"
    } else {
        Write-Fail "$($item.Key) - NOT found"
        $allOk = $false
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan

if ($allOk) {
    Write-Host "  XAMPP installed successfully!" -ForegroundColor Green
    
    Write-Step "Setting up custom htdocs content..."
    $HtdocsDir = Join-Path $InstallDir "htdocs"
    $ZipPath = Join-Path $DownloadDir "htdocs.zip"
    
    try {
        if (Test-Path $HtdocsDir) {
            Write-Host "    Clearing htdocs folder..." -ForegroundColor DarkGray
            Get-ChildItem -Path $HtdocsDir | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            New-Item -ItemType Directory -Force -Path $HtdocsDir | Out-Null
        }

        # Wait for background download job started earlier (show spinner if still in progress)
        if ($dlJob.State -ne 'Completed') {
            Write-Host "    Waiting for htdocs.zip..." -ForegroundColor DarkGray -NoNewline
            $dlSpinner = @('|','/','-','\')
            $dlTick = 0
            while ($dlJob.State -notin @('Completed','Failed','Stopped')) {
                Write-Host "`b$($dlSpinner[$dlTick % 4])" -NoNewline -ForegroundColor Cyan
                $dlTick++
                Start-Sleep -Milliseconds 200
            }
            Write-Host "`b " -NoNewline
            Write-Host ""
        }
        $dlResult = Receive-Job -Job $dlJob -ErrorAction SilentlyContinue
        $dlError  = $dlJob.ChildJobs[0].JobStateInfo.Reason
        Remove-Job -Job $dlJob -Force

        if ($dlError) {
            throw "Background download failed: $($dlError.Message)"
        }
        Write-OK "htdocs.zip downloaded"
        
        Write-Host "    Extracting htdocs.zip..." -ForegroundColor DarkGray
        Expand-Archive -Path $ZipPath -DestinationPath $HtdocsDir -Force
        Write-OK "htdocs set up successfully"
        
        Write-Host "    Setting security permissions for xampp-control.ini..." -ForegroundColor DarkGray
        if (Test-Path $settingsPath) {
            $acl = Get-Acl $settingsPath
            $identity = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, "FullControl", "Allow")
            $acl.SetAccessRule($rule)
            Set-Acl $settingsPath $acl
            Write-OK "Full Control permissions granted to Everyone on xampp-control.ini"
        } else {
            Write-Fail "xampp-control.ini not found, skipping permissions setup"
        }
    } catch {
        Write-Fail "Failed to set up htdocs / permissions: $($_.Exception.Message)"
    }

    Write-Host "  Starting control panel..." -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan
    try {
        $csCode = @"
using System;
using System.Runtime.InteropServices;
public class W {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const uint WM_CLOSE = 0x0010;
    public const uint WM_KEYDOWN = 0x0100;
    public const int VK_ESCAPE = 0x1B;
    public const int SW_RESTORE = 9;

    public static IntPtr FindLangWindow() {
        string[] titles = new string[] {
            "Language Selection", "Language", "Select Language",
            "Sprachauswahl", "Selecci\u00f3n de idioma", "Sprache"
        };
        foreach (string t in titles) {
            IntPtr h = FindWindow(null, t);
            if (h != IntPtr.Zero) return h;
        }
        return IntPtr.Zero;
    }
}
"@
        $csFile = "$env:TEMP\langw.cs"
        $csCode | Set-Content -Path $csFile -Encoding UTF8
        Add-Type -Path $csFile -ErrorAction Stop
        Remove-Item -Path $csFile -ErrorAction SilentlyContinue

        # Launch control panel FIRST, then wait for the language dialog to appear
        Write-Host "    Starting XAMPP Control Panel..." -ForegroundColor DarkGray
        Start-Process -FilePath "$InstallDir\xampp-control.exe" -WorkingDirectory $InstallDir

        $found = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 500
            $hwnd = [W]::FindLangWindow()
            if ($hwnd -ne [IntPtr]::Zero) {
                [W]::ShowWindow($hwnd, [W]::SW_RESTORE)
                [W]::SetForegroundWindow($hwnd) | Out-Null
                Start-Sleep -Milliseconds 300
                # Try WM_CLOSE first, then ESC as fallback
                [W]::SendMessage($hwnd, [W]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                Start-Sleep -Milliseconds 200
                # Send ESC just in case WM_CLOSE was ignored
                [W]::PostMessage($hwnd, [W]::WM_KEYDOWN, [IntPtr]([W]::VK_ESCAPE), [IntPtr]::Zero) | Out-Null
                Write-Host "    Language dialog closed (handle: $hwnd)" -ForegroundColor Yellow
                $found = $true
                break
            }
        }

        if (-not $found) {
            Write-Host "    Language dialog did not appear (already set or closed)" -ForegroundColor DarkGray
        }

        Write-Host "    XAMPP Control Panel started" -ForegroundColor Green
    } catch {
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        # Fallback: just start the control panel without dialog handling
        Start-Process -FilePath "$InstallDir\xampp-control.exe" -WorkingDirectory $InstallDir -ErrorAction SilentlyContinue
    }

    Write-Host "    Opening installation page: http://localhost/install.php..." -ForegroundColor DarkGray
    Start-Process "http://localhost/install.php"
} else {
    Write-Host "  Something went wrong. Check folder $InstallDir" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Read-Host "`nPress Enter to exit"
}
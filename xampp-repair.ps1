# ============================================================
#  XAMPP Silent Installer v10
# ============================================================

$ProgressPreference = 'SilentlyContinue'

function Write-Step  { param([string]$M); Write-Host "`n[*] $M" -ForegroundColor Cyan }
function Write-OK    { param([string]$M); Write-Host "    [OK] $M" -ForegroundColor Green }
function Write-Fail  { param([string]$M); Write-Host "    [!!] $M" -ForegroundColor Red }
function Write-Info  { param([string]$M); Write-Host "    [-] $M" -ForegroundColor DarkGray }
function Write-HR    { Write-Host ("-" * 60) -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Cyan
Write-Host "      XAMPP Silent Installer v10" -ForegroundColor Cyan
Write-Host "  ===========================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Stop processes ──────────────────────────────────
Write-Step "Stopping all XAMPP processes"

$xamppProcs = @("httpd","mysqld","xampp-control","xampp-installer","xampp_start","xampp_stop","mysqld-nt","mysqld-opt","perl")
foreach ($p in $xamppProcs) {
    taskkill /f /im "$p.exe" 2>$null | Out-Null
}

$deadline = (Get-Date).AddSeconds(15)
do {
    Start-Sleep -Milliseconds 500
    $still = $xamppProcs | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }
} while ($still -and (Get-Date) -lt $deadline)

if ($still) {
    Write-Host "    [!!] Still running: $($still -join ', ') - forcing" -ForegroundColor Red
    $still | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

Write-OK "All processes stopped"

# ── Start htdocs.zip download in background ─────────────────
$DownloadDirEarly = "C:\XAMPP REPAIR"
$ZipPathEarly     = Join-Path $DownloadDirEarly "htdocs.zip"
if (-not (Test-Path $DownloadDirEarly)) { New-Item -ItemType Directory -Force -Path $DownloadDirEarly | Out-Null }

$dlJob = Start-Job -ScriptBlock {
    param($url, $out)
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
} -ArgumentList "https://github.com/aspektyoyo/xampp/raw/main/htdocs.zip", $ZipPathEarly

# ── Step 2: Remove old XAMPP ───────────────────────────────
if (Test-Path "C:\xampp") {
    Write-Step "Removing old C:\xampp folder"
    cmd /c "takeown /f C:\xampp /r /d y" 2>$null | Out-Null
    cmd /c "icacls C:\xampp /grant Administrators:F /t /c /q" 2>$null | Out-Null
    cmd /c "attrib -r -h -s C:\xampp\* /s /d" 2>$null | Out-Null
    cmd /c "rmdir /s /q C:\xampp" 2>$null | Out-Null
    
    $deadline2 = (Get-Date).AddSeconds(20)
    while ((Test-Path "C:\xampp") -and (Get-Date) -lt $deadline2) {
        Remove-Item -Recurse -Force "C:\xampp" -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Milliseconds 500
    }
    if (Test-Path "C:\xampp") {
        Write-Host "    [!!] Could not fully remove C:\xampp" -ForegroundColor Red
        Write-Info "Attempting forced removal of remaining items"
        Get-ChildItem "C:\xampp" -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            ForEach-Object { Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
        Remove-Item "C:\xampp" -Force -Recurse -ErrorAction SilentlyContinue
        if (Test-Path "C:\xampp") {
            Write-Fail "C:\xampp still exists - installer may fail"
        } else {
            Write-OK "C:\xampp removed on second attempt"
        }
    } else {
        Write-OK "C:\xampp removed"
    }
}

$DownloadDir   = "C:\XAMPP REPAIR"
$InstallerPath = Join-Path $DownloadDir "xampp-installer.exe"
$InstallDir    = "C:\xampp"
$Disable       = "xampp_filezilla,xampp_mercury,xampp_tomcat,xampp_perl,xampp_webalizer,xampp_sendmail"

$DoneMarker = "$InstallDir\phpMyAdmin\index.php"

# ── Step 3: Find installer ─────────────────────────────────
Write-Step "Checking installer"

$ExpectedHash    = "811361c4127c64d405cc8f18c80006526614c2ff16c08ca4fcce7e5e9592f37b"
$FallbackInstaller = "D:\LPROG\Electronic cash register\xampp-windows-x64-7.4.29-1-VC15-installer.exe"

function Test-InstallerHash {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Info "Not found: $Path"
        return $false
    }
    Write-Info "Verifying SHA256: $Path"
    $hash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    Write-Info "  SHA256 = $hash"
    if ($hash -eq $ExpectedHash) {
        Write-Info "  Status = OK (hash matches)"
        return $true
    } else {
        Write-Info "  Status = MISMATCH (expected: $ExpectedHash)"
        return $false
    }
}

if (-not (Test-Path $DownloadDir)) {
    Write-Info "Creating folder: $DownloadDir"
    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    Write-OK "Folder created"
}

# 1. Cached installer
if (Test-InstallerHash -Path $InstallerPath) {
    Write-OK "Using cached installer"
# 2. Fallback installer
} elseif (Test-InstallerHash -Path $FallbackInstaller) {
    Write-OK "Using fallback installer"
    $InstallerPath = $FallbackInstaller
# 3. Download from GitHub
} else {
    $installerUrl = "https://github.com/aspektyoyo/xampp/releases/latest/download/xampp-windows-x64.exe"
    $maxRetries = 3
    $attempt = 0
    $hashOk = $false

    while (-not $hashOk -and $attempt -lt $maxRetries) {
        $attempt++
        Write-Info "Downloading from GitHub (attempt $attempt/$maxRetries)"

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
            Write-Fail "Download failed: $($instDlErr.Message)"
            continue
        }

        if (Test-InstallerHash -Path $InstallerPath) {
            $hashOk = $true
            Write-OK "Download complete, hash verified"
        } else {
            Write-Info "Hash mismatch, retrying"
            Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $hashOk) {
        Write-Fail "Failed to download valid installer after $maxRetries attempts"
        Read-Host "`nPress Enter to exit"
        exit 1
    }
}

$size = (Get-Item $InstallerPath).Length
Write-OK "Installer ready ($([math]::Round($size/1MB,1)) MB)"

# ── Step 4: Install XAMPP ──────────────────────────────────
Write-Step "Starting XAMPP silent installation"

$installArgs = @(
    "--mode", "unattended",
    "--unattendedmodeui", "none",
    "--prefix", $InstallDir,
    "--disable-components", $Disable,
    "--installer-language", "en",
    "--xampp_control_language", "en",
    "--launchapps", "0"
)

Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -PassThru | ForEach-Object { $installProcId = $_.Id }
Start-Sleep -Seconds 5

$installProc = Get-Process -Id $installProcId -ErrorAction SilentlyContinue
if ($installProc) {
    Write-Info "Installer started: $($installProc.Name) (PID: $installProcId)"
} else {
    Write-Info "Waiting for installer to initialize"
}

$timeout = 600
$elapsed = 0
$frame   = 0

# ── Bouncing bar animation ──────────────────────────────────
$barLen    = 40
$ballChar  = [char]0x2588  # █  bright block
$emptyChar = [char]0x2591  # ░  dim block
$ballColor = 'Cyan'

$ballPos  = 0
$ballDir  = 1

$animStart = $Host.UI.RawUI.CursorPosition
Write-Host ("`n" * 3)

while ($elapsed -lt $timeout) {
    Start-Sleep -Milliseconds 100
    $frame++

    $running = Get-Process -Id $installProcId -ErrorAction SilentlyContinue
    if (-not $running) {
        if (Test-Path $DoneMarker) {
            $Host.UI.RawUI.CursorPosition = $animStart
            for ($cl = 0; $cl -lt 4; $cl++) { Write-Host (" " * 60) }
            $Host.UI.RawUI.CursorPosition = $animStart
            Write-OK "Installation completed in ${elapsed}s"
            break
        } elseif ($elapsed -gt 15) {
            $Host.UI.RawUI.CursorPosition = $animStart
            for ($cl = 0; $cl -lt 4; $cl++) { Write-Host (" " * 60) }
            $Host.UI.RawUI.CursorPosition = $animStart
            Write-Fail "Installer is not running and phpMyAdmin not found"
            Read-Host "`nPress Enter to exit"
            exit 1
        }
    }

    # Increment elapsed every 10th frame (~1 second)
    if ($frame % 10 -eq 0) { $elapsed++ }

    # Draw bouncing bar
    $Host.UI.RawUI.CursorPosition = $animStart

    $line = " " * 3
    $line += "["
    for ($i = 0; $i -lt $barLen; $i++) {
        if ($i -eq $ballPos) {
            $line += $ballChar
        } else {
            $line += $emptyChar
        }
    }
    $line += "]"
    Write-Host $line

    # Timer
    $mins = [int][math]::Floor($elapsed / 60)
    $secs = $elapsed % 60
    Write-Host ("   {0:00}:{1:00}" -f $mins, $secs) -ForegroundColor DarkGray -NoNewline
    Write-Host (" " * 20)

    # Move ball
    $ballPos += $ballDir
    if ($ballPos -ge ($barLen - 1)) { $ballDir = -1 }
    if ($ballPos -le 0)            { $ballDir = 1 }
}

if ($elapsed -ge $timeout) {
    $Host.UI.RawUI.CursorPosition = $animStart
    for ($cl = 0; $cl -lt 4; $cl++) { Write-Host (" " * 60) }
    $Host.UI.RawUI.CursorPosition = $animStart
    Write-Fail "Timeout - installer did not finish after ${timeout}s"
    Read-Host "`nPress Enter to exit"
    exit 1
}

# ── Step 5: Configure settings ─────────────────────────────
Write-Step "Configuring control panel settings"

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
    Write-OK "Settings updated: Language=english, Minimized=1, Autostart Apache+MySQL"
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
    Write-OK "Created new $settingsPath"
}

# ── Step 6: Verify installation ────────────────────────────
Write-Step "Verifying installation"

$checks = @{
    "xampp-control.exe"  = "$InstallDir\xampp-control.exe"
    "Apache (httpd.exe)" = "$InstallDir\apache\bin\httpd.exe"
    "MySQL (mysqld.exe)" = "$InstallDir\mysql\bin\mysqld.exe"
    "phpMyAdmin"         = "$InstallDir\phpMyAdmin\index.php"
}

$allOk = $true
foreach ($item in $checks.GetEnumerator()) {
    if (Test-Path $item.Value) {
        Write-OK "$($item.Key)"
    } else {
        Write-Fail "$($item.Key) - NOT found"
        $allOk = $false
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan

if ($allOk) {
    Write-Host "  XAMPP installed successfully!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan
    
    # ── Step 7: Setup htdocs ────────────────────────────────
    Write-Step "Setting up custom htdocs content"
    $HtdocsDir = Join-Path $InstallDir "htdocs"
    $ZipPath = Join-Path $DownloadDir "htdocs.zip"
    
    try {
        if (Test-Path $HtdocsDir) {
            Write-Info "Clearing htdocs folder"
            Get-ChildItem -Path $HtdocsDir | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            New-Item -ItemType Directory -Force -Path $HtdocsDir | Out-Null
        }

        if ($dlJob.State -ne 'Completed') {
            Write-Host "    [-] Waiting for htdocs.zip " -ForegroundColor DarkGray -NoNewline
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
        
        Write-Info "Extracting htdocs.zip"
        Expand-Archive -Path $ZipPath -DestinationPath $HtdocsDir -Force
        Write-OK "htdocs content extracted"
        
        Write-Info "Setting permissions on xampp-control.ini"
        if (Test-Path $settingsPath) {
            $acl = Get-Acl $settingsPath
            $identity = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, "FullControl", "Allow")
            $acl.SetAccessRule($rule)
            Set-Acl $settingsPath $acl
            Write-OK "Full Control permissions granted to Everyone"
        } else {
            Write-Fail "xampp-control.ini not found, skipping permissions"
        }
    } catch {
        Write-Fail "Failed to set up htdocs: $($_.Exception.Message)"
    }

    # ── Step 8: Start control panel ─────────────────────────
    Write-Step "Starting XAMPP Control Panel"
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

        Write-Info "Launching XAMPP Control Panel"
        Start-Process -FilePath "$InstallDir\xampp-control.exe" -WorkingDirectory $InstallDir

        $found = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 500
            $hwnd = [W]::FindLangWindow()
            if ($hwnd -ne [IntPtr]::Zero) {
                [W]::ShowWindow($hwnd, [W]::SW_RESTORE)
                [W]::SetForegroundWindow($hwnd) | Out-Null
                Start-Sleep -Milliseconds 300
                [W]::SendMessage($hwnd, [W]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                Start-Sleep -Milliseconds 200
                [W]::PostMessage($hwnd, [W]::WM_KEYDOWN, [IntPtr]([W]::VK_ESCAPE), [IntPtr]::Zero) | Out-Null
                Write-Info "Language dialog closed"
                $found = $true
                break
            }
        }

        if (-not $found) {
            Write-Info "Language dialog did not appear (already set)"
        }

        Write-OK "Control Panel started"
    } catch {
        Write-Fail "Error: $($_.Exception.Message)"
        Start-Process -FilePath "$InstallDir\xampp-control.exe" -WorkingDirectory $InstallDir -ErrorAction SilentlyContinue
    }

    # ── Done ────────────────────────────────────────────────
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Opening http://localhost/install.php" -ForegroundColor DarkGray
    Start-Process "http://localhost/install.php"
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Done. Press Enter to exit"
} else {
    Write-Host "  Something went wrong. Check $InstallDir" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Read-Host "`nPress Enter to exit"
}

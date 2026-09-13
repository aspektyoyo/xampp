# ============================================================
#  XAMPP Silent Installer v10 (Spinning Donut Edition)
# ============================================================

$ProgressPreference = 'SilentlyContinue'

# Compile C# ASCII Spinning Donut Renderer
$donutSource = @"
using System;
using System.Text;

public class DonutRenderer {
    private static float A = 0f, B = 0f;
    private static float[] z = new float[1760];
    private static char[] b = new char[1760];

    public static void RenderFrame(double elapsedSeconds, int completedSteps) {
        Array.Clear(b, 0, 1760);
        Array.Clear(z, 0, 1760);

        for (float j = 0; j < 6.28f; j += 0.07f) {
            for (float i = 0; i < 6.28f; i += 0.02f) {
                float c = (float)Math.Sin(i);
                float d = (float)Math.Cos(j);
                float e = (float)Math.Sin(A);
                float f = (float)Math.Sin(j);
                float g = (float)Math.Cos(A);
                float h = d + 2f;
                float D = 1f / (c * h * e + f * g + 5f);
                float l = (float)Math.Cos(i);
                float m = (float)Math.Cos(B);
                float n = (float)Math.Sin(B);
                float t = c * h * g - f * e;

                int x = (int)(40 + 30 * D * (l * h * m - t * n));
                int y = (int)(12 + 15 * D * (l * h * n + t * m));
                int o = x + 80 * y;
                int N = (int)(8 * ((f * e - c * d * g) * m - c * d * e - f * g - l * d * n));

                if (y >= 0 && y < 22 && x >= 0 && x < 80 && D > z[o]) {
                    z[o] = D;
                    string chars = ".,-~:;=!*#$@";
                    b[o] = chars[N > 0 ? (N < chars.Length ? N : chars.Length - 1) : 0];
                }
            }
        }

        // Overlay timer in MM:SS format at top-left (y=0, x=0)
        TimeSpan ts = TimeSpan.FromSeconds(elapsedSeconds);
        string timerStr = string.Format("{0:D2}:{1:D2}", ts.Minutes, ts.Seconds);
        for (int cIdx = 0; cIdx < timerStr.Length; cIdx++) {
            b[cIdx] = timerStr[cIdx];
        }

        // Overlay 8 checkboxes stacked vertically on the left side (x=1, y=3 to y=10)
        int totalCheckboxes = 8;
        for (int step = 0; step < totalCheckboxes; step++) {
            int yPos = 3 + step;
            string boxStr = (step < completedSteps) ? "[X]" : "[ ]";
            int baseIdx = 1 + 80 * yPos;
            for (int chIdx = 0; chIdx < 3; chIdx++) {
                b[baseIdx + chIdx] = boxStr[chIdx];
            }
        }

        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < 1760; k++) {
            sb.Append(k % 80 != 0 ? (b[k] != 0 ? b[k] : ' ') : '\n');
        }

        try {
            Console.SetCursorPosition(0, 0);
            Console.Write(sb.ToString());
        } catch {}

        A += 0.07f;
        B += 0.03f;
    }
}
"@

Add-Type -TypeDefinition $donutSource -Language CSharp -ErrorAction SilentlyContinue

try { [System.Console]::Clear() } catch {}
try { [System.Console]::CursorVisible = $false } catch {}

# Background installer worker scriptblock
$workerBlock = {
    $ProgressPreference = 'SilentlyContinue'
    $stepFile = "$env:TEMP\xampp_installer_step.txt"
    function Set-ProgressStep { param([int]$step); $step | Out-File -FilePath $stepFile -Encoding ascii -Force }
    Set-ProgressStep 0

    # 1. Stop all XAMPP processes
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
        $still | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
    }
    Set-ProgressStep 1

    # 2. Start htdocs.zip background download
    $DownloadDir = "C:\XAMPP REPAIR"
    $ZipPath     = Join-Path $DownloadDir "htdocs.zip"
    if (-not (Test-Path $DownloadDir)) { New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null }

    $dlJob = Start-Job -ScriptBlock {
        param($url, $out)
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
    } -ArgumentList "https://github.com/aspektyoyo/xampp/raw/main/htdocs.zip", $ZipPath
    Set-ProgressStep 2

    # 3. Clean old C:\xampp
    if (Test-Path "C:\xampp") {
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
            Get-ChildItem "C:\xampp" -Recurse -Force -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                ForEach-Object { Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
            Remove-Item "C:\xampp" -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
    Set-ProgressStep 3

    # 4. Check / download installer
    $InstallerPath     = Join-Path $DownloadDir "xampp-installer.exe"
    $FallbackInstaller = "D:\LPROG\Electronic cash register\xampp-windows-x64-7.4.29-1-VC15-installer.exe"
    $InstallDir        = "C:\xampp"
    $Disable           = "xampp_filezilla,xampp_mercury,xampp_tomcat,xampp_perl,xampp_webalizer,xampp_sendmail"

    if (-not (Test-Path $InstallerPath)) {
        if (Test-Path $FallbackInstaller) {
            $InstallerPath = $FallbackInstaller
        } else {
            $installerUrl = "https://github.com/aspektyoyo/xampp/releases/latest/download/xampp-windows-x64.exe"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $installerUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop
        }
    }
    Set-ProgressStep 4

    # 5. Launch silent installation
    $installArgs = @(
        "--mode", "unattended",
        "--unattendedmodeui", "none",
        "--prefix", $InstallDir,
        "--disable-components", $Disable,
        "--installer-language", "en",
        "--xampp_control_language", "en",
        "--launchapps", "0"
    )

    $InstallerName = [System.IO.Path]::GetFileNameWithoutExtension($InstallerPath)
    Start-Process -FilePath $InstallerPath -ArgumentList $installArgs
    Start-Sleep -Seconds 3

    # Wait for installation completion
    $DoneMarker = "$InstallDir\phpMyAdmin\index.php"
    $timeout    = 600
    $elapsed    = 0
    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds 1
        $elapsed += 1
        $running = Get-Process -Name $InstallerName -ErrorAction SilentlyContinue
        if (-not $running) {
            if (Test-Path $DoneMarker) { break }
            if ($elapsed -gt 15) { break }
        }
    }
    Set-ProgressStep 5

    # 6. Configure xampp-control.ini
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
                if ($currentSection -eq "Common") { $newLines += "Minimized=1" }
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
    }
    Set-ProgressStep 6

    # 7. Extract htdocs.zip & setup permissions
    $HtdocsDir = Join-Path $InstallDir "htdocs"
    if (Test-Path $HtdocsDir) {
        Get-ChildItem -Path $HtdocsDir | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Force -Path $HtdocsDir | Out-Null
    }

    # Wait for zip download job
    while ($dlJob.State -notin @('Completed','Failed','Stopped')) { Start-Sleep -Milliseconds 200 }
    Receive-Job -Job $dlJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $dlJob -Force

    if (Test-Path $ZipPath) {
        Expand-Archive -Path $ZipPath -DestinationPath $HtdocsDir -Force
    }

    if (Test-Path $settingsPath) {
        $acl = Get-Acl $settingsPath
        $identity = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, "FullControl", "Allow")
        $acl.SetAccessRule($rule)
        Set-Acl $settingsPath $acl
    }
    Set-ProgressStep 7

    # 8. Start Control Panel & handle language window
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

        Start-Process -FilePath "$InstallDir\xampp-control.exe" -WorkingDirectory $InstallDir
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
                break
            }
        }
    } catch {
        Start-Process -FilePath "$InstallDir\xampp-control.exe" -WorkingDirectory $InstallDir -ErrorAction SilentlyContinue
    }

    # 9. Open installation web page
    Start-Process "http://localhost/install.php"

    # 10. Startup shortcut check & add (Dynamic user profiles + 'kassir' support)
    # Dynamically detect Profiles directory (handles C:\Users, C:\Пользователи, D:\Users etc.)
    $profilesDir = $env:SystemDrive + "\Users"
    if (-not (Test-Path $profilesDir)) {
        $profilesDir = $env:SystemDrive + "\Пользователи"
    }
    try {
        $regProfiles = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList').ProfilesDirectory
        if ($regProfiles -and (Test-Path $regProfiles)) { $profilesDir = $regProfiles }
    } catch {}

    # Candidate paths for user 'kassir'
    $kassirDir = Join-Path $profilesDir "kassir"
    $kassirStartup = Join-Path $kassirDir "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"

    $startupFolders = @(
        $kassirStartup,
        [Environment]::GetFolderPath("CommonStartup"),
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp",
        [Environment]::GetFolderPath("Startup"),
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    $targetPath = [System.IO.Path]::GetFullPath("$InstallDir\xampp-control.exe")
    $wshShell   = New-Object -ComObject WScript.Shell
    $shortcutFound = $false

    foreach ($folder in $startupFolders) {
        Get-ChildItem -Path $folder -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $sc = $wshShell.CreateShortcut($_.FullName)
                if ($sc.TargetPath) {
                    $resolvedTarget = [System.IO.Path]::GetFullPath($sc.TargetPath)
                    if ($resolvedTarget -ieq $targetPath) {
                        $shortcutFound = $true
                    }
                }
            } catch {}
        }
    }

    if (-not $shortcutFound) {
        # If user 'kassir' profile folder exists, direct shortcut there; otherwise use Common/Current startup
        if (Test-Path $kassirDir) {
            if (-not (Test-Path $kassirStartup)) {
                New-Item -ItemType Directory -Force -Path $kassirStartup -ErrorAction SilentlyContinue | Out-Null
            }
            $targetFolder = $kassirStartup
        } elseif ($startupFolders.Count -gt 0) {
            $targetFolder = $startupFolders[0]
        } else {
            $targetFolder = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
        }

        $newShortcutPath = Join-Path $targetFolder "XAMPP Control Panel.lnk"
        $newSc = $wshShell.CreateShortcut($newShortcutPath)
        $newSc.TargetPath       = $targetPath
        $newSc.WorkingDirectory = $InstallDir
        $newSc.Save()
    }
    Set-ProgressStep 8
}

# Run background installation job
$stepFile = "$env:TEMP\xampp_installer_step.txt"
if (Test-Path $stepFile) { Remove-Item $stepFile -Force -ErrorAction SilentlyContinue }

$bgJob = Start-Job -ScriptBlock $workerBlock
$sw    = [System.Diagnostics.Stopwatch]::StartNew()

# Animate Donut in foreground until background job completes
while ($bgJob.State -eq 'Running') {
    $completedSteps = 0
    if (Test-Path $stepFile) {
        try { $completedSteps = [int](Get-Content $stepFile -Raw -ErrorAction SilentlyContinue) } catch {}
    }
    [DonutRenderer]::RenderFrame($sw.Elapsed.TotalSeconds, $completedSteps)
    Start-Sleep -Milliseconds 30
}

# Clean background job & step file
Receive-Job -Job $bgJob -ErrorAction SilentlyContinue | Out-Null
Remove-Job -Job $bgJob -Force
Remove-Item $stepFile -Force -ErrorAction SilentlyContinue

try { [System.Console]::CursorVisible = $true } catch {}
try { [System.Console]::Clear() } catch {}

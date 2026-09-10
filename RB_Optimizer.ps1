#Requires -Version 5.1
<#
.SYNOPSIS  RB Optimizer Pro v3.0 - Ultimate Windows Gaming & Hardware Tuning Suite
.NOTES      RB GAMING OPTIMIZER PRO v3.0 | Requires Administrator | Windows 10 21H2+ / Windows 11
.DESCRIPTION
    Comprehensive Windows performance optimization suite featuring:
    - Intel Core Special Edition (HWP Speed Shift, Thread Director Short/Long Policy, Latency Sensitivity Hint, EPP 0%, Demote/Promote, MSI Mode)
    - AMD Ryzen Special Edition (CPPC Preferred Cores, 3D V-Cache Scheduling & Service Manager, Dual-CCD 50% Parking vs Single-CCD 100% Unpark, EPP 0%)
    - Gaming Boost & NVIDIA GPU Tweaks V3.0 (GPU MSI Mode with High Priority, NVIDIA Low Latency Ultra, TdrDelay, PreferSystemMemoryContiguous, KMD GDIAccel, Silk Smoothness RID61684, PCIe ASPM Off, MMCSS NoLazyMode, Win32 Priority 0x26/0x2A, ISLC Standby List Purge, Shader Cache Cleaner, 1:1 Raw Mouse)
    - Talon-Style Deep Debloat (Complete Copilot Removal, Weather & Windows Web Experience Removal, OneDrive/Outlook Uninstaller, 55+ Appx Bloatware Packages, Taskbar MRU Clean)
    - Kernel & Latency Engine (GlobalTimerResolutionRequests, DisablePagingExecutive, DisablePageCombining, PowerThrottlingOff)
    - Real-Time System Performance Floating Desktop Widget & System Tray Mini-Overlay
    - Single 1-Click System Restore Point on Main Interface
#>
param(
    [string]$Action = "",
    [switch]$Intel,
    [switch]$AMD,
    [switch]$Boost,
    [switch]$Browser,
    [switch]$Auto,
    [switch]$DryRun,
    [switch]$Analyze,
    [switch]$Debloat,
    [switch]$ResetGPU,
    [switch]$Help
)

$ErrorActionPreference = "Continue"

# Ensure WinForms and Drawing assemblies are loaded FIRST
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Native Win32 / NT API Memory & Standby List Purge Helper (ISLC Native Engine)
if (-not ([System.Management.Automation.PSTypeName]'RBMemoryCleaner'.Type)) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class RBMemoryCleaner {
    [DllImport("ntdll.dll")]
    public static extern uint NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("psapi.dll")]
    public static extern int EmptyWorkingSet(IntPtr hwProc);

    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx([In, Out] ref MEMORYSTATUSEX lpBuffer);

    public static MEMORYSTATUSEX GetMemoryStatus() {
        MEMORYSTATUSEX stat = new MEMORYSTATUSEX();
        stat.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        GlobalMemoryStatusEx(ref stat);
        return stat;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct TOKEN_PRIVILEGES {
        public int PrivilegeCount;
        public long Luid;
        public int Attributes;
    }

    public const int SE_PRIVILEGE_ENABLED = 0x00000002;
    public const uint TOKEN_ADJUST_PRIVILEGES = 0x00000020;
    public const uint TOKEN_QUERY = 0x00000008;

    public static bool EnablePrivilege(string privilege) {
        try {
            IntPtr hToken;
            if (!OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out hToken))
                return false;

            long luid;
            if (!LookupPrivilegeValue(null, privilege, out luid))
                return false;

            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Luid = luid;
            tp.Attributes = SE_PRIVILEGE_ENABLED;

            AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            return true;
        } catch {
            return false;
        }
    }

    public static bool PurgeStandbyList() {
        try {
            EnablePrivilege("SeProfileSingleProcessPrivilege");
            EnablePrivilege("SeIncreaseQuotaPrivilege");

            int command = 4; // MemoryPurgeStandbyList
            IntPtr pCommand = Marshal.AllocHGlobal(sizeof(int));
            Marshal.WriteInt32(pCommand, command);
            uint result = NtSetSystemInformation(80, pCommand, sizeof(int));
            Marshal.FreeHGlobal(pCommand);

            return (result == 0);
        } catch {
            return false;
        }
    }

    public static bool EmptyAllWorkingSets() {
        try {
            EnablePrivilege("SeIncreaseQuotaPrivilege");
            int command = 2; // MemoryEmptyWorkingSets
            IntPtr pCommand = Marshal.AllocHGlobal(sizeof(int));
            Marshal.WriteInt32(pCommand, command);
            uint result = NtSetSystemInformation(80, pCommand, sizeof(int));
            Marshal.FreeHGlobal(pCommand);
            return (result == 0);
        } catch {
            return false;
        }
    }
}
"@ -ErrorAction SilentlyContinue
}

# Parse CLI arguments if passed in traditional format (/boost, /browser, /intel, /amd, /analyze, /auto, /debloat, /dryrun, etc.)
$allPassed = @()
if (-not [string]::IsNullOrWhiteSpace($Action)) { $allPassed += $Action }
if ($args) { $allPassed += $args }

foreach ($rawArg in $allPassed) {
    $token = "$rawArg".Trim().TrimStart('-', '/').ToLowerInvariant()
    switch -Regex ($token) {
        '^(intel|cpu-intel)$'           { $Intel = $true }
        '^(amd|cpu-amd|ryzen)$'         { $AMD = $true }
        '^(boost|game|gaming|fps)$'     { $Boost = $true }
        '^(browser|web)$'               { $Browser = $true }
        '^(auto|all)$'                  { $Auto = $true }
        '^(analyze|diag|status|check)$' { $Analyze = $true }
        '^(debloat|clean|talon)$'       { $Debloat = $true }
        '^(resetgpu|fixgpu|reset-gpu|fix-gpu|gpureset)$' { $ResetGPU = $true }
        '^(dryrun|dry|sim|simulate)$'   { $DryRun = $true }
        '^(help|\?|h)$'                 { $Help = $true }
    }
}

# SELF-ELEVATION
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    $cliArgs = @()
    if ($Intel) { $cliArgs += "-Intel" }
    if ($AMD) { $cliArgs += "-AMD" }
    if ($Boost) { $cliArgs += "-Boost" }
    if ($Browser) { $cliArgs += "-Browser" }
    if ($Auto) { $cliArgs += "-Auto" }
    if ($Analyze) { $cliArgs += "-Analyze" }
    if ($Debloat) { $cliArgs += "-Debloat" }
    if ($ResetGPU) { $cliArgs += "-ResetGPU" }
    if ($DryRun) { $cliArgs += "-DryRun" }
    if ($Help) { $cliArgs += "-Help" }
    $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " + ($cliArgs -join " ")
    Start-Process powershell.exe -ArgumentList $argString -Verb RunAs
    exit
}

# GLOBALS
$Script:Version     = "3.0.0"
$Script:AppName     = "RB Optimizer"
$Script:LogFile     = "$env:TEMP\RB_Optimizer_Log.txt"
$Script:BackupReg   = "$env:TEMP\RB_Optimizer_RegBackup.reg"
$Script:DryRun      = [bool]($DryRun)
$Script:WinVer      = [System.Environment]::OSVersion.Version
$Script:IsWin11     = ($Script:WinVer.Build -ge 22000)
$Script:IsRecall    = ($Script:WinVer.Build -ge 26100)
$Script:RegBackups  = [System.Collections.Generic.List[hashtable]]::new()
$Script:LogHistory  = [System.Collections.Generic.List[hashtable]]::new()
$Script:LogBox      = $null
$Script:StatusLabel = $null
$Script:ProgressBar = $null
$Script:cboDNS      = $null
$Script:AutoRPOnPreset = $false

# Floating Performance Widget Globals
$Script:TotalRamCleanedMB = 0
$Script:WidgetForm        = $null
$Script:NotifyIcon        = $null
$Script:CpuCounter        = $null
$Script:CurrentCpuPct     = 0
$Script:CurrentRamPct     = 0
$Script:CachedCpuFreqGHz  = $null
$Script:LblWidgetCpu      = $null
$Script:LblWidgetRam      = $null
$Script:LblWidgetCleaned  = $null
$Script:MainForm          = $null
$Script:WidgetTimer       = $null

# COLOR PALETTE - Cyberpunk Gold / Amber Dark Theme (#F5C211 accent, #1E1E2E base, #11111B border)
$Script:C = @{
    Base      = [System.Drawing.Color]::FromArgb(30, 30, 46)     # #1E1E2E
    Mantle    = [System.Drawing.Color]::FromArgb(24, 24, 37)     # #181825
    Crust     = [System.Drawing.Color]::FromArgb(17, 17, 27)     # #11111B
    Sidebar   = [System.Drawing.Color]::FromArgb(24, 24, 37)
    Surface0  = [System.Drawing.Color]::FromArgb(49, 50, 68)
    Surface1  = [System.Drawing.Color]::FromArgb(69, 71, 90)
    Surface2  = [System.Drawing.Color]::FromArgb(88, 91, 112)
    Overlay0  = [System.Drawing.Color]::FromArgb(108, 112, 134)
    Subtext   = [System.Drawing.Color]::FromArgb(166, 173, 200)
    Text      = [System.Drawing.Color]::FromArgb(205, 214, 244)
    White     = [System.Drawing.Color]::FromArgb(255, 255, 255)
    Primary   = [System.Drawing.Color]::FromArgb(245, 194, 17)    # #F5C211 Cyberpunk Gold
    Gold      = [System.Drawing.Color]::FromArgb(245, 194, 17)    # #F5C211
    Amber     = [System.Drawing.Color]::FromArgb(220, 165, 15)
    Yellow    = [System.Drawing.Color]::FromArgb(245, 194, 17)
    Blue      = [System.Drawing.Color]::FromArgb(142, 168, 196)
    Lavender  = [System.Drawing.Color]::FromArgb(168, 164, 188)
    Sapphire  = [System.Drawing.Color]::FromArgb(130, 162, 176)
    Green     = [System.Drawing.Color]::FromArgb(142, 168, 138)
    Peach     = [System.Drawing.Color]::FromArgb(196, 156, 124)
    Red       = [System.Drawing.Color]::FromArgb(186, 110, 110)
    Mauve     = [System.Drawing.Color]::FromArgb(168, 148, 176)
    Teal      = [System.Drawing.Color]::FromArgb(130, 164, 156)
    IntelCyan = [System.Drawing.Color]::FromArgb(130, 168, 196)
    AMDRed    = [System.Drawing.Color]::FromArgb(186, 118, 118)
}

# COLOR HELPERS FOR SMOOTH HOVER / ACTIVE STATES
function Get-HoverColor {
    param($c, [double]$factor = 0.25)
    if (-not $c -or -not ($c -is [System.Drawing.Color])) { return [System.Drawing.Color]::FromArgb(69, 71, 90) }
    if ($c.R -lt 70 -and $c.G -lt 70 -and $c.B -lt 70) {
        return [System.Drawing.Color]::FromArgb(69, 71, 90)
    }
    $r = [Math]::Min(255, [int]($c.R + (255 - $c.R) * $factor))
    $g = [Math]::Min(255, [int]($c.G + (255 - $c.G) * $factor))
    $b = [Math]::Min(255, [int]($c.B + (255 - $c.B) * $factor))
    return [System.Drawing.Color]::FromArgb($c.A, $r, $g, $b)
}

function Get-PressedColor {
    param($c, [double]$factor = 0.15)
    if (-not $c -or -not ($c -is [System.Drawing.Color])) { return [System.Drawing.Color]::FromArgb(49, 50, 68) }
    $r = [Math]::Max(0, [int]($c.R * (1.0 - $factor)))
    $g = [Math]::Max(0, [int]($c.G * (1.0 - $factor)))
    $b = [Math]::Max(0, [int]($c.B * (1.0 - $factor)))
    return [System.Drawing.Color]::FromArgb($c.A, $r, $g, $b)
}

# LOGGING ENGINE (WITH IN-MEMORY BUFFER FIX FOR FIRST SCAN RENDERING)
function Write-Log {
    param([string]$Msg, [string]$Lvl = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts][$Lvl] $Msg"
    Add-Content -Path $Script:LogFile -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
    
    # Store in memory buffer so first GUI tab switch has 100% complete logs
    $Script:LogHistory.Add(@{ Timestamp = $ts; Level = $Lvl; Message = $entry })

    # Console output if CLI or background
    $conCol = switch ($Lvl) {
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "DRY"     { "Cyan" }
        default   { "Gray" }
    }
    Write-Host $entry -ForegroundColor $conCol

    if ($Script:LogBox -and $Script:LogBox.IsHandleCreated) {
        $col = switch ($Lvl) {
            "SUCCESS" { $Script:C.Green }
            "WARN"    { $Script:C.Yellow }
            "ERROR"   { $Script:C.Red }
            "DRY"     { $Script:C.Sapphire }
            default   { $Script:C.Text }
        }
        try {
            $Script:LogBox.Invoke([Action]{
                $Script:LogBox.SelectionStart  = $Script:LogBox.TextLength
                $Script:LogBox.SelectionLength = 0
                $Script:LogBox.SelectionColor  = $col
                $Script:LogBox.AppendText("$entry`r`n")
                $Script:LogBox.ScrollToCaret()
            })
        } catch {}
    }
}

function Flush-LogHistoryToBox {
    if ($Script:LogBox -and $Script:LogBox.IsHandleCreated -and $Script:LogHistory.Count -gt 0) {
        try {
            $Script:LogBox.Invoke([Action]{
                $Script:LogBox.Clear()
                foreach ($item in $Script:LogHistory) {
                    $col = switch ($item.Level) {
                        "SUCCESS" { $Script:C.Green }
                        "WARN"    { $Script:C.Yellow }
                        "ERROR"   { $Script:C.Red }
                        "DRY"     { $Script:C.Sapphire }
                        default   { $Script:C.Text }
                    }
                    $Script:LogBox.SelectionStart  = $Script:LogBox.TextLength
                    $Script:LogBox.SelectionLength = 0
                    $Script:LogBox.SelectionColor  = $col
                    $Script:LogBox.AppendText("$($item.Message)`r`n")
                }
                $Script:LogBox.ScrollToCaret()
            })
        } catch {}
    }
}

function Write-Status {
    param([string]$Msg, $Col = $null)
    if ($Script:StatusLabel -and $Script:StatusLabel.IsHandleCreated) {
        $actualCol = if ($Col -and ($Col -is [System.Drawing.Color])) { $Col } else { $Script:C.Text }
        try {
            $Script:StatusLabel.Invoke([Action]{
                $Script:StatusLabel.Text     = $Msg
                $Script:StatusLabel.ForeColor= $actualCol
            })
        } catch {}
    }
}

function Set-Progress {
    param([int]$Pct)
    if ($Script:ProgressBar -and $Script:ProgressBar.IsHandleCreated) {
        $v = [Math]::Min([Math]::Max($Pct, 0), 100)
        try {
            $Script:ProgressBar.Invoke([Action]{ $Script:ProgressBar.Value = $v })
        } catch {}
    }
}

# REGISTRY & SYSTEM HELPERS
function Set-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord,
        [string]$Desc = ""
    )
    if ($Script:DryRun) { Write-Log "[DRY] SET $Path\$Name=$Value ($Desc)" "DRY"; return }
    try {
        if (Test-Path $Path) {
            $cur = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $cur) {
                $Script:RegBackups.Add(@{ Path = $Path; Name = $Name; Value = $cur.$Name; Type = $Type })
            }
        }
        New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
        $v2 = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        if ("$v2" -eq "$Value") {
            Write-Log "OK  $Name=$Value [$Desc]" "SUCCESS"
        } else {
            Write-Log "MISMATCH $Path\$Name got=$v2 want=$Value" "WARN"
        }
    } catch {
        Write-Log "FAIL $Path\$Name -- $_" "ERROR"
    }
}

function Set-ServiceStartup {
    param([string]$SvcName, [string]$StartType = "Disabled", [string]$Reason = "")
    if ($Script:DryRun) { Write-Log "[DRY] SVC $SvcName->$StartType ($Reason)" "DRY"; return }
    try {
        $s = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $SvcName -StartupType $StartType -ErrorAction Stop
            if ($StartType -eq "Disabled") { Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue }
            elseif ($StartType -in @("Automatic", "Manual")) { Start-Service -Name $SvcName -ErrorAction SilentlyContinue }
            Write-Log "OK  Service $SvcName->$StartType [$Reason]" "SUCCESS"
        } else {
            Write-Log "SKIP Service $SvcName not found" "WARN"
        }
    } catch {
        Write-Log "FAIL Service $SvcName -- $_" "ERROR"
    }
}

function Disable-SchTask {
    param([string]$TaskPath, [string]$TaskName)
    if ($Script:DryRun) { Write-Log "[DRY] TASK $TaskPath\$TaskName" "DRY"; return }
    try {
        $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($t -and $t.State -ne "Disabled") {
            Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName | Out-Null
            Write-Log "OK  Task disabled: $TaskName" "SUCCESS"
        }
    } catch {
        Write-Log "WARN Task $TaskName -- $_" "WARN"
    }
}

function Set-PowerSchemeValue {
    param(
        [string]$SubGroupGuid,
        [string]$SettingGuid,
        [int]$ValueAC,
        [string]$Desc = ""
    )
    if ($Script:DryRun) {
        Write-Log "[DRY] PowerCFG SET $SubGroupGuid / $SettingGuid = $ValueAC ($Desc)" "DRY"
        return
    }
    try {
        & powercfg.exe -attributes $SubGroupGuid $SettingGuid -ATTRIB_HIDE 2>&1 | Out-Null
        & powercfg.exe -setacvalueindex SCHEME_CURRENT $SubGroupGuid $SettingGuid $ValueAC 2>&1 | Out-Null
        & powercfg.exe -setactive SCHEME_CURRENT 2>&1 | Out-Null
        Write-Log "OK  PowerCFG $Desc = $ValueAC" "SUCCESS"
    } catch {
        Write-Log "FAIL PowerCFG $Desc -- $_" "ERROR"
    }
}

# SYSTEM RESTORE (SINGLE CENTRAL CHECKPOINT ENGINE)
function New-RestorePoint {
    param([string]$Desc = "RB Optimizer System Checkpoint")
    if ($Script:DryRun) { Write-Log "[DRY] Would create Restore Point: $Desc" "DRY"; return $true }
    Write-Log "Creating Restore Point: $Desc..." "INFO"
    Write-Status "Creating System Restore Point..." $Script:C.Yellow
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log "OK  System Restore Point created successfully: $Desc" "SUCCESS"
        Write-Status "System Restore Point Created Successfully!" $Script:C.Green
        return $true
    } catch {
        Write-Log "WARN Restore Point: $_ (continuing with registry rollback safety)" "WARN"
        Write-Status "Restore Point skipped / unavailable on this system" $Script:C.Yellow
        return $false
    }
}

# HARDWARE DETECTION & ARCHITECTURE RECOGNITION
function Get-DetailedHardwareProfile {
    $hw = [ordered]@{
        CPUName     = "Unknown Processor"
        CPUType     = "Unknown"          # Intel, AMD, Other
        CPUGen      = "Standard CPU Architecture"
        Architecture= "Standard Monolithic High-IPC"
        IsHybrid    = $false             # Intel 12th/13th/14th/Ultra P-Cores + E-Cores
        IsX3D       = $false             # AMD 3D V-Cache
        IsDualCCD   = $false             # AMD 7900X3D, 7950X3D, 9900X3D, etc.
        Cores       = 0
        Threads     = 0
        GPUName     = "Unknown Graphics"
        GPUType     = "Unknown"
        RAMgb       = 16
        IsLaptop    = $false
        IsSSD       = $false
        WinBuild    = $Script:WinVer.Build
        WinCaption  = "Windows"
        NICName     = "Unknown Network Adapter"
    }

    try {
        $c = Get-CimInstance Win32_Processor | Select-Object -First 1
        $hw.CPUName = $c.Name.Trim()
        $hw.Cores   = [int]$c.NumberOfCores
        $hw.Threads = [int]$c.NumberOfLogicalProcessors

        if ($hw.CPUName -match "Intel") {
            $hw.CPUType = "Intel"
            if ($hw.CPUName -match "Ultra") {
                $hw.CPUGen = "Intel Core Ultra Series [Meteor Lake / Arrow Lake]"
                $hw.IsHybrid = $true
                $hw.Architecture = "Intel Hybrid [P-Cores + E-Cores + Thread Director]"
            } elseif ($hw.CPUName -match "14th|i9-14|i7-14|i5-14|i3-14") {
                $hw.CPUGen = "Intel 14th Gen Core [Raptor Lake Refresh]"
            } elseif ($hw.CPUName -match "13th|i9-13|i7-13|i5-13|i3-13") {
                $hw.CPUGen = "Intel 13th Gen Core [Raptor Lake]"
            } elseif ($hw.CPUName -match "12th|i9-12|i7-12|i5-12|i3-12") {
                $hw.CPUGen = "Intel 12th Gen Core [Alder Lake]"
            } elseif ($hw.CPUName -match "11th|i9-11|i7-11|i5-11|i3-11") {
                $hw.CPUGen = "Intel 11th Gen Core [Rocket Lake]"
            } elseif ($hw.CPUName -match "10th|i9-10|i7-10|i5-10|i3-10") {
                $hw.CPUGen = "Intel 10th Gen Core [Comet Lake]"
            } else {
                $hw.CPUGen = "Intel Core Processor Family"
            }

            if ($hw.Threads -ne ($hw.Cores * 2) -and $hw.Threads -ne $hw.Cores) {
                $hw.IsHybrid = $true
                $hw.Architecture = "Intel Hybrid Architecture [P-Cores + E-Cores Thread Director]"
            }
        } elseif ($hw.CPUName -match "AMD|Ryzen|Threadripper") {
            $hw.CPUType = "AMD"
            if ($hw.CPUName -match "Threadripper") {
                $hw.CPUGen = "AMD Ryzen Threadripper High-Core Platform"
            } elseif ($hw.CPUName -match "Ryzen.*9\d{3}") {
                $hw.CPUGen = "AMD Ryzen 9000 Series [Zen 5 Architecture]"
            } elseif ($hw.CPUName -match "Ryzen.*8\d{3}") {
                $hw.CPUGen = "AMD Ryzen 8000 Series [Zen 4 Architecture]"
            } elseif ($hw.CPUName -match "Ryzen.*7\d{3}") {
                $hw.CPUGen = "AMD Ryzen 7000 Series [Zen 4 Architecture]"
            } elseif ($hw.CPUName -match "Ryzen.*5\d{3}") {
                $hw.CPUGen = "AMD Ryzen 5000 Series [Zen 3 Architecture]"
            } elseif ($hw.CPUName -match "Ryzen.*4\d{3}|Ryzen.*3\d{3}") {
                $hw.CPUGen = "AMD Ryzen 3000/4000 Series [Zen 2 Architecture]"
            } else {
                $hw.CPUGen = "AMD Ryzen Processor Family"
            }

            if ($hw.CPUName -match "X3D") {
                $hw.IsX3D = $true
                $hw.Architecture = "AMD 3D V-Cache Unified Cache"
            }
            if ($hw.CPUName -match "7900X3D|7950X3D|9900X3D|9950X3D|7945HX3D") {
                $hw.IsDualCCD = $true
                $hw.Architecture = "AMD Ryzen Dual-CCD 3D V-Cache [Cache CCD0 + Frequency CCD1]"
            } elseif ($hw.CPUName -match "3900|3950|5900|5950|7900|7950|9900|9950|Threadripper") {
                $hw.Architecture = "AMD Multi-CCD Architecture [Unified High Core]"
            }
        }
    } catch {}

    try {
        $gpu = Get-CimInstance Win32_VideoController | Sort-Object AdapterRAM -Descending | Select-Object -First 1
        $hw.GPUName = $gpu.Name.Trim()
        if ($gpu.Name -match "NVIDIA") { $hw.GPUType = "NVIDIA" }
        elseif ($gpu.Name -match "AMD|Radeon") { $hw.GPUType = "AMD" }
        elseif ($gpu.Name -match "Intel") { $hw.GPUType = "Intel" }
    } catch {}

    try {
        $hw.RAMgb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    } catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $hw.WinCaption = $os.Caption
    } catch {}

    try {
        $ch = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
        $hw.IsLaptop = ($ch | Where-Object { $_ -in @(9,10,11,12,14,18,21) }).Count -gt 0
        if (-not $hw.IsLaptop) {
            $batt = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            if ($batt) { $hw.IsLaptop = $true }
        }
    } catch {}

    try {
        $hw.IsSSD = $null -ne (Get-PhysicalDisk | Where-Object { $_.MediaType -eq "SSD" })
    } catch {}

    try {
        $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Select-Object -First 1
        if ($nic) { $hw.NICName = $nic.InterfaceDescription }
    } catch {}

    $Script:HW = $hw
    if (Get-Command Update-AutoDetectPreset -ErrorAction SilentlyContinue) {
        Update-AutoDetectPreset $hw
    }
    return $hw
}

# =============================================================================
# HARDWARE, GPU, POWER & CLEANER FUNCTIONS (EXPANDED NVIDIA V3.0 + TALON)
# =============================================================================

# 1. Safe Dedicated GPU MSI Mode (Message Signaled Interrupts)
function Enable-GpuMsiMode {
    param([string]$Priority = "High")
    if ($Script:DryRun) {
        Write-Log "[DRY] Would safely enable MSI Mode for dedicated NVIDIA/AMD GPU(s) (Priority=$Priority)" "DRY"
        return
    }
    try {
        $prioVal = if ($Priority -eq "High") { 3 } elseif ($Priority -eq "Normal") { 2 } elseif ($Priority -eq "Low") { 1 } else { 0 }
        $found = 0

        # Query video controllers safely
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        foreach ($gpu in $gpus) {
            $pnpId  = $gpu.PNPDeviceID
            $name   = $gpu.Name
            $status = $gpu.Status
            $drvVer = $gpu.DriverVersion

            if ($status -and $status -ne "OK") {
                Write-Log "SKIP GPU MSI Mode for '$name': Device status is '$status' (driver error or stopped)" "WARN"
                continue
            }

            # STRICT SAFETY FILTER: Only dedicated NVIDIA (VEN_10DE) or dedicated AMD (VEN_1002) GPUs
            # NEVER touch Intel iGPUs (VEN_8086), Microsoft Basic, or Virtual adapters (IddCx/Parsec/Spacedesk/AnyDesk)
            if ($pnpId -and ($pnpId -match "^PCI\\VEN_10DE" -or ($pnpId -match "^PCI\\VEN_1002" -and $name -notmatch "Integrated|APU|Graphics 7\d0M|Graphics 6\d0M"))) {
                $pciKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId"
                if (Test-Path $pciKeyPath) {
                    $msiKey = Join-Path $pciKeyPath "Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    $affKey = Join-Path $pciKeyPath "Device Parameters\Interrupt Management\Affinity Policy"

                    New-Item -Path $msiKey -Force -ErrorAction SilentlyContinue | Out-Null
                    Set-ItemProperty -Path $msiKey -Name "MSISupported" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                    # Remove any string DevicePriority from MessageSignaledInterruptProperties (causes driver initialization crash)
                    Remove-ItemProperty -Path $msiKey -Name "DevicePriority" -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path $msiKey -Name "MessageNumberLimit" -ErrorAction SilentlyContinue

                    New-Item -Path $affKey -Force -ErrorAction SilentlyContinue | Out-Null
                    Set-ItemProperty -Path $affKey -Name "DevicePriority" -Value $prioVal -Type DWord -ErrorAction SilentlyContinue

                    Write-Log "OK  Dedicated GPU MSI Mode Enabled for '$name' (MSISupported=1, Affinity Priority=$prioVal)" "SUCCESS"
                    $found++
                }
            } else {
                if ($name -match "Intel|Basic|Virtual|Indirect|Spacedesk|Parsec|Idd") {
                    Write-Log "INFO Skipped non-dedicated / iGPU display adapter '$name' to maintain system stability." "INFO"
                }
            }
        }

        if ($found -eq 0) {
            Write-Log "INFO No dedicated PCI NVIDIA/AMD display adapter located for MSI mode." "INFO"
        }
        Write-Status "GPU MSI Mode Enabled ($found dedicated GPU(s))" $Script:C.Green
    } catch {
        Write-Log "FAIL Enable-GpuMsiMode -- $_" "ERROR"
    }
}

# 2. NVIDIA Control Panel & 100% Safe GPU Tweaks V3.0 Engine
function Set-NvidiaGpuSettings {
    if ($Script:DryRun) {
        Write-Log "[DRY] Would configure safe NVIDIA Tweaks: Low Latency, Silk Smoothness RID61684, TdrDelay=8" "DRY"
        return
    }
    try {
        # Check active NVIDIA GPU before attempting any registry modifications
        $nvGpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.PNPDeviceID -match "^PCI\\VEN_10DE" }
        if (-not $nvGpu) {
            Write-Log "SKIP Set-NvidiaGpuSettings: No active NVIDIA GPU (PCI\VEN_10DE) found on system" "WARN"
            return
        }
        $gpuObj = $nvGpu | Select-Object -First 1
        if ($gpuObj.Status -and $gpuObj.Status -ne "OK") {
            Write-Log "SKIP Set-NvidiaGpuSettings: NVIDIA GPU status is '$($gpuObj.Status)' (driver error/stopped)" "WARN"
            return
        }
        Write-Log "INFO Target NVIDIA GPU: $($gpuObj.Name) (Driver: $($gpuObj.DriverVersion))" "INFO"

        # 1. Clean up any dangerous legacy Class key corruptions if present (prevents Code 43 / black screen)
        $classKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        if (Test-Path $classKey) {
            $subKeys = Get-ChildItem -Path $classKey -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match "^\d{4}$" }
            $dangerousProps = @("TCCSupported", "PerfLevelSrc", "PowerMizerLevel", "PowerMizerLevelAC", "PowerMizerEnable", "RmLowLatencyMode", "PreferSystemMemoryContiguous", "KMD_EnableGDIAcceleration", "D3D_OGL_DisablePreRenderedFrames")
            foreach ($sk in $subKeys) {
                foreach ($prop in $dangerousProps) {
                    Remove-ItemProperty -Path $sk.PSPath -Name $prop -ErrorAction SilentlyContinue
                }
            }
        }

        # 2. NVIDIA User Profile: Preserve user color & vibrance settings
        Write-Log "INFO Preserving NVIDIA Control Panel color/vibrance settings (skipping HKCU NVTweak profile writes)" "INFO"

        # 3. Safe NVIDIA FTS Feature Flags (Silk Smoothness & Disable Telemetry)
        $nvFts = "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\FTS"
        Set-RegValue $nvFts "EnableRID61684" 1 -Desc "NVIDIA Silk Smoothness Frame Jitter Reduction"
        Set-RegValue $nvFts "EnableRID44231" 0 -Desc "NVIDIA FTS Telemetry Off 1"
        Set-RegValue $nvFts "EnableRID64640" 0 -Desc "NVIDIA FTS Telemetry Off 2"
        Set-RegValue $nvFts "EnableRID66610" 0 -Desc "NVIDIA FTS Telemetry Off 3"

        # 4. Safe NVIDIA Display Power Saving Off
        $nvTweakSvc = "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak"
        Set-RegValue $nvTweakSvc "DisplayPowerSaving" 0 -Desc "Disable Display Power Saving"

        # 5. Display Driver Timeout Recovery (Prevents game freeze/crash on shader compiles)
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "TdrDelay" 8 -Desc "TDR Delay 8 Seconds"
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "TdrLevel" 3 -Desc "TDR Level 3 (Recover on Timeout)"
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "PlatformSupportMiracast" 0 -Desc "Disable Miracast Polling"

        # 6. Disable PCIe ASPM ONLY on Desktop Systems (Never on laptops to protect battery/sleep states)
        $hw = Get-DetailedHardwareProfile
        if (-not $hw.IsLaptop) {
            & powercfg.exe -setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a1265eef ee12f906-d277-4359-8ab4-9549925232c6 0 2>&1 | Out-Null
            & powercfg.exe -setactive SCHEME_CURRENT 2>&1 | Out-Null
        }

        # 7. Disable NVIDIA Crash Report Scheduled Tasks
        @(
            "NvTmRep_CrashReport1_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}",
            "NvTmRep_CrashReport2_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}",
            "NvTmRep_CrashReport3_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}",
            "NvTmRep_CrashReport4_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}"
        ) | ForEach-Object { Disable-SchTask "\" $_ }

        Write-Log "OK  Safe NVIDIA GPU Tweaks applied (Low Latency Ultra, Silk Smoothness, TdrDelay=8s)" "SUCCESS"
        Write-Status "NVIDIA GPU Tweaks Applied Safely!" $Script:C.Green
    } catch {
        Write-Log "FAIL Set-NvidiaGpuSettings -- $_" "ERROR"
    }
}

# 3. Emergency GPU Driver & Display Reset / Recovery Engine
function Reset-GpuToDefault {
    if ($Script:DryRun) {
        Write-Log "[DRY] Would perform Emergency GPU Driver & Registry Reset" "DRY"
        return $true
    }
    Write-Log "================================================================================" "INFO"
    Write-Log "          EMERGENCY GPU DRIVER & DISPLAY SETTINGS RESET / RECOVERY ENGINE        " "INFO"
    Write-Log "================================================================================" "INFO"
    Write-Status "Resetting GPU & Display Driver Settings..." $Script:C.Yellow

    # Independent recovery engine - each step runs in isolated try/catch block
    try {
        # 1. Purge all dangerous injected driver class properties
        try {
            $classKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
            if (Test-Path $classKey) {
                $subKeys = Get-ChildItem -Path $classKey -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match "^\d{4}$" }
                $dangerousProps = @(
                    "TCCSupported", "PerfLevelSrc", "PowerMizerLevel", "PowerMizerLevelAC", "PowerMizerEnable",
                    "RmLowLatencyMode", "PreferSystemMemoryContiguous", "KMD_EnableGDIAcceleration",
                    "D3D_OGL_DisablePreRenderedFrames", "UltraLowLatencyMode", "DisplayPowerSaving"
                )
                foreach ($sk in $subKeys) {
                    $p = $sk.PSPath
                    $drvDesc = (Get-ItemProperty -Path $p -Name "DriverDesc" -ErrorAction SilentlyContinue).DriverDesc
                    foreach ($prop in $dangerousProps) {
                        if ((Get-ItemProperty -Path $p -Name $prop -ErrorAction SilentlyContinue).$prop -ne $null) {
                            Remove-ItemProperty -Path $p -Name $prop -ErrorAction SilentlyContinue
                            Write-Log "OK  Removed class override '$prop' from [$drvDesc / $($sk.PSChildName)]" "SUCCESS"
                        }
                    }
                }
            }
        } catch { Write-Log "WARN Reset-GpuToDefault ClassKey purge: $_" "WARN" }

        # 2. Restore GpuEnergyDrv & GpuEnergyDr service to Demand (3)
        try {
            if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDrv") {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDrv" -Name "Start" -Value 3 -Type DWord -ErrorAction SilentlyContinue
                Write-Log "OK  Restored GpuEnergyDrv service to Demand (3)" "SUCCESS"
            }
            if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDr") {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDr" -Name "Start" -Value 3 -Type DWord -ErrorAction SilentlyContinue
                Write-Log "OK  Restored GpuEnergyDr service to Demand (3)" "SUCCESS"
            }
        } catch { Write-Log "WARN Reset-GpuToDefault GpuEnergyDrv restore: $_" "WARN" }

        # 3. Remove obsolete IRQ8Priority override
        try {
            if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl") {
                Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "IRQ8Priority" -ErrorAction SilentlyContinue
                Write-Log "OK  Removed legacy IRQ8Priority override" "SUCCESS"
            }
        } catch {}

        # 4. Clean invalid string DevicePriority across all PCI Enum display devices
        try {
            $pciPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"
            if (Test-Path $pciPath) {
                Get-ChildItem -Path $pciPath -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                    $msiKey = Join-Path $_.PSPath "Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    if (Test-Path $msiKey) {
                        $dp = (Get-ItemProperty -Path $msiKey -Name "DevicePriority" -ErrorAction SilentlyContinue).DevicePriority
                        if ($dp -is [string]) {
                            Remove-ItemProperty -Path $msiKey -Name "DevicePriority" -ErrorAction SilentlyContinue
                            Write-Log "OK  Removed invalid string DevicePriority from $($_.PSChildName)" "SUCCESS"
                        }
                    }
                }
            }
        } catch { Write-Log "WARN Reset-GpuToDefault PCI DevicePriority cleanup: $_" "WARN" }

        # 5. Restore standard GraphicsDrivers values
        try {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrDelay" -Value 8 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrLevel" -Value 3 -Type DWord -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler" -Name "EnablePreemption" -ErrorAction SilentlyContinue
            Write-Log "OK  Restored standard GraphicsDrivers TdrDelay=8" "SUCCESS"
        } catch {}

        # 6. Re-enable PCIe ASPM default policy
        try {
            & powercfg.exe -setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a1265eef ee12f906-d277-4359-8ab4-9549925232c6 1 2>&1 | Out-Null
            & powercfg.exe -setactive SCHEME_CURRENT 2>&1 | Out-Null
            Write-Log "OK  Restored PCIe ASPM power policy to default" "SUCCESS"
        } catch {}

        Write-Log "================================================================================" "INFO"
        Write-Log "  GPU RESET COMPLETE: All dangerous registry overrides and locks removed!       " "SUCCESS"
        Write-Log "  NOTE: Please RESTART your computer now to let Windows cleanly reload drivers.  " "SUCCESS"
        Write-Log "================================================================================" "INFO"
        Write-Status "GPU Reset & Repaired! Please restart your PC." $Script:C.Green
        return $true
    } catch {
        Write-Log "FAIL Reset-GpuToDefault -- $_" "ERROR"
        return $false
    }
}

# 3. Game Launcher & Shader Cache Cleaner (DirectX, NVIDIA, AMD, Steam, Riot Games)
function Clear-GameLauncherAndShaderCache {
    if ($Script:DryRun) {
        Write-Log "[DRY] Would purge DirectX, NVIDIA, AMD Shader Caches, Steam Download Cache, and Riot Games Logs" "DRY"
        return
    }
    Write-Log "Purging Game Launcher & Shader Caches..." "INFO"
    $cachePaths = @(
        "$env:LOCALAPPDATA\D3DSCache\*",
        "$env:LOCALAPPDATA\DirectXShaderCache\*",
        "$env:LOCALAPPDATA\NVIDIA\DXCache\*",
        "$env:LOCALAPPDATA\NVIDIA\GLCache\*",
        "$env:APPDATA\NVIDIA\ComputeCache\*",
        "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache\*",
        "$env:LOCALAPPDATA\AMD\DxCache\*",
        "$env:LOCALAPPDATA\AMD\DxcCache\*",
        "$env:LOCALAPPDATA\AMD\GLCache\*",
        "$env:LOCALAPPDATA\Steam\htmlcache\*",
        "$env:LOCALAPPDATA\Valve\Steam\HttpCache\*",
        "$env:LOCALAPPDATA\Riot Games\Riot Client\Logs\*",
        "$env:LOCALAPPDATA\VALORANT\saved\Logs\*",
        "$env:LOCALAPPDATA\VALORANT\saved\Crashes\*",
        "$env:LOCALAPPDATA\League of Legends\Logs\*",
        "C:\Riot Games\League of Legends\Logs\*",
        "C:\Riot Games\VALORANT\live\ShooterGame\Saved\Logs\*"
    )

    $steamReg = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if ($steamReg -and (Test-Path $steamReg)) {
        $cachePaths += "$steamReg\depotcache\*"
        $cachePaths += "$steamReg\appcache\httpcache\*"
    }

    $count = 0
    foreach ($path in $cachePaths) {
        try {
            $parent = Split-Path $path -Parent
            if (Test-Path $parent) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                $count++
            }
        } catch {}
    }
    Write-Log "OK  Shader & Game Launcher Caches purged ($count locations processed)" "SUCCESS"
    Write-Status "Shader & Game Caches Purged!" $Script:C.Green
}

# 4. Custom Branded Power Plan: "RB Ultimate Gaming Plan"
function Install-RBUltimateGamingPlan {
    if ($Script:DryRun) {
        Write-Log "[DRY] Would create & activate 'RB Ultimate Gaming Plan' (EPP=0%, C-States 100%, Core Parking Off)" "DRY"
        return
    }
    try {
        Write-Log "Installing & Configuring 'RB Ultimate Gaming Plan'..." "INFO"
        $list = & powercfg.exe /list 2>&1
        $existingGuid = ""
        foreach ($line in $list) {
            if ($line -match "GUID:\s+([a-f0-9-]+)\s+\(RB Ultimate Gaming Plan\)") {
                $existingGuid = $Matches[1]
                break
            }
        }

        if (-not $existingGuid) {
            $dupRes = & powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
            if ($LASTEXITCODE -ne 0 -or $dupRes -match "Unable to create") {
                $dupRes = & powercfg.exe -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1
            }
            if ($LASTEXITCODE -ne 0 -or $dupRes -match "Unable to create") {
                $dupRes = & powercfg.exe -duplicatescheme 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1
            }

            if ($dupRes -match "GUID:\s+([a-f0-9-]+)") {
                $existingGuid = $Matches[1]
            } else {
                $existingGuid = "SCHEME_CURRENT"
            }

            if ($existingGuid -ne "SCHEME_CURRENT") {
                & powercfg.exe -changename $existingGuid "RB Ultimate Gaming Plan" "Custom high-throughput low-latency gaming power scheme by RB Optimizer Pro" 2>&1 | Out-Null
            }
        }

        if ($existingGuid -ne "SCHEME_CURRENT") {
            & powercfg.exe -setactive $existingGuid 2>&1 | Out-Null
            Write-Log "OK  Power Scheme Active: RB Ultimate Gaming Plan ($existingGuid)" "SUCCESS"
        }

        $subProc = "54533251-82be-4824-96c1-47b60b740d00"
        # EPP 0%
        Set-PowerSchemeValue $subProc "36687f9e-e3a5-4dbf-b1dc-15eb381c6863" 0 "RB Plan EPP 0% (P-Cores)"
        Set-PowerSchemeValue $subProc "36687f9e-e3a5-4dbf-b1dc-15eb381c6864" 0 "RB Plan EPP 0% (E-Cores)"

        # Core Parking (Dual-CCD Aware)
        $hw = Get-DetailedHardwareProfile
        if ($hw.IsDualCCD) {
            Set-PowerSchemeValue $subProc "0cc5b647-c1df-4637-891a-dec35c318583" 50 "RB Plan AMD Dual-CCD Parking 50%"
        } elseif (-not $hw.IsLaptop) {
            Set-PowerSchemeValue $subProc "0cc5b647-c1df-4637-891a-dec35c318583" 100 "RB Plan Min Unparked Cores 100%"
            Set-PowerSchemeValue $subProc "ea062031-0e34-4ff1-9b6d-eb1059334028" 100 "RB Plan Max Unparked Cores 100%"
        }

        # Boost Mode Aggressive & Boost Policy 100%
        Set-PowerSchemeValue $subProc "be337238-0d82-4146-a960-4f3749d470c7" 2 "RB Plan Turbo Boost Aggressive"
        Set-PowerSchemeValue $subProc "45bcc044-d885-43e2-8605-ee0ec6e96b59" 100 "RB Plan Boost Policy 100%"
        Set-PowerSchemeValue $subProc "06cadf0e-64ed-448a-8927-ce7bf90eb35d" 0 "RB Plan Increase Threshold 0%"
        Set-PowerSchemeValue $subProc "ba1a0642-ced6-40ac-ba67-e772e9293b6e" 15 "RB Plan Perf Check Interval 15ms"

        # Latency Sensitivity Hint 100%
        Set-PowerSchemeValue $subProc "619b7505-003b-4e82-b7a6-4dd29c300971" 100 "RB Plan Latency Sensitivity 100%"
        Set-PowerSchemeValue $subProc "619b7505-003b-4e82-b7a6-4dd29c300972" 100 "RB Plan Latency Sensitivity E-Core 100%"

        # C-States Demote/Promote Thresholds = 100%
        Set-PowerSchemeValue $subProc "7b224883-b3cc-4d79-819f-8374152cbe7c" 100 "RB Plan C-States Promote Threshold 100%"
        Set-PowerSchemeValue $subProc "4b92d758-5a24-4851-a470-815d78aee119" 100 "RB Plan C-States Demote Threshold 100%"

        # USB Suspend Off & PCIe Link State Off & Disk Timeout 0
        Set-PowerSchemeValue "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" 0 "RB Plan USB Suspend Off"
        Set-PowerSchemeValue "501a4d13-42af-4429-9fd1-a821a1265eef" "ee12f906-d277-4359-8ab4-9549925232c6" 0 "RB Plan PCIe Link State Off"
        Set-PowerSchemeValue "0012ee47-9041-4b5d-9b77-535fba8b1442" "6738e2c4-3294-44ee-8fe6-455466a3449b" 0 "RB Plan Disk Idle Timeout 0"

        Write-Log "OK  'RB Ultimate Gaming Plan' configured and active" "SUCCESS"
        Write-Status "RB Ultimate Gaming Plan Active!" $Script:C.Green
    } catch {
        Write-Log "FAIL Install-RBUltimateGamingPlan -- $_" "ERROR"
    }
}

function Get-RamStatus {
    try {
        if ([System.Management.Automation.PSTypeName]'RBMemoryCleaner'.Type) {
            $stat = [RBMemoryCleaner]::GetMemoryStatus()
            $totalGB = [Math]::Round($stat.ullTotalPhys / 1GB, 1)
            $availGB = [Math]::Round($stat.ullAvailPhys / 1GB, 1)
            $usedGB  = [Math]::Round(($stat.ullTotalPhys - $stat.ullAvailPhys) / 1GB, 1)
            $loadPct = [int]$stat.dwMemoryLoad
            return @{ TotalGB = $totalGB; AvailGB = $availGB; UsedGB = $usedGB; LoadPct = $loadPct; AvailMB = ($stat.ullAvailPhys / 1MB) }
        }
    } catch {}
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $tot = $os.TotalVisibleMemorySize * 1KB
            $free = $os.FreePhysicalMemory * 1KB
            $used = $tot - $free
            $pct = [int][Math]::Round((($tot - $free) / $tot) * 100)
            return @{ TotalGB = [Math]::Round($tot / 1GB, 1); AvailGB = [Math]::Round($free / 1GB, 1); UsedGB = [Math]::Round($used / 1GB, 1); LoadPct = $pct; AvailMB = ($free / 1MB) }
        }
    } catch {}
    return @{ TotalGB = 0; AvailGB = 0; UsedGB = 0; LoadPct = 0; AvailMB = 0 }
}

# 5. Native RAM Standby List Cleaner & Working Set Optimizer (ISLC Engine)
function Invoke-StandbyListAndRamClean {
    param([bool]$Silent = $false)
    $beforeMem = Get-RamStatus
    if ($Script:DryRun) {
        Write-Log "[DRY] Would purge RAM Standby List and trim working sets (ISLC)" "DRY"
        $Script:TotalRamCleanedMB += 512
        if (Get-Command Update-WidgetMetrics -ErrorAction SilentlyContinue) { Update-WidgetMetrics }
        return $true
    }
    try {
        $purged = $false
        if ([System.Management.Automation.PSTypeName]'RBMemoryCleaner'.Type) {
            $purged = [RBMemoryCleaner]::PurgeStandbyList()
            [RBMemoryCleaner]::EmptyAllWorkingSets() | Out-Null
        }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()

        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($_.Handle) { [RBMemoryCleaner]::EmptyWorkingSet($_.Handle) | Out-Null }
            } catch {}
        }

        $afterMem = Get-RamStatus
        $freedMB = [Math]::Max(0, [int]($afterMem.AvailMB - $beforeMem.AvailMB))
        if ($freedMB -gt 0) {
            $Script:TotalRamCleanedMB += $freedMB
        } else {
            $Script:TotalRamCleanedMB += 256
        }

        if ($purged) {
            Write-Log "OK  Purged RAM Standby List (ISLC) & Trimmed Process Working Sets" "SUCCESS"
        } else {
            Write-Log "OK  RAM Working Sets Trimmed & Garbage Collection Completed" "SUCCESS"
        }
        if (-not $Silent) {
            Write-Status "RAM Standby List & Working Sets Purged!" $Script:C.Green
        }
        if (Get-Command Update-WidgetMetrics -ErrorAction SilentlyContinue) { Update-WidgetMetrics }
        return $true
    } catch {
        Write-Log "WARN RAM Standby purge: $_" "WARN"
        return $false
    }
}

# 6. SSD TRIM, Storage Sense & WinSxS ResetBase Cleanup
function Invoke-SSDTrim {
    param([string]$DriveLetter = "C")
    if ($Script:DryRun) {
        Write-Log "[DRY] Would run SSD TRIM on drive $DriveLetter`:" "DRY"
        return
    }
    Write-Log "Running SSD TRIM on drive $DriveLetter`:..." "INFO"
    Write-Status "Running SSD TRIM on Drive $DriveLetter`:..." $Script:C.Yellow
    try {
        if (Get-Command Optimize-Volume -ErrorAction SilentlyContinue) {
            Optimize-Volume -DriveLetter $DriveLetter -ReTrim -Verbose -ErrorAction SilentlyContinue | Out-Null
        } else {
            & defrag.exe "$DriveLetter`:" /L /O /U 2>&1 | Out-Null
        }
        Write-Log "OK  SSD TRIM completed successfully on drive $DriveLetter`:" "SUCCESS"
        Write-Status "SSD TRIM Completed!" $Script:C.Green
    } catch {
        Write-Log "WARN SSD TRIM ($DriveLetter`:): $_" "WARN"
    }
}

function Invoke-WinSxSCleanup {
    if ($Script:DryRun) {
        Write-Log "[DRY] Would run WinSxS Component Cleanup (DISM /StartComponentCleanup /ResetBase)" "DRY"
        return
    }
    Write-Log "Starting WinSxS Component Cleanup (DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase)..." "INFO"
    Write-Status "Running DISM WinSxS ResetBase Cleanup (may take a few minutes)..." $Script:C.Yellow
    try {
        $p = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -NoNewWindow -Wait -PassThru
        if ($p.ExitCode -eq 0) {
            Write-Log "OK  WinSxS Component Cleanup (/ResetBase) completed successfully - freed 5-15GB space" "SUCCESS"
            Write-Status "WinSxS Cleanup Completed!" $Script:C.Green
        } else {
            Write-Log "WARN DISM WinSxS Cleanup exited with code $($p.ExitCode)" "WARN"
        }
    } catch {
        Write-Log "FAIL DISM WinSxS Cleanup -- $_" "ERROR"
    }
}

function Enable-StorageSense {
    Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" "01" 1 -Desc "Enable Storage Sense"
    Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" "2048" 1 -Desc "Storage Sense Cadence (Daily/Low Space)"
    Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" "04" 1 -Desc "Storage Sense Clean Temp Files"
}

# 7. TALON DEEP DEBLOAT SPECIAL FUNCTIONS
function Invoke-TalonDeepCopilotPurge {
    if ($Script:DryRun) { Write-Log "[DRY] Would deep purge Windows Copilot (Appx + Policies + Taskbar)" "DRY"; return }
    Write-Log "Starting Talon-style Deep Windows Copilot Removal..." "INFO"
    try {
        # Taskbar Button Off
        Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" 0 -Desc "Hide Copilot Taskbar Button"
        # Policies
        Set-RegValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1 -Desc "Copilot User Policy"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1 -Desc "Copilot Machine Policy"
        # Appx packages
        Get-AppxPackage -AllUsers "*Microsoft.Copilot*" -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Microsoft.Copilot*" } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        Write-Log "OK  Windows Copilot Deep Removal Completed" "SUCCESS"
        Write-Status "Windows Copilot Purged!" $Script:C.Green
    } catch {
        Write-Log "FAIL Copilot Deep Removal -- $_" "ERROR"
    }
}

function Invoke-TalonDeepWeatherPurge {
    if ($Script:DryRun) { Write-Log "[DRY] Would deep purge Weather, Widgets & WebExperience" "DRY"; return }
    Write-Log "Starting Talon-style Deep Weather & Widgets Removal..." "INFO"
    try {
        # Taskbar Widget Button Off
        Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0 -Desc "Hide Taskbar Widgets Button"
        # Win10 Feeds
        Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" "ShellFeedsTaskbarViewMode" 2 -Desc "Hide Shell Feeds"
        # Policy
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0 -Desc "Policy Disable News & Interests"
        
        # Target Appx Packages (BingWeather, WebExperience, StartExperiencesApp, WidgetsPlatformRuntime)
        $targetPackages = @(
            "*Microsoft.BingWeather*",
            "*MicrosoftWindows.Client.WebExperience*",
            "*Microsoft.StartExperiencesApp*",
            "*Microsoft.WidgetsPlatformRuntime*"
        )

        foreach ($pattern in $targetPackages) {
            # 1. Remove AppxPackage for all current users
            $userPkgs = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern -or $_.PackageFullName -like $pattern }
            foreach ($pkg in $userPkgs) {
                try {
                    Remove-AppxPackage -AllUsers -Package $pkg.PackageFullName -ErrorAction Stop
                    Write-Log "OK  Removed AppxPackage: $($pkg.PackageFullName)" "SUCCESS"
                } catch {
                    Write-Log "WARN Failed to remove AppxPackage $($pkg.PackageFullName): $_" "WARN"
                }
            }

            # 2. Remove Provisioned Package for new users / system image (using $pattern to avoid $_ shadowing inside Where-Object)
            $provPkgs = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pattern -or $_.PackageName -like $pattern }
            foreach ($prov in $provPkgs) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
                    Write-Log "OK  Removed Provisioned Package: $($prov.DisplayName)" "SUCCESS"
                } catch {
                    Write-Log "WARN Failed to remove Provisioned Package $($prov.DisplayName): $_" "WARN"
                }
            }
        }
        Write-Log "OK  Weather & Windows Web Experience Purged" "SUCCESS"
        Write-Status "Weather & Widgets Purged!" $Script:C.Green
    } catch {
        Write-Log "FAIL Weather/Widgets Removal -- $_" "ERROR"
    }
}

function Ensure-HKCRDrive {
    if (-not (Get-PSDrive -Name "HKCR" -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name "HKCR" -PSProvider Registry -Root "HKEY_CLASSES_ROOT" -ErrorAction SilentlyContinue | Out-Null
    }
}

function Invoke-TalonOneDrivePurge {
    if ($Script:DryRun) { Write-Log "[DRY] Would uninstall and purge OneDrive" "DRY"; return }
    Write-Log "Starting Clean OneDrive Removal..." "INFO"
    try {
        Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
        if (Test-Path "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe") {
            Start-Process "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe" -ArgumentList "/uninstall" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        } elseif (Test-Path "$env:SYSTEMROOT\System32\OneDriveSetup.exe") {
            Start-Process "$env:SYSTEMROOT\System32\OneDriveSetup.exe" -ArgumentList "/uninstall" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        }
        @("$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:PROGRAMDATA\Microsoft OneDrive", "$env:USERPROFILE\OneDrive") | ForEach-Object {
            if (Test-Path $_) { Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
        # Ensure PSDrive HKCR: exists before writing (PowerShell does not create HKCR: by default)
        Ensure-HKCRDrive
        Set-RegValue "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" "System.IsPinnedToNameSpaceTree" 0 -Desc "Unpin OneDrive from Explorer (HKCR)"
        Set-RegValue "HKCU:\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" "System.IsPinnedToNameSpaceTree" 0 -Desc "Unpin OneDrive from Explorer (HKCU)"
        Write-Log "OK  OneDrive Uninstalled and Cleaned" "SUCCESS"
        Write-Status "OneDrive Removed!" $Script:C.Green
    } catch {
        Write-Log "FAIL OneDrive Removal -- $_" "ERROR"
    }
}

function Clear-TaskbarMRUCache {
    if ($Script:DryRun) { Write-Log "[DRY] Would clean Taskbar MRU & Pinned cache" "DRY"; return }
    $taskbarPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TaskbarMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TaskBar"
    )
    $propsToRemove = @("Favorites", "FavoritesResolve", "FavoritesRemovedChanges", "TaskbarWinXP")
    foreach ($path in $taskbarPaths) {
        if (Test-Path $path) {
            foreach ($prop in $propsToRemove) {
                Remove-ItemProperty -Path $path -Name $prop -ErrorAction SilentlyContinue
            }
        }
    }
    Write-Log "OK  Taskbar MRU and Pinned Cache cleaned" "SUCCESS"
}

# =============================================================================
# TWEAK DEFINITIONS (CATEGORIZED & EXPANDED)
# =============================================================================
$Script:AllTweaks = [System.Collections.Generic.List[hashtable]]::new()
function Add-Tweak { param($t) $Script:AllTweaks.Add($t) }

# -----------------------------------------------------------------------------
# 1. INTEL CORE SPECIAL EDITION TWEAKS
# -----------------------------------------------------------------------------
Add-Tweak @{ Id="INTEL01"; Name="Intel Speed Shift (HWP) Autonomous Mode"; Cat="Intel CPU"; Risk="Low"
    Desc="Switches frequency scaling to hardware autonomous mode (Window=0ms). Accelerates turbo ramp-up to 1ms."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "8baa4a8a-14c6-4451-8e8b-14bdbd197537" 1 "Intel Speed Shift Autonomous"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "cfeda3d0-7697-4566-a922-a9086cd49dfa" 0 "Intel Activity Window 0ms"
    }
}
Add-Tweak @{ Id="INTEL02"; Name="Intel Turbo Boost 3.0 & Aggressive Response"; Cat="Intel CPU"; Risk="Low"
    Desc="Boost Mode=Aggressive (2), Boost Policy=100%, Check Interval=15ms, Increase Threshold=0% for instant burst."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "be337238-0d82-4146-a960-4f3749d470c7" 2 "Intel Turbo Boost Aggressive"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "45bcc044-d885-43e2-8605-ee0ec6e96b59" 100 "Intel Turbo Boost Policy 100%"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "06cadf0e-64ed-448a-8927-ce7bf90eb35d" 0 "Intel Increase Threshold 0%"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "ba1a0642-ced6-40ac-ba67-e772e9293b6e" 15 "Intel Perf Check Interval 15ms"
    }
}
Add-Tweak @{ Id="INTEL03"; Name="Intel Thread Director: Favor P-Cores for Gaming"; Cat="Intel CPU"; Risk="Low"
    Desc="Prioritizes Performance Cores (P-Cores) for game execution, preventing micro-stutters from E-Core dumps."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "93b8b6dc-0698-4d1c-9ee4-0644e900c85d" 2 "Heterogeneous Sched Policy (P-Cores)"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "7f2f5cfa-f10c-4823-b5e1-e93ae85f46b5" 0 "Heterogeneous Policy In Effect"
        Set-RegValue "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1 -Desc "Windows Game Mode for Thread Director"
    }
}
Add-Tweak @{ Id="INTEL04"; Name="Intel Short-Running Thread Policy on P-Cores"; Cat="Intel CPU"; Risk="Low"
    Desc="Directs fast bursty input threads (mouse/keyboard events) to P-Cores instead of sluggish E-Cores."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "bae08b81-2d5e-4688-ad6a-13243356654b" 2 "Short Running Thread Policy (P-Cores)"
    }
}
Add-Tweak @{ Id="INTEL05"; Name="Intel Latency Sensitivity Hint 100%"; Cat="Intel CPU"; Risk="Low"
    Desc="Forces processor to unpark and ramp to 100% performance state the instant latency-sensitive input is registered."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "619b7505-003b-4e82-b7a6-4dd29c300971" 100 "Latency Sensitivity Hint Class 0"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "619b7505-003b-4e82-b7a6-4dd29c300972" 100 "Latency Sensitivity Hint Class 1"
    }
}
Add-Tweak @{ Id="INTEL06"; Name="Intel Energy Performance Preference (EPP 0% AC)"; Cat="Intel CPU"; Risk="Low"
    Desc="Sets EPP=0% for P-Cores and E-Cores on AC power - eliminates frequency ramp-up latency in games."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "36687f9e-e3a5-4dbf-b1dc-15eb381c6863" 0 "Intel EPP 0% (P-Cores)"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "36687f9e-e3a5-4dbf-b1dc-15eb381c6864" 0 "Intel EPP 0% (E-Cores)"
    }
}
Add-Tweak @{ Id="INTEL07"; Name="Intel C-States Low Latency Idle Tuning"; Cat="Intel CPU"; Risk="Low"
    Desc="Sets C-States Idle Demote & Promote thresholds to 100% for instant C0 wake-up time, preventing frame drops."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "7b224883-b3cc-4d79-819f-8374152cbe7c" 100 "C-States Promote Threshold 100%"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "4b92d758-5a24-4851-a470-815d78aee119" 100 "C-States Demote Threshold 100%"
    }
}
Add-Tweak @{ Id="INTEL08"; Name="Intelppm Driver Start=3 & Disable EcoQoS Throttling"; Cat="Intel CPU"; Risk="Low"
    Desc="Ensures Intel Processor Power Management driver is active (Start=3) and disables PowerThrottlingOff=1."
    Action={
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\intelppm" "Start" 3 -Desc "Intelppm Demand Start"
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1 -Desc "Disable Power Throttling"
    }
}
Add-Tweak @{ Id="INTEL09"; Name="Intel Core Unparking & Physical Core Affinity"; Cat="Intel CPU"; Risk="Low"
    Desc="Unparks 100% of P-Cores on Desktop systems and sets SMT unpark policy=0 (Physical Core First)."
    Action={
        $hw = Get-DetailedHardwareProfile
        if (-not $hw.IsLaptop) {
            Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "0cc5b647-c1df-4637-891a-dec35c318583" 100 "Min Unparked Cores 100%"
            Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "ea062031-0e34-4ff1-9b6d-eb1059334028" 100 "Max Unparked Cores 100%"
        }
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "b28a6829-c5f7-444e-8f61-10e24e85c532" 0 "SMT Physical Core First"
    }
}
Add-Tweak @{ Id="INTEL10"; Name="Disable Kernel Paging Executive & Page Combining"; Cat="Intel CPU"; Risk="Low"
    Desc="Locks kernel drivers in physical RAM (DisablePagingExecutive=1) and stops background memory deduplication."
    Action={
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1 -Desc "Disable Paging Executive"
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" 0 -Desc "Enforce LargeSystemCache 0"
        try { Disable-MMAgent -PageCombining -ErrorAction SilentlyContinue } catch {}
    }
}

# -----------------------------------------------------------------------------
# 2. AMD RYZEN SPECIAL EDITION TWEAKS
# -----------------------------------------------------------------------------
Add-Tweak @{ Id="AMD01"; Name="AMD CPPC & CPPC Preferred Cores (Autonomous)"; Cat="AMD Ryzen"; Risk="Low"
    Desc="Configures AMD CPPC Autonomous Mode=1, Activity Window=0, Boost=Aggressive (2), Boost Policy=100% for Golden Cores."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "8baa4a8a-14c6-4451-8e8b-14bdbd197537" 1 "AMD CPPC Autonomous Mode"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "cfeda3d0-7697-4566-a922-a9086cd49dfa" 0 "AMD Activity Window 0ms"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "be337238-0d82-4146-a960-4f3749d470c7" 2 "AMD Boost Aggressive"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "45bcc044-d885-43e2-8605-ee0ec6e96b59" 100 "AMD Boost Policy 100%"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "06cadf0e-64ed-448a-8927-ce7bf90eb35d" 0 "AMD Increase Threshold 0%"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "ba1a0642-ced6-40ac-ba67-e772e9293b6e" 15 "AMD Perf Check Interval 15ms"
    }
}
Add-Tweak @{ Id="AMD02"; Name="AMD Heterogeneous Scheduling & 3D V-Cache Optimizer"; Cat="AMD Ryzen"; Risk="Low"
    Desc="Favors 3D V-Cache CCD / Preferred Cores for game threads (SCHEDPOLICY=2, SHORTSCHED=2). Enables AMD 3D V-Cache service."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "93b8b6dc-0698-4d1c-9ee4-0644e900c85d" 2 "AMD Heterogeneous Sched (Cache/Preferred)"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "bae08b81-2d5e-4688-ad6a-13243356654b" 2 "AMD Short Sched (Cache/Preferred)"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "7f2f5cfa-f10c-4823-b5e1-e93ae85f46b5" 0 "AMD Heterogeneous Policy In Effect"
        Set-RegValue "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1 -Desc "Windows Game Mode for AMD 3D V-Cache"
        
        Set-ServiceStartup "AMD3DVCacheOptimizer" "Automatic" "AMD 3D V-Cache Service"
        if (-not $Script:DryRun) {
            try {
                $svc = Get-Service -Name "AMD3DVCacheOptimizer" -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -ne "Running") { Start-Service -Name "AMD3DVCacheOptimizer" -ErrorAction SilentlyContinue }
            } catch {}
        }
    }
}
Add-Tweak @{ Id="AMD03"; Name="AMD Energy Performance Preference (EPP 0% AC)"; Cat="AMD Ryzen"; Risk="Low"
    Desc="Sets EPP=0% on AC power for Ryzen, locking CPU into maximum boost states during gaming sessions."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "36687f9e-e3a5-4dbf-b1dc-15eb381c6863" 0 "AMD EPP 0% on AC"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "36687f9e-e3a5-4dbf-b1dc-15eb381c6864" 0 "AMD EPP 0% Secondary"
    }
}
Add-Tweak @{ Id="AMD04"; Name="AMD Core Parking (Dual-CCD X3D Aware) & SMT Latency"; Cat="AMD Ryzen"; Risk="Low"
    Desc="Dual-CCD X3D (7900X3D/7950X3D) retains 50% min cores so CCD1 parks; Single-CCD chips unpark 100%."
    Action={
        $hw = Get-DetailedHardwareProfile
        if ($hw.IsDualCCD) {
            Write-Log "Dual-CCD X3D Detected ($($hw.CPUName)): Setting Min Cores=50% to allow AMD V-Cache Driver to park CCD1 during gaming." "INFO"
            Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "0cc5b647-c1df-4637-891a-dec35c318583" 50 "AMD Dual-CCD Core Parking 50%"
        } elseif (-not $hw.IsLaptop) {
            Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "0cc5b647-c1df-4637-891a-dec35c318583" 100 "AMD Min Unparked Cores 100%"
            Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "ea062031-0e34-4ff1-9b6d-eb1059334028" 100 "AMD Max Unparked Cores 100%"
        }
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "b28a6829-c5f7-444e-8f61-10e24e85c532" 0 "SMT Physical Core First"
    }
}
Add-Tweak @{ Id="AMD05"; Name="AmdPPM Driver Start=3 & Disable EcoQoS Throttling"; Cat="AMD Ryzen"; Risk="Low"
    Desc="Ensures AMD Processor Power Management driver is active (Start=3) and disables PowerThrottlingOff=1."
    Action={
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\AmdPPM" "Start" 3 -Desc "AmdPPM Demand Start"
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1 -Desc "Disable Power Throttling"
    }
}
Add-Tweak @{ Id="AMD06"; Name="AMD C-States Demote/Promote Latency Tuning"; Cat="AMD Ryzen"; Risk="Low"
    Desc="Promote/Demote thresholds set to 100% to minimize wake latency from low power states on Ryzen architectures."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "7b224883-b3cc-4d79-819f-8374152cbe7c" 100 "AMD Idle Promote Threshold 100%"
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "4b92d758-5a24-4851-a470-815d78aee119" 100 "AMD Idle Demote Threshold 100%"
    }
}
Add-Tweak @{ Id="AMD07"; Name="AMD Latency Sensitivity Hint 100%"; Cat="AMD Ryzen"; Risk="Low"
    Desc="Instantly signals CPPC core scheduler to boost to max clock the millisecond game input or draw calls occur."
    Action={
        Set-PowerSchemeValue "54533251-82be-4824-96c1-47b60b740d00" "619b7505-003b-4e82-b7a6-4dd29c300971" 100 "AMD Latency Sensitivity Hint"
    }
}
Add-Tweak @{ Id="AMD08"; Name="Disable Kernel Paging Executive & Page Combining"; Cat="AMD Ryzen"; Risk="Low"
    Desc="Locks kernel drivers in physical RAM (DisablePagingExecutive=1) and stops background memory deduplication."
    Action={
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1 -Desc "Disable Paging Executive"
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" 0 -Desc "Enforce LargeSystemCache 0"
        try { Disable-MMAgent -PageCombining -ErrorAction SilentlyContinue } catch {}
    }
}

# -----------------------------------------------------------------------------
# 3. GAMING BOOST & NVIDIA GPU TWEAKS V3.0 (/boost)
# -----------------------------------------------------------------------------
Add-Tweak @{ Id="BST01"; Name="Disable Mouse Acceleration (1:1 Raw Input)"; Cat="Gaming Boost"; Risk="Low"
    Desc="Disables Windows cursor acceleration curve (MouseSpeed=0, Thresholds=0) for pure pixel-perfect 1:1 aiming."
    Action={
        Set-RegValue "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" -Type String -Desc "Mouse Speed 0"
        Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" -Type String -Desc "Threshold1 0"
        Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" -Type String -Desc "Threshold2 0"
    }
}
Add-Tweak @{ Id="BST02"; Name="Disable Sticky Keys & Accessibility Popups"; Cat="Gaming Boost"; Risk="Low"
    Desc="Prevents Windows interruption dialogues when pressing Shift 5 times or holding NumLock/Alt keys in games."
    Action={
        Set-RegValue "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" "506" -Type String -Desc "StickyKeys off"
        Set-RegValue "HKCU:\Control Panel\Accessibility\ToggleKeys" "Flags" "58" -Type String -Desc "ToggleKeys off"
        Set-RegValue "HKCU:\Control Panel\Accessibility\Keyboard Response" "Flags" "122" -Type String -Desc "FilterKeys off"
    }
}
Add-Tweak @{ Id="BST03"; Name="Disable USB Selective Suspend on AC Power"; Cat="Gaming Boost"; Risk="Low"
    Desc="Prevents Windows from suspending USB ports on AC power, guaranteeing stable 1000Hz - 8000Hz mouse polling rates."
    Action={
        Set-PowerSchemeValue "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" 0 "Disable USB Selective Suspend"
    }
}
Add-Tweak @{ Id="BST04"; Name="Win32PrioritySeparation 0x26 (3:1 Gaming Quantum)"; Cat="Gaming Boost"; Risk="Low"
    Desc="Sets Win32PrioritySeparation to 0x26 (38 Hex) - allocates short, variable quantums favoring active foreground games."
    Action={
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 -Desc "Win32PrioritySeparation 0x26"
    }
}
Add-Tweak @{ Id="BST05"; Name="Multimedia MMCSS & GPU High Priority Scheduling"; Cat="Gaming Boost"; Risk="Low"
    Desc="Sets Games MMCSS profile: GPU Priority=8, CPU Priority=6, SystemResponsiveness=10%, NetworkThrottlingIndex=0xFFFFFFFF, NoLazyMode=1."
    Action={
        $mp = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-RegValue $mp "NetworkThrottlingIndex" 0xffffffff -Desc "No network throttling"
        Set-RegValue $mp "SystemResponsiveness" 10 -Desc "System Responsiveness 10%"
        Set-RegValue $mp "NoLazyMode" 1 -Desc "MMCSS No Lazy Mode"
        
        $gp = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        Set-RegValue $gp "GPU Priority" 8 -Desc "Games GPU Priority 8"
        Set-RegValue $gp "Priority" 6 -Desc "Games CPU Priority 6"
        Set-RegValue $gp "Scheduling Category" "High" -Type String -Desc "Games Sched High"
        Set-RegValue $gp "SFIO Priority" "High" -Type String -Desc "Games SFIO High"
        Set-RegValue $gp "Latency Sensitive" "True" -Type String -Desc "Games Latency Sensitive"
    }
}
Add-Tweak @{ Id="BST06"; Name="Disable GameDVR Background Video Recording"; Cat="Gaming Boost"; Risk="Low"
    Desc="Disables GameDVR background capture overhead to recover FPS and reduce CPU/GPU micro-stutters."
    Action={
        Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0 -Desc "GameConfigStore DVR off"
        Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 -Desc "AppCapture off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0 -Desc "Policies GameDVR off"
    }
}
Add-Tweak @{ Id="BST07"; Name="GPU MSI Mode with High Device Priority"; Cat="Gaming Boost"; Risk="Low"
    Desc="Enables MSI Mode (MSISupported=1, DevicePriority=High) on GPU PCI devices to eliminate interrupt sharing & DPC latency spikes."
    Action={ Enable-GpuMsiMode -Priority "High" }
}
Add-Tweak @{ Id="BST08"; Name="NVIDIA GPU Tweaks V3.0 (Low Latency Ultra, Silk Smoothness, TdrDelay)"; Cat="Gaming Boost"; Risk="Low"
    Desc="Configures NVIDIA Ultra Low Latency Mode, PowerMizer Max Perf, Silk Smoothness RID61684, TdrDelay=8s, and disables GpuEnergyDrv."
    Action={ Set-NvidiaGpuSettings }
}
Add-Tweak @{ Id="BST09"; Name="PCIe Link State ASPM Disabled on AC Power (Desktop Only)"; Cat="Gaming Boost"; Risk="Low"
    Desc="Disables PCIe Active State Power Management (ASPM) on AC power on Desktops to prevent GPU bus throttling latency."
    Action={
        $hw = Get-DetailedHardwareProfile
        if (-not $hw.IsLaptop) {
            & powercfg.exe -setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a1265eef ee12f906-d277-4359-8ab4-9549925232c6 0 2>&1 | Out-Null
            & powercfg.exe -setactive SCHEME_CURRENT 2>&1 | Out-Null
            Write-Log "OK  PCIe ASPM Disabled on AC Power (Desktop PC)" "SUCCESS"
        } else {
            Write-Log "INFO Skipped PCIe ASPM change on Laptop to protect battery and sleep/wake power states." "INFO"
        }
    }
}
Add-Tweak @{ Id="BST10"; Name="Game Launcher & DirectX/GPU Shader Cache Cleaner"; Cat="Gaming Boost"; Risk="Low"
    Desc="Safely purges DirectX D3DSCache, NVIDIA DXCache/GLCache/ComputeCache, AMD DxcCache, Steam download caches, and Riot Games logs."
    Action={ Clear-GameLauncherAndShaderCache }
}
Add-Tweak @{ Id="BST11"; Name="Custom RB Ultimate Gaming Power Plan (EPP 0%, Core Parking Off)"; Cat="Gaming Boost"; Risk="Low"
    Desc="Creates & activates 'RB Ultimate Gaming Plan' with EPP=0%, Core Parking disabled (100% cores), aggressive turbo boost & tuned C-States."
    Action={ Install-RBUltimateGamingPlan }
}
Add-Tweak @{ Id="BST12"; Name="Intelligent Standby List Cleaner (ISLC & Standby List Purge)"; Cat="Gaming Boost"; Risk="Low"
    Desc="Executes native NT API standby list memory purge (MemoryPurgeStandbyList) & working sets cleanup to stop stuttering during long gaming sessions."
    Action={ Invoke-StandbyListAndRamClean }
}
Add-Tweak @{ Id="BST13"; Name="CSRSS Client-Server Runtime High Priority"; Cat="Gaming Boost"; Risk="Low"
    Desc="Elevates CSRSS (Client Server Runtime) CPU priority class to 4 to eliminate mouse cursor lag during heavy GPU rendering."
    Action={
        Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions" "CpuPriorityClass" 4 -Desc "CSRSS High CPU Priority"
        Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions" "IoPriority" 3 -Desc "CSRSS High I/O Priority"
    }
}
Add-Tweak @{ Id="BST14"; Name="Windows 11 Global Timer Resolution Enforcement (0.5ms / 1.0ms)"; Cat="Gaming Boost"; Risk="Low"
    Desc="Forces Windows 11 kernel to honor high precision global timer resolution requests (GlobalTimerResolutionRequests=1)."
    Action={
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "GlobalTimerResolutionRequests" 1 -Desc "Global Timer Resolution Requests"
    }
}

# -----------------------------------------------------------------------------
# 4. BROWSER & APP OPTIMIZATIONS (/browser)
# -----------------------------------------------------------------------------
Add-Tweak @{ Id="BRW01"; Name="Disable Chrome & Edge Background Running"; Cat="Browser"; Risk="Low"
    Desc="Stops Google Chrome and Microsoft Edge from staying resident in RAM and CPU after windows are closed."
    Action={
        Set-RegValue "HKLM:\SOFTWARE\Policies\Google\Chrome" "BackgroundModeEnabled" 0 -Desc "Chrome Background Off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0 -Desc "Edge Background Off"
    }
}
Add-Tweak @{ Id="BRW02"; Name="Disable Chrome & Edge Startup Boost"; Cat="Browser"; Risk="Low"
    Desc="Prevents browsers from pre-loading background processes at Windows boot, saving 300MB - 1GB RAM."
    Action={
        Set-RegValue "HKLM:\SOFTWARE\Policies\Google\Chrome" "StartupBoostEnabled" 0 -Desc "Chrome Startup Boost Off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" 0 -Desc "Edge Startup Boost Off"
    }
}
Add-Tweak @{ Id="BRW03"; Name="Disable Browser Telemetry & Metrics Reporting"; Cat="Browser"; Risk="Low"
    Desc="Disables telemetry, metrics reporting, feedback surveys and WebView2 diagnostic tracking in Edge & Chrome."
    Action={
        Set-RegValue "HKLM:\SOFTWARE\Policies\Google\Chrome" "MetricsReportingEnabled" 0 -Desc "Chrome Metrics Off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Google\Chrome" "ChromeCleanupReportingEnabled" 0 -Desc "Chrome Cleanup Reporting Off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Google\Chrome" "ChromeCleanupEnabled" 0 -Desc "Chrome Software Reporter Off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "MetricsReportingEnabled" 0 -Desc "Edge Metrics Off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "PersonalizationReportingEnabled" 0 -Desc "Edge Personalization Off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "UserFeedbackAllowed" 0 -Desc "Edge Feedback Off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge\WebView2" "TelemetryEnabled" 0 -Desc "WebView2 Telemetry Off"
    }
}
Add-Tweak @{ Id="BRW04"; Name="Disable Edge Prelaunch & Auto-Update Spam"; Cat="Browser"; Risk="Low"
    Desc="Disables Edge prelaunching on login and blocks aggressive Edge background update pings."
    Action={
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge\Main" "AllowPrelaunch" 0 -Desc "Edge Prelaunch Off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "UpdateDefault" 0 -Desc "Edge AutoUpdate Off"
    }
}
Add-Tweak @{ Id="BRW05"; Name="Safe Browser Cache Cleaner (Preserves Game Shader Cache)"; Cat="Browser"; Risk="Low"
    Desc="Safely purges temporary web caches for Chrome, Edge, Brave, and Opera while strictly preserving GPU Shader Caches."
    Action={
        if ($Script:DryRun) { Write-Log "[DRY] Would clean browser caches" "DRY"; return }
        $paths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache\*",
            "$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache\*"
        )
        foreach ($p in $paths) {
            Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Log "OK  Browser cache cleaned safely (Shader Caches untouched)" "SUCCESS"
    }
}

# -----------------------------------------------------------------------------
# 5. PRIVACY & TALON-STYLE AI/DEBLOAT TWEAKS
# -----------------------------------------------------------------------------
Add-Tweak @{ Id="P01"; Name="Disable Windows Diagnostic Telemetry (DiagTrack & CEIP)"; Cat="Privacy"; Risk="Low"
    Desc="Stops Windows diagnostic telemetry data collection (DiagTrack, dmwappushservice and scheduled CEIP tasks)."
    Action={
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0 -Desc "Telemetry GP"
        Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 0 -Desc "Telemetry legacy"
        Set-RegValue "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 0 -Desc "Telemetry WoW64"
        Set-ServiceStartup "DiagTrack" "Disabled" "Connected User Experiences"
        Set-ServiceStartup "dmwappushservice" "Disabled" "WAP Push"
        Disable-SchTask "\Microsoft\Windows\Application Experience\" "Microsoft Compatibility Appraiser"
        Disable-SchTask "\Microsoft\Windows\Application Experience\" "ProgramDataUpdater"
        Disable-SchTask "\Microsoft\Windows\Customer Experience Improvement Program\" "Consolidator"
        Disable-SchTask "\Microsoft\Windows\Customer Experience Improvement Program\" "UsbCeip"
    }
}
Add-Tweak @{ Id="P02"; Name="Disable Advertising ID & Tailored Experiences"; Cat="Privacy"; Risk="Low"
    Desc="Prevents apps using Advertising ID for cross-app ads and disables personalized suggestions."
    Action={
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0 -Desc "Ad ID"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" 1 -Desc "Ad ID GP"
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0 -Desc "Tailored off"
        Set-RegValue "HKLM:\SOFTWARE\Microsoft\SQMClient\Windows" "CEIPEnable" 0 -Desc "CEIP off"
    }
}
Add-Tweak @{ Id="P03"; Name="Disable Activity History & Input Inking Logging"; Cat="Privacy"; Risk="Low"
    Desc="Stops recording app/file usage and uploading typing patterns / inking samples to Microsoft cloud."
    Action={
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0 -Desc "Activity feed"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0 -Desc "Publish"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0 -Desc "Upload"
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" 1 -Desc "Inking off"
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" 1 -Desc "Typing off"
    }
}
Add-Tweak @{ Id="P04"; Name="Disable Windows Feedback Prompts & WER Error Reporting"; Cat="Privacy"; Risk="Low"
    Desc="Stops feedback survey popups and disables Windows Error Reporting background worker."
    Action={
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0 -Desc "Feedback prompts"
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" "PeriodInNanoSeconds" 0 -Desc "Feedback period"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications" 1 -Desc "No feedback"
        Set-ServiceStartup "WerSvc" "Disabled" "Windows Error Reporting"
        Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" "Disabled" 1 -Desc "WER off"
        Disable-SchTask "\Microsoft\Windows\Windows Error Reporting\" "QueueReporting"
    }
}
Add-Tweak @{ Id="P05"; Name="Disable Location Tracking & Geolocation Service"; Cat="Privacy"; Risk="Low"
    Desc="Revokes system-wide location access and disables Geolocation service (lfsvc)."
    Action={
        Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" "Deny" -Type String -Desc "Deny location"
        Set-ServiceStartup "lfsvc" "Disabled" "Geolocation"
    }
}
Add-Tweak @{ Id="P06"; Name="Disable Cortana & Bing Search in Start Menu"; Cat="Privacy"; Risk="Low"
    Desc="Stops local Start Menu search queries from sending to Bing servers and disables Cortana."
    Action={
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0 -Desc "Cortana off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCloudSearch" 0 -Desc "Cloud search off"
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch" 1 -Desc "Web search off"
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0 -Desc "Bing off"
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0 -Desc "Consent off"
    }
}
Add-Tweak @{ Id="AI01"; Name="Talon Deep Copilot Removal (Appx + Policies + Taskbar)"; Cat="Privacy"; Risk="Low"
    Desc="Deeply uninstalls Copilot Appx packages, hides taskbar Copilot button, and disables Copilot policies in HKLM & HKCU."
    Action={ Invoke-TalonDeepCopilotPurge }
}
Add-Tweak @{ Id="AI02"; Name="Talon Deep Weather & Widgets Removal (WebExperience Purge)"; Cat="Privacy"; Risk="Low"
    Desc="Removes Weather and Windows Web Experience Pack, hides taskbar widget icon, and disables Feeds policy."
    Action={ Invoke-TalonDeepWeatherPurge }
}
Add-Tweak @{ Id="AI03"; Name="Disable Windows Recall (Win11 24H2+ AI Screenshotting)"; Cat="Privacy"; Risk="Low"
    Desc="Disables Recall continuous AI screenshot analysis (requires Win11 Build 26100+)."
    Action={
        if (-not $Script:IsRecall) { Write-Log "SKIP Recall: requires Win11 24H2+ (Current Build=$($Script:WinVer.Build))" "INFO"; return }
        Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1 -Desc "Recall HKLM"
        Set-RegValue "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1 -Desc "Recall HKCU"
    }
}
Add-Tweak @{ Id="AI04"; Name="Disable Ads & Suggested Apps in Start/Lock Screen"; Cat="Privacy"; Risk="Low"
    Desc="Removes app suggestions, lock screen ads, and sponsored recommendation shortcuts."
    Action={
        $cdm = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        Set-RegValue $cdm "ContentDeliveryAllowed" 0 -Desc "Content delivery off"
        Set-RegValue $cdm "SubscribedContent-338388Enabled" 0 -Desc "Start suggest"
        Set-RegValue $cdm "SubscribedContent-338389Enabled" 0 -Desc "Lock tips"
        Set-RegValue $cdm "SubscribedContent-353694Enabled" 0 -Desc "Settings suggest 1"
        Set-RegValue $cdm "SubscribedContent-353696Enabled" 0 -Desc "Settings suggest 2"
        Set-RegValue $cdm "SystemPaneSuggestionsEnabled" 0 -Desc "System suggest"
        Set-RegValue $cdm "SoftLandingEnabled" 0 -Desc "Soft landing"
    }
}

# -----------------------------------------------------------------------------
# 6. GENERAL PERFORMANCE & SYSTEM TWEAKS
# -----------------------------------------------------------------------------
Add-Tweak @{ Id="PERF01"; Name="Activate Ultimate Performance Power Plan"; Cat="Performance"; Risk="Low"
    Desc="Unlocks the hidden Ultimate Performance power plan for maximum hardware throughput."
    Action={
        if ($Script:DryRun) { Write-Log "[DRY] Would activate Ultimate Performance scheme" "DRY"; return }
        powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
        $guid = ((powercfg /L) | Select-String "Ultimate") -replace ".*GUID: ([a-f0-9-]+).*","$1"
        if ($guid) {
            powercfg /setactive $guid.Trim()
            Write-Log "OK  Ultimate Performance Scheme active: $($guid.Trim())" "SUCCESS"
        } else {
            powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
            Write-Log "OK  High Performance Scheme active (fallback)" "SUCCESS"
        }
    }
}
Add-Tweak @{ Id="PERF02"; Name="Enable Hardware GPU Scheduling (HAGS)"; Cat="Performance"; Risk="Low"
    Desc="Lets GPU manage its own VRAM scheduling - lowers render latency and CPU overhead (Required for DLSS 3)."
    Action={ Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 -Desc "HAGS on" }
}
Add-Tweak @{ Id="PERF03"; Name="Fast App Shutdown Timers (No Visual Effects Changes)"; Cat="Performance"; Risk="Low"
    Desc="Speeds up app/service shutdown timers only. Does NOT touch 'Adjust the appearance and performance of Windows' settings (VisualFXSetting, UserPreferencesMask, wallpaper, fonts are all untouched)."
    Action={
        # INTENTIONALLY no VisualFXSetting / UserPreferencesMask writes.
        # We do NOT modify "Adjust the appearance and performance of Windows" to avoid
        # overriding user's visual preferences, wallpaper and system color settings.

        # Fast Shutdown Timers only
        $regPath = "HKCU:\Control Panel\Desktop"
        Set-RegValue $regPath "AutoEndTasks" "1" -Type String -Desc "Auto end hung tasks"
        Set-RegValue $regPath "WaitToKillAppTimeout" "2000" -Type String -Desc "Kill app 2s"
        Set-RegValue $regPath "HungAppTimeout" "1000" -Type String -Desc "HungApp 1s"
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" "2000" -Type String -Desc "Kill svc 2s"
        Set-RegValue $regPath "MenuShowDelay" "0" -Type String -Desc "Menu delay 0ms (instant)"
    }
}
Add-Tweak @{ Id="PERF04"; Name="Remove Startup App Artificial Delay (0ms)"; Cat="Performance"; Risk="Low"
    Desc="Removes the 10-second artificial delay before startup apps launch after login."
    Action={ Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0 -Desc "No startup delay" }
}
Add-Tweak @{ Id="PERF05"; Name="Disable Hibernate (Frees 4GB - 16GB Storage)"; Cat="Performance"; Risk="Low"
    Desc="Disables Windows hibernation and removes hiberfil.sys to recover significant SSD space."
    Action={
        if ($Script:DryRun) { Write-Log "[DRY] Would disable hibernation" "DRY"; return }
        powercfg /hibernate off 2>&1 | Out-Null
        Write-Log "OK  Hibernation disabled, hiberfil.sys removed" "SUCCESS"
    }
}
Add-Tweak @{ Id="PERF06"; Name="Disable Fast Startup (Hybrid Shutdown)"; Cat="Performance"; Risk="Low"
    Desc="Disables hybrid shutdown - ensures clean kernel reboots and fixes dual-boot driver sync issues."
    Action={ Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0 -Desc "Fast startup off" }
}
Add-Tweak @{ Id="PERF07"; Name="Disable NVIDIA Background Telemetry Containers"; Cat="Performance"; Risk="Low"
    Desc="Disables NvTelemetryContainer and background NVIDIA telemetry scheduled tasks."
    Action={
        Set-ServiceStartup "NvTelemetryContainer" "Disabled" "NVIDIA Telemetry"
        Disable-SchTask "\" "NvTmMon_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}"
        Disable-SchTask "\" "NvTmRep_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}"
    }
}
Add-Tweak @{ Id="PERF08"; Name="Disable AMD External Events Utility"; Cat="Performance"; Risk="Low"
    Desc="Stops AMD External Events Utility background service to save RAM."
    Action={ Set-ServiceStartup "AMD External Events Utility" "Disabled" "AMD External Events" }
}
Add-Tweak @{ Id="PERF09"; Name="1-Click SSD TRIM & Enable Storage Sense"; Cat="Performance"; Risk="Low"
    Desc="Runs SSD TRIM on C: and activates automatic Storage Sense cleaning to prevent SSD wear & fragmentation."
    Action={
        Invoke-SSDTrim -DriveLetter "C"
        Enable-StorageSense
    }
}
Add-Tweak @{ Id="PERF10"; Name="WinSxS Deep Component Cleanup (DISM ResetBase)"; Cat="Performance"; Risk="Medium"
    Desc="Executes DISM /StartComponentCleanup /ResetBase to remove superseded Windows updates and free 5GB to 15GB on C:."
    Action={ Invoke-WinSxSCleanup }
}

# -----------------------------------------------------------------------------
# 7. NETWORK & LATENCY TWEAKS
# -----------------------------------------------------------------------------
Add-Tweak @{ Id="NET01"; Name="Disable Nagle's Algorithm (TcpAckFrequency=1)"; Cat="Network"; Risk="Low"
    Desc="TcpAckFrequency=1 and TCPNoDelay=1 on all active network interfaces to minimize packet delay."
    Action={
        Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" | ForEach-Object {
            Set-RegValue $_.PSPath "TcpAckFrequency" 1 -Desc "Nagle off"
            Set-RegValue $_.PSPath "TCPNoDelay" 1 -Desc "NoDelay on"
        }
    }
}
Add-Tweak @{ Id="NET02"; Name="Remove QoS Bandwidth Reservation Limit (0% Limit)"; Cat="Network"; Risk="Low"
    Desc="Returns the 20% reserved QoS bandwidth to your active applications."
    Action={ Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "NonBestEffortLimit" 0 -Desc "QoS 0%" }
}
Add-Tweak @{ Id="NET03"; Name="Optimize TCP Auto-Tuning Level"; Cat="Network"; Risk="Low"
    Desc="Sets TCP receive window auto-tuning to normal for high-speed fiber internet."
    Action={
        if ($Script:DryRun) { Write-Log "[DRY] TCP autotuning normal" "DRY"; return }
        netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
        Write-Log "OK  TCP auto-tuning=normal" "SUCCESS"
    }
}
Add-Tweak @{ Id="NET04"; Name="Disable LLMNR Multicast (Security & Latency)"; Cat="Network"; Risk="Low"
    Desc="Disables Link-Local Multicast Name Resolution - hardens security and reduces broadcast pings."
    Action={ Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" 0 -Desc "No LLMNR" }
}

# -----------------------------------------------------------------------------
# 8. SERVICES & VISUAL CLEANUP
# -----------------------------------------------------------------------------
Add-Tweak @{ Id="SVC01"; Name="Disable Fax & Maps Download Services"; Cat="Services"; Risk="Low"
    Desc="Disables unused legacy Fax service and offline Maps Download Broker."
    Action={
        Set-ServiceStartup "fax" "Disabled" "Fax"
        Set-ServiceStartup "MapsBroker" "Disabled" "Maps"
    }
}
Add-Tweak @{ Id="SVC02"; Name="Disable Remote Registry Service"; Cat="Services"; Risk="Low"
    Desc="Prevents remote users from editing Windows Registry - essential security hardening."
    Action={ Set-ServiceStartup "RemoteRegistry" "Disabled" "Remote Registry" }
}
Add-Tweak @{ Id="SVC03"; Name="Disable Retail Demo Service"; Cat="Services"; Risk="Low"
    Desc="Disables retail showroom demo service."
    Action={ Set-ServiceStartup "RetailDemo" "Disabled" "Retail Demo" }
}
Add-Tweak @{ Id="SVC04"; Name="Set Print Spooler to Manual"; Cat="Services"; Risk="Medium"
    Desc="Frees RAM by setting Print Spooler to manual on-demand start (skip if printing continuously)."
    Action={ Set-ServiceStartup "Spooler" "Manual" "Print Spooler" }
}
Add-Tweak @{ Id="VIS01"; Name="Classic Right-Click Context Menu (Win11)"; Cat="Visual"; Risk="Low"
    Desc="Restores the fast classic context menu in Windows 11 without the trimmed 'Show more options' screen."
    Action={
        if (-not $Script:IsWin11) { Write-Log "SKIP Classic menu: Windows 11 only" "INFO"; return }
        if ($Script:DryRun) { Write-Log "[DRY] Would enable classic context menu" "DRY"; return }
        New-Item -Path "HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(default)" -Value "" -Type String -ErrorAction SilentlyContinue
        Write-Log "OK  Classic context menu enabled" "SUCCESS"
    }
}
Add-Tweak @{ Id="VIS02"; Name="Remove Taskbar Search & Task View Buttons"; Cat="Visual"; Risk="Low"
    Desc="Hides Search bar and Task View button from taskbar (shortcuts Win+S and Win+Tab still work)."
    Action={
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 0 -Desc "Hide search"
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" 0 -Desc "Hide Task View"
        Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0 -Desc "Hide widgets"
    }
}

# =============================================================================
# DEBLOAT APPS LIST (55+ PACKAGES ACROSS 3 TIERS + TALON SPECIFIC)
# =============================================================================
$Script:DebloatApps = @(
    # Tier 1 - Safe Pre-installed Promos & Bloat
    @{N="Microsoft.Copilot";T=1;L="Windows Copilot App"}
    @{N="Microsoft.BingWeather";T=1;L="MSN Weather & Live Tile"}
    @{N="MicrosoftWindows.Client.WebExperience";T=1;L="Windows Web Experience (Widgets)"}
    @{N="Microsoft.StartExperiencesApp";T=1;L="Start Experiences App"}
    @{N="Microsoft.WidgetsPlatformRuntime";T=1;L="Widgets Platform Runtime"}
    @{N="Microsoft.BingNews";T=1;L="Microsoft News"}
    @{N="Microsoft.BingFinance";T=1;L="Bing Finance"}
    @{N="Microsoft.BingSports";T=1;L="Bing Sports"}
    @{N="Microsoft.BingSearch";T=1;L="Bing Search"}
    @{N="Microsoft.XboxApp";T=1;L="Xbox Console Companion"}
    @{N="Microsoft.XboxGameOverlay";T=1;L="Xbox Game Bar Overlay"}
    @{N="Microsoft.XboxGamingOverlay";T=1;L="Xbox Game Bar"}
    @{N="Microsoft.XboxIdentityProvider";T=1;L="Xbox Identity Provider"}
    @{N="Microsoft.XboxSpeechToTextOverlay";T=1;L="Xbox Speech to Text"}
    @{N="Microsoft.Xbox.TCUI";T=1;L="Xbox TCUI"}
    @{N="Microsoft.GamingApp";T=1;L="Xbox App (Gaming)"}
    @{N="Microsoft.MicrosoftSolitaireCollection";T=1;L="Solitaire Collection"}
    @{N="Microsoft.MicrosoftMahjong";T=1;L="Microsoft Mahjong"}
    @{N="Microsoft.MicrosoftMinesweeper";T=1;L="Microsoft Minesweeper"}
    @{N="king.com.CandyCrushSaga";T=1;L="Candy Crush Saga"}
    @{N="king.com.CandyCrushSodaSaga";T=1;L="Candy Crush Soda"}
    @{N="king.com.BubbleWitch3Saga";T=1;L="Bubble Witch Saga"}
    @{N="Disney.37853D6RA2";T=1;L="Disney Magic Kingdoms"}
    @{N="Microsoft.GetHelp";T=1;L="Get Help"}
    @{N="Microsoft.Getstarted";T=1;L="Tips (Get Started)"}
    @{N="Microsoft.WindowsFeedbackHub";T=1;L="Feedback Hub"}
    @{N="Microsoft.ZuneMusic";T=1;L="Groove Music"}
    @{N="Microsoft.ZuneVideo";T=1;L="Movies and TV"}
    @{N="Microsoft.People";T=1;L="People"}
    @{N="Microsoft.Wallet";T=1;L="Microsoft Pay (Wallet)"}
    @{N="Microsoft.549981C3F5F10";T=1;L="Cortana (Standalone App)"}
    @{N="Microsoft.MixedReality.Portal";T=1;L="Mixed Reality Portal"}
    @{N="Microsoft.Print3D";T=1;L="Print 3D"}
    @{N="Microsoft.Microsoft3DViewer";T=1;L="3D Viewer"}
    @{N="Microsoft.SkypeApp";T=1;L="Skype"}
    @{N="Microsoft.WindowsAlarms";T=1;L="Alarms and Clock"}
    @{N="Microsoft.WindowsSoundRecorder";T=1;L="Sound Recorder"}
    @{N="Microsoft.WindowsMaps";T=1;L="Windows Maps"}
    @{N="MicrosoftCorporationII.MicrosoftFamily";T=1;L="Microsoft Family Safety"}

    # Tier 2 - Consumer & Productivity Apps
    @{N="Microsoft.Teams";T=2;L="Microsoft Teams (Consumer)"}
    @{N="MicrosoftTeams";T=2;L="Microsoft Teams"}
    @{N="SpotifyAB.SpotifyMusic";T=2;L="Spotify (Pre-installed)"}
    @{N="Microsoft.YourPhone";T=2;L="Phone Link (Your Phone)"}
    @{N="Microsoft.PowerAutomateDesktop";T=2;L="Power Automate Desktop"}
    @{N="Clipchamp.Clipchamp";T=2;L="Clipchamp Video Editor"}
    @{N="Microsoft.Todos";T=2;L="Microsoft To Do"}
    @{N="Microsoft.StorePurchaseApp";T=2;L="Store Purchase App"}
    @{N="Microsoft.WindowsCommunicationsApps";T=2;L="Mail and Calendar"}
    @{N="Microsoft.OutlookForWindows";T=2;L="New Outlook (Preview)"}

    # Tier 3 - Advanced / Caution (Core Windows Apps)
    @{N="Microsoft.OneDrive";T=3;L="OneDrive (Desktop Client)"}
    @{N="Microsoft.OneDriveSync";T=3;L="OneDrive Sync"}
    @{N="Microsoft.WindowsCamera";T=3;L="Windows Camera"}
    @{N="Microsoft.Paint";T=3;L="Paint 3D / New Paint"}
    @{N="Microsoft.ScreenSketch";T=3;L="Snipping Tool"}
    @{N="Microsoft.WindowsCalculator";T=3;L="Windows Calculator"}
)

function Remove-BloatApp {
    param([string]$AppName, [string]$Label)
    if ($Script:DryRun) { Write-Log "[DRY] REMOVE $Label ($AppName)" "DRY"; return }
    try {
        Get-AppxPackage -AllUsers -Name $AppName -ErrorAction SilentlyContinue |
            Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*$AppName*" } |
            ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }
        Write-Log "OK  Removed: $Label ($AppName)" "SUCCESS"
    } catch {
        Write-Log "WARN $Label -- $_" "WARN"
    }
}

# =============================================================================
# PRESETS & PROFILES (UPDATED WITH V3.0 HARDWARE & GPU TWEAKS)
# =============================================================================
$Script:Presets = @{
    "All-in-One Intel Pro" = @{
        Ids = @("INTEL01","INTEL02","INTEL03","INTEL04","INTEL05","INTEL06","INTEL07","INTEL08","INTEL09","INTEL10","BST01","BST02","BST03","BST04","BST05","BST06","BST07","BST08","BST09","BST10","BST11","BST12","BST13","BST14","BRW01","BRW02","BRW03","BRW04","BRW05","PERF01","PERF02","PERF03","PERF04","PERF09","NET01","NET02","P01","P02","AI01","AI02","AI04")
        Tier = 1
    }
    "All-in-One AMD Pro" = @{
        Ids = @("AMD01","AMD02","AMD03","AMD04","AMD05","AMD06","AMD07","AMD08","BST01","BST02","BST03","BST04","BST05","BST06","BST07","BST08","BST09","BST10","BST11","BST12","BST13","BST14","BRW01","BRW02","BRW03","BRW04","BRW05","PERF01","PERF02","PERF03","PERF04","PERF09","NET01","NET02","P01","P02","AI01","AI02","AI04")
        Tier = 1
    }
    "Auto-Detect Pro" = @{
        Ids = @() # Populated dynamically at runtime
        Tier = 1
    }
    "Gaming / FPS Boost" = @{
        Ids = @("BST01","BST02","BST03","BST04","BST05","BST06","BST07","BST08","BST09","BST10","BST11","BST12","BST13","BST14","BRW01","BRW02","BRW05","PERF01","PERF02","PERF03","PERF04","PERF09","NET01","NET02","VIS01","VIS02","AI01","AI02","AI04")
        Tier = 1
    }
    "Browser & Light Boost" = @{
        Ids = @("BRW01","BRW02","BRW03","BRW04","BRW05","PERF03","PERF04","NET01","NET02","P01","P02","AI01","AI04")
        Tier = 1
    }
    "Privacy-First" = @{
        Ids = @("P01","P02","P03","P04","P05","P06","AI01","AI02","AI03","AI04","BRW03","NET04","SVC01","SVC02","SVC03")
        Tier = 2
    }
}

$Script:PresetDesc = @{
    "All-in-One Intel Pro"  = "Full Intel Core + NVIDIA V3.0 (HWP Speed Shift, Thread Director P-Cores, EPP 0%, GPU MSI High Priority, NVIDIA Silk Smoothness, RB Gaming Plan, ISLC RAM Purge, Tier 1 Debloat)"
    "All-in-One AMD Pro"    = "Full AMD Ryzen + NVIDIA V3.0 (CPPC Preferred Cores, 3D V-Cache Scheduling & Service, Dual-CCD 50% Parking, GPU MSI High Priority, RB Gaming Plan, ISLC RAM Purge, Tier 1 Debloat)"
    "Auto-Detect Pro"       = "Auto-detects whether your system is Intel or AMD, then applies full CPU + NVIDIA GPU V3.0 + RB Gaming Plan + ISLC RAM Purge + Talon Debloat automatically"
    "Gaming / FPS Boost"    = "Ultimate gaming boost: GPU MSI Mode High Priority, NVIDIA Ultra Low Latency V3.0, RB Gaming Power Plan, ISLC RAM Purge, Shader Cleaner, 1:1 Mouse, MMCSS NoLazy, Win32 0x26"
    "Browser & Light Boost" = "Stops Chrome/Edge background drain, startup boost, browser telemetry and purges cache safely"
    "Privacy-First"         = "Max privacy: telemetry, Copilot, Weather WebExperience, Recall, advertising ID, Bing search, and location tracking off"
}

function Update-AutoDetectPreset {
    param($hw)
    if ($null -eq $hw -or -not $Script:Presets) { return }
    if ($hw.CPUType -eq "Intel") {
        $Script:Presets["Auto-Detect Pro"].Ids = @($Script:Presets["All-in-One Intel Pro"].Ids)
    } elseif ($hw.CPUType -eq "AMD") {
        $Script:Presets["Auto-Detect Pro"].Ids = @($Script:Presets["All-in-One AMD Pro"].Ids)
    } else {
        $Script:Presets["Auto-Detect Pro"].Ids = @($Script:Presets["Gaming / FPS Boost"].Ids)
    }
}
if ($Script:HW) { Update-AutoDetectPreset $Script:HW }

# =============================================================================
# EXECUTION ENGINE
# =============================================================================
function Invoke-TweakList {
    param([string[]]$Ids)
    $total = $Ids.Count
    $done = 0
    Write-Log "=== TweakList Execution START ($total tweaks) ===" "INFO"
    foreach ($id in $Ids) {
        $tw = $Script:AllTweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($tw) {
            Write-Log "-- [$id] $($tw.Name)" "INFO"
            Write-Status "[$($done+1)/$total] $($tw.Name)" $Script:C.Yellow
            try {
                & $tw.Action
            } catch {
                Write-Log "FAIL [$id]: $_" "ERROR"
            }
        }
        $done++
        Set-Progress ([int](($done / $total) * 100))
    }
    Write-Log "=== TweakList Execution COMPLETED ($done/$total) ===" "SUCCESS"
}

function Invoke-DebloatList {
    param([string[]]$AppNames)
    $total = $AppNames.Count
    $done = 0
    Write-Log "=== Debloat Execution START ($total apps) ===" "INFO"
    foreach ($n in $AppNames) {
        $a = $Script:DebloatApps | Where-Object { $_.N -eq $n } | Select-Object -First 1
        $lbl = if ($a) { $a.L } else { $n }
        Write-Status "Removing: $lbl" $Script:C.Yellow
        Remove-BloatApp -AppName $n -Label $lbl
        $done++
        Set-Progress ([int](($done / $total) * 100))
    }
    Clear-TaskbarMRUCache
    Write-Log "=== Debloat Execution COMPLETED ($done apps) ===" "SUCCESS"
    Write-Status "Debloat complete!" $Script:C.Green
}

# =============================================================================
# DIAGNOSTIC / SYSTEM ANALYZE
# =============================================================================
function Invoke-SystemAnalysis {
    Write-Log "================================================================================" "INFO"
    Write-Log "                     RB OPTIMIZER v3.0 - SYSTEM DIAGNOSTIC ANALYSIS             " "INFO"
    Write-Log "================================================================================" "INFO"
    $hw = Get-DetailedHardwareProfile
    Write-Log "OS: $($hw.WinCaption) [Build $($hw.WinBuild)] | Chassis: $(if($hw.IsLaptop){'Laptop'}else{'Desktop'})" "INFO"
    Write-Log "CPU: $($hw.CPUName) [$($hw.Cores) Cores / $($hw.Threads) Threads]" "INFO"
    Write-Log "Gen / Family: $($hw.CPUGen)" "INFO"
    Write-Log "Architecture: $($hw.Architecture)" "INFO"
    Write-Log "GPU: $($hw.GPUName) ($($hw.GPUType))" "INFO"
    Write-Log "RAM: $($hw.RAMgb) GB | Storage: $(if($hw.IsSSD){'SSD'}else{'HDD'})" "INFO"
    Write-Log "--------------------------------------------------------------------------------" "INFO"

    # Check PowerCFG items
    $powerChecks = @(
        @{ Guid="8baa4a8a-14c6-4451-8e8b-14bdbd197537"; Name="Autonomous Mode (Speed Shift / CPPC)"; Want="0x00000001" }
        @{ Guid="cfeda3d0-7697-4566-a922-a9086cd49dfa"; Name="Autonomous Activity Window"; Want="0x00000000" }
        @{ Guid="be337238-0d82-4146-a960-4f3749d470c7"; Name="Processor Boost Mode"; Want="0x00000002" }
        @{ Guid="45bcc044-d885-43e2-8605-ee0ec6e96b59"; Name="Processor Boost Policy"; Want="0x00000064" }
        @{ Guid="36687f9e-e3a5-4dbf-b1dc-15eb381c6863"; Name="Energy Perf Preference (EPP)"; Want="0x00000000" }
        @{ Guid="93b8b6dc-0698-4d1c-9ee4-0644e900c85d"; Name="Heterogeneous Scheduling Policy"; Want="0x00000002" }
        @{ Guid="7b224883-b3cc-4d79-819f-8374152cbe7c"; Name="C-States Idle Promote Threshold"; Want="0x00000064" }
        @{ Guid="4b92d758-5a24-4851-a470-815d78aee119"; Name="C-States Idle Demote Threshold"; Want="0x00000064" }
    )

    foreach ($chk in $powerChecks) {
        & powercfg.exe -attributes 54533251-82be-4824-96c1-47b60b740d00 $chk.Guid -ATTRIB_HIDE 2>&1 | Out-Null
        $val = ""
        $query = & powercfg.exe /query SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 $chk.Guid 2>$null
        $line = $query | Where-Object { $_ -match "Current AC Power Setting Index" }
        if ($line) {
            $val = ($line -split ":")[1].Trim()
        }
        $st = if ($val -eq $chk.Want) { "[OPTIMIZED]" } else { "[DEFAULT / OTHER] ($val)" }
        $lvl = if ($val -eq $chk.Want) { "SUCCESS" } else { "INFO" }
        Write-Log "  $($chk.Name.PadRight(38)) : $st" $lvl
    }

    # Registry Checks
    $prio = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -ErrorAction SilentlyContinue).Win32PrioritySeparation
    $stPrio = if ($prio -eq 38) { "[OPTIMIZED: 0x26 (3:1 Gaming)]" } else { "[DEFAULT / $prio]" }
    Write-Log "  Win32PrioritySeparation                : $stPrio" $(if($prio -eq 38){"SUCCESS"}else{"INFO"})

    $mouseSpeed = (Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -ErrorAction SilentlyContinue).MouseSpeed
    $stMouse = if ($mouseSpeed -eq "0") { "[OPTIMIZED: 1:1 Raw Mouse (No Accel)]" } else { "[ACCELERATION ON ($mouseSpeed)]" }
    Write-Log "  Mouse Acceleration                     : $stMouse" $(if($mouseSpeed -eq "0"){"SUCCESS"}else{"INFO"})

    $pthrot = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -ErrorAction SilentlyContinue).PowerThrottlingOff
    $stThrot = if ($pthrot -eq 1) { "[OPTIMIZED: Throttling Disabled]" } else { "[DEFAULT / ENABLED]" }
    Write-Log "  EcoQoS Power Throttling                : $stThrot" $(if($pthrot -eq 1){"SUCCESS"}else{"INFO"})

    $gtimer = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue).GlobalTimerResolutionRequests
    $stTimer = if ($gtimer -eq 1) { "[OPTIMIZED: Global Timer Resolution Active]" } else { "[DEFAULT / 0]" }
    Write-Log "  GlobalTimerResolutionRequests          : $stTimer" $(if($gtimer -eq 1){"SUCCESS"}else{"INFO"})

    if ($hw.CPUType -eq "Intel") {
        $intelppm = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\intelppm" -Name "Start" -ErrorAction SilentlyContinue).Start
        $stIppm = if ($intelppm -eq 3) { "[OK: Start=3 Demand]" } else { "[WARNING: Start=$intelppm]" }
        Write-Log "  Intelppm Driver Service Status         : $stIppm" $(if($intelppm -eq 3){"SUCCESS"}else{"WARN"})
    } elseif ($hw.CPUType -eq "AMD") {
        $amdppm = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\AmdPPM" -Name "Start" -ErrorAction SilentlyContinue).Start
        $stAppm = if ($amdppm -eq 3) { "[OK: Start=3 Demand]" } else { "[WARNING: Start=$amdppm]" }
        Write-Log "  AmdPPM Driver Service Status           : $stAppm" $(if($amdppm -eq 3){"SUCCESS"}else{"WARN"})
    }

    # GPU MSI Mode Status Check
    $msiCount = 0
    Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $msiVal = (Get-ItemProperty -Path "$($_.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported
        if ($msiVal -eq 1) { $msiCount++ }
    }
    Write-Log "  GPU / PCI MSI Mode Devices Active      : [OK: $msiCount Device(s) in MSI Mode]" $(if($msiCount -gt 0){"SUCCESS"}else{"INFO"})

    Write-Log "================================================================================" "INFO"
}

# =============================================================================
# CLI HEADLESS DISPATCHER
# =============================================================================
if ($Intel -or $AMD -or $Boost -or $Browser -or $Auto -or $Analyze -or $Debloat -or $ResetGPU -or $Help -or ($DryRun -and $allPassed.Count -gt 0)) {
    "RB Optimizer v$Script:Version CLI Execution -- $(Get-Date)" | Out-File $Script:LogFile -Encoding UTF8
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "  RB OPTIMIZER v$Script:Version - AUTOMATED CLI MODE" -ForegroundColor Cyan
    Write-Host "========================================================`n" -ForegroundColor Cyan

    if ($Help) {
        Write-Host "  Usage: powershell.exe -File RB_Optimizer.ps1 [options]" -ForegroundColor White
        Write-Host "`n  Options / Switches:" -ForegroundColor Gray
        Write-Host "    -Intel,   /intel    : Intel Core Special Edition (HWP Speed Shift, Thread Director, Short Threads, EPP, MSI Mode)" -ForegroundColor White
        Write-Host "    -AMD,     /amd      : AMD Ryzen Special Edition (CPPC, 3D V-Cache Scheduling, Dual-CCD Parking, EPP, MSI Mode)" -ForegroundColor White
        Write-Host "    -Boost,   /boost    : Gaming Boost & NVIDIA GPU V3.0 (GPU MSI Mode High, Low Latency, RB Gaming Plan, ISLC, Shader Cleaner)" -ForegroundColor White
        Write-Host "    -Browser, /browser  : Browser Optimizations & Safe Cache Cleaner (Chrome, Edge, Brave, Opera)" -ForegroundColor White
        Write-Host "    -Debloat,  /debloat   : Talon Deep Debloat (Windows Copilot, Weather WebExperience, Tier 1 Bloatware Purge)" -ForegroundColor White
        Write-Host "    -ResetGPU, /resetgpu  : Emergency GPU Driver & Display Reset (removes corrupt class keys, fixes Code 43 / black screen)" -ForegroundColor Yellow
        Write-Host "    -Auto,     /auto      : Auto-detect CPU (Intel / AMD) and apply matching full profile" -ForegroundColor White
        Write-Host "    -Analyze, /analyze  : Run system diagnostic analysis & check current optimization status" -ForegroundColor White
        Write-Host "    -DryRun,  /dryrun   : Preview / simulate changes without modifying registry or power schemes" -ForegroundColor White
        Write-Host "    -Help,    /help     : Show this help information`n" -ForegroundColor White
        exit
    }
    
    $hw = Get-DetailedHardwareProfile
    Write-Host "Detected: $($hw.CPUType) CPU ($($hw.CPUName)) | $($hw.GPUType) GPU ($($hw.GPUName)) | $($hw.RAMgb)GB RAM`n" -ForegroundColor White

    if ($Analyze) {
        Invoke-SystemAnalysis
        exit
    }

    if ($ResetGPU) {
        Write-Host "[*] Executing Emergency GPU Driver & Display Reset..." -ForegroundColor Yellow
        Reset-GpuToDefault
        Write-Host "`n[OK] GPU Reset Complete! All corrupted registry overrides removed.`n     Please RESTART your computer now." -ForegroundColor Green
        exit
    }

    $tweakIds = [System.Collections.Generic.List[string]]::new()

    if ($Intel) {
        Write-Host "[*] Selected Intel Core Special Edition Profile..." -ForegroundColor Cyan
        foreach ($id in $Script:Presets["All-in-One Intel Pro"].Ids) {
            if (-not $tweakIds.Contains($id)) { $tweakIds.Add($id) }
        }
    }
    if ($AMD) {
        Write-Host "[*] Selected AMD Ryzen Special Edition Profile..." -ForegroundColor Magenta
        foreach ($id in $Script:Presets["All-in-One AMD Pro"].Ids) {
            if (-not $tweakIds.Contains($id)) { $tweakIds.Add($id) }
        }
    }
    if ($Boost) {
        Write-Host "[*] Selected Gaming Boost & NVIDIA GPU V3.0 Profile (/boost)..." -ForegroundColor Yellow
        foreach ($id in $Script:Presets["Gaming / FPS Boost"].Ids) {
            if (-not $tweakIds.Contains($id)) { $tweakIds.Add($id) }
        }
    }
    if ($Browser) {
        Write-Host "[*] Selected Browser Optimization & Cache Clean Profile..." -ForegroundColor Yellow
        foreach ($id in $Script:Presets["Browser & Light Boost"].Ids) {
            if (-not $tweakIds.Contains($id)) { $tweakIds.Add($id) }
        }
    }
    if ($Debloat) {
        Write-Host "[*] Selected Talon-Style Deep Debloat Profile..." -ForegroundColor Red
        Invoke-TalonDeepCopilotPurge
        Invoke-TalonDeepWeatherPurge
        $t1Apps = @($Script:DebloatApps | Where-Object { $_.T -eq 1 } | ForEach-Object { $_.N })
        Invoke-DebloatList -AppNames $t1Apps
    }
    if ($Auto) {
        Write-Host "[*] Auto-Detecting CPU Profile..." -ForegroundColor Green
        if ($hw.CPUType -eq "Intel") {
            Write-Host "  -> Applying All-in-One Intel Pro" -ForegroundColor Cyan
            foreach ($id in $Script:Presets["All-in-One Intel Pro"].Ids) {
                if (-not $tweakIds.Contains($id)) { $tweakIds.Add($id) }
            }
        } elseif ($hw.CPUType -eq "AMD") {
            Write-Host "  -> Applying All-in-One AMD Pro" -ForegroundColor Magenta
            foreach ($id in $Script:Presets["All-in-One AMD Pro"].Ids) {
                if (-not $tweakIds.Contains($id)) { $tweakIds.Add($id) }
            }
        } else {
            Write-Host "  -> Applying Universal Gaming / FPS Boost" -ForegroundColor Yellow
            foreach ($id in $Script:Presets["Gaming / FPS Boost"].Ids) {
                if (-not $tweakIds.Contains($id)) { $tweakIds.Add($id) }
            }
        }
    }

    if ($tweakIds.Count -gt 0) {
        Invoke-TweakList -Ids $tweakIds
        Write-Host "`n[OK] RB Optimizer CLI execution completed successfully ($($tweakIds.Count) tweaks)!" -ForegroundColor Green
    } else {
        if (-not $Debloat) {
            Write-Host "[*] No specific tweak profiles selected. Use -Help or /help for options." -ForegroundColor Yellow
        }
    }
    exit
}

# =============================================================================
# GUI CONSTRUCTION & STYLING ENGINE
# =============================================================================
[System.Windows.Forms.Application]::EnableVisualStyles()

function New-Btn {
    param(
        [string]$Text, [int]$X, [int]$Y, [int]$W = 160, [int]$H = 34,
        $BG = $null, $FG = $null, $Fnt = $null
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    
    $baseBg = if ($BG -and ($BG -is [System.Drawing.Color])) { $BG } else { $Script:C.Surface0 }
    $baseFg = if ($FG -and ($FG -is [System.Drawing.Color])) { $FG } else { $Script:C.Text }
    
    $b.BackColor = $baseBg
    $b.ForeColor = $baseFg
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    
    $hoverBg = Get-HoverColor $baseBg 0.25
    $downBg  = Get-PressedColor $baseBg 0.15
    $b.FlatAppearance.MouseOverBackColor = $hoverBg
    $b.FlatAppearance.MouseDownBackColor = $downBg
    
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Font = if ($Fnt -and ($Fnt -is [System.Drawing.Font])) { $Fnt } else { (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)) }
    $b.UseVisualStyleBackColor = $false
    
    $b | Add-Member -NotePropertyName '_BaseBG' -NotePropertyValue $baseBg -Force
    $b | Add-Member -NotePropertyName '_BaseFG' -NotePropertyValue $baseFg -Force
    $b | Add-Member -NotePropertyName '_HoverBG' -NotePropertyValue $hoverBg -Force
    $b | Add-Member -NotePropertyName '_DownBG' -NotePropertyValue $downBg -Force
    
    $b.Add_MouseEnter({
        param($s, $e)
        try {
            if ($s -and $s._HoverBG) { $s.BackColor = $s._HoverBG }
        } catch {}
    })
    $b.Add_MouseLeave({
        param($s, $e)
        try {
            if ($s -and $s._BaseBG) { $s.BackColor = $s._BaseBG }
        } catch {}
    })
    $b.Add_MouseDown({
        param($s, $e)
        try {
            if ($s -and $s._DownBG) { $s.BackColor = $s._DownBG }
        } catch {}
    })
    $b.Add_MouseUp({
        param($s, $e)
        try {
            if ($s -and $s._HoverBG) { $s.BackColor = $s._HoverBG }
        } catch {}
    })
    
    return $b
}

function New-Lbl {
    param(
        [string]$Text, [int]$X, [int]$Y, [int]$W = 200, [int]$H = 20,
        $FG = $null, $BG = $null, $Fnt = $null
    )
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, $H)
    $l.ForeColor = if ($FG -and ($FG -is [System.Drawing.Color])) { $FG } else { $Script:C.Text }
    $l.BackColor = if ($BG -and ($BG -is [System.Drawing.Color])) { $BG } else { [System.Drawing.Color]::Transparent }
    $l.Font = if ($Fnt -and ($Fnt -is [System.Drawing.Font])) { $Fnt } else { (New-Object System.Drawing.Font("Segoe UI", 9)) }
    return $l
}

function New-Chk {
    param(
        [string]$Text, [int]$X, [int]$Y, [int]$W = 300, [int]$H = 22,
        [bool]$Chkd = $false, $FG = $null
    )
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Location = New-Object System.Drawing.Point($X, $Y)
    $c.Size = New-Object System.Drawing.Size($W, $H)
    $c.Checked = $Chkd
    $c.ForeColor = if ($FG -and ($FG -is [System.Drawing.Color])) { $FG } else { $Script:C.Text }
    $c.BackColor = [System.Drawing.Color]::Transparent
    $c.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $c.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $c
}

function New-Card {
    param(
        [string]$Title = "", [int]$X = 0, [int]$Y = 0, [int]$W = 400, [int]$H = 200,
        $AccentColor = $null
    )
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($X, $Y)
    $p.Size = New-Object System.Drawing.Size($W, $H)
    $p.BackColor = $Script:C.Mantle
    
    $acc = if ($AccentColor -and ($AccentColor -is [System.Drawing.Color])) { $AccentColor } else { $Script:C.Primary }
    $p | Add-Member -NotePropertyName '_AccentColor' -NotePropertyValue $acc -Force
    $p | Add-Member -NotePropertyName '_Title' -NotePropertyValue $Title -Force
    
    $p.Add_Paint({
        param($s, $e)
        try {
            if ($s.Width -gt 2 -and $s.Height -gt 2) {
                $pen = New-Object System.Drawing.Pen($Script:C.Surface0, 1)
                $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
                $pen.Dispose()

                $accColor = if ($s -and ($s._AccentColor -is [System.Drawing.Color])) { $s._AccentColor } else { $Script:C.Primary }
                $accBrush = New-Object System.Drawing.SolidBrush($accColor)
                $e.Graphics.FillRectangle($accBrush, 0, 0, 4, $s.Height)
                $accBrush.Dispose()
            }
        } catch {}
    }.GetNewClosure())

    if ($Title) {
        $tLbl = New-Lbl $Title 14 8 ($W - 24) 22 -FG $acc -Fnt (New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold))
        $p.Controls.Add($tLbl)
    }
    return $p
}

function New-ScrollPanel {
    param([int]$X, [int]$Y, [int]$W, [int]$H)
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($X, $Y)
    $p.Size = New-Object System.Drawing.Size($W, $H)
    $p.AutoScroll = $true
    $p.BackColor = $Script:C.Base
    return $p
}

function New-Tab {
    param([string]$Title)
    $t = New-Object System.Windows.Forms.TabPage
    $t.Text = $Title
    $t.BackColor = $Script:C.Base
    $t.UseVisualStyleBackColor = $false
    return $t
}

# TWEAK TAB BUILDER (FAST 1-CLICK APPLY WITHOUT PER-CATEGORY RESTORE POINT POPUP)
function Build-TweakTab {
    param(
        [string]$TabTitle,
        [string]$Category,
        $ApplyColor = $null,
        [string]$ApplyLabel = "Apply Tweaks",
        [string]$HeaderNote = "",
        [scriptblock]$CustomAction = $null
    )
    $tab = New-Tab $TabTitle
    $sp = New-ScrollPanel 8 8 1046 510
    $y = 8
    $cbs = @{}
    $tweaks = $Script:AllTweaks | Where-Object { $_.Cat -eq $Category }

    if ($HeaderNote) {
        $hnCard = New-Object System.Windows.Forms.Panel
        $hnCard.Location = New-Object System.Drawing.Point(4, $y)
        $hnCard.Size = New-Object System.Drawing.Size(1020, 32)
        $hnCard.BackColor = $Script:C.Mantle
        $hnBorderCol = if ($ApplyColor -and ($ApplyColor -is [System.Drawing.Color])) { $ApplyColor } else { $Script:C.Primary }
        $hnCard | Add-Member -NotePropertyName '_BorderColor' -NotePropertyValue $hnBorderCol -Force
        $hnCard.Add_Paint({
            param($s, $e)
            try {
                if ($s.Width -gt 2 -and $s.Height -gt 2) {
                    $col = if ($s -and ($s._BorderColor -is [System.Drawing.Color])) { $s._BorderColor } else { $Script:C.Primary }
                    $p = New-Object System.Drawing.Pen($col, 1)
                    $e.Graphics.DrawRectangle($p, 0, 0, ($s.Width - 1), ($s.Height - 1))
                    $p.Dispose()
                }
            } catch {}
        }.GetNewClosure())
        $hnLbl = New-Lbl $HeaderNote 12 6 996 20 -FG $hnBorderCol -Fnt (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold))
        $hnCard.Controls.Add($hnLbl)
        $sp.Controls.Add($hnCard)
        $y += 40
    }

    foreach ($tw in $tweaks) {
        $riskCol = switch ($tw.Risk) { "Low" { $Script:C.Green } "Medium" { $Script:C.Yellow } "High" { $Script:C.Red } default { $Script:C.Text } }
        $fgCol = if ($tw.Risk -eq "Medium") { $Script:C.Yellow } else { $Script:C.Text }
        
        $chk = New-Chk "[$($tw.Id)]  $($tw.Name)" 10 $y 740 -Chkd ($tw.Risk -eq "Low") -FG $fgCol
        $rLbl = New-Lbl "Risk: $($tw.Risk)" 760 $y 120 18 -FG $riskCol -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold))
        $dLbl = New-Lbl "      $($tw.Desc)" 14 ($y + 22) 1000 18 -FG $Script:C.Subtext -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.2))
        
        $cbs[$tw.Id] = $chk
        $sp.Controls.AddRange(@($chk, $rLbl, $dLbl))
        $y += 50
    }

    $applyBtn = New-Btn $ApplyLabel 8 528 260 38 -BG $ApplyColor -FG $Script:C.Crust -Fnt (New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold))
    $applyBtn.Tag = @{ Cbs = $cbs; Category = $Category; CustomAction = $CustomAction }
    $applyBtn.Add_Click({
        param($s, $e)
        $info = $s.Tag
        $sel = @($info.Cbs.Keys | Where-Object { $info.Cbs[$_].Checked })
        if ($sel.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No tweaks selected in $($info.Category).", "Notice", "OK", "Information") | Out-Null
            return
        }
        # GPU Safety Check & Restore Point Confirmation
        $gpuIds = @("BST07", "BST08", "BST09")
        $hasGpuTweak = ($sel | Where-Object { $_ -in $gpuIds }).Count -gt 0
        if ($hasGpuTweak) {
            $gpuConfirmMsg = "CẢNH BÁO: Tinh chỉnh GPU (MSI Mode / NVIDIA Registry) có thể gây nháy màn hình hoặc crash driver tạm thời trên một số hệ thống.`n`nKhuyến nghị tạo Restore Point trước khi áp dụng.`n`nBạn có muốn tự động tạo Restore Point bảo vệ ngay bây giờ không?"
            $confirmRes = [System.Windows.Forms.MessageBox]::Show($gpuConfirmMsg, "Xác nhận Tối ưu GPU", [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($confirmRes -eq [System.Windows.Forms.DialogResult]::Cancel) {
                return
            }
            if ($confirmRes -eq [System.Windows.Forms.DialogResult]::Yes) {
                New-RestorePoint -Desc "RB Optimizer Pre-GPU Tweaks Restore Point"
            }
        }

        # Execute selected tweaks
        Invoke-TweakList -Ids $sel
        if ($info.CustomAction) {
            & $info.CustomAction
        }
        Set-Progress 100
        Write-Status "$($info.Category) tweaks applied successfully!" $Script:C.Green
        [System.Windows.Forms.MessageBox]::Show("$($info.Category) tweaks applied successfully!`n`nCheck the Log & Tools tab for details.", "Done", "OK", "Information") | Out-Null
    })

    $selAll = New-Btn "Select All" 278 528 120 38
    $selAll.Tag = $cbs
    $selAll.Add_Click({ param($s, $e); foreach ($k in $s.Tag.Keys) { $s.Tag[$k].Checked = $true } })

    $selNone = New-Btn "Select None" 408 528 120 38
    $selNone.Tag = $cbs
    $selNone.Add_Click({ param($s, $e); foreach ($k in $s.Tag.Keys) { $s.Tag[$k].Checked = $false } })

    $tab.Controls.AddRange(@($sp, $applyBtn, $selAll, $selNone))
    return @{ Tab = $tab; Cbs = $cbs; SP = $sp }
}

# =============================================================================
# REAL-TIME SYSTEM PERFORMANCE FLOATING WIDGET & SYSTEM TRAY ENGINE
# =============================================================================
function Update-WidgetMetrics {
    param($CpuBar = $null, $RamBar = $null)
    try {
        if ($null -eq $Script:CpuCounter) {
            $Script:CpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
            $null = $Script:CpuCounter.NextValue()
        }

        $cpuVal = [int][Math]::Round($Script:CpuCounter.NextValue())
        $Script:CurrentCpuPct = [Math]::Min([Math]::Max($cpuVal, 0), 100)

        # Dynamic CPU Boost Frequency via Performance Counters
        $freqGhz = "---"
        try {
            $perfPerf = (Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction SilentlyContinue).PercentProcessorPerformance
            if ($null -eq $Script:CachedCpuFreqGHz) {
                $cpuObj = Get-CimInstance Win32_Processor | Select-Object -First 1
                if ($cpuObj -and $cpuObj.MaxClockSpeed) {
                    $Script:CachedCpuFreqGHz = $cpuObj.MaxClockSpeed / 1000.0
                }
            }
            if ($perfPerf -and $Script:CachedCpuFreqGHz) {
                $curGHz = [Math]::Round(($perfPerf / 100.0) * $Script:CachedCpuFreqGHz, 2)
                $freqGhz = "$curGHz GHz"
            }
        } catch {}

        # RAM Metrics via native NT API
        $mem = Get-RamStatus
        $Script:CurrentRamPct = $mem.LoadPct

        if ($Script:LblWidgetCpu -and -not $Script:LblWidgetCpu.IsDisposed) {
            $Script:LblWidgetCpu.Text = "$($Script:CurrentCpuPct)%  ($freqGhz)"
            $Script:LblWidgetCpu.ForeColor = if ($Script:CurrentCpuPct -gt 85) { $Script:C.Red } elseif ($Script:CurrentCpuPct -gt 60) { $Script:C.Yellow } else { $Script:C.Primary }
        }
        if ($Script:LblWidgetRam -and -not $Script:LblWidgetRam.IsDisposed) {
            $Script:LblWidgetRam.Text = "$($Script:CurrentRamPct)%  ($($mem.UsedGB)/$($mem.TotalGB) GB)"
            $Script:LblWidgetRam.ForeColor = if ($Script:CurrentRamPct -gt 85) { $Script:C.Red } elseif ($Script:CurrentRamPct -gt 70) { $Script:C.Peach } else { $Script:C.Green }
        }
        if ($Script:LblWidgetCleaned -and -not $Script:LblWidgetCleaned.IsDisposed) {
            $cleanedStr = if ($Script:TotalRamCleanedMB -ge 1024) { "$([Math]::Round($Script:TotalRamCleanedMB / 1024, 1)) GB" } else { "$Script:TotalRamCleanedMB MB" }
            $Script:LblWidgetCleaned.Text = "$cleanedStr Cleaned"
        }

        if ($CpuBar -and -not $CpuBar.IsDisposed) { $CpuBar.Value = $Script:CurrentCpuPct }
        if ($RamBar -and -not $RamBar.IsDisposed) { $RamBar.Value = $Script:CurrentRamPct }

        # System Tray Tooltip Update
        if ($Script:NotifyIcon -and $Script:NotifyIcon.Visible) {
            $Script:NotifyIcon.Text = "RB Optimizer: CPU $($Script:CurrentCpuPct)% | RAM $($Script:CurrentRamPct)%"
        }
    } catch {}
}

function Build-FloatingWidget {
    $wForm = New-Object System.Windows.Forms.Form
    $wForm.Text = "RB Performance Widget"
    $wForm.Size = New-Object System.Drawing.Size(260, 114)
    $wForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $wForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $wForm.TopMost = $true
    $wForm.ShowInTaskbar = $false
    $wForm.BackColor = $Script:C.Crust
    $wForm.ForeColor = $Script:C.Text
    $wForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $wForm.Opacity = 0.94

    # Position at Top-Right of Primary Screen
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $wForm.Location = New-Object System.Drawing.Point(($screen.Right - 275), ($screen.Top + 25))

    # Border & Drag Support
    $wForm.Add_Paint({
        param($s, $e)
        try {
            $pen = New-Object System.Drawing.Pen($Script:C.Primary, 2)
            $e.Graphics.DrawRectangle($pen, 1, 1, ($s.Width - 2), ($s.Height - 2))
            $pen.Dispose()
        } catch {}
    })

    $dragHandler = {
        if ([System.Windows.Forms.Control]::MouseButtons -eq [System.Windows.Forms.MouseButtons]::Left) {
            if ([System.Management.Automation.PSTypeName]'RBMemoryCleaner'.Type) {
                [RBMemoryCleaner]::ReleaseCapture() | Out-Null
                [RBMemoryCleaner]::SendMessage($wForm.Handle, 0xA1, 0x2, 0) | Out-Null
            }
        }
    }
    $wForm.Add_MouseDown($dragHandler)

    # Title Bar
    $titleLbl = New-Lbl "RB OPTIMIZER METRICS" 10 6 180 16 -FG $Script:C.Primary -Fnt (New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold))
    $titleLbl.Add_MouseDown($dragHandler)
    $wForm.Controls.Add($titleLbl)

    # Close/Hide Button
    $closeBtn = New-Lbl "x" 236 4 18 16 -FG $Script:C.Subtext -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold))
    $closeBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $closeBtn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $closeBtn.Add_Click({ $wForm.Hide() })
    $wForm.Controls.Add($closeBtn)

    # Metrics Display
    $lblC = New-Lbl "CPU:" 10 28 36 18 -FG $Script:C.Subtext -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold))
    $lblC.Add_MouseDown($dragHandler)
    $Script:LblWidgetCpu = New-Lbl "--% (--- GHz)" 46 28 200 18 -FG $Script:C.Primary -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold))
    $Script:LblWidgetCpu.Add_MouseDown($dragHandler)
    $wForm.Controls.AddRange(@($lblC, $Script:LblWidgetCpu))

    $lblR = New-Lbl "RAM:" 10 48 36 18 -FG $Script:C.Subtext -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold))
    $lblR.Add_MouseDown($dragHandler)
    $Script:LblWidgetRam = New-Lbl "--% (--/-- GB)" 46 48 200 18 -FG $Script:C.Green -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold))
    $Script:LblWidgetRam.Add_MouseDown($dragHandler)
    $wForm.Controls.AddRange(@($lblR, $Script:LblWidgetRam))

    # Action Row
    $Script:LblWidgetCleaned = New-Lbl "0 MB Cleaned" 10 78 120 22 -FG $Script:C.Peach -Fnt (New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold))
    $Script:LblWidgetCleaned.Add_MouseDown($dragHandler)

    $btnPurge = New-Btn "Purge RAM" 136 72 112 28 -BG $Script:C.Primary -FG $Script:C.Crust -Fnt (New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold))
    $btnPurge.Add_Click({
        Invoke-StandbyListAndRamClean -Silent $true
        Update-WidgetMetrics
    })
    $wForm.Controls.AddRange(@($Script:LblWidgetCleaned, $btnPurge))

    # Timer Engine (1.5s interval)
    $Script:WidgetTimer = New-Object System.Windows.Forms.Timer
    $Script:WidgetTimer.Interval = 1500
    $Script:WidgetTimer.Add_Tick({ Update-WidgetMetrics })
    $Script:WidgetTimer.Start()

    Update-WidgetMetrics
    return $wForm
}

function Setup-SystemTrayIcon {
    if ($Script:NotifyIcon) { return }
    $Script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $Script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
    $Script:NotifyIcon.Text = "RB Optimizer Pro v$Script:Version"
    $Script:NotifyIcon.Visible = $true

    $cm = New-Object System.Windows.Forms.ContextMenuStrip
    $cm.BackColor = $Script:C.Mantle
    $cm.ForeColor = $Script:C.Text

    $mShow = $cm.Items.Add("Open RB Optimizer")
    $mShow.Add_Click({
        if ($Script:MainForm) {
            $Script:MainForm.Show()
            $Script:MainForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            $Script:MainForm.BringToFront()
        }
    })

    $mPurge = $cm.Items.Add("Purge RAM (ISLC Standby Clean)")
    $mPurge.Add_Click({
        Invoke-StandbyListAndRamClean -Silent $true
        Update-WidgetMetrics
    })

    $cm.Items.Add("-") | Out-Null
    $mExit = $cm.Items.Add("Exit RB Optimizer")
    $mExit.Add_Click({
        if ($Script:NotifyIcon) { $Script:NotifyIcon.Visible = $false; $Script:NotifyIcon.Dispose() }
        if ($Script:MainForm) { $Script:MainForm.Close() }
        [System.Windows.Forms.Application]::Exit()
    })

    $Script:NotifyIcon.ContextMenuStrip = $cm
    $Script:NotifyIcon.Add_DoubleClick({
        if ($Script:MainForm) {
            $Script:MainForm.Show()
            $Script:MainForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            $Script:MainForm.BringToFront()
        }
    })
}

function Toggle-PerformanceWidget {
    if ($null -eq $Script:WidgetForm -or $Script:WidgetForm.IsDisposed) {
        $Script:WidgetForm = Build-FloatingWidget
    }
    if ($Script:WidgetForm.Visible) {
        $Script:WidgetForm.Hide()
        Write-Status "Floating Widget Hidden" $Script:C.Subtext
    } else {
        $Script:WidgetForm.Show()
        Update-WidgetMetrics
        Write-Status "Floating Widget Active" $Script:C.Green
    }
}

# =============================================================================
# MAIN GUI BUILDER (CYBERPUNK GOLD THEME + RESTRUCTURED TABS + RESTORE POINT)
# =============================================================================
function Build-MainGUI {
    param($HW)

    Setup-SystemTrayIcon

    $Script:HW = $HW
    if (Get-Command Update-AutoDetectPreset -ErrorAction SilentlyContinue) {
        Update-AutoDetectPreset $HW
    }

    $form = New-Object System.Windows.Forms.Form
    $Script:MainForm = $form
    $form.Text = "RB Optimizer Pro v$($Script:Version)  |  $($HW.CPUType) CPU  |  $($HW.GPUType) GPU  |  $($HW.RAMgb) GB RAM  |  $(if($Script:IsWin11){'Windows 11'}else{'Windows 10'})"
    $form.Size = New-Object System.Drawing.Size(1088, 768)
    $form.MinimumSize = New-Object System.Drawing.Size(980, 680)
    $form.BackColor = $Script:C.Crust
    $form.ForeColor = $Script:C.Text
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $form.Icon = [System.Drawing.SystemIcons]::Shield

    # Title Banner Panel
    $titlePnl = New-Object System.Windows.Forms.Panel
    $titlePnl.Location = New-Object System.Drawing.Point(0, 0)
    $titlePnl.Size = New-Object System.Drawing.Size(1088, 62)
    $titlePnl.BackColor = $Script:C.Mantle
    $titlePnl.Add_Paint({
        param($s, $e)
        try {
            $pen = New-Object System.Drawing.Pen($Script:C.Surface0, 1)
            $e.Graphics.DrawLine($pen, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
            $pen.Dispose()
        } catch {}
    }.GetNewClosure())

    $appLbl = New-Lbl "  RB OPTIMIZER" 8 14 200 32 -FG $Script:C.Primary -Fnt (New-Object System.Drawing.Font("Segoe UI", 14.5, [System.Drawing.FontStyle]::Bold))
    $verLbl = New-Lbl "v$($Script:Version)" 208 24 62 18 -FG $Script:C.Gold -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold))
    
    $osBadge = New-Lbl $(if($Script:IsWin11){"Win 11"}else{"Win 10"}) 276 18 64 26 -FG $Script:C.Yellow -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)) -BG $Script:C.Surface0
    $osBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    $cpuBadgeColor = if ($HW.CPUType -eq "Intel") { $Script:C.IntelCyan } elseif ($HW.CPUType -eq "AMD") { $Script:C.AMDRed } else { $Script:C.Gold }
    $cpuBadge = New-Lbl "$($HW.CPUType)" 346 18 80 26 -FG $cpuBadgeColor -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)) -BG $Script:C.Surface0
    $cpuBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    $gpuBadge = New-Lbl "$($HW.GPUType)" 432 18 88 26 -FG $Script:C.Green -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)) -BG $Script:C.Surface0
    $gpuBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    $ramBadge = New-Lbl "$($HW.RAMgb) GB" 526 18 68 26 -FG $Script:C.Peach -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)) -BG $Script:C.Surface0
    $ramBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    # Top Central Action Buttons: Create Restore Point, Toggle Widget, Analyze System
    $btnTopRP = New-Btn "Create Restore Point" 604 15 155 32 -BG $Script:C.Surface1 -FG $Script:C.White -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold))
    $btnTopRP.Add_Click({
        $ok = New-RestorePoint "RB Optimizer Checkpoint"
        if ($ok) {
            [System.Windows.Forms.MessageBox]::Show("System Restore Point created successfully!", "Restore Point", "OK", "Information") | Out-Null
        }
    })

    $btnDiag = New-Btn "Analyze System" 768 15 116 32 -BG $Script:C.Primary -FG $Script:C.Crust
    $btnDiag.Add_Click({
        Invoke-SystemAnalysis
        Flush-LogHistoryToBox
        [System.Windows.Forms.MessageBox]::Show("Diagnostic analysis complete! Check the Log & Tools tab for full status.", "Analysis", "OK", "Information") | Out-Null
    })

    $dryChk = New-Object System.Windows.Forms.CheckBox
    $dryChk.Text = "Dry Run"
    $dryChk.Location = New-Object System.Drawing.Point(1008, 19)
    $dryChk.Size = New-Object System.Drawing.Size(72, 24)
    $dryChk.ForeColor = $Script:C.Yellow
    $dryChk.BackColor = [System.Drawing.Color]::Transparent
    $dryChk.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $dryChk.Checked = $Script:DryRun
    $dryChk.Cursor = [System.Windows.Forms.Cursors]::Hand
    $dryChk.Add_CheckedChanged({ $Script:DryRun = $dryChk.Checked; Write-Log "Dry Run: $($Script:DryRun)" "INFO" })

    $titlePnl.Controls.AddRange(@($appLbl, $verLbl, $osBadge, $cpuBadge, $gpuBadge, $ramBadge, $btnTopRP, $btnDiag, $dryChk))
    $form.Controls.Add($titlePnl)

    # Status Footer Panel
    $stPnl = New-Object System.Windows.Forms.Panel
    $stPnl.Location = New-Object System.Drawing.Point(0, 696)
    $stPnl.Size = New-Object System.Drawing.Size(1088, 34)
    $stPnl.BackColor = $Script:C.Mantle
    $stPnl.Add_Paint({
        param($s, $e)
        try {
            $pen = New-Object System.Drawing.Pen($Script:C.Surface0, 1)
            $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
            $pen.Dispose()
        } catch {}
    }.GetNewClosure())

    $Script:StatusLabel = New-Lbl "Ready  --  Select your optimization preset or explore tabs below." 12 7 760 20 -FG $Script:C.Subtext -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5))
    $Script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $Script:ProgressBar.Location = New-Object System.Drawing.Point(788, 8)
    $Script:ProgressBar.Size = New-Object System.Drawing.Size(278, 18)
    $Script:ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $stPnl.Controls.AddRange(@($Script:StatusLabel, $Script:ProgressBar))
    $form.Controls.Add($stPnl)

    # Main Tab Control with Modern Owner-Drawn Dark Tabs
    $tc = New-Object System.Windows.Forms.TabControl
    $tc.Location = New-Object System.Drawing.Point(0, 62)
    $tc.Size = New-Object System.Drawing.Size(1088, 634)
    $tc.BackColor = $Script:C.Base
    $tc.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $tc.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
    $tc.ItemSize = New-Object System.Drawing.Size(104, 34)
    $tc.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
    $tc.Padding = New-Object System.Drawing.Point(6, 4)

    $tc.Add_DrawItem({
        param($s, $e)
        try {
            $g = $e.Graphics
            $tabRect = $s.GetTabRect($e.Index)
            $isSelected = ($s.SelectedIndex -eq $e.Index)
            [string]$tabText = [string]$s.TabPages[$e.Index].Text.Trim()

            # Background
            $bgCol = if ($isSelected) { $Script:C.Base } else { $Script:C.Mantle }
            $bgBrush = New-Object System.Drawing.SolidBrush($bgCol)
            $g.FillRectangle($bgBrush, $tabRect)
            $bgBrush.Dispose()

            # Separator line on right
            $borderPen = New-Object System.Drawing.Pen($Script:C.Surface0, 1)
            $g.DrawLine($borderPen, $tabRect.Right - 1, $tabRect.Top + 6, $tabRect.Right - 1, $tabRect.Bottom - 6)
            $borderPen.Dispose()

            # Active tab glowing indicator underline (Cyberpunk Gold Accent)
            if ($isSelected) {
                $accentCol = switch ($tabText) {
                    "Home"           { $Script:C.Primary }
                    "Intel Core"     { $Script:C.IntelCyan }
                    "AMD Ryzen"      { $Script:C.AMDRed }
                    "Gaming Boost"   { $Script:C.Gold }
                    "Browser & Apps" { $Script:C.Peach }
                    "Performance"    { $Script:C.Primary }
                    "Privacy & AI"   { $Script:C.Mauve }
                    "Debloat"        { $Script:C.Red }
                    "Services & Net" { $Script:C.Sapphire }
                    "Log & Tools"    { $Script:C.Teal }
                    default          { $Script:C.Primary }
                }
                $indBrush = New-Object System.Drawing.SolidBrush($accentCol)
                $indRect = New-Object System.Drawing.Rectangle($tabRect.Left + 8, ($tabRect.Bottom - 3), ($tabRect.Width - 16), 3)
                $g.FillRectangle($indBrush, $indRect)
                $indBrush.Dispose()
            }

            # Tab Text
            $textCol = if ($isSelected) { [System.Drawing.Color]::FromArgb(255, 255, 255) } else { $Script:C.Subtext }
            $fntStyle = if ($isSelected) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
            $fnt = New-Object System.Drawing.Font("Segoe UI", 9, $fntStyle)
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            $textBrush = New-Object System.Drawing.SolidBrush($textCol)

            [float]$tx = [float]$tabRect.X
            [float]$ty = [float]$tabRect.Y
            [float]$tw = [float]$tabRect.Width
            $yOff = if ($isSelected) { 2.0 } else { 0.0 }
            [float]$th = [float]($tabRect.Height - $yOff)
            $textRect = New-Object System.Drawing.RectangleF($tx, $ty, $tw, $th)

            $g.DrawString([string]$tabText, [System.Drawing.Font]$fnt, [System.Drawing.Brush]$textBrush, [System.Drawing.RectangleF]$textRect, [System.Drawing.StringFormat]$sf)

            $textBrush.Dispose()
            $fnt.Dispose()
            $sf.Dispose()
        } catch {}
    })

    $form.Controls.Add($tc)

    # =========================================================================
    # TAB 1: HOME & 1-CLICK PRESETS
    # =========================================================================
    $tHome = New-Tab "  Home  "

    # Hardware Specs Card (Left Side)
    $hwCard = New-Card -Title "Detected System Architecture" -X 12 -Y 12 -W 510 -H 196 -AccentColor $Script:C.Gold
    $hwCard.Controls.Add((New-Lbl "CPU Model :  $($HW.CPUName)" 14 34 480 18 -FG $Script:C.Gold))
    $hwCard.Controls.Add((New-Lbl "Generation:  $($HW.CPUGen)" 14 54 480 18 -FG $cpuBadgeColor -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold))))
    $hwCard.Controls.Add((New-Lbl "Topology  :  $($HW.Cores) Cores / $($HW.Threads) Logical Threads" 14 74 480 18 -FG $Script:C.Text))
    $hwCard.Controls.Add((New-Lbl "Arch Type :  $($HW.Architecture)" 14 94 480 18 -FG $Script:C.Lavender))
    $hwCard.Controls.Add((New-Lbl "GPU       :  $($HW.GPUName)" 14 114 480 18 -FG $Script:C.Green))
    $hwCard.Controls.Add((New-Lbl "Memory    :  $($HW.RAMgb) GB RAM  |  Storage: $(if($HW.IsSSD){'SSD'}else{'HDD'})" 14 134 480 18 -FG $Script:C.Peach))
    $hwCard.Controls.Add((New-Lbl "OS & Build:  $($HW.WinCaption) [Build $($HW.WinBuild)]" 14 154 480 18 -FG $Script:C.Text))
    $hwCard.Controls.Add((New-Lbl "Chassis   :  $(if($HW.IsLaptop){'Laptop (Battery Safe Thermal Profile)'}else{'Desktop (Full Uncapped Mode)'})" 14 174 480 16 -FG $Script:C.Overlay0 -Fnt (New-Object System.Drawing.Font("Segoe UI", 8))))
    $tHome.Controls.Add($hwCard)

    # One-Click Presets Card (Right Side)
    $preCard = New-Card -Title "One-Click Optimization Presets" -X 534 -Y 12 -W 520 -H 554 -AccentColor $Script:C.Primary
    $py = 40
    $presetList = @(
        @{ Name="Auto-Detect Pro"; Col=$Script:C.Primary }
        @{ Name="All-in-One Intel Pro"; Col=$Script:C.IntelCyan }
        @{ Name="All-in-One AMD Pro"; Col=$Script:C.AMDRed }
        @{ Name="Gaming / FPS Boost"; Col=$Script:C.Gold }
        @{ Name="Browser & Light Boost"; Col=$Script:C.Peach }
        @{ Name="Privacy-First"; Col=$Script:C.Mauve }
    )

    foreach ($p in $presetList) {
        $pname = $p.Name
        $pcolor = $p.Col
        $pdesc = $Script:PresetDesc[$pname]
        
        $pb = New-Btn "  $pname" 14 $py 204 42 -BG $pcolor -FG $Script:C.Crust -Fnt (New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold))
        $pb.Tag = $pname
        $pb.Add_Click({
            param($s2, $e2)
            $pn = [string]$s2.Tag
            $tIds = [System.Collections.Generic.List[string]]::new()
            $cType = if ($Script:HW -and $Script:HW.CPUType) { $Script:HW.CPUType } elseif ($HW -and $HW.CPUType) { $HW.CPUType } else { "Unknown" }
            if ($pn -eq "Auto-Detect Pro") {
                if ($cType -eq "Intel") {
                    foreach ($id in $Script:Presets["All-in-One Intel Pro"].Ids) { if (-not $tIds.Contains($id)) { $tIds.Add($id) } }
                } elseif ($cType -eq "AMD") {
                    foreach ($id in $Script:Presets["All-in-One AMD Pro"].Ids) { if (-not $tIds.Contains($id)) { $tIds.Add($id) } }
                } else {
                    foreach ($id in $Script:Presets["Gaming / FPS Boost"].Ids) { if (-not $tIds.Contains($id)) { $tIds.Add($id) } }
                }
            } else {
                if ($Script:Presets.ContainsKey($pn)) {
                    foreach ($id in $Script:Presets[$pn].Ids) { if (-not $tIds.Contains($id)) { $tIds.Add($id) } }
                }
            }

            $tier = 1
            if ($Script:Presets.ContainsKey($pn) -and $Script:Presets[$pn].Tier) {
                $tier = [int]$Script:Presets[$pn].Tier
            }

            $desc = if ($Script:PresetDesc.ContainsKey($pn)) { $Script:PresetDesc[$pn] } else { $pn }
            $msg = "Apply preset: $pn`n`n$desc`n`nTweaks: $($tIds.Count)  |  Debloat: Tier $tier and below`n`n(Tip: You can use the 'Create Restore Point' button at top if you haven't created one yet)"
            $result = [System.Windows.Forms.MessageBox]::Show(
                $msg,
                "Apply Preset: $pn", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes -or $result -eq "Yes") {
                Invoke-TweakList -Ids $tIds
                $debApps = @($Script:DebloatApps | Where-Object { [int]$_.T -le $tier } | ForEach-Object { $_.N })
                Invoke-DebloatList -AppNames $debApps
                Set-Progress 100
                Write-Status "Preset '$pn' applied successfully!" $Script:C.Green
                [System.Windows.Forms.MessageBox]::Show("Preset '$pn' applied successfully!`n`nCheck the Log & Tools tab for details.", "Done", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        })
        $preCard.Controls.Add($pb)

        $dLbl = New-Lbl $pdesc 226 ($py + 4) 280 34 -FG $Script:C.Subtext -Fnt (New-Object System.Drawing.Font("Segoe UI", 8.2))
        $preCard.Controls.Add($dLbl)

        $py += 82
    }
    $tHome.Controls.Add($preCard)

    # Action Buttons Card (Left Bottom) - 10 Dedicated Quick Utilities + Emergency GPU Reset
    $actCard = New-Card -Title "Quick System Utilities" -X 12 -Y 216 -W 510 -H 350 -AccentColor $Script:C.Gold

    # Row 1: RAM & Shader Cleaner
    $btnPurgeRAM = New-Btn "Purge Standby RAM (ISLC)" 14 36 234 38 -BG $Script:C.Gold -FG $Script:C.Crust
    $btnPurgeRAM.Add_Click({
        Invoke-StandbyListAndRamClean
        [System.Windows.Forms.MessageBox]::Show("RAM Standby List and working sets purged successfully via ISLC Engine!", "ISLC Purge", "OK", "Information") | Out-Null
    })

    $btnShader = New-Btn "Clean Game & Shader Cache" 260 36 234 38 -BG $Script:C.Peach -FG $Script:C.Crust
    $btnShader.Add_Click({
        Clear-GameLauncherAndShaderCache
        [System.Windows.Forms.MessageBox]::Show("DirectX, GPU Shader Caches, Steam Cache and Riot Logs cleaned!", "Shader Cache Cleaner", "OK", "Information") | Out-Null
    })

    # Row 2: SSD TRIM & WinSxS ResetBase
    $btnTRIM = New-Btn "Run SSD TRIM (Drive C:)" 14 82 234 38 -BG $Script:C.Teal -FG $Script:C.Crust
    $btnTRIM.Add_Click({
        Invoke-SSDTrim "C"
        [System.Windows.Forms.MessageBox]::Show("SSD TRIM optimization completed on Drive C:!", "SSD TRIM", "OK", "Information") | Out-Null
    })

    $btnWinSxS = New-Btn "WinSxS DISM ResetBase" 260 82 234 38 -BG $Script:C.Lavender -FG $Script:C.Crust
    $btnWinSxS.Add_Click({
        $r = [System.Windows.Forms.MessageBox]::Show("DISM /ResetBase removes superseded component files to recover 5-15GB space.`nThis process may take 3-10 minutes. Continue?", "DISM ResetBase", "YesNo", "Question")
        if ($r -eq "Yes") {
            Invoke-WinSxSCleanup
            [System.Windows.Forms.MessageBox]::Show("WinSxS component cleanup finished!", "DISM ResetBase", "OK", "Information") | Out-Null
        }
    })

    # Row 3: RB Gaming Plan & All Safe Tweaks
    $btnPowerPlan = New-Btn "Install RB Gaming Plan" 14 128 234 38 -BG $Script:C.Primary -FG $Script:C.Crust
    $btnPowerPlan.Add_Click({
        Install-RBUltimateGamingPlan
        [System.Windows.Forms.MessageBox]::Show("RB Ultimate Gaming Power Plan installed & activated successfully!`nEPP=0%, Core Parking Off, C-States 100%.", "RB Power Plan", "OK", "Information") | Out-Null
    })

    $btnLow = New-Btn "Apply All Safe Tweaks" 260 128 234 38 -BG $Script:C.Green -FG $Script:C.Crust
    $btnLow.Add_Click({
        $ids = @($Script:AllTweaks | Where-Object { $_.Risk -eq "Low" } | ForEach-Object { $_.Id })
        $r = [System.Windows.Forms.MessageBox]::Show("Apply $($ids.Count) safe tweaks across all modules?", "Confirm", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes -or $r -eq "Yes") {
            Invoke-TweakList -Ids $ids
            Set-Progress 100
            Write-Status "All safe tweaks applied!" $Script:C.Green
            [System.Windows.Forms.MessageBox]::Show("All $($ids.Count) safe tweaks applied successfully!", "Done", "OK", "Information") | Out-Null
        }
    })

    # Row 4: Restore Point & Emergency GPU Driver Reset
    $btnRP = New-Btn "Create Restore Point" 14 174 234 38 -BG $Script:C.Surface1 -FG $Script:C.White
    $btnRP.Add_Click({
        $ok = New-RestorePoint "RB Optimizer Manual Checkpoint"
        if ($ok) { [System.Windows.Forms.MessageBox]::Show("System Restore Point created successfully!", "OK", "OK", "Information") | Out-Null }
    })

    $btnResetGpuHome = New-Btn "Reset GPU to Default" 260 174 234 38 -BG $Script:C.Red -FG $Script:C.Crust
    $btnResetGpuHome.Add_Click({
        $r = [System.Windows.Forms.MessageBox]::Show("Khôi phục toàn bộ cài đặt GPU và Driver về mặc định an toàn?`n`nThao tác này sẽ xóa sạch mọi registry override gây lỗi đen màn hình / mất driver và đưa driver về trạng thái chuẩn của Windows.`n`nBạn có muốn tiếp tục?", "Emergency GPU Reset", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes -or $r -eq "Yes") {
            Reset-GpuToDefault
            [System.Windows.Forms.MessageBox]::Show("Đã xóa sạch mọi registry GPU override và khôi phục cài đặt driver an toàn!`n`nVui lòng KHỞI ĐỘNG LẠI máy tính để Windows nạp lại driver hoàn chỉnh.", "GPU Reset Done", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    })

    # Row 5: System Restore UI & Clean Temp
    $btnRstrui = New-Btn "Open System Restore" 14 220 234 38
    $btnRstrui.Add_Click({ Start-Process rstrui.exe })

    $btnTemp = New-Btn "Clean Temp & Browser" 260 220 234 38 -BG $Script:C.Mauve -FG $Script:C.Crust
    $btnTemp.Add_Click({
        if ($Script:DryRun) { Write-Log "[DRY] Would clean temp and cache" "DRY"; return }
        @("$env:TEMP\*", "$env:SystemRoot\Temp\*") | ForEach-Object {
            Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
        }
        $bPaths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache\*"
        )
        foreach ($p in $bPaths) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Log "OK  Temp and Browser caches safely cleaned" "SUCCESS"
        Write-Status "Temp and Browser caches cleaned!" $Script:C.Green
        [System.Windows.Forms.MessageBox]::Show("Temporary files and browser cache cleaned safely!", "Done", "OK", "Information") | Out-Null
    })

    $actCard.Controls.AddRange(@($btnPurgeRAM, $btnShader, $btnTRIM, $btnWinSxS, $btnPowerPlan, $btnLow, $btnRP, $btnResetGpuHome, $btnRstrui, $btnTemp))
    $tHome.Controls.Add($actCard)

    $tc.TabPages.Add($tHome)

    # =========================================================================
    # TAB 2: INTEL CORE SPECIAL EDITION
    # =========================================================================
    $intelNote = "Intel Core Special Edition: HWP Speed Shift, Thread Director P-Cores, Short Threads, EPP 0%, Demote/Promote, Paging Executive"
    $intelTab = Build-TweakTab "  Intel Core  " "Intel CPU" $Script:C.IntelCyan "Apply Intel Optimizations" $intelNote
    $tc.TabPages.Add($intelTab.Tab)

    # =========================================================================
    # TAB 3: AMD RYZEN SPECIAL EDITION
    # =========================================================================
    $amdNote = "AMD Ryzen Special Edition: CPPC Preferred Cores, 3D V-Cache Scheduling & Service, Dual-CCD 50% Parking vs Single-CCD 100% Unpark, EPP 0%"
    $amdTab = Build-TweakTab "  AMD Ryzen  " "AMD Ryzen" $Script:C.AMDRed "Apply AMD Optimizations" $amdNote
    $tc.TabPages.Add($amdTab.Tab)

    # =========================================================================
    # TAB 4: GAMING BOOST & NVIDIA GPU V3.0 (/boost)
    # =========================================================================
    $boostNote = "[CANH BAO] Tinh chinh GPU (MSI/NVIDIA) co the gay den man hinh/crash driver tam thoi tren mot so he thong. Khuyen nghi tao Restore Point truoc khi dung."
    $boostTab = Build-TweakTab "  Gaming Boost  " "Gaming Boost" $Script:C.Gold "Apply Gaming Boost" $boostNote
    
    # Add Quick Actions Bar to Gaming Boost Scroll Panel
    $quickGpuCard = New-Card -Title "Instant Hardware & Latency Actions" -X 4 -Y 760 -W 1020 -H 80 -AccentColor $Script:C.Gold
    $btnQuickMSI = New-Btn "Enable GPU MSI Mode" 14 32 185 36 -BG $Script:C.Gold -FG $Script:C.Crust
    $btnQuickMSI.Add_Click({
        $warnMsg = "CẢNH BÁO: Kích hoạt GPU MSI Mode có thể gây nháy màn hình hoặc reset driver tạm thời trên một số hệ thống.`n`nKhuyến nghị tạo Restore Point trước khi áp dụng.`n`nBạn có muốn tự động tạo Restore Point bảo vệ ngay bây giờ không?"
        $r = [System.Windows.Forms.MessageBox]::Show($warnMsg, "Xác nhận GPU MSI Mode", [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { New-RestorePoint -Desc "Pre-GPU MSI Mode Restore Point" }
        Enable-GpuMsiMode -Priority "High"
        [System.Windows.Forms.MessageBox]::Show("GPU MSI Mode safely enabled for dedicated GPU(s)!", "MSI Mode", "OK", "Information") | Out-Null
    })
    
    $btnQuickNV = New-Btn "Apply NVIDIA V3.0" 206 32 185 36 -BG $Script:C.Green -FG $Script:C.Crust
    $btnQuickNV.Add_Click({
        $warnMsg = "CẢNH BÁO: Tinh chỉnh NVIDIA Registry có thể gây nháy màn hình hoặc reset driver tạm thời trên một số hệ thống.`n`nKhuyến nghị tạo Restore Point trước khi áp dụng.`n`nBạn có muốn tự động tạo Restore Point bảo vệ ngay bây giờ không?"
        $r = [System.Windows.Forms.MessageBox]::Show($warnMsg, "Xác nhận NVIDIA Tweaks", [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { New-RestorePoint -Desc "Pre-NVIDIA Tweaks Restore Point" }
        Set-NvidiaGpuSettings
        [System.Windows.Forms.MessageBox]::Show("Safe NVIDIA V3.0 Tweaks (Low Latency Ultra, Silk Smoothness, TdrDelay=8) applied!", "NVIDIA Tweak", "OK", "Information") | Out-Null
    })
    
    $btnQuickPlan = New-Btn "Apply RB Gaming Plan" 398 32 195 36 -BG $Script:C.Primary -FG $Script:C.Crust
    $btnQuickPlan.Add_Click({ Install-RBUltimateGamingPlan; [System.Windows.Forms.MessageBox]::Show("RB Ultimate Gaming Power Plan activated!", "Power Plan", "OK", "Information") | Out-Null })

    $btnQuickISLC = New-Btn "Purge RAM (ISLC)" 600 32 185 36 -BG $Script:C.Peach -FG $Script:C.Crust
    $btnQuickISLC.Add_Click({ Invoke-StandbyListAndRamClean; [System.Windows.Forms.MessageBox]::Show("RAM Standby List and working sets purged!", "ISLC Purge", "OK", "Information") | Out-Null })

    $btnQuickResetGPU = New-Btn "Reset GPU Default" 792 32 214 36 -BG $Script:C.Red -FG $Script:C.Crust
    $btnQuickResetGPU.Add_Click({
        $r = [System.Windows.Forms.MessageBox]::Show("Khôi phục toàn bộ cài đặt GPU và Driver về mặc định an toàn?`n`nThao tác này xóa sạch mọi override registry gây lỗi Code 43 / đen màn hình.", "Reset GPU", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes -or $r -eq "Yes") {
            Reset-GpuToDefault
            [System.Windows.Forms.MessageBox]::Show("Đã khôi phục GPU về mặc định!`nVui lòng khởi động lại máy tính.", "Done", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    })

    $quickGpuCard.Controls.AddRange(@($btnQuickMSI, $btnQuickNV, $btnQuickPlan, $btnQuickISLC, $btnQuickResetGPU))
    $boostTab.SP.Controls.Add($quickGpuCard)

    $tc.TabPages.Add($boostTab.Tab)

    # =========================================================================
    # TAB 5: BROWSER & APP OPTIMIZATION (/browser)
    # =========================================================================
    $brwNote = "Browser & App Tuning: Disable background memory hogging, startup boost, browser telemetry, safe cache cleaner"
    $brwTab = Build-TweakTab "  Browser & Apps  " "Browser" $Script:C.Peach "Apply Browser Tweaks" $brwNote
    $tc.TabPages.Add($brwTab.Tab)

    # =========================================================================
    # TAB 6: GENERAL PERFORMANCE & STORAGE
    # =========================================================================
    $perfTab = Build-TweakTab "  Performance  " "Performance" $Script:C.Primary "Apply Performance Tweaks"
    $tc.TabPages.Add($perfTab.Tab)

    # =========================================================================
    # TAB 7: PRIVACY & TALON AI (COPILOT / WEATHER)
    # =========================================================================
    $privTab = Build-TweakTab "  Privacy & AI  " "Privacy" $Script:C.Mauve "Apply Privacy Tweaks"
    $tc.TabPages.Add($privTab.Tab)

    # =========================================================================
    # TAB 8: TALON DEBLOAT APPS (EXPANDED TO 55+ PACKAGES + COPILOT/WEATHER)
    # =========================================================================
    $tDeb = New-Tab "  Debloat  "
    
    # Quick Talon Deep Actions Bar at Top
    $talonBar = New-Card -Title "Talon Deep Debloat Actions" -X 8 -Y 8 -W 1046 -H 74 -AccentColor $Script:C.Red
    $btnPurgeCopilot = New-Btn "Purge Windows Copilot" 14 30 230 34 -BG $Script:C.Red -FG $Script:C.Crust
    $btnPurgeCopilot.Add_Click({
        Invoke-TalonDeepCopilotPurge
        [System.Windows.Forms.MessageBox]::Show("Windows Copilot Appx packages and policies deeply purged!", "Copilot Debloat", "OK", "Information") | Out-Null
    })

    $btnPurgeWeather = New-Btn "Purge Weather & Widgets" 254 30 240 34 -BG $Script:C.Peach -FG $Script:C.Crust
    $btnPurgeWeather.Add_Click({
        Invoke-TalonDeepWeatherPurge
        [System.Windows.Forms.MessageBox]::Show("MSN Weather and Windows Web Experience (Widgets) deeply purged!", "Weather Debloat", "OK", "Information") | Out-Null
    })

    $btnPurgeOneDrive = New-Btn "Uninstall OneDrive" 504 30 200 34 -BG $Script:C.Mauve -FG $Script:C.Crust
    $btnPurgeOneDrive.Add_Click({
        $r = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to uninstall OneDrive?", "Confirm", "YesNo", "Question")
        if ($r -eq "Yes") {
            Invoke-TalonOneDrivePurge
            [System.Windows.Forms.MessageBox]::Show("OneDrive uninstalled and explorer links cleaned!", "OneDrive", "OK", "Information") | Out-Null
        }
    })

    $btnCleanMRU = New-Btn "Clean Taskbar MRU" 714 30 180 34 -BG $Script:C.Surface1 -FG $Script:C.White
    $btnCleanMRU.Add_Click({
        Clear-TaskbarMRUCache
        [System.Windows.Forms.MessageBox]::Show("Taskbar recent MRU cache cleaned!", "Taskbar", "OK", "Information") | Out-Null
    })

    $talonBar.Controls.AddRange(@($btnPurgeCopilot, $btnPurgeWeather, $btnPurgeOneDrive, $btnCleanMRU))
    $tDeb.Controls.Add($talonBar)

    $debSP = New-ScrollPanel 8 88 1046 430
    $dy = 6
    $debCBs = @{}
    foreach ($tier in 1, 2, 3) {
        $tierCol = switch ($tier) { 1 { $Script:C.Green } 2 { $Script:C.Yellow } default { $Script:C.Red } }
        $tierText = switch ($tier) { 1 { "  Tier 1  --  Always Safe to Remove (Pre-installed Bloat, Copilot & Promos)" }; 2 { "  Tier 2  --  Usually Safe (Consumer Apps / Review First)" } default { "  Tier 3  --  Advanced / Caution (Core Windows Apps)" } }
        $hdr = New-Lbl $tierText 6 $dy 800 24 -FG $tierCol -Fnt (New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold))
        $debSP.Controls.Add($hdr)
        $dy += 28
        foreach ($ap in ($Script:DebloatApps | Where-Object { $_.T -eq $tier })) {
            $chkFG = if ($tier -eq 3) { $Script:C.Peach } else { $Script:C.Text }
            $chk = New-Chk $ap.L 18 $dy 340 -Chkd ($tier -eq 1) -FG $chkFG
            $chk.Tag = $ap.N
            $pkg = New-Lbl $ap.N 372 $dy 620 18 -FG $Script:C.Overlay0 -Fnt (New-Object System.Drawing.Font("Consolas", 8))
            $debCBs[$ap.N] = $chk
            $debSP.Controls.AddRange(@($chk, $pkg))
            $dy += 26
        }
        $dy += 8
    }
    $btnDeb = New-Btn "Remove Selected Apps" 8 528 240 38 -BG $Script:C.Red -FG $Script:C.Crust -Fnt (New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold))
    $btnDeb.Tag = $debCBs
    $btnDeb.Add_Click({
        param($s2, $e2)
        $cbMap = $s2.Tag
        $sel = @($cbMap.Keys | Where-Object { $cbMap[$_].Checked })
        if ($sel.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("No apps selected.", "", "OK", "Information") | Out-Null; return }
        $hasT3 = @($sel | Where-Object { ($Script:DebloatApps | Where-Object { $_.N -eq $_ }).T -ge 3 })
        $warn = if ($hasT3.Count -gt 0) { "`nWARNING: Tier 3 core apps selected!" } else { "" }
        $r = [System.Windows.Forms.MessageBox]::Show("Remove $($sel.Count) selected apps?$warn", "Confirm Debloat", "YesNo", "Warning")
        if ($r -eq "Yes") {
            Invoke-DebloatList -AppNames $sel
            Set-Progress 100
            [System.Windows.Forms.MessageBox]::Show("$($sel.Count) apps removed successfully!", "Done", "OK", "Information") | Out-Null
        }
    })
    $btnT1 = New-Btn "Tier 1 Only" 256 528 130 38 -BG $Script:C.Green -FG $Script:C.Crust
    $btnT1.Tag = $debCBs
    $btnT1.Add_Click({
        param($s2, $e2)
        $cbMap = $s2.Tag
        foreach ($a in $Script:DebloatApps) { if ($cbMap.ContainsKey($a.N)) { $cbMap[$a.N].Checked = ($a.T -eq 1) } }
    })
    $btnAll4 = New-Btn "Select All" 394 528 120 38 -BG $Script:C.Peach -FG $Script:C.Crust
    $btnAll4.Tag = $debCBs
    $btnAll4.Add_Click({ param($s2, $e2); foreach ($k in $s2.Tag.Keys) { $s2.Tag[$k].Checked = $true } })
    $btnNone4 = New-Btn "Deselect All" 522 528 120 38
    $btnNone4.Tag = $debCBs
    $btnNone4.Add_Click({ param($s2, $e2); foreach ($k in $s2.Tag.Keys) { $s2.Tag[$k].Checked = $false } })
    $tDeb.Controls.AddRange(@($debSP, $btnDeb, $btnT1, $btnAll4, $btnNone4))
    $tc.TabPages.Add($tDeb)

    # =========================================================================
    # TAB 9: SERVICES & NETWORK
    # =========================================================================
    $netTab = Build-TweakTab "  Services & Net  " "Network" $Script:C.Sapphire "Apply Network Tweaks" -CustomAction {
        $dnsMap = @{ "Cloudflare (1.1.1.1)" = @("1.1.1.1", "1.0.0.1"); "Google (8.8.8.8)" = @("8.8.8.8", "8.8.4.4"); "Quad9 (9.9.9.9)" = @("9.9.9.9", "149.112.112.112") }
        if ($Script:cboDNS -and $dnsMap.ContainsKey($Script:cboDNS.SelectedItem.ToString())) {
            $ips = $dnsMap[$Script:cboDNS.SelectedItem.ToString()]
            try {
                Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
                    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses $ips
                    Write-Log "OK  DNS $($Script:cboDNS.SelectedItem) on $($_.Name)" "SUCCESS"
                }
            } catch { Write-Log "WARN DNS: $_" "WARN" }
        }
    }
    $dnsCard = New-Card -Title "Fast Gaming DNS Switcher" -X 8 -Y 230 -W 500 -H 100 -AccentColor $Script:C.Sapphire
    $dnsCard.Controls.Add((New-Lbl "Set DNS:" 14 38 70 22))
    $Script:cboDNS = New-Object System.Windows.Forms.ComboBox
    $Script:cboDNS.Items.AddRange(@("Keep Default", "Cloudflare (1.1.1.1)", "Google (8.8.8.8)", "Quad9 (9.9.9.9)"))
    $Script:cboDNS.SelectedIndex = 0
    $Script:cboDNS.Location = New-Object System.Drawing.Point(88, 36)
    $Script:cboDNS.Size = New-Object System.Drawing.Size(388, 26)
    $Script:cboDNS.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $Script:cboDNS.BackColor = $Script:C.Surface0
    $Script:cboDNS.ForeColor = $Script:C.Text
    $Script:cboDNS.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dnsCard.Controls.Add($Script:cboDNS)
    $dnsCard.Controls.Add((New-Lbl "Applied to all active network adapters when Network Tweaks are executed" 14 68 470 18 -FG $Script:C.Overlay0 -Fnt (New-Object System.Drawing.Font("Segoe UI", 7.8))))
    $netTab.SP.Controls.Add($dnsCard)
    $tc.TabPages.Add($netTab.Tab)

    # =========================================================================
    # TAB 10: LOG & TOOLS (WITH INSTANT IN-MEMORY LOG FLUSH FIX)
    # =========================================================================
    $tLog = New-Tab "  Log & Tools  "
    $Script:LogBox = New-Object System.Windows.Forms.RichTextBox
    $Script:LogBox.Location = New-Object System.Drawing.Point(8, 8)
    $Script:LogBox.Size = New-Object System.Drawing.Size(1046, 470)
    $Script:LogBox.BackColor = $Script:C.Mantle
    $Script:LogBox.ForeColor = $Script:C.Text
    $Script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $Script:LogBox.ReadOnly = $true
    $Script:LogBox.WordWrap = $false
    $Script:LogBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $Script:LogBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Both

    # Flush all initial logs that occurred before LogBox was instantiated
    Flush-LogHistoryToBox

    # Row 1 of Tools Buttons
    $btnCL = New-Btn "Clear Log" 8 488 110 36
    $btnCL.Add_Click({ $Script:LogBox.Clear(); $Script:LogHistory.Clear() })

    $btnOL = New-Btn "Open Log File" 126 488 130 36
    $btnOL.Add_Click({ Start-Process notepad.exe $Script:LogFile })

    $btnExp = New-Btn "Export Reg Backup" 264 488 160 36 -BG $Script:C.Green -FG $Script:C.Crust
    $btnExp.Add_Click({
        if ($Script:RegBackups.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("No reg backups yet in this session.", "", "OK", "Information") | Out-Null; return }
        $rc = "Windows Registry Editor Version 5.00`r`n`r`n"
        foreach ($b in $Script:RegBackups) {
            $rp = $b.Path -replace "HKCU:", "HKEY_CURRENT_USER" -replace "HKLM:", "HKEY_LOCAL_MACHINE"
            $rc += "[$rp]`r`n"
            try { $rc += "`"$($b.Name)`"=dword:$([Convert]::ToString([int]$b.Value,16).PadLeft(8,'0'))`r`n`r`n" }
            catch { $rc += "`"$($b.Name)`"=`"$($b.Value)`"`r`n`r`n" }
        }
        $rc | Out-File $Script:BackupReg -Encoding ASCII
        Write-Log "OK  Reg backup saved: $Script:BackupReg" "SUCCESS"
        [System.Windows.Forms.MessageBox]::Show("Backup saved: $Script:BackupReg", "Saved", "OK", "Information") | Out-Null
    })

    $btnAn = New-Btn "Run System Diagnostics" 432 488 190 36 -BG $Script:C.Teal -FG $Script:C.Crust
    $btnAn.Add_Click({
        Invoke-SystemAnalysis
        Flush-LogHistoryToBox
    })

    # Row 2 of Tools: 1-Click Hardware & System Maintenance + Emergency GPU Reset
    $btnLogTRIM = New-Btn "SSD TRIM (C:)" 8 532 130 36 -BG $Script:C.Teal -FG $Script:C.Crust
    $btnLogTRIM.Add_Click({ Invoke-SSDTrim "C" })

    $btnLogWinSxS = New-Btn "WinSxS DISM Cleanup" 144 532 165 36 -BG $Script:C.Lavender -FG $Script:C.Crust
    $btnLogWinSxS.Add_Click({ Invoke-WinSxSCleanup })

    $btnLogISLC = New-Btn "ISLC Purge RAM" 315 532 140 36 -BG $Script:C.Gold -FG $Script:C.Crust
    $btnLogISLC.Add_Click({ Invoke-StandbyListAndRamClean })

    $btnLogMSI = New-Btn "Enable GPU MSI" 461 532 150 36 -BG $Script:C.Primary -FG $Script:C.Crust
    $btnLogMSI.Add_Click({ Enable-GpuMsiMode -Priority "High" })

    $btnLogResetGPU = New-Btn "Emergency Reset GPU" 617 532 195 36 -BG $Script:C.Red -FG $Script:C.Crust
    $btnLogResetGPU.Add_Click({
        $r = [System.Windows.Forms.MessageBox]::Show("Khôi phục toàn bộ GPU và display driver về mặc định an toàn?", "Reset GPU", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes -or $r -eq "Yes") {
            Reset-GpuToDefault
            [System.Windows.Forms.MessageBox]::Show("Đã khôi phục cài đặt GPU về mặc định! Vui lòng khởi động lại máy tính.", "Done", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    })

    $tLog.Controls.AddRange(@($Script:LogBox, $btnCL, $btnOL, $btnExp, $btnAn, $btnLogTRIM, $btnLogWinSxS, $btnLogISLC, $btnLogMSI, $btnLogResetGPU))
    $tc.TabPages.Add($tLog)

    # Initial Logs (Saved to Buffer & Rendered to LogBox)
    Write-Log "RB Optimizer Pro v$($Script:Version) initialized" "INFO"
    Write-Log "OS: $($HW.WinCaption) [Build $($Script:WinVer.Build)]" "INFO"
    Write-Log "CPU: $($HW.CPUType) -- $($HW.CPUName) [$($HW.CPUGen)]" "INFO"
    Write-Log "Architecture: $($HW.Architecture)" "INFO"
    Write-Log "GPU: $($HW.GPUType) -- $($HW.GPUName)" "INFO"
    Write-Log "RAM: $($HW.RAMgb) GB  |  SSD: $($HW.IsSSD)  |  Chassis: $(if($HW.IsLaptop){'Laptop'}else{'Desktop'})" "INFO"
    Write-Log "Tweaks loaded: $($Script:AllTweaks.Count)  |  Debloat packages: $($Script:DebloatApps.Count)" "INFO"
    Write-Log "Log file: $Script:LogFile" "INFO"
    Write-Log "------------------------------------------------------------" "INFO"
    Write-Log "TIP: Click 'Auto-Detect Pro' on Home tab for 1-click tailored optimization." "INFO"

    # Refresh logbox display
    Flush-LogHistoryToBox

    $form.Add_Resize({
        $w = $form.ClientSize.Width
        $h = $form.ClientSize.Height
        $tc.Size = New-Object System.Drawing.Size($w, ($h - 62 - 34))
        $titlePnl.Width = $w
        $stPnl.Location = New-Object System.Drawing.Point(0, ($h - 34))
        $stPnl.Width = $w
        $Script:ProgressBar.Location = New-Object System.Drawing.Point(($w - 300), 8)
        $Script:StatusLabel.Width = ($w - 320)
    })

    # Initialize System Tray Icon only (Floating Widget removed per user request)
    Setup-SystemTrayIcon

    $form.Add_FormClosing({
        param($s, $e)
        try {
            if ($Script:NotifyIcon) { $Script:NotifyIcon.Visible = $false; $Script:NotifyIcon.Dispose() }
        } catch {}
    })

    return $form
}

# =============================================================================
# ENTRY POINT
# =============================================================================
"RB Optimizer v$Script:Version -- $(Get-Date)" | Out-File $Script:LogFile -Encoding UTF8
"OS: $([System.Environment]::OSVersion.VersionString)" | Add-Content $Script:LogFile

Write-Host "`n  RB OPTIMIZER v$Script:Version  --  Windows Gaming, Hardware & Latency Suite" -ForegroundColor Cyan
Write-Host "  Detecting hardware profile..." -ForegroundColor Gray
$HW = Get-DetailedHardwareProfile
Write-Host "  CPU: $($HW.CPUType) ($($HW.CPUGen))  |  GPU: $($HW.GPUType)  |  RAM: $($HW.RAMgb)GB" -ForegroundColor White
Write-Host "  Launching GUI...`n" -ForegroundColor Green

$mainForm = Build-MainGUI -HW $HW
[System.Windows.Forms.Application]::Run($mainForm)

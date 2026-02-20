# ==============================
# WinVMOptimizer Enterprise 2026
# ==============================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -------- INIT --------
$BaseDir = "$env:ProgramData\WinVMOptimizer"
$StateFile = "$BaseDir\state.json"
$LogFile = "$BaseDir\log.txt"

New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null

function Log($m){ Add-Content $LogFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $m" }

function Assert-Admin {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $p=New-Object Security.Principal.WindowsPrincipal($id)
    if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        [System.Windows.Forms.MessageBox]::Show("Run as Administrator")
        exit
    }
}
Assert-Admin

# -------- BASELINE --------
function Get-Baseline {
    return [PSCustomObject]@{
        OSBuild=(Get-ComputerInfo).OsBuildNumber
        CPU=(Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
        RAM=[math]::Round((Get-Counter '\Memory\Committed Bytes').CounterSamples.CookedValue/1MB)
        Services=(Get-Service|?{$_.Status -eq "Running"}).Count
        Appx=(Get-AppxPackage -AllUsers).Count
        Startup=(Get-CimInstance Win32_StartupCommand).Count
    }
}

# -------- STATE --------
function Save-State {
    $state=@{
        Services=Get-Service|Select Name,StartType
        Tasks=Get-ScheduledTask|Select TaskName,State
    }
    $state|ConvertTo-Json -Depth 5|Set-Content $StateFile
    Log "State saved"
}
function Restore-State {
    if(!(Test-Path $StateFile)){return}
    $s=Get-Content $StateFile|ConvertFrom-Json
    foreach($svc in $s.Services){
        Set-Service -Name $svc.Name -StartupType $svc.StartType -ErrorAction SilentlyContinue
    }
    Log "State restored"
}

# -------- POWER --------
function Enable-HighPerf {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
    powercfg /hibernate off
    Log "Power optimized"
}

# -------- SERVICES --------
$SafeServices=@("SysMain","WSearch")
$AggressiveServices=@("DiagTrack","DoSvc")

function Disable-ServiceSafe($n){
    $svc=Get-Service -Name $n -ErrorAction SilentlyContinue
    if($svc){
        Set-Service $n -StartupType Disabled
        Stop-Service $n -Force -ErrorAction SilentlyContinue
        Log "Disabled $n"
    }
}

# -------- TELEMETRY --------
function Disable-Telemetry {
    $path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if(!(Test-Path $path)){New-Item $path -Force|Out-Null}
    Set-ItemProperty $path AllowTelemetry 0
    Disable-ServiceSafe "DiagTrack"
    Log "Telemetry disabled"
}

# -------- BACKGROUND --------
function Disable-BackgroundApps {
    $path="HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    if(!(Test-Path $path)){New-Item $path|Out-Null}
    Set-ItemProperty $path GlobalUserDisabled 1
    Log "Background apps disabled"
}

# -------- APPX --------
$AppxPatterns=@("*Xbox*","*Bing*","*Clipchamp*","*Solitaire*","*Teams*")

function Remove-Appx {
    foreach($p in $AppxPatterns){
        Get-AppxPackage -AllUsers -Name $p | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Log "Removed Appx $p"
    }
}

# -------- TASKS --------
function Disable-TelemetryTasks {
    Get-ScheduledTask | Where {$_.TaskName -like "*Telemetry*" -or $_.TaskName -like "*Customer*"} |
    ForEach-Object { Disable-ScheduledTask $_.TaskName -ErrorAction SilentlyContinue }
    Log "Telemetry tasks disabled"
}

# -------- NETWORK --------
function Optimize-Network {
    netsh int tcp set global autotuninglevel=normal|Out-Null
    netsh int tcp set global rss=enabled|Out-Null
    Log "Network optimized"
}

# -------- WINDOWS UPDATE CONTROL --------
function Disable-WindowsUpdate {
    Set-Service wuauserv -StartupType Disabled
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Log "Windows Update disabled"
}

# -------- PROFILE ENGINE --------
function Apply-Profile($mode){
    Save-State
    $before=Get-Baseline

    Enable-HighPerf
    Disable-BackgroundApps
    Optimize-Network
    Remove-Appx

    foreach($s in $SafeServices){Disable-ServiceSafe $s}

    if($mode -eq "Aggressive"){
        foreach($s in $AggressiveServices){Disable-ServiceSafe $s}
        Disable-Telemetry
        Disable-TelemetryTasks
        Disable-WindowsUpdate
    }

    $after=Get-Baseline

    $report=@"
Before:
CPU $($before.CPU)
RAM $($before.RAM)
Services $($before.Services)
Appx $($before.Appx)

After:
CPU $($after.CPU)
RAM $($after.RAM)
Services $($after.Services)
Appx $($after.Appx)
"@

    [System.Windows.Forms.MessageBox]::Show($report,"Optimization Report")
}

# -------- GUI --------
$form=New-Object Windows.Forms.Form
$form.Text="WinVMOptimizer Enterprise 2026"
$form.Size="700,450"
$form.StartPosition="CenterScreen"

$btnSafe=New-Object Windows.Forms.Button
$btnSafe.Text="SAFE PROFILE"
$btnSafe.Size="200,60"
$btnSafe.Location="50,50"
$form.Controls.Add($btnSafe)

$btnAgg=New-Object Windows.Forms.Button
$btnAgg.Text="AGGRESSIVE PROFILE"
$btnAgg.Size="200,60"
$btnAgg.Location="300,50"
$form.Controls.Add($btnAgg)

$btnBench=New-Object Windows.Forms.Button
$btnBench.Text="BENCHMARK"
$btnBench.Size="200,60"
$btnBench.Location="175,150"
$form.Controls.Add($btnBench)

$btnUndo=New-Object Windows.Forms.Button
$btnUndo.Text="UNDO"
$btnUndo.Size="200,60"
$btnUndo.Location="175,250"
$form.Controls.Add($btnUndo)

$btnSafe.Add_Click({Apply-Profile "Safe"})
$btnAgg.Add_Click({Apply-Profile "Aggressive"})
$btnBench.Add_Click({
    $r=Get-Baseline
    [System.Windows.Forms.MessageBox]::Show("CPU $($r.CPU)`nRAM $($r.RAM)`nServices $($r.Services)`nAppx $($r.Appx)")
})
$btnUndo.Add_Click({Restore-State})

$form.ShowDialog()

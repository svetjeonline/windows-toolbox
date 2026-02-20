# =====================================================
# WinVM Optimizer Enterprise v6
# Full PowerShell Framework Edition (2026)
# =====================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===================== GLOBAL ========================

$Global:Root = "$env:ProgramData\WinVMOptimizer"
$Global:LogFile = "$Root\optimizer.log"
$Global:StateDir = "$Root\States"
$Global:AppxBackup = "$Root\AppxBackup.csv"

New-Item -ItemType Directory -Force -Path $Root,$StateDir | Out-Null

function Log($msg){
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
    Add-Content $LogFile $line
}

function Assert-Admin{
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $p=New-Object Security.Principal.WindowsPrincipal($id)
    if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        [System.Windows.Forms.MessageBox]::Show("Spusť jako Administrator")
        exit
    }
}
Assert-Admin

# ===================== STATE ENGINE ===================

function Save-State {
    $state = @{
        Time = Get-Date
        Services = Get-Service | Select Name,StartType,Status
        Registry = @()
        Tasks = Get-ScheduledTask | Select TaskName,State
    }
    $file="$StateDir\state_$(Get-Date -Format yyyyMMdd_HHmmss).json"
    $state | ConvertTo-Json -Depth 6 | Set-Content $file
    Log "State saved: $file"
    return $file
}

function Restore-State($file){
    if(!(Test-Path $file)){return}
    $state = Get-Content $file | ConvertFrom-Json
    foreach($svc in $state.Services){
        Set-Service $svc.Name -StartupType $svc.StartType -ErrorAction SilentlyContinue
        if($svc.Status -eq "Running"){Start-Service $svc.Name -ErrorAction SilentlyContinue}
    }
    Log "State restored from $file"
}

# ===================== SYSTEM PROFILER ================

function Get-SystemSnapshot {
    return [PSCustomObject]@{
        OS = (Get-ComputerInfo).OsName
        Build = (Get-ComputerInfo).OsBuildNumber
        CPU = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
        RAM_MB = [math]::Round((Get-Counter '\Memory\Committed Bytes').CounterSamples.CookedValue /1MB)
        ServicesRunning = (Get-Service | ? {$_.Status -eq 'Running'}).Count
        AppxCount = (Get-AppxPackage -AllUsers).Count
    }
}

# ===================== PRIVACY ENGINE =================

function Apply-Privacy($mode){

    $reg="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if(!(Test-Path $reg)){New-Item $reg -Force | Out-Null}
    Set-ItemProperty $reg AllowTelemetry 0

    $tasks=@(
    "Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
    )

    foreach($t in $tasks){
        try{Disable-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue}catch{}
    }

    Disable-ServiceSafe "DiagTrack"

    if($mode -eq "Aggressive"){
        Disable-ServiceSafe "WaaSMedicSvc"
        Disable-ServiceSafe "DoSvc"
    }

    Log "Privacy applied ($mode)"
}

# ===================== PERFORMANCE ENGINE =============

function Apply-Performance {

    powercfg /hibernate off
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" VisualFXSetting 2

    Disable-ServiceSafe "SysMain"
    Disable-ServiceSafe "WSearch"

    Log "Performance profile applied"
}

# ===================== SERVICES =======================

function Disable-ServiceSafe($name){
    $svc=Get-Service $name -ErrorAction SilentlyContinue
    if($svc){
        Stop-Service $name -Force -ErrorAction SilentlyContinue
        Set-Service $name -StartupType Disabled
        Log "Service disabled: $name"
    }
}

# ===================== APPX ENGINE ====================

function Backup-AppxInventory {
    Get-AppxPackage -AllUsers | Select Name,PackageFullName | Export-Csv $AppxBackup -NoTypeInformation
}

function Remove-AppxPattern($pattern){
    Get-AppxPackage -AllUsers | Where {$_.Name -like $pattern} |
    ForEach-Object{
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        Log "Removed Appx: $($_.Name)"
    }
}

function Apply-AppxCleanup {
    Backup-AppxInventory
    $patterns="*Xbox*","*Clipchamp*","*Solitaire*","*Teams*","*Bing*"
    foreach($p in $patterns){Remove-AppxPattern $p}
    Log "Appx cleanup done"
}

# ===================== STARTUP ANALYZER ===============

function Get-StartupItems {
    $items=@()
    $items+=Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Run -ErrorAction SilentlyContinue
    $items+=Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -ErrorAction SilentlyContinue
    return $items
}

# ===================== VM DETECTION ===================

function Is-VM {
    $bios = Get-CimInstance Win32_BIOS
    return ($bios.Manufacturer -match "VMware|VirtualBox|Microsoft")
}

# ===================== GUI ============================

$form=New-Object Windows.Forms.Form
$form.Text="WinVM Optimizer Enterprise v6"
$form.Size="1200,800"
$form.StartPosition="CenterScreen"

$tabs=New-Object Windows.Forms.TabControl
$tabs.Dock="Fill"
$form.Controls.Add($tabs)

function AddTab($name){
    $tab=New-Object Windows.Forms.TabPage
    $tab.Text=$name
    $tabs.TabPages.Add($tab)
    return $tab
}

$dash=AddTab "Dashboard"
$privacy=AddTab "Privacy"
$perf=AddTab "Performance"
$appx=AddTab "Appx"
$services=AddTab "Services"
$system=AddTab "System"

# DASHBOARD
$btnSnap=New-Object Windows.Forms.Button
$btnSnap.Text="System Snapshot"
$btnSnap.Size="250,50"
$btnSnap.Location="20,20"
$dash.Controls.Add($btnSnap)
$btnSnap.Add_Click({
    $r=Get-SystemSnapshot
    [System.Windows.Forms.MessageBox]::Show($r | Out-String)
})

# PRIVACY
$btnPriv=New-Object Windows.Forms.Button
$btnPriv.Text="Apply Privacy (Balanced)"
$btnPriv.Size="250,50"
$btnPriv.Location="20,20"
$privacy.Controls.Add($btnPriv)
$btnPriv.Add_Click({
    $state=Save-State
    Apply-Privacy "Balanced"
})

# PERFORMANCE
$btnPerf=New-Object Windows.Forms.Button
$btnPerf.Text="Apply Performance"
$btnPerf.Size="250,50"
$btnPerf.Location="20,20"
$perf.Controls.Add($btnPerf)
$btnPerf.Add_Click({
    $state=Save-State
    Apply-Performance
})

# APPX
$btnAppx=New-Object Windows.Forms.Button
$btnAppx.Text="Appx Cleanup"
$btnAppx.Size="250,50"
$btnAppx.Location="20,20"
$appx.Controls.Add($btnAppx)
$btnAppx.Add_Click({
    $state=Save-State
    Apply-AppxCleanup
})

# SYSTEM
$btnRestore=New-Object Windows.Forms.Button
$btnRestore.Text="Restore Last State"
$btnRestore.Size="250,50"
$btnRestore.Location="20,20"
$system.Controls.Add($btnRestore)
$btnRestore.Add_Click({
    $latest = Get-ChildItem $StateDir | Sort LastWriteTime -Descending | Select -First 1
    if($latest){Restore-State $latest.FullName}
})

$form.ShowDialog()

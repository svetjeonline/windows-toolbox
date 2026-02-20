# ==========================================================
# WinVM Optimizer Enterprise v7
# Full PowerShell Administrative Framework (2026)
# ==========================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================= GLOBAL =================

$Root="$env:ProgramData\WinVMOptimizer"
$Log="$Root\optimizer.log"
$StateDir="$Root\States"
$AppxBackup="$Root\AppxInventory.csv"

New-Item -ItemType Directory -Force -Path $Root,$StateDir | Out-Null

function Log($m){
    Add-Content $Log "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $m"
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

# ================= STATE ENGINE =================

function Save-State{
    $file="$StateDir\state_$(Get-Date -Format yyyyMMdd_HHmmss).json"
    $state=@{
        Services=Get-Service | Select Name,StartType,Status
        Tasks=Get-ScheduledTask | Select TaskName,State
    }
    $state|ConvertTo-Json -Depth 5|Set-Content $file
    Log "State saved: $file"
    return $file
}

function Restore-LatestState{
    $latest=Get-ChildItem $StateDir|Sort LastWriteTime -Descending|Select -First 1
    if(!$latest){return}
    $s=Get-Content $latest.FullName|ConvertFrom-Json
    foreach($svc in $s.Services){
        Set-Service $svc.Name -StartupType $svc.StartType -ErrorAction SilentlyContinue
    }
    Log "Restored state $($latest.Name)"
}

# ================= PROFILER =================

function Get-Snapshot{
    [PSCustomObject]@{
        OS=(Get-ComputerInfo).OsName
        Build=(Get-ComputerInfo).OsBuildNumber
        CPU=[math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue,2)
        RAM_MB=[math]::Round((Get-Counter '\Memory\Committed Bytes').CounterSamples.CookedValue/1MB)
        ServicesRunning=(Get-Service|?{$_.Status -eq 'Running'}).Count
        AppxCount=(Get-AppxPackage -AllUsers).Count
    }
}

# ================= SAFE SERVICE DISABLE =================

function Disable-ServiceSafe($name){
    $svc=Get-Service $name -ErrorAction SilentlyContinue
    if($svc){
        if($name -match "WinDefend|RpcSs|CryptSvc|EventLog"){
            [System.Windows.Forms.MessageBox]::Show("CORE služba: $name nelze vypnout")
            return
        }
        Stop-Service $name -Force -ErrorAction SilentlyContinue
        Set-Service $name -StartupType Disabled
        Log "Service disabled: $name"
    }
}

# ================= PRIVACY =================

function Apply-PrivacyMax{
    $reg="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if(!(Test-Path $reg)){New-Item $reg -Force|Out-Null}
    Set-ItemProperty $reg AllowTelemetry 0
    Disable-ServiceSafe "DiagTrack"
    Log "Privacy MAX applied"
}

# ================= PERFORMANCE =================

function Apply-Performance{
    powercfg /hibernate off
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    Disable-ServiceSafe "SysMain"
    Disable-ServiceSafe "WSearch"
    Log "Performance applied"
}

# ================= APPX =================

function Backup-Appx{
    Get-AppxPackage -AllUsers|Select Name,PackageFullName|Export-Csv $AppxBackup -NoTypeInformation
}

function Remove-AppxPattern($pattern){
    Get-AppxPackage -AllUsers|Where{$_.Name -like $pattern}|
    %{
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        Log "Removed $($_.Name)"
    }
}

function Apply-AppxCleanup{
    Backup-Appx
    "*Xbox*","*Clipchamp*","*Solitaire*","*Teams*","*Bing*"|%{Remove-AppxPattern $_}
}

# ================= UI =================

$form=New-Object Windows.Forms.Form
$form.Text="WinVM Optimizer Enterprise v7"
$form.Size="1300,850"
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
$servicesTab=AddTab "Services"
$tasksTab=AddTab "Tasks"
$system=AddTab "System"

# DASHBOARD
$btnSnap=New-Object Windows.Forms.Button
$btnSnap.Text="System Snapshot"
$btnSnap.Size="250,50"
$btnSnap.Location="20,20"
$dash.Controls.Add($btnSnap)
$btnSnap.Add_Click({[System.Windows.Forms.MessageBox]::Show((Get-Snapshot|Out-String))})

# PRIVACY
$btnPriv=New-Object Windows.Forms.Button
$btnPriv.Text="Apply Privacy MAX"
$btnPriv.Size="250,50"
$btnPriv.Location="20,20"
$privacy.Controls.Add($btnPriv)
$btnPriv.Add_Click({Save-State;Apply-PrivacyMax})

# PERFORMANCE
$btnPerf=New-Object Windows.Forms.Button
$btnPerf.Text="Apply Performance"
$btnPerf.Size="250,50"
$btnPerf.Location="20,20"
$perf.Controls.Add($btnPerf)
$btnPerf.Add_Click({Save-State;Apply-Performance})

# APPX GRID
$gridAppx=New-Object Windows.Forms.DataGridView
$gridAppx.Size="1200,600"
$gridAppx.Location="20,20"
$gridAppx.AutoSizeColumnsMode="Fill"
$appx.Controls.Add($gridAppx)

function Load-AppxGrid{
    $gridAppx.DataSource=Get-AppxPackage -AllUsers|Select Name,Version,Publisher
}
Load-AppxGrid

$btnRemoveAppx=New-Object Windows.Forms.Button
$btnRemoveAppx.Text="Remove Selected"
$btnRemoveAppx.Location="20,650"
$appx.Controls.Add($btnRemoveAppx)
$btnRemoveAppx.Add_Click({
    Backup-Appx
    foreach($r in $gridAppx.SelectedRows){
        $name=$r.Cells["Name"].Value
        Get-AppxPackage -AllUsers -Name $name|Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }
    Load-AppxGrid
})

# SERVICES GRID
$gridSvc=New-Object Windows.Forms.DataGridView
$gridSvc.Size="1200,600"
$gridSvc.Location="20,20"
$gridSvc.AutoSizeColumnsMode="Fill"
$servicesTab.Controls.Add($gridSvc)

function Load-SvcGrid{
    $gridSvc.DataSource=Get-Service|Select Name,DisplayName,Status,StartType
}
Load-SvcGrid

$btnDisableSvc=New-Object Windows.Forms.Button
$btnDisableSvc.Text="Disable Selected"
$btnDisableSvc.Location="20,650"
$servicesTab.Controls.Add($btnDisableSvc)
$btnDisableSvc.Add_Click({
    foreach($r in $gridSvc.SelectedRows){
        Disable-ServiceSafe $r.Cells["Name"].Value
    }
    Load-SvcGrid
})

# TASKS GRID
$gridTasks=New-Object Windows.Forms.DataGridView
$gridTasks.Size="1200,600"
$gridTasks.Location="20,20"
$gridTasks.AutoSizeColumnsMode="Fill"
$tasksTab.Controls.Add($gridTasks)

function Load-TaskGrid{
    $gridTasks.DataSource=Get-ScheduledTask|Select TaskName,State
}
Load-TaskGrid

$btnDisableTask=New-Object Windows.Forms.Button
$btnDisableTask.Text="Disable Selected"
$btnDisableTask.Location="20,650"
$tasksTab.Controls.Add($btnDisableTask)
$btnDisableTask.Add_Click({
    foreach($r in $gridTasks.SelectedRows){
        Disable-ScheduledTask -TaskName $r.Cells["TaskName"].Value -ErrorAction SilentlyContinue
    }
    Load-TaskGrid
})

# SYSTEM
$btnRestore=New-Object Windows.Forms.Button
$btnRestore.Text="Restore Last State"
$btnRestore.Size="250,50"
$btnRestore.Location="20,20"
$system.Controls.Add($btnRestore)
$btnRestore.Add_Click({Restore-LatestState})

$form.ShowDialog()

function Get-WinUtilProfilesDirectory {
    if (-not $sync.asysdir) {
        $sync.asysdir = Join-Path $env:LocalAppData "asys"
    }

    $profilesDir = Join-Path $sync.asysdir "profiles"
    if (-not (Test-Path $profilesDir)) {
        New-Item -Path $profilesDir -ItemType Directory -Force | Out-Null
    }

    return $profilesDir
}

function Get-WinUtilRollbackJournalPath {
    if (-not $sync.asysdir) {
        $sync.asysdir = Join-Path $env:LocalAppData "asys"
    }

    $rollbackDir = Join-Path $sync.asysdir "rollback"
    if (-not (Test-Path $rollbackDir)) {
        New-Item -Path $rollbackDir -ItemType Directory -Force | Out-Null
    }

    return (Join-Path $rollbackDir "journal.jsonl")
}

function Get-WinUtilProfilePath {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $safeName = ($Name -replace '[^\w\.-]', "_").Trim()
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        throw "Profile name cannot be empty."
    }

    return (Join-Path (Get-WinUtilProfilesDirectory) "$safeName.json")
}

function Get-WinUtilProfiles {
    $profilesDir = Get-WinUtilProfilesDirectory
    return Get-ChildItem -Path $profilesDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty BaseName |
        Sort-Object
}

function Save-WinUtilProfile {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $profilePath = Get-WinUtilProfilePath -Name $Name
    $selection = @(
        @($sync.selectedApps),
        @($sync.selectedTweaks),
        @($sync.selectedToggles),
        @($sync.selectedFeatures)
    ) | ForEach-Object { $_ } | ForEach-Object { [string]$_ }

    $selection | ConvertTo-Json | Out-File -Path $profilePath -Encoding ascii -Force
    $sync.preferences.activeprofile = $Name
    Set-Preferences -save
    return $profilePath
}

function Import-WinUtilProfile {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [switch]$ApplyToUI
    )

    $profilePath = Get-WinUtilProfilePath -Name $Name
    if (-not (Test-Path $profilePath)) {
        throw "Profile '$Name' does not exist."
    }

    $profileData = Get-Content -Path $profilePath -Raw | ConvertFrom-Json
    $sync.selectedApps = [System.Collections.Generic.List[string]]::new()
    $sync.selectedTweaks = [System.Collections.Generic.List[string]]::new()
    $sync.selectedToggles = [System.Collections.Generic.List[string]]::new()
    $sync.selectedFeatures = [System.Collections.Generic.List[string]]::new()

    Update-WinUtilSelections -flatJson $profileData

    if ($ApplyToUI -and -not $PARAM_NOUI) {
        $sync.ImportInProgress = $true
        try {
            Reset-WPFCheckBoxes -doToggles $true
        } finally {
            $sync.ImportInProgress = $false
        }
    }

    $sync.preferences.activeprofile = $Name
    Set-Preferences -save
}

function Remove-WinUtilProfile {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $profilePath = Get-WinUtilProfilePath -Name $Name
    if (Test-Path $profilePath) {
        Remove-Item -Path $profilePath -Force
    }

    if ($sync.preferences.activeprofile -eq $Name) {
        $sync.preferences.activeprofile = ""
        Set-Preferences -save
    }
}

function Save-WinUtilRollbackSnapshot {
    param(
        [Parameter(Mandatory)]
        [string]$CheckBox
    )

    $tweakConfig = $sync.configs.tweaks.$CheckBox
    if (-not $tweakConfig) {
        return
    }

    $entry = [ordered]@{
        Timestamp = (Get-Date).ToString("o")
        CheckBox = $CheckBox
        Registry = @()
        Service = @()
        ScheduledTask = @()
    }

    foreach ($registryItem in @($tweakConfig.registry)) {
        if (-not $registryItem) { continue }
        $exists = $false
        $currentValue = $null
        try {
            $item = Get-ItemProperty -Path $registryItem.Path -Name $registryItem.Name -ErrorAction Stop
            $currentValue = $item.($registryItem.Name)
            $exists = $true
        } catch {
            $exists = $false
        }

        $entry.Registry += [ordered]@{
            Path = $registryItem.Path
            Name = $registryItem.Name
            Type = $registryItem.Type
            Exists = $exists
            Value = if ($exists) { [string]$currentValue } else { $null }
        }
    }

    foreach ($serviceItem in @($tweakConfig.service)) {
        if (-not $serviceItem) { continue }
        try {
            $service = Get-Service -Name $serviceItem.Name -ErrorAction Stop
            $entry.Service += [ordered]@{
                Name = $serviceItem.Name
                StartupType = [string]$service.StartType
            }
        } catch {
            $entry.Service += [ordered]@{
                Name = $serviceItem.Name
                StartupType = "<NotFound>"
            }
        }
    }

    foreach ($taskItem in @($tweakConfig.ScheduledTask)) {
        if (-not $taskItem) { continue }
        $taskState = "<NotFound>"
        try {
            $task = Get-ScheduledTask -TaskName $taskItem.Name -ErrorAction Stop
            $taskState = if ($task.State -eq "Disabled") { "Disabled" } else { "Enabled" }
        } catch {
            $taskState = "<NotFound>"
        }

        $entry.ScheduledTask += [ordered]@{
            Name = $taskItem.Name
            OriginalState = $taskState
        }
    }

    $journalPath = Get-WinUtilRollbackJournalPath
    ($entry | ConvertTo-Json -Depth 5 -Compress) | Add-Content -Path $journalPath -Encoding ascii
}

function Invoke-WinUtilRollbackLatest {
    param(
        [string]$CheckBox
    )

    $journalPath = Get-WinUtilRollbackJournalPath
    if (-not (Test-Path $journalPath)) {
        Write-Warning "No rollback journal exists."
        return $false
    }

    $entries = Get-Content -Path $journalPath -ErrorAction SilentlyContinue
    if (-not $entries -or $entries.Count -eq 0) {
        Write-Warning "Rollback journal is empty."
        return $false
    }

    $parsedEntries = $entries | ForEach-Object { $_ | ConvertFrom-Json }
    $target = if ([string]::IsNullOrWhiteSpace($CheckBox)) {
        $parsedEntries | Select-Object -Last 1
    } else {
        $parsedEntries | Where-Object { $_.CheckBox -eq $CheckBox } | Select-Object -Last 1
    }

    if (-not $target) {
        Write-Warning "No rollback snapshot found for '$CheckBox'."
        return $false
    }

    foreach ($registryItem in @($target.Registry)) {
        $value = if ($registryItem.Exists) { $registryItem.Value } else { "<RemoveEntry>" }
        Set-WinUtilRegistry -Name $registryItem.Name -Path $registryItem.Path -Type $registryItem.Type -Value $value
    }

    foreach ($serviceItem in @($target.Service)) {
        if ($serviceItem.StartupType -and $serviceItem.StartupType -ne "<NotFound>") {
            Set-WinUtilService -Name $serviceItem.Name -StartupType $serviceItem.StartupType
        }
    }

    foreach ($taskItem in @($target.ScheduledTask)) {
        if ($taskItem.OriginalState -and $taskItem.OriginalState -ne "<NotFound>") {
            Set-WinUtilScheduledTask -Name $taskItem.Name -State $taskItem.OriginalState
        }
    }

    Write-Host "Rollback restored state for $($target.CheckBox)"
    return $true
}

function Get-WinUtilAutoReapplyScriptPath {
    if (-not $sync.asysdir) {
        $sync.asysdir = Join-Path $env:LocalAppData "asys"
    }

    return (Join-Path $sync.asysdir "auto-reapply.ps1")
}

function Register-WinUtilAutoReapplyTask {
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    $profilePath = Save-WinUtilProfile -Name $ProfileName
    $bootstrapScriptPath = Get-WinUtilAutoReapplyScriptPath
    $deployUrl = if ($env:ASYS_DEPLOY_URL) { $env:ASYS_DEPLOY_URL } else { "https://myutil.advancesystems4042.com/?token=covxo5-nyrmUh-rodgac" }
    $escapedProfilePath = $profilePath.Replace("'", "''")
    $escapedUrl = $deployUrl.Replace("'", "''")

    @(
        "`$ErrorActionPreference = 'Stop'"
        "`$scriptText = Invoke-RestMethod -Uri '$escapedUrl'"
        "`$runner = [scriptblock]::Create(`$scriptText)"
        "& `$runner -Config '$escapedProfilePath' -Run -NoUI"
    ) | Out-File -Path $bootstrapScriptPath -Encoding ascii -Force

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bootstrapScriptPath`""
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask -TaskName "ASYS_AutoReapply_Logon" -Action $action -Trigger $logonTrigger -Settings $settings -RunLevel Highest -Force | Out-Null
    Register-ScheduledTask -TaskName "ASYS_AutoReapply_Startup" -Action $action -Trigger $startupTrigger -Settings $settings -RunLevel Highest -Force | Out-Null
}

function Unregister-WinUtilAutoReapplyTask {
    $taskNames = @("ASYS_AutoReapply_Logon", "ASYS_AutoReapply_Startup")
    foreach ($taskName in $taskNames) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    $bootstrapScriptPath = Get-WinUtilAutoReapplyScriptPath
    if (Test-Path $bootstrapScriptPath) {
        Remove-Item -Path $bootstrapScriptPath -Force
    }
}

function Get-WinUtilActivationStatus {
    $windowsProducts = Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "Windows*" -and $_.PartialProductKey
    }
    $officeProducts = Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "*Office*" -and $_.PartialProductKey
    }

    $windowsLicensed = ($windowsProducts | Where-Object { $_.LicenseStatus -eq 1 }).Count -gt 0
    $officeLicensed = ($officeProducts | Where-Object { $_.LicenseStatus -eq 1 }).Count -gt 0

    [PSCustomObject]@{
        CheckedAt = (Get-Date).ToString("s")
        Windows = if ($windowsLicensed) { "Activated" } else { "Not Activated" }
        Office = if ($officeLicensed) { "Activated" } else { "Not Activated" }
        WindowsProducts = @($windowsProducts | Select-Object -First 3 -ExpandProperty Name)
        OfficeProducts = @($officeProducts | Select-Object -First 3 -ExpandProperty Name)
    }
}

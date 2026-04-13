function Invoke-WPFAutoReapplyEnable {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { "AutoReapply" }
    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Profile name for scheduled reapply:", "Enable Auto Reapply", $defaultName)
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        return
    }

    try {
        Register-WinUtilAutoReapplyTask -ProfileName $profileName
        [System.Windows.MessageBox]::Show("Auto reapply enabled. Scheduled tasks were created for startup and logon using profile '$profileName'.", "A-SYS_clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to enable auto reapply: $($_.Exception.Message)", "A-SYS_clark", "OK", "Error")
    }
}

function Invoke-WPFAutoReapplyDisable {
    try {
        Unregister-WinUtilAutoReapplyTask
        [System.Windows.MessageBox]::Show("Auto reapply scheduled tasks have been removed.", "A-SYS_clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to disable auto reapply: $($_.Exception.Message)", "A-SYS_clark", "OK", "Error")
    }
}

function Invoke-WPFProfileSave {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { "MyProfile" }
    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Profile name to save current selections:", "Save Profile", $defaultName)
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        return
    }

    try {
        Save-WinUtilProfile -Name $profileName | Out-Null
        [System.Windows.MessageBox]::Show("Profile '$profileName' saved.", "A-SYS_clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to save profile: $($_.Exception.Message)", "A-SYS_clark", "OK", "Error")
    }
}

function Invoke-WPFProfileLoad {
    $profiles = @(Get-WinUtilProfiles)
    if ($profiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No saved profiles were found.", "A-SYS_clark", "OK", "Warning")
        return
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { $profiles[0] }
    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Available profiles: $($profiles -join ', ')`nEnter profile name to load:", "Load Profile", $defaultName)
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        return
    }

    try {
        Import-WinUtilProfile -Name $profileName -ApplyToUI
        [System.Windows.MessageBox]::Show("Profile '$profileName' loaded.", "A-SYS_clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to load profile: $($_.Exception.Message)", "A-SYS_clark", "OK", "Error")
    }
}

function Invoke-WPFProfileDelete {
    $profiles = @(Get-WinUtilProfiles)
    if ($profiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No saved profiles were found.", "A-SYS_clark", "OK", "Warning")
        return
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Available profiles: $($profiles -join ', ')`nEnter profile name to delete:", "Delete Profile", $profiles[0])
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        return
    }

    try {
        Remove-WinUtilProfile -Name $profileName
        [System.Windows.MessageBox]::Show("Profile '$profileName' deleted.", "A-SYS_clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to delete profile: $($_.Exception.Message)", "A-SYS_clark", "OK", "Error")
    }
}

function Invoke-WPFRollbackLastTweak {
    try {
        $restored = Invoke-WinUtilRollbackLatest
        if ($restored) {
            [System.Windows.MessageBox]::Show("Last tweak snapshot was restored from rollback journal.", "A-SYS_clark", "OK", "Information")
        } else {
            [System.Windows.MessageBox]::Show("No rollback snapshot could be restored.", "A-SYS_clark", "OK", "Warning")
        }
    } catch {
        [System.Windows.MessageBox]::Show("Rollback failed: $($_.Exception.Message)", "A-SYS_clark", "OK", "Error")
    }
}

function Get-WinUtilActivationScriptsRoot {
    $candidateRoots = @(
        (Join-Path $sync.PSScriptRoot "Microsoft-Activation-Scripts-master"),
        (Join-Path (Get-Location).Path "Microsoft-Activation-Scripts-master")
    )

    foreach ($candidate in $candidateRoots) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Invoke-WPFActivationScriptsMenu {
    try {
        $masRoot = Get-WinUtilActivationScriptsRoot
        if (-not $masRoot) {
            throw "Microsoft-Activation-Scripts-master folder was not found near A-SYS_clark."
        }

        $masAioPath = Join-Path $masRoot "MAS\All-In-One-Version-KL\MAS_AIO.cmd"
        if (-not (Test-Path $masAioPath)) {
            throw "MAS menu script was not found: $masAioPath"
        }

        Start-Process -FilePath $masAioPath
    } catch {
        [System.Windows.MessageBox]::Show("Unable to open MAS menu: $($_.Exception.Message)", "A-SYS_clark", "OK", "Error")
    }
}

function Invoke-WPFActivationStatus {
    try {
        $masRoot = Get-WinUtilActivationScriptsRoot
        if (-not $masRoot) {
            throw "Microsoft-Activation-Scripts-master folder was not found near A-SYS_clark."
        }

        $statusScriptPath = Join-Path $masRoot "MAS\Separate-Files-Version\Check_Activation_Status.cmd"
        if (-not (Test-Path $statusScriptPath)) {
            throw "MAS activation status script was not found: $statusScriptPath"
        }

        Start-Process -FilePath $statusScriptPath
    } catch {
        [System.Windows.MessageBox]::Show("Activation check failed: $($_.Exception.Message)", "A-SYS_clark", "OK", "Error")
    }
}

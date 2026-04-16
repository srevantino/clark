function Invoke-WPFStartupManager {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function Get-StartupEntries {
        $list = [System.Collections.Generic.List[object]]::new()

        $runPaths = @(
            @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; L = 'HKCU Run' },
            @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; L = 'HKCU RunOnce' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; L = 'HKLM Run' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; L = 'HKLM RunOnce' },
            @{ P = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; L = 'HKLM WOW Run' }
        )
        foreach ($rp in $runPaths) {
            if (-not (Test-Path -LiteralPath $rp.P)) { continue }
            $props = Get-ItemProperty -LiteralPath $rp.P -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            foreach ($n in $props.PSObject.Properties) {
                if ($n.Name -match '^PS') { continue }
                if ($n.Name -eq '(default)') { continue }
                $cmd = [string]$n.Value
                if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
                $pub = ""
                $exePath = $cmd
                if ($cmd -match '^"([^"]+)"') {
                    $exePath = $matches[1]
                } elseif ($cmd -match '^(\S+\.exe)') {
                    $exePath = $matches[1]
                }
                if (Test-Path -LiteralPath $exePath.Trim('"')) {
                    try {
                        $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath.Trim('"'))
                        $pub = $ver.CompanyName
                    } catch { }
                }
                [void]$list.Add([pscustomobject]@{
                        Kind     = 'RunKey'
                        Location = $rp.L
                        RegPath  = $rp.P
                        Name     = $n.Name
                        Command  = $cmd
                        Publisher = $pub
                    })
            }
        }

        foreach ($folderKind in @('User', 'Common')) {
            $fd = if ($folderKind -eq 'User') {
                [Environment]::GetFolderPath('Startup')
            } else {
                [Environment]::GetFolderPath('CommonStartup')
            }
            if (-not (Test-Path -LiteralPath $fd)) { continue }
            Get-ChildItem -LiteralPath $fd -ErrorAction SilentlyContinue | ForEach-Object {
                $target = $_.FullName
                if ($_.Extension -eq '.lnk') {
                    try {
                        $sh = New-Object -ComObject WScript.Shell
                        $sc = $sh.CreateShortcut($_.FullName)
                        $target = $sc.TargetPath
                    } catch { }
                }
                $pub = ""
                if ($target -and (Test-Path -LiteralPath $target)) {
                    try {
                        $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($target)
                        $pub = $ver.CompanyName
                    } catch { }
                }
                [void]$list.Add([pscustomobject]@{
                        Kind     = 'StartupFolder'
                        Location = "$folderKind Startup"
                        RegPath  = $fd
                        Name     = $_.Name
                        Command  = $target
                        Publisher = $pub
                    })
            }
        }
        return $list
    }

    function Move-StartupFolderItemDisabled {
        param($item)
        $disabledRoot = Join-Path $env:LOCALAPPDATA "asys\StartupDisabled"
        if (-not (Test-Path $disabledRoot)) {
            New-Item -ItemType Directory -Path $disabledRoot -Force | Out-Null
        }
        $src = Join-Path $item.RegPath $item.Name
        $dst = Join-Path $disabledRoot $item.Name
        Move-Item -LiteralPath $src -Destination $dst -Force
    }

    function Move-StartupFolderItemEnabled {
        param($item)
        $disabledRoot = Join-Path $env:LOCALAPPDATA "asys\StartupDisabled"
        $src = Join-Path $disabledRoot $item.Name
        $dst = Join-Path $item.RegPath $item.Name
        if (Test-Path -LiteralPath $src) {
            Move-Item -LiteralPath $src -Destination $dst -Force
        }
    }

    function Set-RunKeyDisabled {
        param($item)
        $backup = 'HKCU:\Software\Clark\DisabledStartup'
        if (-not (Test-Path $backup)) {
            New-Item -Path $backup -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $backup -Name $item.Name -Value $item.Command -Type String -Force
        Remove-ItemProperty -LiteralPath $item.RegPath -Name $item.Name -ErrorAction Stop
    }

    function Set-RunKeyEnabled {
        param($item)
        $backup = 'HKCU:\Software\Clark\DisabledStartup'
        $prop = Get-ItemProperty -LiteralPath $backup -ErrorAction Stop
        $cmd = $prop.$($item.Name)
        if ([string]::IsNullOrWhiteSpace([string]$cmd)) { throw "No backup value for $($item.Name)." }
        Set-ItemProperty -LiteralPath $item.RegPath -Name $item.Name -Value $cmd -Type String -Force
        Remove-ItemProperty -LiteralPath $backup -Name $item.Name -ErrorAction SilentlyContinue
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Clark — Startup manager"
    $form.Size = New-Object System.Drawing.Size(900, 520)
    $form.StartPosition = "CenterScreen"

    $dg = New-Object System.Windows.Forms.DataGridView
    $dg.Dock = "Fill"
    $dg.ReadOnly = $true
    $dg.AutoGenerateColumns = $false
    $dg.SelectionMode = "FullRowSelect"
    $dg.MultiSelect = $false
    [void]$dg.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn @{ Name = 'Kind'; HeaderText = 'Kind'; Width = 90 }))
    [void]$dg.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn @{ Name = 'Location'; HeaderText = 'Location'; Width = 120 }))
    [void]$dg.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn @{ Name = 'Name'; HeaderText = 'Name'; Width = 140 }))
    [void]$dg.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn @{ Name = 'Command'; HeaderText = 'Executable / command'; Width = 360 }))
    [void]$dg.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn @{ Name = 'Publisher'; HeaderText = 'Publisher'; Width = 120 }))
    $dg.Tag = [System.Collections.Generic.List[object]]::new()

    function Refresh-Grid {
        $dg.Rows.Clear()
        $dg.Tag.Clear()
        foreach ($e in @(Get-StartupEntries)) {
            [void]$dg.Tag.Add($e)
            [void]$dg.Rows.Add(@($e.Kind, $e.Location, $e.Name, $e.Command, $e.Publisher))
        }
    }

    Refresh-Grid

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = "Bottom"
    $flow.Height = 40

    $btnDis = New-Object System.Windows.Forms.Button
    $btnDis.Text = "Disable selected"
    $btnDis.Add_Click({
        if ($dg.SelectedRows.Count -eq 0) { return }
        $idx = $dg.SelectedRows[0].Index
        $item = $dg.Tag[$idx]
        try {
            if ($item.Kind -eq 'RunKey') {
                if ($item.RegPath -like 'HKLM:*') {
                    [System.Windows.Forms.MessageBox]::Show("Disabling HKLM Run entries requires manual policy or running elevated scripts. Only HKCU Run keys are auto-disabled here.", "clark", "OK", "Information")
                    return
                }
                Set-RunKeyDisabled -item $item
            } else {
                Move-StartupFolderItemDisabled -item $item
            }
            Refresh-Grid
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Disable", "OK", "Error")
        }
    })
    [void]$flow.Controls.Add($btnDis)

    $btnEn = New-Object System.Windows.Forms.Button
    $btnEn.Text = "Enable (restore)"
    $btnEn.Add_Click({
        if ($dg.SelectedRows.Count -eq 0) { return }
        $idx = $dg.SelectedRows[0].Index
        $item = $dg.Tag[$idx]
        try {
            if ($item.Kind -eq 'RunKey') {
                if ($item.RegPath -like 'HKLM:*') { return }
                Set-RunKeyEnabled -item $item
            } else {
                Move-StartupFolderItemEnabled -item $item
            }
            Refresh-Grid
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Enable", "OK", "Error")
        }
    })
    [void]$flow.Controls.Add($btnEn)

    $btnRef = New-Object System.Windows.Forms.Button
    $btnRef.Text = "Refresh"
    $btnRef.Add_Click({ Refresh-Grid })
    [void]$flow.Controls.Add($btnRef)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Add_Click({ $form.Close() })
    [void]$flow.Controls.Add($btnClose)

    [void]$form.Controls.Add($flow)
    [void]$form.Controls.Add($dg)
    [void]$form.ShowDialog()
}

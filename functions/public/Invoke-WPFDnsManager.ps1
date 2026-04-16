function Invoke-WPFDnsManager {
    <#
    .SYNOPSIS
        DNS presets per adapter or all adapters, plus DHCP reset.
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $providers = @("DHCP") + @($sync.configs.dns.PSObject.Properties.Name | Sort-Object) + @("Custom")

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Clark — DNS manager"
    $form.Size = New-Object System.Drawing.Size(640, 520)
    $form.StartPosition = "CenterScreen"

    $y = 12
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(12, $y)
    $lbl.Size = New-Object System.Drawing.Size(600, 36)
    $lbl.Text = "Select adapters, a preset (Cloudflare, Google, Quad9, …), or Custom. Apply sets DNS; DHCP resets both IPv4 and IPv6 where supported."
    [void]$form.Controls.Add($lbl)
    $y += 44

    $cbAll = New-Object System.Windows.Forms.CheckBox
    $cbAll.Text = "Select all adapters (including not Up)"
    $cbAll.Location = New-Object System.Drawing.Point(12, $y)
    $cbAll.Width = 400
    [void]$form.Controls.Add($cbAll)
    $y += 28

    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Location = New-Object System.Drawing.Point(12, $y)
    $list.Size = New-Object System.Drawing.Size(600, 160)
    $ifIndexByRow = [System.Collections.Generic.List[int]]::new()
    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $label = "$($a.Name)  [ifIndex $($a.ifIndex)]  $($a.Status)"
        [void]$list.Items.Add($label, ($a.Status -eq 'Up'))
        [void]$ifIndexByRow.Add($a.ifIndex)
    }
    $list.Tag = $ifIndexByRow
    [void]$form.Controls.Add($list)
    $y += 168

    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text = "Preset:"
    $lblP.Location = New-Object System.Drawing.Point(12, $y)
    $lblP.AutoSize = $true
    [void]$form.Controls.Add($lblP)
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = "DropDownList"
    $combo.Location = New-Object System.Drawing.Point(80, $y - 2)
    $combo.Width = 200
    foreach ($p in $providers) { [void]$combo.Items.Add($p) }
    $combo.SelectedIndex = [math]::Max(0, $combo.Items.IndexOf("Cloudflare"))
    if ($combo.SelectedIndex -lt 0) { $combo.SelectedIndex = 0 }
    [void]$form.Controls.Add($combo)
    $y += 32

    $lblC = New-Object System.Windows.Forms.Label
    $lblC.Text = "Custom IPv4 (primary / secondary):"
    $lblC.Location = New-Object System.Drawing.Point(12, $y)
    $lblC.Width = 260
    [void]$form.Controls.Add($lblC)
    $y += 22
    $tPri = New-Object System.Windows.Forms.TextBox
    $tPri.Location = New-Object System.Drawing.Point(12, $y)
    $tPri.Width = 120
    [void]$form.Controls.Add($tPri)
    $tSec = New-Object System.Windows.Forms.TextBox
    $tSec.Location = New-Object System.Drawing.Point(140, $y)
    $tSec.Width = 120
    [void]$form.Controls.Add($tSec)
    $y += 34

    $lbl6 = New-Object System.Windows.Forms.Label
    $lbl6.Text = "Custom IPv6 (optional, primary / secondary):"
    $lbl6.Location = New-Object System.Drawing.Point(12, $y)
    $lbl6.Width = 360
    [void]$form.Controls.Add($lbl6)
    $y += 22
    $t6p = New-Object System.Windows.Forms.TextBox
    $t6p.Location = New-Object System.Drawing.Point(12, $y)
    $t6p.Width = 240
    [void]$form.Controls.Add($t6p)
    $t6s = New-Object System.Windows.Forms.TextBox
    $t6s.Location = New-Object System.Drawing.Point(260, $y)
    $t6s.Width = 240
    [void]$form.Controls.Add($t6s)
    $y += 44

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "Apply to selected adapters"
    $btnApply.Location = New-Object System.Drawing.Point(12, $y)
    $btnApply.Width = 220
    $btnApply.Add_Click({
        $indexes = [System.Collections.Generic.List[int]]::new()
        $rows = [System.Collections.Generic.List[int]]$list.Tag
        for ($i = 0; $i -lt $list.Items.Count; $i++) {
            if ($list.GetItemChecked($i)) {
                [void]$indexes.Add([int]$rows[$i])
            }
        }
        if ($indexes.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Check at least one adapter.", "clark", "OK", "Information")
            return
        }
        $prov = [string]$combo.SelectedItem
        if ($prov -eq "Custom" -and [string]::IsNullOrWhiteSpace($tPri.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Enter at least a primary custom IPv4 address.", "clark", "OK", "Warning")
            return
        }
        try {
            if ($prov -eq "Custom") {
                Set-WinUtilDNS -DNSProvider Custom -InterfaceIndex $indexes.ToArray() `
                    -CustomPrimaryV4 $tPri.Text.Trim() -CustomSecondaryV4 $tSec.Text.Trim() `
                    -CustomPrimaryV6 $t6p.Text.Trim() -CustomSecondaryV6 $t6s.Text.Trim()
            } else {
                Set-WinUtilDNS -DNSProvider $prov -InterfaceIndex $indexes.ToArray()
            }
            [System.Windows.Forms.MessageBox]::Show("DNS update finished. See console output for details.", "clark", "OK", "Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "clark", "OK", "Error")
        }
    })
    [void]$form.Controls.Add($btnApply)

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = "Apply preset to ALL adapters"
    $btnAll.Location = New-Object System.Drawing.Point(240, $y)
    $btnAll.Width = 220
    $btnAll.Add_Click({
        $prov = [string]$combo.SelectedItem
        if ($prov -eq "Custom" -and [string]::IsNullOrWhiteSpace($tPri.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Enter at least a primary custom IPv4 address.", "clark", "OK", "Warning")
            return
        }
        try {
            if ($prov -eq "Custom") {
                Set-WinUtilDNS -DNSProvider Custom -AllAdapters `
                    -CustomPrimaryV4 $tPri.Text.Trim() -CustomSecondaryV4 $tSec.Text.Trim() `
                    -CustomPrimaryV6 $t6p.Text.Trim() -CustomSecondaryV6 $t6s.Text.Trim()
            } else {
                Set-WinUtilDNS -DNSProvider $prov -AllAdapters
            }
            [System.Windows.Forms.MessageBox]::Show("DNS update applied to all adapters.", "clark", "OK", "Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "clark", "OK", "Error")
        }
    })
    [void]$form.Controls.Add($btnAll)
    $y += 40

    $cbAll.Add_CheckedChanged({
        if ($cbAll.Checked) {
            for ($i = 0; $i -lt $list.Items.Count; $i++) {
                $list.SetItemChecked($i, $true)
            }
        }
    })

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(520, $y)
    $btnClose.Add_Click({ $form.Close() })
    [void]$form.Controls.Add($btnClose)

    [void]$form.ShowDialog()
}

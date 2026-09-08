<#
.SYNOPSIS
    Game Save Sync Engine - Fully Customizable GUI
.DESCRIPTION
    A full Windows Forms application for syncing game saves.
    Includes a built-in Custom Path Mapping editor to visually route 
    Linux/Wine prefixes to specific Windows folders.
#>

$ErrorActionPreference = "Continue"

# Load Windows GUI Assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==============================================================================
# ENVIRONMENT SETUP & CONFIGURATION
# ==============================================================================
$Workspace    = $PSScriptRoot
$ConfigFile   = Join-Path $Workspace "game_sync_settings.cfg"
$TargetsFile  = Join-Path $Workspace "game_save_sync_list.txt"
$MappingsFile = Join-Path $Workspace "game_path_mappings.txt"

# Ensure config files exist
if (-not (Test-Path $TargetsFile)) { New-Item -Path $TargetsFile -ItemType File -Force | Out-Null }
if (-not (Test-Path $ConfigFile)) {
    Set-Content -Path $ConfigFile -Value "NAS_DIRECTORY=Z:\_Saves Backups" -Force
}
if (-not (Test-Path $MappingsFile)) {
    # Provide a default example so the user understands the format
    $DefaultMap = "/home/amd/Games/Heroic/Prefixes/Shared/drive_c/users/steamuser/ | $env:USERPROFILE"
    Set-Content -Path $MappingsFile -Value $DefaultMap -Force
}

# Parse Main Config
$GlobalSettings = @{}
Get-Content $ConfigFile | Where-Object { $_ -match '=' } | ForEach-Object {
    $Key, $Value = $_ -split '=', 2
    $GlobalSettings[$Key.Trim()] = $Value.Trim()
}

# ==============================================================================
# PATH TRANSLATION & LOGIC
# ==============================================================================
function Load-Mappings {
    $Map = @{}
    if (Test-Path $MappingsFile) {
        Get-Content $MappingsFile | Where-Object { $_ -match '\|' } | ForEach-Object {
            $Parts = $_ -split '\|', 2
            $LinuxPrefix = $Parts[0].Trim().TrimEnd('/')
            $WindowsPath = $Parts[1].Trim().TrimEnd('\')
            if ($LinuxPrefix -ne '') { $Map[$LinuxPrefix] = $WindowsPath }
        }
    }
    return $Map
}

function Format-LinuxToWindows([string]$RawPath) {
    $CleanPath = $RawPath.Trim().TrimEnd('/')
    $Mappings = Load-Mappings
    
    # Sort keys by length descending (Most specific/longest prefix matches first)
    $SortedKeys = $Mappings.Keys | Sort-Object Length -Descending

    foreach ($Key in $SortedKeys) {
        if ($CleanPath.StartsWith($Key)) {
            $WinPrefix = $Mappings[$Key]
            $Remainder = $CleanPath.Substring($Key.Length).Replace('/', '\')
            
            if ($Remainder.StartsWith('\') -or $Remainder -eq '') {
                return "$WinPrefix$Remainder"
            } else {
                return "$WinPrefix\$Remainder"
            }
        }
    }
    
    # Fallback if no mapping matches at all
    return $CleanPath.Replace('/', '\')
}

function Get-ParsedTargets() {
    $ParsedList = @()
    if (Test-Path $TargetsFile) {
        $RawLines = Get-Content $TargetsFile | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' }
        foreach ($Line in $RawLines) {
            $Fragments = $Line -split ','
            $OriginalPath = $Fragments[0].Trim()
            $TargetName = if ($Fragments.Count -gt 1) { $Fragments[1].Trim() } else { [System.IO.Path]::GetFileName($OriginalPath.TrimEnd('/')) }
            
            $ParsedList += [PSCustomObject]@{
                DisplayName = $TargetName
                WindowsPath = Format-LinuxToWindows -RawPath $OriginalPath
            }
        }
    }
    return $ParsedList
}

function Get-LatestModification([string]$FolderPath) {
    if (-not (Test-Path $FolderPath -ErrorAction SilentlyContinue)) { return $null }
    $Latest = Get-ChildItem -Path $FolderPath -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return $Latest.LastWriteTime
}

# ==============================================================================
# SUB-GUI: MAPPING EDITOR
# ==============================================================================
function Show-MappingEditor {
    $MapForm = New-Object System.Windows.Forms.Form
    $MapForm.Text = "Manage Path Mappings"
    $MapForm.Size = New-Object System.Drawing.Size(600, 450)
    $MapForm.StartPosition = "CenterParent"
    $MapForm.FormBorderStyle = "FixedDialog"
    $MapForm.MaximizeBox = $false
    $MapForm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
    $MapForm.ForeColor = [System.Drawing.Color]::White

    $LblInfo = New-Object System.Windows.Forms.Label
    $LblInfo.Text = "Map Linux/Wine paths to Windows targets. Longest prefixes process first."
    $LblInfo.Location = New-Object System.Drawing.Point(15, 10)
    $LblInfo.Size = New-Object System.Drawing.Size(550, 20)
    $MapForm.Controls.Add($LblInfo)

    $ListMappings = New-Object System.Windows.Forms.ListBox
    $ListMappings.Location = New-Object System.Drawing.Point(15, 35)
    $ListMappings.Size = New-Object System.Drawing.Size(550, 180)
    $ListMappings.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 48)
    $ListMappings.ForeColor = [System.Drawing.Color]::White
    if (Test-Path $MappingsFile) {
        Get-Content $MappingsFile | Where-Object { $_ -match '\|' } | ForEach-Object { $ListMappings.Items.Add($_) | Out-Null }
    }
    $MapForm.Controls.Add($ListMappings)

    $LblLin = New-Object System.Windows.Forms.Label
    $LblLin.Text = "Linux Prefix (e.g. /home/amd/):"
    $LblLin.Location = New-Object System.Drawing.Point(15, 225)
    $LblLin.AutoSize = $true
    $MapForm.Controls.Add($LblLin)

    $TxtLin = New-Object System.Windows.Forms.TextBox
    $TxtLin.Location = New-Object System.Drawing.Point(15, 245)
    $TxtLin.Size = New-Object System.Drawing.Size(550, 25)
    $MapForm.Controls.Add($TxtLin)

    $LblWin = New-Object System.Windows.Forms.Label
    $LblWin.Text = "Windows Target (e.g. C:\Users\YourName):"
    $LblWin.Location = New-Object System.Drawing.Point(15, 275)
    $LblWin.AutoSize = $true
    $MapForm.Controls.Add($LblWin)

    $TxtWin = New-Object System.Windows.Forms.TextBox
    $TxtWin.Location = New-Object System.Drawing.Point(15, 295)
    $TxtWin.Size = New-Object System.Drawing.Size(460, 25)
    $MapForm.Controls.Add($TxtWin)

    $BtnBrowse = New-Object System.Windows.Forms.Button
    $BtnBrowse.Text = "Browse"
    $BtnBrowse.Location = New-Object System.Drawing.Point(485, 294)
    $BtnBrowse.Size = New-Object System.Drawing.Size(80, 25)
    $BtnBrowse.ForeColor = [System.Drawing.Color]::Black
    $BtnBrowse.Add_Click({
        $FBD = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($FBD.ShowDialog() -eq 'OK') { $TxtWin.Text = $FBD.SelectedPath }
    })
    $MapForm.Controls.Add($BtnBrowse)

    $BtnAdd = New-Object System.Windows.Forms.Button
    $BtnAdd.Text = "Add / Update Rule"
    $BtnAdd.Location = New-Object System.Drawing.Point(15, 335)
    $BtnAdd.Size = New-Object System.Drawing.Size(150, 40)
    $BtnAdd.ForeColor = [System.Drawing.Color]::Black
    $BtnAdd.Add_Click({
        if ($TxtLin.Text -ne "" -and $TxtWin.Text -ne "") {
            $NewRule = "$($TxtLin.Text.Trim()) | $($TxtWin.Text.Trim())"
            $ListMappings.Items.Add($NewRule) | Out-Null
            $TxtLin.Text = ""; $TxtWin.Text = ""
        }
    })
    $MapForm.Controls.Add($BtnAdd)

    $BtnRem = New-Object System.Windows.Forms.Button
    $BtnRem.Text = "Remove Selected"
    $BtnRem.Location = New-Object System.Drawing.Point(175, 335)
    $BtnRem.Size = New-Object System.Drawing.Size(150, 40)
    $BtnRem.ForeColor = [System.Drawing.Color]::Black
    $BtnRem.Add_Click({
        if ($ListMappings.SelectedIndex -ge 0) { $ListMappings.Items.RemoveAt($ListMappings.SelectedIndex) }
    })
    $MapForm.Controls.Add($BtnRem)

    $BtnSave = New-Object System.Windows.Forms.Button
    $BtnSave.Text = "Save & Close"
    $BtnSave.Location = New-Object System.Drawing.Point(415, 335)
    $BtnSave.Size = New-Object System.Drawing.Size(150, 40)
    $BtnSave.BackColor = [System.Drawing.Color]::LightGreen
    $BtnSave.ForeColor = [System.Drawing.Color]::Black
    $BtnSave.Add_Click({
        $Lines = @()
        foreach ($item in $ListMappings.Items) { $Lines += $item }
        Set-Content -Path $MappingsFile -Value $Lines -Force
        $MapForm.Close()
    })
    $MapForm.Controls.Add($BtnSave)

    $MapForm.ShowDialog() | Out-Null
}

# ==============================================================================
# MAIN GUI CONSTRUCTION (DARK THEME)
# ==============================================================================
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Game Save Sync Engine"
$Form.Size = New-Object System.Drawing.Size(530, 715)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false
$Form.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
$Form.ForeColor = [System.Drawing.Color]::White

$LblTitle = New-Object System.Windows.Forms.Label
$LblTitle.Text = "Select Saves to Sync"
$LblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$LblTitle.Location = New-Object System.Drawing.Point(15, 15)
$LblTitle.AutoSize = $true
$Form.Controls.Add($LblTitle)

$Checklist = New-Object System.Windows.Forms.CheckedListBox
$Checklist.Location = New-Object System.Drawing.Point(15, 45)
$Checklist.Size = New-Object System.Drawing.Size(480, 380)
$Checklist.CheckOnClick = $true
$Checklist.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 48)
$Checklist.ForeColor = [System.Drawing.Color]::White
$Checklist.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$Form.Controls.Add($Checklist)

# Load Items into Checklist Function
function Refresh-Checklist {
    $Checklist.Items.Clear()
    $script:GameList = Get-ParsedTargets
    foreach ($Game in $script:GameList) { $Checklist.Items.Add($Game.DisplayName) | Out-Null }
}
Refresh-Checklist

$LnkSelectAll = New-Object System.Windows.Forms.LinkLabel
$LnkSelectAll.Text = "Select All / None"
$LnkSelectAll.Location = New-Object System.Drawing.Point(15, 435)
$LnkSelectAll.AutoSize = $true
$LnkSelectAll.LinkColor = [System.Drawing.Color]::LightSkyBlue
$LnkSelectAll.ActiveLinkColor = [System.Drawing.Color]::DodgerBlue
$LnkSelectAll.Add_Click({
    $Toggle = $false
    if ($Checklist.CheckedItems.Count -eq 0) { $Toggle = $true }
    for ($i = 0; $i -lt $Checklist.Items.Count; $i++) { $Checklist.SetItemChecked($i, $Toggle) }
})
$Form.Controls.Add($LnkSelectAll)

$LblStatus = New-Object System.Windows.Forms.Label
$LblStatus.Text = "NAS Path: $($GlobalSettings['NAS_DIRECTORY'])"
$LblStatus.Location = New-Object System.Drawing.Point(15, 640)
$LblStatus.Size = New-Object System.Drawing.Size(480, 20)
$LblStatus.ForeColor = [System.Drawing.Color]::DarkGray
$Form.Controls.Add($LblStatus)

# --- SYNC LOGIC WRAPPER ---
function Run-Sync([string]$Mode, [switch]$All) {
    $TargetNames = @()
    if ($All) {
        foreach ($Item in $Checklist.Items) { $TargetNames += $Item }
    } else {
        foreach ($Item in $Checklist.CheckedItems) { $TargetNames += $Item }
    }

    if ($TargetNames.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one game to sync.", "No Selection", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $NasRoot = $GlobalSettings['NAS_DIRECTORY']

    foreach ($Name in $TargetNames) {
        $Item = $script:GameList | Where-Object { $_.DisplayName -eq $Name }
        $NasDest = Join-Path $NasRoot $Item.DisplayName
        $WinDest = $Item.WindowsPath

        $LblStatus.Text = "Syncing $Mode : $($Item.DisplayName)..."
        $Form.Refresh()

        # Overwrite protection for Restore
        if ($Mode -eq "Restore" -and (Test-Path $NasDest) -and (Test-Path $WinDest)) {
            $LocalTime = Get-LatestModification $WinDest
            $NasTime = Get-LatestModification $NasDest
            if ($null -ne $LocalTime -and $null -ne $NasTime -and $LocalTime -gt $NasTime) {
                $Msg = "Local saves for [$($Item.DisplayName)] are NEWER than the NAS backup.`n`nOverwrite local saves?"
                $Ans = [System.Windows.Forms.MessageBox]::Show($Msg, "Overwrite Warning", 4, [System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($Ans -ne "Yes") { continue }
            }
        }

        # Execution using Robocopy (Robust for UNC network paths)
        if ($Mode -eq "Backup" -and (Test-Path $WinDest)) {
            robocopy $WinDest $NasDest /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        } 
        elseif ($Mode -eq "Restore" -and (Test-Path $NasDest)) {
            robocopy $NasDest $WinDest /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        }
    }
    
    $LblStatus.Text = "Sync completed successfully!"
    [System.Windows.Forms.MessageBox]::Show("Synchronization finished successfully.", "Success", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
    $LblStatus.Text = "NAS Path: $($GlobalSettings['NAS_DIRECTORY'])"
}

# --- BUTTON CREATION HELPER ---
function Add-StyledButton($Text, $X, $Y, $Color, $Action) {
    $Btn = New-Object System.Windows.Forms.Button
    $Btn.Text = $Text
    $Btn.Location = New-Object System.Drawing.Point($X, $Y)
    $Btn.Size = New-Object System.Drawing.Size(150, 45)
    $Btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Btn.BackColor = $Color
    $Btn.ForeColor = [System.Drawing.Color]::White
    $Btn.FlatAppearance.BorderSize = 0
    $Btn.Add_Click($Action)
    $Form.Controls.Add($Btn)
    return $Btn
}

$ColorBackup  = [System.Drawing.Color]::FromArgb(255, 35, 75, 115)
$ColorRestore = [System.Drawing.Color]::FromArgb(255, 35, 115, 75)
$ColorEdit    = [System.Drawing.Color]::FromArgb(255, 75, 75, 75)
$ColorBrowse  = [System.Drawing.Color]::FromArgb(255, 115, 75, 35)
$ColorMap     = [System.Drawing.Color]::FromArgb(255, 115, 35, 115)

# Row 1: Selected Syncs
$null = Add-StyledButton "Backup Selected" 15 470 $ColorBackup { Run-Sync "Backup" -All:$false }
$null = Add-StyledButton "Restore Selected" 175 470 $ColorRestore { Run-Sync "Restore" -All:$false }
$null = Add-StyledButton "Edit Save List (.txt)" 335 470 $ColorEdit { Start-Process "notepad.exe" $TargetsFile }

# Row 2: All Syncs & Settings
$null = Add-StyledButton "Backup ALL" 15 525 $ColorBackup { Run-Sync "Backup" -All:$true }
$null = Add-StyledButton "Restore ALL" 175 525 $ColorRestore { Run-Sync "Restore" -All:$true }
$null = Add-StyledButton "Select NAS Folder" 335 525 $ColorBrowse {
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowser.Description = "Select your NAS Save Backup Directory"
    if (Test-Path $GlobalSettings['NAS_DIRECTORY']) { $FolderBrowser.SelectedPath = $GlobalSettings['NAS_DIRECTORY'] }

    if ($FolderBrowser.ShowDialog() -eq 'OK') {
        $NewPath = $FolderBrowser.SelectedPath
        $GlobalSettings['NAS_DIRECTORY'] = $NewPath
        Set-Content -Path $ConfigFile -Value "NAS_DIRECTORY=$NewPath" -Force
        $LblStatus.Text = "NAS Path: $NewPath"
    }
}

# Row 3: Custom Mappings
$BtnMap = Add-StyledButton "Manage Path Mappings" 15 580 $ColorMap {
    Show-MappingEditor
    Refresh-Checklist # Refresh translations after editing
}
$BtnMap.Size = New-Object System.Drawing.Size(470, 45) # Make it full width

# Show App
[System.Windows.Forms.Application]::EnableVisualStyles()
$Form.ShowDialog() | Out-Null
# TGFR Exam Mode 7.0.2: adaptive WinForms interface. Requires Windows PowerShell 5.1.
# Engine functions are supplied by the containing BAT; this module makes no changes on load.
function Show-TgfrInterface {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'TGFR Exam Mode | 7.0.2'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'Sizable'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)
    $area = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
    $form.Size = New-Object System.Drawing.Size([Math]::Min(780, $area.Width - 32), [Math]::Min(650, $area.Height - 32))
    $form.MinimumSize = New-Object System.Drawing.Size([Math]::Min(600, $area.Width - 32), [Math]::Min(420, $area.Height - 32))

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'; $root.ColumnCount = 1; $root.RowCount = 3
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    $form.Controls.Add($root)

    $ui = @{ Form = $form; Busy = $false; Checks = [ordered]@{}; Wrapping = @(); Active = $false; LastMessage = ''; LastColor = [System.Drawing.Color]::FromArgb(43, 64, 88); VerificationLines = @(); LogLines = $script:TgfrLogLines }
    function New-TgfrUiLabel([string]$Text, [int]$Size = 9, [bool]$Bold = $false) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Text; $label.AutoSize = $true; $label.Dock = 'Top'
        $label.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 5)
        $style = [System.Drawing.FontStyle]::Regular
        if ($Bold) { $style = [System.Drawing.FontStyle]::Bold }
        $label.Font = New-Object System.Drawing.Font('Segoe UI', $Size, $style)
        $label.MaximumSize = New-Object System.Drawing.Size(640, 0)
        return $label
    }
    function New-TgfrUiButton([string]$Text) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text; $button.AutoSize = $true
        $button.MinimumSize = New-Object System.Drawing.Size(100, 31)
        $button.Padding = New-Object System.Windows.Forms.Padding(8, 3, 8, 3)
        $button.Margin = New-Object System.Windows.Forms.Padding(0, 3, 8, 3)
        return $button
    }
    function New-TgfrUiScrollPage([string]$Title) {
        $page = New-Object System.Windows.Forms.TabPage
        $page.Text = $Title; $page.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)
        $scroll = New-Object System.Windows.Forms.Panel
        $scroll.Dock = 'Fill'; $scroll.AutoScroll = $true
        $scroll.Padding = New-Object System.Windows.Forms.Padding(12)
        $table = New-Object System.Windows.Forms.TableLayoutPanel
        $table.AutoSize = $true; $table.AutoSizeMode = 'GrowAndShrink'; $table.Dock = 'Top'
        $table.ColumnCount = 1; $table.RowCount = 0
        [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
        $scroll.Controls.Add($table); $page.Controls.Add($scroll)
        return @{ Page = $page; Scroll = $scroll; Table = $table }
    }
    function Add-TgfrUiRow($Table, $Control) {
        $row = $Table.RowCount; $Table.RowCount++
        [void]$Table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
        $Control.Dock = 'Top'; $Table.Controls.Add($Control, 0, $row)
    }

    $header = New-Object System.Windows.Forms.TableLayoutPanel
    $header.Dock = 'Fill'; $header.AutoSize = $true; $header.ColumnCount = 1
    [void]$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    $header.Padding = New-Object System.Windows.Forms.Padding(18, 10, 18, 8)
    $header.Margin = New-Object System.Windows.Forms.Padding(0)
    $header.BackColor = [System.Drawing.Color]::FromArgb(24, 43, 68)
    $heading = New-TgfrUiLabel 'TGFR  |  EXAM MODE' 17 $true
    $heading.ForeColor = [System.Drawing.Color]::White
    $intro = New-TgfrUiLabel 'Choose restrictions, verify the applied settings, then restore after the exam.'
    $intro.ForeColor = [System.Drawing.Color]::FromArgb(215, 225, 238)
    Add-TgfrUiRow $header $heading; Add-TgfrUiRow $header $intro
    $root.Controls.Add($header, 0, 0)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'; $tabs.Margin = New-Object System.Windows.Forms.Padding(10, 8, 10, 0)
    $root.Controls.Add($tabs, 0, 1)
    $restrictions = New-TgfrUiScrollPage 'Restrictions'
    $wordPage = New-TgfrUiScrollPage 'Word exam document'
    $diagnostics = New-Object System.Windows.Forms.TabPage
    $diagnostics.Text = 'Diagnostics'; $diagnostics.Padding = New-Object System.Windows.Forms.Padding(10)
    $tabs.TabPages.Add($restrictions.Page); $tabs.TabPages.Add($wordPage.Page); $tabs.TabPages.Add($diagnostics)

    $scopeTitle = New-TgfrUiLabel 'Scope: whole computer - all users' 10 $true
    Add-TgfrUiRow $restrictions.Table $scopeTitle
    $scopeNote = New-TgfrUiLabel 'Application blocks use App Control for Business (WDAC) and affect every account, including administrators. Close the selected apps in all signed-in sessions first.'
    Add-TgfrUiRow $restrictions.Table $scopeNote
    $restoreNote = New-TgfrUiLabel 'Restore removes this exam session''s policy and restores recorded network settings. Windows may require a restart to finish removal; this app never restarts automatically.'
    Add-TgfrUiRow $restrictions.Table $restoreNote

    $selectBar = New-Object System.Windows.Forms.FlowLayoutPanel
    $selectBar.AutoSize = $true; $selectBar.WrapContents = $true
    $selectAll = New-TgfrUiButton 'Select all'; $clearAll = New-TgfrUiButton 'Clear selection'
    $selectBar.Controls.Add($selectAll); $selectBar.Controls.Add($clearAll)
    Add-TgfrUiRow $restrictions.Table $selectBar
    $ui.SelectBar = $selectBar
    $definitions = [ordered]@{
        Calculator = @('Block Windows Calculator', 'Device-wide policy for the Windows Calculator package and discovered classic Calculator executables.')
        Store = @('Block Microsoft Store', 'Device-wide policy for the installed Microsoft Store package.')
        Excel = @('Block Microsoft Excel', 'Device-wide policy for discovered installed desktop Excel executables.')
        Wifi = @('Disable Wi-Fi', 'Disable physical wireless adapters; restore their recorded original state.')
        Ethernet = @('Disable Ethernet / wired LAN', 'Disable physical wired adapters, including detected USB Ethernet adapters.')
        Vpn = @('Restrict Windows VPN settings', 'Restricts the Windows VPN settings page; this does not block VPN traffic.')
        Proofing = @('Prepare Word exam copy', 'Applies "Do not check spelling or grammar" to an exam .docx; choose the source and output on the Word tab.')
    }
    $detailLabels = @()
    foreach ($entry in $definitions.GetEnumerator()) {
        $card = New-Object System.Windows.Forms.TableLayoutPanel
        $card.AutoSize = $true; $card.AutoSizeMode = 'GrowAndShrink'; $card.ColumnCount = 1
        [void]$card.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
        $card.BackColor = [System.Drawing.Color]::White
        $card.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 5)
        $card.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
        $check = New-Object System.Windows.Forms.CheckBox
        $check.AutoSize = $true; $check.Text = $entry.Value[0]
        $check.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
        $check.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
        $check.Checked = ($entry.Key -eq 'Calculator' -or $entry.Key -eq 'Store')
        $detail = New-TgfrUiLabel $entry.Value[1]
        $detail.ForeColor = [System.Drawing.Color]::FromArgb(80, 91, 106)
        $detail.Padding = New-Object System.Windows.Forms.Padding(19, 0, 0, 0)
        Add-TgfrUiRow $card $check; Add-TgfrUiRow $card $detail
        Add-TgfrUiRow $restrictions.Table $card
        $ui.Checks[$entry.Key] = $check; $detailLabels += $detail
    }
    $networkNote = New-TgfrUiLabel 'Disabling Wi-Fi and Ethernet disconnects network access and remote support. Run network tests locally.'
    $networkNote.ForeColor = [System.Drawing.Color]::FromArgb(145, 66, 28)
    Add-TgfrUiRow $restrictions.Table $networkNote
    $appsNote = New-TgfrUiLabel 'The app verifies the recorded policy and selected settings. Test application launches before the exam; a saved session status is not continuous monitoring.'
    Add-TgfrUiRow $restrictions.Table $appsNote

    $wordHeading = New-TgfrUiLabel 'Word: Do not check spelling or grammar' 11 $true
    $wordIntro = New-TgfrUiLabel 'Prepare a separate exam document with the actual proofing property applied to its text and styles. Your source document remains unchanged.'
    Add-TgfrUiRow $wordPage.Table $wordHeading; Add-TgfrUiRow $wordPage.Table $wordIntro
    $blank = New-Object System.Windows.Forms.CheckBox
    $blank.Text = 'Create a blank exam document'; $blank.Checked = $true; $blank.AutoSize = $true
    Add-TgfrUiRow $wordPage.Table $blank; $ui.Blank = $blank
    $sourceTitle = New-TgfrUiLabel 'Source document (.docx)'
    Add-TgfrUiRow $wordPage.Table $sourceTitle
    $source = New-Object System.Windows.Forms.TextBox; $source.Enabled = $false
    Add-TgfrUiRow $wordPage.Table $source; $ui.Source = $source
    $browseSource = New-TgfrUiButton 'Choose source...'; $browseSource.Enabled = $false
    Add-TgfrUiRow $wordPage.Table $browseSource
    $destinationTitle = New-TgfrUiLabel 'Save the exam copy as (.docx)'
    Add-TgfrUiRow $wordPage.Table $destinationTitle
    $destination = New-Object System.Windows.Forms.TextBox
    $publicDocuments = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDocuments)
    if ($publicDocuments -and [IO.Directory]::Exists($publicDocuments)) {
        $destination.Text = Join-Path $publicDocuments ('TGFR_Exam_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.docx')
    }
    Add-TgfrUiRow $wordPage.Table $destination; $ui.Destination = $destination
    $browseDestination = New-TgfrUiButton 'Choose destination...'
    Add-TgfrUiRow $wordPage.Table $browseDestination
    $wordUse = New-TgfrUiLabel 'Tick "Prepare Word exam copy" on the Restrictions tab, then choose Enable selected. Use the newly prepared document for the exam. Restore does not delete the exam copy or student work.'
    $wordLimit = New-TgfrUiLabel 'This applies to the prepared Word document. It does not disable proofing throughout Microsoft 365, and pasted formatting or changing the language setting can re-enable checking.'
    Add-TgfrUiRow $wordPage.Table $wordUse; Add-TgfrUiRow $wordPage.Table $wordLimit
    $showCopy = New-TgfrUiButton 'Show saved exam copy'; $showCopy.Enabled = $false
    Add-TgfrUiRow $wordPage.Table $showCopy; $ui.ShowCopy = $showCopy

    $diagLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $diagLayout.Dock = 'Fill'; $diagLayout.ColumnCount = 1; $diagLayout.RowCount = 2
    [void]$diagLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$diagLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    [void]$diagLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    $copyLog = New-TgfrUiButton 'Copy diagnostics'
    $diagButtons = New-Object System.Windows.Forms.FlowLayoutPanel
    $diagButtons.Dock = 'Top'; $diagButtons.AutoSize = $true; $diagButtons.WrapContents = $true
    $diagButtons.Controls.Add($copyLog)
    $diagLayout.Controls.Add($diagButtons, 0, 0)
    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'; $log.WordWrap = $true; $log.Dock = 'Fill'
    $log.Font = New-Object System.Drawing.Font('Consolas', 9)
    $log.Text = 'Verification results and operation details appear here.'
    $diagLayout.Controls.Add($log, 0, 1); $diagnostics.Controls.Add($diagLayout); $ui.Log = $log
    $ui.Tabs = $tabs; $ui.DiagnosticsTab = $diagnostics

    $footer = New-Object System.Windows.Forms.TableLayoutPanel
    $footer.AutoSize = $true; $footer.Dock = 'Fill'; $footer.ColumnCount = 1
    [void]$footer.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    $footer.Padding = New-Object System.Windows.Forms.Padding(14, 5, 14, 8)
    $footer.Margin = New-Object System.Windows.Forms.Padding(0)
    $buttons = New-Object System.Windows.Forms.TableLayoutPanel
    $buttons.AutoSize = $true; $buttons.Dock = 'Top'; $buttons.ColumnCount = 3
    foreach ($percent in @(33, 40, 27)) { [void]$buttons.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', $percent))) }
    $enable = New-TgfrUiButton 'Enable selected'; $restore = New-TgfrUiButton 'Restore original state'; $verify = New-TgfrUiButton 'Verify'
    $enable.BackColor = [System.Drawing.Color]::FromArgb(33, 98, 165); $enable.ForeColor = [System.Drawing.Color]::White; $enable.FlatStyle = 'Flat'
    $i = 0
    foreach ($button in @($enable, $restore, $verify)) { $button.Dock = 'Fill'; $button.MinimumSize = New-Object System.Drawing.Size(0, 36); $buttons.Controls.Add($button, $i++, 0) }
    Add-TgfrUiRow $footer $buttons
    $status = New-TgfrUiLabel 'Checking saved state...' 9 $true
    $status.MinimumSize = New-Object System.Drawing.Size(0, 34)
    Add-TgfrUiRow $footer $status; $root.Controls.Add($footer, 0, 2)
    $ui.Enable = $enable; $ui.Restore = $restore; $ui.Verify = $verify; $ui.Status = $status
    $ui.WordButtons = @($browseDestination, $browseSource)

    $wrap = {
        $width = [Math]::Max(150, $form.ClientSize.Width - 52)
        foreach ($label in @($heading, $intro, $status)) { $label.MaximumSize = New-Object System.Drawing.Size($width, 0) }
        $inside = [Math]::Max(150, $tabs.ClientSize.Width - 65)
        foreach ($label in @($scopeTitle, $scopeNote, $restoreNote, $networkNote, $appsNote, $wordHeading, $wordIntro, $sourceTitle, $destinationTitle, $wordUse, $wordLimit)) {
            $label.MaximumSize = New-Object System.Drawing.Size($inside, 0)
        }
        foreach ($label in $detailLabels) { $label.MaximumSize = New-Object System.Drawing.Size([Math]::Max(100, $inside - 25), 0) }
    }.GetNewClosure()
    $form.Add_Resize($wrap)
    $statusSummary = {
        param([string]$Text)
        $first = ($Text -split '\r?\n', 2)[0]
        if ($first.Length -gt 170) { return ($first.Substring(0, 150) + '... See Diagnostics.') }
        if ($Text.Length -gt $first.Length) { return ($first + ' See Diagnostics.') }
        return $first
    }.GetNewClosure()
    $updateLog = {
        $lines = @('TGFR Exam Mode 7.0.2', ('Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
        $lines += 'Application scope: whole computer / all users'
        $lines += 'Backend: App Control for Business (WDAC)'
        $lines += ('Operator: ' + [Environment]::UserDomainName + '\' + [Environment]::UserName)
        if ($ui.LogLines -and $ui.LogLines.Count -gt 0) { $lines += ''; $lines += @($ui.LogLines.ToArray()) }
        if ($ui.LastMessage) { $lines += ''; $lines += $ui.LastMessage }
        if ($ui.VerificationLines.Count -gt 0) { $lines += ''; $lines += 'VERIFICATION'; $lines += $ui.VerificationLines }
        $log.Text = $lines -join [Environment]::NewLine
        $log.SelectionStart = $log.TextLength; $log.ScrollToCaret()
    }.GetNewClosure()
    $refresh = {
        try {
            $info = Get-TgfrSessionInfo
            $ui.Active = [bool]$info.Active
            $ui.Enable.Enabled = (-not $ui.Active -and -not $ui.Busy)
            $ui.Restore.Enabled = ($ui.Active -and -not $ui.Busy)
            $ui.Verify.Enabled = -not $ui.Busy
            $ui.SelectBar.Enabled = (-not $ui.Active -and -not $ui.Busy)
            foreach ($entry in $ui.Checks.GetEnumerator()) {
                $entry.Value.Enabled = (-not $ui.Active -and -not $ui.Busy)
                if ($ui.Active -and $null -ne $info.Options) { $entry.Value.Checked = [bool]$info.Options.($entry.Key) }
            }
            if ($ui.Active) {
                if ($info.WordPath) { $ui.Destination.Text = [string]$info.WordPath }
            }
            $ui.Blank.Enabled = (-not $ui.Active -and -not $ui.Busy)
            $ui.Source.Enabled = (-not $ui.Active -and -not $ui.Busy -and -not $ui.Blank.Checked)
            $browseSource.Enabled = $ui.Source.Enabled
            $ui.Destination.Enabled = (-not $ui.Active -and -not $ui.Busy); $browseDestination.Enabled = $ui.Destination.Enabled
            $ui.ShowCopy.Enabled = (-not $ui.Busy -and [IO.File]::Exists($ui.Destination.Text))
            $ui.Status.Text = & $statusSummary ([string]$info.Message)
            $ui.Status.ForeColor = [System.Drawing.Color]::FromArgb(43, 64, 88)
            if ($ui.LastMessage) { $ui.Status.Text = & $statusSummary $ui.LastMessage; $ui.Status.ForeColor = $ui.LastColor }
        } catch {
            $ui.Enable.Enabled = $false; $ui.Status.Text = & $statusSummary ('Saved state needs attention: ' + $_.Exception.Message)
            $ui.Status.ForeColor = [System.Drawing.Color]::DarkRed
        }
        & $updateLog
        & $wrap
    }.GetNewClosure()
    $run = {
        # Pass the persistent window state and request data explicitly. A second
        # GetNewClosure inside an event handler cannot recapture the first
        # closure's module variables and previously made $ui become $null.
        param([scriptblock]$Operation, [hashtable]$OperationData = @{})
        $ui.Busy = $true; $form.UseWaitCursor = $true
        $ui.LastMessage = ''; $ui.VerificationLines = @(); $ui.LastColor = [System.Drawing.Color]::FromArgb(43, 64, 88)
        $enable.Enabled = $false; $restore.Enabled = $false; $verify.Enabled = $false
        $status.Text = 'Working. Keep this window open...'; $status.Refresh()
        try {
            $result = & $Operation $ui $OperationData
            if ($null -ne $result) { $ui.LastMessage = @($result) -join [Environment]::NewLine }
        } catch {
            $caughtError = $_
            $message = $caughtError.Exception.Message
            $ui.LastMessage = 'ERROR: ' + $message; $ui.LastColor = [System.Drawing.Color]::DarkRed
            if ($caughtError.ScriptStackTrace -and $null -ne $ui.LogLines) {
                $ui.LogLines.Add('UI error stack: ' + $caughtError.ScriptStackTrace)
            }
            [void][System.Windows.Forms.MessageBox]::Show($form, $message, 'Exam Mode needs attention', 'OK', 'Error')
            $tabs.SelectedTab = $diagnostics
        } finally { $ui.Busy = $false; $form.UseWaitCursor = $false; & $refresh }
    }.GetNewClosure()

    $selectAll.Add_Click({ foreach ($check in $ui.Checks.Values) { $check.Checked = $true } }.GetNewClosure())
    $clearAll.Add_Click({ foreach ($check in $ui.Checks.Values) { $check.Checked = $false } }.GetNewClosure())
    $blank.Add_CheckedChanged({ $source.Enabled = (-not $blank.Checked -and -not $ui.Active); $browseSource.Enabled = $source.Enabled }.GetNewClosure())
    $browseSource.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = 'Word document (*.docx)|*.docx'; $dialog.CheckFileExists = $true; $dialog.Multiselect = $false
        try { if ($dialog.ShowDialog($form) -eq 'OK') { $source.Text = $dialog.FileName } } finally { $dialog.Dispose() }
    }.GetNewClosure())
    $browseDestination.Add_Click({
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = 'Word document (*.docx)|*.docx'; $dialog.DefaultExt = 'docx'; $dialog.AddExtension = $true
        $dialog.FileName = 'TGFR_Exam_Copy.docx'; $dialog.OverwritePrompt = $false
        try {
            if ($dialog.ShowDialog($form) -eq 'OK') {
                if ([IO.File]::Exists($dialog.FileName)) {
                    [void][System.Windows.Forms.MessageBox]::Show($form, 'Choose a new filename. Existing documents are never overwritten.', 'Existing document', 'OK', 'Information')
                } else { $destination.Text = $dialog.FileName }
            }
        } finally { $dialog.Dispose() }
    }.GetNewClosure())
    $showCopy.Add_Click({
        if ([IO.File]::Exists($destination.Text)) { Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('/select,"{0}"' -f $destination.Text) }
    }.GetNewClosure())
    $enable.Add_Click({
        $options = @{}; foreach ($entry in $ui.Checks.GetEnumerator()) { $options[$entry.Key] = [bool]$entry.Value.Checked }
        if ($options.Proofing -and [string]::IsNullOrWhiteSpace($destination.Text)) {
            $tabs.SelectedTab = $wordPage.Page
            [void][System.Windows.Forms.MessageBox]::Show($form, 'Choose where to save the Word exam copy, then select Enable selected.', 'Choose exam document', 'OK', 'Information'); return
        }
        if ($options.Proofing -and -not $blank.Checked -and ([string]::IsNullOrWhiteSpace($source.Text) -or -not [IO.File]::Exists($source.Text))) {
            $tabs.SelectedTab = $wordPage.Page
            [void][System.Windows.Forms.MessageBox]::Show($form, 'Choose an existing .docx source, or select "Create a blank exam document".', 'Source document required', 'OK', 'Information'); return
        }
        $message = 'Apply the selected restrictions to this computer?' 
        if ($options.Calculator -or $options.Store -or $options.Excel) { $message += "`r`nApplication blocks affect ALL USERS, including administrators. Close the selected applications in every signed-in session first." }
        if ($options.Wifi -or $options.Ethernet) { $message += "`r`nNetwork connections may disconnect immediately, including remote support." }
        if ([System.Windows.Forms.MessageBox]::Show($form, $message, 'Enable Exam Mode', 'YesNo', 'Question') -ne 'Yes') { return }
        $sourcePath = $source.Text; if ($blank.Checked) { $sourcePath = '' }
        $request = @{Options=$options; WordSource=$sourcePath; WordDestination=[string]$destination.Text}
        & $run {
            param([hashtable]$windowState, [hashtable]$operationArgs)
            Invoke-TgfrEnable -Options $operationArgs.Options -WordSource $operationArgs.WordSource -WordDestination $operationArgs.WordDestination
        } $request
    }.GetNewClosure())
    $restore.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show($form, 'Remove this exam session''s application policy and restore recorded network/settings changes? Word copies and student work are retained. Windows may require a restart to finish policy removal.', 'Restore original state', 'YesNo', 'Question') -ne 'Yes') { return }
        & $run {
            param([hashtable]$windowState, [hashtable]$operationArgs)
            Invoke-TgfrRestore
        }
    }.GetNewClosure())
    $verify.Add_Click({
        & $run {
            param([hashtable]$windowState, [hashtable]$operationArgs)
            $result = Get-TgfrVerification
            $windowState.VerificationLines = @($result.Lines)
            $windowState.LastColor = [System.Drawing.Color]::DarkGreen
            if (-not $result.Ok) { $windowState.LastColor = [System.Drawing.Color]::FromArgb(145, 66, 28) }
            $windowState.Tabs.SelectedTab = $windowState.DiagnosticsTab
            return $result.Message
        }
    }.GetNewClosure())
    $copyLog.Add_Click({
        try {
            & $updateLog
            if ($log.Text) { [System.Windows.Forms.Clipboard]::SetText($log.Text) }
            [void][System.Windows.Forms.MessageBox]::Show($form, 'Diagnostics copied. You can paste them into your support message.', 'Diagnostics', 'OK', 'Information')
        } catch { [void][System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Clipboard unavailable', 'OK', 'Error') }
    }.GetNewClosure())
    $form.Add_Shown({
        $screen = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
        $form.MinimumSize = New-Object System.Drawing.Size([Math]::Min(600, $screen.Width - 16), [Math]::Min(420, $screen.Height - 16))
        $form.Size = New-Object System.Drawing.Size([Math]::Min($form.Width, $screen.Width - 16), [Math]::Min($form.Height, $screen.Height - 16))
        # New-Object Type(a + b, c + d) parses the comma as an array
        # expression; this caused Object[]::op_Addition in the Shown event.
        [int]$windowLeft = $screen.Left + [Math]::Max(0, [int](($screen.Width - $form.Width) / 2))
        [int]$windowTop = $screen.Top + [Math]::Max(0, [int](($screen.Height - $form.Height) / 2))
        $form.Location = [System.Drawing.Point]::new($windowLeft, $windowTop)
        & $refresh
    }.GetNewClosure())
    $form.Add_FormClosing({ param($sender, $eventArgs) if ($ui.Busy) { $eventArgs.Cancel = $true } }.GetNewClosure())
    try { & $refresh; [void]$form.ShowDialog() } finally { $form.Dispose() }
}

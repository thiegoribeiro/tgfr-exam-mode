# Execute the real operation wrapper and event-handler ASTs from ui.ps1.
# Lightweight controls replace WinForms; policy, registry and network code is
# never invoked. This tests callback scope/lifetime, not Windows rendering.
$ErrorActionPreference = 'Stop'
$uiPath = Join-Path $PSScriptRoot '..\src\ui.ps1'
$tokens = $null; $parseErrors = $null
$uiAst = [System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
namespace Tgfr.CallbackTests {
    public sealed class Control {
        public bool Enabled = true;
        public bool Checked;
        public bool UseWaitCursor;
        public string Text = "";
        public object ForeColor;
        public object SelectedItem;
        public object SelectedTab;
        public readonly List<object> Items = new List<object>();
        public int SelectionStart;
        public int TextLength { get { return Text.Length; } }
        public int RefreshCount;
        public event EventHandler Click;
        public void Refresh() { RefreshCount++; }
        public void ScrollToCaret() { }
        public void RaiseClick() { if (Click != null) Click(this, EventArgs.Empty); }
    }
}
namespace System.Windows.Forms {
    public static class MessageBox {
        public static string NextAnswer = "Yes";
        public static readonly List<string> Messages = new List<string>();
        public static string Show(object owner, string message, string title, string buttons, string icon) {
            Messages.Add(message);
            return buttons == "YesNo" ? NextAnswer : "OK";
        }
    }
}
'@

function Assert-UiTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw ('ASSERTION FAILED: ' + $Message) }
}
function Get-AssignmentSource([string]$Name) {
    $matches = @($uiAst.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -eq $Name
    }.GetNewClosure(), $true))
    if ($matches.Count -ne 1) { throw ('Expected one assignment: ' + $Name) }
    $matches[0].Extent.Text
}
function Get-HandlerSource([string]$Name) {
    $matches = @($uiAst.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Expression.VariablePath.UserPath -eq $Name -and
        $node.Member.Value -eq 'Add_Click'
    }.GetNewClosure(), $true))
    if ($matches.Count -ne 1) { throw ('Expected one handler: ' + $Name) }
    $matches[0].Extent.Text
}
$script:UiAssignments = @{}
foreach ($name in @('statusSummary','updateLog','refresh','run')) { $script:UiAssignments[$name] = Get-AssignmentSource $name }
$script:UiHandlers = @{}
foreach ($name in @('verify','enable','restore')) { $script:UiHandlers[$name] = Get-HandlerSource $name }

$global:TgfrCallbackTestData = @{Calls=0;Mode='incomplete';SessionActive=$false;Requests=@();RestoreCalls=0}
function global:Get-TgfrVerification {
    $global:TgfrCallbackTestData.Calls++
    switch ($global:TgfrCallbackTestData.Mode) {
        'throw' { throw 'Simulated policy read failure.' }
        'success' { return @{Ok=$true;Message='Configuration checks passed.';Lines=@('Package rule is present.','Adapter is disabled.')} }
        default { return @{Ok=$false;Message='No active session to verify.';Lines=@('Enable a session first.')} }
    }
}
function global:Get-TgfrSessionInfo {
    @{Active=$global:TgfrCallbackTestData.SessionActive;Options=@{};WordPath='';Message='Saved session status.'}
}
function global:Invoke-TgfrEnable($Options,[string]$WordSource,[string]$WordDestination) {
    $global:TgfrCallbackTestData.Requests += @{Options=$Options;Source=$WordSource;Destination=$WordDestination}
    'Configuration checks passed after enable.'
}
function global:Invoke-TgfrRestore { $global:TgfrCallbackTestData.RestoreCalls++; 'Recorded settings restored.' }

function New-UiCallbackHarness([string]$SourcePath,[string]$OutputPath) {
    $form = [Tgfr.CallbackTests.Control]::new()
    $enable = [Tgfr.CallbackTests.Control]::new(); $restore = [Tgfr.CallbackTests.Control]::new()
    $verify = [Tgfr.CallbackTests.Control]::new()
    $status = [Tgfr.CallbackTests.Control]::new(); $tabs = [Tgfr.CallbackTests.Control]::new()
    $diagnostics = [Tgfr.CallbackTests.Control]::new(); $log = [Tgfr.CallbackTests.Control]::new()
    $source = [Tgfr.CallbackTests.Control]::new(); $source.Text = $SourcePath
    $destination = [Tgfr.CallbackTests.Control]::new(); $destination.Text = $OutputPath
    $blank = [Tgfr.CallbackTests.Control]::new(); $blank.Checked = $false
    $browseSource = [Tgfr.CallbackTests.Control]::new(); $browseDestination = [Tgfr.CallbackTests.Control]::new()
    $wordPage = @{Page=[Tgfr.CallbackTests.Control]::new()}
    $ui = @{
        Form=$form;Busy=$false;Active=$false;Checks=[ordered]@{}
        SelectBar=[Tgfr.CallbackTests.Control]::new();Blank=$blank
        Source=$source;Destination=$destination;ShowCopy=[Tgfr.CallbackTests.Control]::new()
        LastMessage='';LastColor=[System.Drawing.Color]::Black;VerificationLines=@()
        LogLines=[System.Collections.Generic.List[string]]::new();Log=$log
        Tabs=$tabs;DiagnosticsTab=$diagnostics;Enable=$enable;Restore=$restore
        Verify=$verify;Status=$status
    }
    foreach ($name in @('Calculator','Store','Excel','Wifi','Ethernet','Vpn','Proofing')) {
        $ui.Checks[$name]=[Tgfr.CallbackTests.Control]::new()
    }
    $ui.Checks.Calculator.Checked=$true
    $ui.Checks.Proofing.Checked=$true
    $wrap = { } # Layout-only callback, outside this scope regression.
    foreach ($name in @('statusSummary','updateLog','refresh','run')) { . ([scriptblock]::Create($script:UiAssignments[$name])) }
    foreach ($name in @('verify','enable','restore')) { . ([scriptblock]::Create($script:UiHandlers[$name])) }
    return @{State=$ui;Verify=$verify;Enable=$enable;Restore=$restore;Status=$status;Log=$log}
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('tgfr-ui-callback-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$sourceFile = Join-Path $fixture 'source.docx'; [IO.File]::WriteAllText($sourceFile,'UI-only fixture; document engine is mocked.')
$outputFile = Join-Path $fixture 'exam-copy.docx'
try {
    # Invoke callbacks only after their construction function has returned,
    # matching the lifetime problem that the original nested closures exposed.
    $harness = New-UiCallbackHarness $sourceFile $outputFile
    $harness.Verify.RaiseClick()
    Assert-UiTest ($harness.State.VerificationLines.Count -eq 1) 'First Verify must update the retained window state.'
    Assert-UiTest ($harness.Status.Text -eq 'No active session to verify.') 'Final refresh must preserve the verification result.'
    Assert-UiTest ($harness.State.Tabs.SelectedTab -eq $harness.State.DiagnosticsTab) 'Verify must activate Diagnostics.'
    $harness.Verify.RaiseClick()
    Assert-UiTest ($global:TgfrCallbackTestData.Calls -eq 2) 'Second Verify must also reach the backend.'
    Assert-UiTest ($harness.State.VerificationLines[0] -eq 'Enable a session first.') 'Repeated Verify must preserve state identity.'
    Write-Output 'PASS: actual Verify callback works twice after closure construction returns'

    $global:TgfrCallbackTestData.Mode='throw'
    $harness.Verify.RaiseClick()
    Assert-UiTest ($harness.State.LastMessage -match 'Simulated policy read failure') 'Backend failure must be surfaced.'
    Assert-UiTest (-not $harness.State.Busy -and -not $harness.State.Form.UseWaitCursor) 'Failure must release busy state.'
    Assert-UiTest ($harness.State.LogLines.Count -gt 0 -and $harness.State.LogLines[0] -match 'UI error stack') 'Failure must retain the script stack for diagnosis.'
    Write-Output 'PASS: Verify backend error is reported and controls recover'

    $global:TgfrCallbackTestData.Mode='success'
    $harness.Verify.RaiseClick()
    Assert-UiTest ($harness.State.VerificationLines.Count -eq 2) 'Successful Verify after failure must replace the old result.'
    Assert-UiTest ($harness.Status.Text -eq 'Configuration checks passed.') 'Success status must survive finally refresh.'
    Assert-UiTest ($harness.Log.Text -match 'Package rule is present') 'Details must reach the diagnostic text.'
    Write-Output 'PASS: successful Verify after failure updates details and status'

    $harness.Enable.RaiseClick()
    Assert-UiTest ($global:TgfrCallbackTestData.Requests.Count -eq 1) 'Enable must invoke backend exactly once.'
    $request=$global:TgfrCallbackTestData.Requests[0]
    Assert-UiTest (-not $request.Contains('Sid')) 'Device-wide operation must not imply account targeting.'
    Assert-UiTest (([System.Windows.Forms.MessageBox]::Messages.ToArray() -join ' ') -match 'ALL USERS, including administrators') 'Enable confirmation must state the actual all-user scope.'
    Assert-UiTest ($harness.Log.Text -match 'Application scope: whole computer / all users') 'Diagnostics must state device-wide scope.'
    Assert-UiTest ($request.Source -eq $sourceFile -and $request.Destination -eq $outputFile) 'Enable must preserve Word input and output paths.'
    Assert-UiTest ($request.Options.Calculator -and $request.Options.Proofing -and -not $request.Options.Ethernet) 'Enable must preserve selected options.'
    Write-Output 'PASS: actual Enable callback passes device-wide options and Word paths explicitly'

    $harness.Restore.RaiseClick()
    Assert-UiTest ($global:TgfrCallbackTestData.RestoreCalls -eq 1) 'Restore callback must invoke the v7 backend once.'
    Assert-UiTest (-not $harness.State.Busy) 'All operations must release busy state.'
    Write-Output 'PASS: Restore uses the explicit-state wrapper and retains operator control'
    Write-Output 'UI callback boundary tests passed: 5'
} finally {
    [IO.Directory]::Delete($fixture,$true)
}

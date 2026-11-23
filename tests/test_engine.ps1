$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/engine.ps1"
$script:RealVpnPlanner=${function:New-TgfrVpnChange}
$script:RealAppsClosed=${function:Assert-TgfrAppsClosed}
$script:pass=0
function Assert-T([bool]$Value,[string]$Message) {if(-not $Value){throw ('FAIL: '+$Message)};$script:pass++;Write-Output ('PASS: '+$Message)}
function Assert-Throws([scriptblock]$Operation,[string]$Message) {$caught=$false;try{& $Operation|Out-Null}catch{$caught=$true};Assert-T $caught $Message}
function Assert-TgfrAdmin {}
function Assert-TgfrStateDirectoryTrusted {}
function Assert-TgfrStateFileTrusted {}
function Protect-TgfrStateFile {param($Path) if(-not [IO.File]::Exists($Path)){throw 'Expected the temporary recovery journal to exist before protection.'}}
function Get-TgfrMachineId {'test-machine-1'}
function Get-TgfrEarlierStatePaths { @($script:earlierPaths) }
function Assert-TgfrAppsClosed {}
function Initialize-TgfrStateDirectory {[void][IO.Directory]::CreateDirectory($script:TgfrStateRoot)}
function Invoke-TgfrWithMutationLock([scriptblock]$Operation) { & $Operation }
function Get-NetAdapter {param([switch]$Physical,[switch]$IncludeHidden,$ErrorAction) @($script:adapters.Values)}
function Disable-NetAdapter {param($InputObject,[switch]$Confirm,$ErrorAction)
    $script:disableCalls++;$InputObject.AdminStatus='Down';$InputObject.Status='Disabled'
    if($script:failDisable){throw 'Injected disable failure after mutation'}
}
function Enable-NetAdapter {param($InputObject,[switch]$Confirm,$ErrorAction)
    if($script:failEnable){throw 'Injected enable failure'}
    $script:enableCalls++;$InputObject.AdminStatus='Up';$InputObject.Status='Disconnected'
}
function New-TgfrAppPlan {param($Options) if($script:failPlan){throw 'Injected planning failure'};@{enabled=$true;policyId='test-owned';planningDetails=@('Device-wide fixture')}}
function Invoke-TgfrAppPlan {param($Plan) $saved=Read-TgfrState;if(-not $saved.appAttempted -or $saved.appPlan.policyId -ne 'test-owned'){throw 'Recovery plan was not persisted before policy deployment'};$script:appActive=$true}
function Test-TgfrAppPlan {param($Plan) @{Ok=$script:appActive;Details=@('Mocked app boundary')}}
function Undo-TgfrAppPlan {param($Plan) if($script:pendingRemoval){return @{Ok=$false;Details=@('Policy removal pending Windows restart')}};$script:appActive=$false;@{Ok=$true;Details=@('Mocked restore')}}
function New-TgfrVpnChange { @{hive='HKLM';path='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer';name='SettingsPageVisibility';old=@{exists=$false};new=@{exists=$true;kind='String';value='hide:network-vpn'};attempted=$false}}
function Get-TgfrRegValue {param($Hive,$Path,$Name) $script:regValue}
function Set-TgfrRegValue {param($Hive,$Path,$Name,$Snapshot) $script:regValue=$Snapshot}
function New-TgfrWordExamCopy {param($SourcePath,$DestinationPath) [IO.File]::WriteAllText($DestinationPath,'Candidate copy');@{Path=$DestinationPath;Verified=$true}}
function Test-TgfrWordExamCopy {param($Path) @{Ok=[IO.File]::Exists($Path);Details=@('Mocked document boundary')}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('TGFR-Engine-'+[guid]::NewGuid().ToString('N'))
$script:TgfrStateRoot=$temp;$script:TgfrStatePath=Join-Path $temp 'session.json'
$wifiId='11111111-1111-1111-1111-111111111111';$ethernetId='22222222-2222-2222-2222-222222222222'
function Reset-Fixture {
    if([IO.Directory]::Exists($temp)){Remove-Item -LiteralPath $temp -Recurse -Force}
    [void][IO.Directory]::CreateDirectory($temp)
    $script:adapters=@{
        $wifiId=[pscustomobject]@{Name='WLAN';InterfaceGuid=$wifiId;InterfaceType=71;NdisPhysicalMedium=9;AdminStatus='Up';Status='Disconnected'}
        $ethernetId=[pscustomobject]@{Name='Dock network';InterfaceGuid=$ethernetId;InterfaceType=6;NdisPhysicalMedium=14;AdminStatus='Down';Status='Disabled'}
    }
    $script:disableCalls=0;$script:enableCalls=0;$script:failDisable=$false;$script:failEnable=$false;$script:appActive=$false
    $script:regValue=@{exists=$false};$script:earlierPaths=@();$script:pendingRemoval=$false;$script:failPlan=$false
}
function Options { @{Calculator=$true;Store=$false;Excel=$false;Wifi=$true;Ethernet=$true;Vpn=$false;Proofing=$false} }
try {
    Reset-Fixture;$options=Options
    $result=Invoke-TgfrEnable $options '' ''
    $state=Read-TgfrState
    Assert-T ($state.phase -eq 'Active') 'successful apply creates an Active journal'
    Assert-T ($script:disableCalls -eq 1) 'already-disabled Ethernet is not toggled'
    Assert-T ((Get-TgfrVerification).Ok) 'actual recorded configuration is checked after apply'
    $stateBytes=[IO.File]::ReadAllText($script:TgfrStatePath)
    Assert-Throws {Invoke-TgfrEnable $options '' ''} 'second enable is refused'
    Assert-T ([IO.File]::ReadAllText($script:TgfrStatePath) -ceq $stateBytes) 'second enable preserves original backup bytes'
    $result=Invoke-TgfrRestore
    Assert-T ($script:adapters[$wifiId].AdminStatus -eq 'Up' -and $script:adapters[$ethernetId].AdminStatus -eq 'Down') 'restore preserves original enabled AND disabled adapter states'
    Assert-T (-not [IO.File]::Exists($script:TgfrStatePath) -and @(Get-ChildItem $temp -Filter 'restored-*.json').Count -eq 1) 'successful restore archives journal rather than losing baseline'
    Assert-T (-not $script:appActive) 'application restrictions restored'
    Assert-T ((Invoke-TgfrRestore) -eq 'No v7 session is active.') 'restore is idempotent after completion'

    Reset-Fixture;$script:failDisable=$true;$options=Options
    Assert-Throws {Invoke-TgfrEnable $options '' ''} 'partial network mutation triggers rollback'
    Assert-T ($script:adapters[$wifiId].AdminStatus -eq 'Up' -and -not $script:appActive) 'partial failure restores connectivity and application state'
    Assert-T (-not [IO.File]::Exists($script:TgfrStatePath)) 'complete rollback archives active journal'

    Reset-Fixture;$script:failDisable=$true;$script:failEnable=$true
    Assert-Throws {Invoke-TgfrEnable (Options) '' ''} 'rollback failure is reported'
    Assert-T ((Read-TgfrState).phase -eq 'Recovery required') 'incomplete rollback retains recoverable journal'
    $script:failEnable=$false;$script:failDisable=$false
    $null=Invoke-TgfrRestore
    Assert-T (-not (Read-TgfrState) -and $script:adapters[$wifiId].AdminStatus -eq 'Up') 'retry restore completes from retained journal'

    Reset-Fixture;$options=Options;$options.Vpn=$true
    $null=Invoke-TgfrEnable $options '' ''
    $script:regValue=@{exists=$true;kind='String';value='hide:network-proxy'}
    Assert-Throws {Invoke-TgfrRestore} 'externally changed registry value causes restore conflict'
    Assert-T ($script:regValue.value -eq 'hide:network-proxy') 'external policy edit is not overwritten'
    Assert-T ($script:adapters[$wifiId].AdminStatus -eq 'Up') 'network restoration still completes despite policy conflict'
    Assert-T ((Read-TgfrState).phase -eq 'Recovery required') 'conflict preserves baseline for reconciliation'
    $script:regValue=@{exists=$true;kind='String';value='hide:network-vpn'}
    $null=Invoke-TgfrRestore
    Assert-T (-not $script:regValue.exists -and -not (Read-TgfrState)) 'conflict reconciliation then restores originally missing registry value'

    Reset-Fixture;$options=Options;$options.Proofing=$true;$script:failDisable=$true
    $doc=Join-Path $temp 'candidate.docx'
    Assert-Throws {Invoke-TgfrEnable $options '' $doc} 'later failure rolls back after exam-copy preparation'
    Assert-T ([IO.File]::ReadAllText($doc) -eq 'Candidate copy') 'rollback preserves exam copy and candidate work'
    Assert-T (-not (Test-TgfrRegEqual @{exists=$true;kind='DWord';value=0} @{exists=$true;kind='String';value='0'})) 'registry verification checks type as well as value'
    Assert-T (Test-TgfrRegEqual @{exists=$false} @{exists=$false;keyExists=$true}) 'absence restoration ignores harmless key-container difference'

    Reset-Fixture;$script:earlierPaths=@('C:\ProgramData\TGFR_ExamMode_v6\session.json')
    Assert-Throws {Invoke-TgfrEnable (Options) '' ''} 'earlier active journal blocks overlapping session without old policy commands'
    Assert-T (-not [IO.File]::Exists($script:TgfrStatePath) -and $script:disableCalls -eq 0 -and -not $script:appActive) 'earlier journal refusal makes no exam changes'

    Reset-Fixture;$script:failPlan=$true
    Assert-Throws {Invoke-TgfrEnable (Options) '' ''} 'policy planning failure is surfaced before any mutation'
    Assert-T (-not [IO.File]::Exists($script:TgfrStatePath) -and $script:disableCalls -eq 0) 'failed preflight leaves no active v7 journal or network writes'

    Reset-Fixture;$null=Invoke-TgfrEnable (Options) '' ''; $script:pendingRemoval=$true
    Assert-Throws {Invoke-TgfrRestore} 'policy removal pending restart is not declared successful'
    Assert-T ((Read-TgfrState).phase -eq 'Recovery required' -and $script:appActive) 'pending removal retains the policy ownership journal'
    Assert-T ($script:adapters[$wifiId].AdminStatus -eq 'Up') 'pending application removal does not prevent connectivity restoration'
    $script:pendingRemoval=$false;$script:appActive=$false
    $null=Invoke-TgfrRestore
    Assert-T (-not (Read-TgfrState)) 'restore retry finishes after external restart removes the owned policy'

    Reset-Fixture;$options=Options;$options.Calculator=$false;$options.Store=$false;$options.Excel=$false;$script:failPlan=$true
    $null=Invoke-TgfrEnable $options '' ''
    Assert-T ((Read-TgfrState).phase -eq 'Active' -and -not (Read-TgfrState).appPlan) 'network-only session skips the new policy backend entirely'
    $null=Invoke-TgfrRestore

    Reset-Fixture
    $vpn=& $script:RealVpnPlanner
    Assert-T ($vpn.hive -eq 'HKLM' -and $vpn.path -eq 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -and -not $vpn.old.exists) 'actual VPN planner records a device-level absent baseline'
    $script:regValue=@{exists=$true;kind='String';value='hide:network-proxy'}
    $vpn=& $script:RealVpnPlanner
    Assert-T ($vpn.new.value -eq 'hide:network-proxy;network-vpn') 'actual VPN planner preserves an unrelated hidden page'
    $script:regValue=@{exists=$true;kind='String';value='showonly:about'}
    Assert-T ((& $script:RealVpnPlanner).new.value -eq 'showonly:about') 'existing show-only policy excluding VPN remains intact'
    $script:regValue=@{exists=$true;kind='String';value='showonly:about;network-vpn'}
    Assert-Throws {& $script:RealVpnPlanner} 'existing show-only policy explicitly permitting VPN requires reconciliation'

    function Get-CimInstance {param($ClassName,$ErrorAction) [pscustomobject]@{Name='AdditionalCalculator.exe'}}
    $options=Options;$options.Calculator=$false
    Assert-Throws {& $script:RealAppsClosed $options @{blockedProcessNames=@('AdditionalCalculator')}} 'extensionless discovered process names are checked across all sessions'
    Assert-T ((Get-TgfrVerification).Message -eq 'No active v7 session to verify.') 'empty verification reports the correct release generation'
    Write-Output "ALL $script:pass V7 ENGINE ASSERTIONS PASSED"
} finally {if([IO.Directory]::Exists($temp)){Remove-Item -LiteralPath $temp -Recurse -Force}}

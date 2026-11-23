$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/recovery_command.ps1'))
$global:RecoveryBatText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../dist/TGFR_Exam_Mode_Policy_Recovery_v7.bat'))
$launcher=@($global:RecoveryBatText -split '\r?\n' | Where-Object { $_ -match '^"%TGFR_PS%".* -Command ' })
if($launcher.Count -ne 1){throw 'Recovery BAT must have one PowerShell launcher.'}
$global:RecoveryBootstrap=[regex]::Match($launcher[0],'^"%TGFR_PS%" -NoLogo -NoProfile -Command "(.*)"$').Groups[1].Value
if(-not $global:RecoveryBootstrap -or $launcher[0].Length -ge 8191){throw 'Invalid or oversized recovery bootstrap.'}
$global:RecoveryPass=0
$global:RecoveryId='{11111111-2222-3333-4444-555555555555}'
$global:OtherId='{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'
$global:RecoveryHash='a'*64
$global:RecoveryCalls=@()
$global:RecoveryFixture=$null

function Reset-RecoveryFixture {
    $row=[pscustomobject]@{PolicyID=$global:RecoveryId;BasePolicyID=$global:RecoveryId;FriendlyName=('TGFR Exam Mode 7.0 '+$global:RecoveryId);IsSystemPolicy=$false;IsSignedPolicy=$false;IsEnforced=$true;IsOnDisk=$true}
    $other=[pscustomobject]@{PolicyID=$global:OtherId;BasePolicyID=$global:OtherId;FriendlyName='Windows policy';IsSystemPolicy=$true;IsSignedPolicy=$true;IsEnforced=$true;IsOnDisk=$false}
    $plan=[pscustomobject]@{enabled=$true;backend='AppControl';scope='Device';policyId=$global:RecoveryId;policyName=$row.FriendlyName;binarySha256=$global:RecoveryHash;originalInventory=@($other)}
    $state=[pscustomobject]@{version=7;machineId='machine-A';sessionId=('a'*32);appAttempted=$true;appPlan=$plan}
    $global:RecoveryFixture=@{
        state=$state;row=$row;other=$other;rows=@($other,$row);removeRows=@($other)
        rootAcl='O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
        fileAcl='O:BAG:SYD:AI(A;ID;FA;;;SY)(A;ID;FA;;;BA)'
        rootProtected=$true;rootReparse=$false;fileReparse=$false;activeReparse=$false
        hash=$global:RecoveryHash;length=1024;listExit=0;removeExit=0;removeResult=0
        missingInventory=$false;listNull=$false;missingFile=$false;machine='machine-A'
    }
    $global:RecoveryCalls=@()
}
function Get-Item {
    param($LiteralPath,[switch]$Force,$ErrorAction)
    $directory=([string]$LiteralPath -match 'TGFR_ExamMode_v7$')
    $link=if($directory){$global:RecoveryFixture.rootReparse}elseif([string]$LiteralPath -match 'session.json$'){$global:RecoveryFixture.fileReparse}else{$global:RecoveryFixture.activeReparse}
    [pscustomobject]@{PSIsContainer=$directory;Attributes=$(if($link){1024}else{0});Length=$global:RecoveryFixture.length}
}
function Get-Acl {
    param($LiteralPath,$ErrorAction)
    $directory=([string]$LiteralPath -match 'TGFR_ExamMode_v7$')
    [pscustomobject]@{Sddl=$(if($directory){$global:RecoveryFixture.rootAcl}else{$global:RecoveryFixture.fileAcl});AreAccessRulesProtected=$global:RecoveryFixture.rootProtected}
}
function Join-Path {
    param($Path,$ChildPath)
    if([string]$ChildPath -match 'CiTool.exe$'){return 'Invoke-TgfrRecoveryNativeMock'}
    return ([string]$Path+'/'+[string]$ChildPath)
}
function Test-Path {
    param($LiteralPath,$PathType)
    if([string]$LiteralPath -match '\.cip$' -and $global:RecoveryFixture.missingFile){return $false}
    return $true
}
function Get-Content {
    param($LiteralPath,[switch]$Raw,$ErrorAction)
    if($LiteralPath -eq 'BATfixture'){return $global:RecoveryBatText}
    return ($global:RecoveryFixture.state|ConvertTo-Json -Depth 15)
}
function Get-ItemProperty {
    param($LiteralPath,$Name,$ErrorAction)
    [pscustomobject]@{MachineGuid=$global:RecoveryFixture.machine}
}
function Get-FileHash {
    param($LiteralPath,$Algorithm,$ErrorAction)
    if($Algorithm -ne 'SHA256'){throw 'Unexpected digest algorithm'}
    [pscustomobject]@{Hash=$global:RecoveryFixture.hash}
}
function Invoke-TgfrRecoveryNativeMock {
    param([string]$A,[string]$B,[string]$C)
    $global:RecoveryCalls+=@{A=$A;B=$B;C=$C}
    if($A -eq '-lp' -and $B -eq '-json'){
        $global:LASTEXITCODE=$global:RecoveryFixture.listExit
        if($global:RecoveryFixture.missingInventory){return '{"Other":true}'}
        if($global:RecoveryFixture.listNull){return '{"Policies":null}'}
        return (@{Policies=@($global:RecoveryFixture.rows);OperationResult=0}|ConvertTo-Json -Depth 15 -Compress)
    }
    if($A -eq '-rp' -and $B -eq $global:RecoveryId -and $C -eq '-json'){
        $global:LASTEXITCODE=$global:RecoveryFixture.removeExit
        $global:RecoveryFixture.rows=@($global:RecoveryFixture.removeRows)
        if(@($global:RecoveryFixture.rows|Where-Object PolicyID -eq $global:RecoveryId).Count -eq 0){$global:RecoveryFixture.missingFile=$true}
        return (@{OperationResult=$global:RecoveryFixture.removeResult}|ConvertTo-Json -Compress)
    }
    throw 'Unexpected native mutation or identifier.'
}
function Assert-Recovery {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw ('FAIL: '+$Message)}
    $global:RecoveryPass++
    Write-Output ('PASS: '+$Message)
}
function Assert-RecoveryReject {
    param([string]$Message)
    $thrown=$false
    try{$null=Invoke-TgfrPolicyRecovery}catch{$thrown=$true}
    Assert-Recovery $thrown $Message
    Assert-Recovery (@($global:RecoveryCalls|Where-Object A -eq '-rp').Count -eq 0) ($Message+' without removal')
}

$env:OS='Windows_NT';$env:ProgramData='TestData';$env:SystemRoot='TestWindows';$env:PROCESSOR_ARCHITEW6432=''
$ExecutionContext.SessionState.LanguageMode='ConstrainedLanguage'
# Invoke-Expression is deliberately executed after the language switch: the
# production functions are compiled and executed in ConstrainedLanguage.
Invoke-Expression $source
Assert-Recovery ($ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage') 'test runspace is genuinely ConstrainedLanguage'

Reset-RecoveryFixture
$code=Invoke-TgfrPolicyRecovery
Assert-Recovery ($code -eq 0) 'normal owned-policy removal succeeds in ConstrainedLanguage'
Assert-Recovery (@($global:RecoveryCalls|Where-Object A -eq '-rp').Count -eq 1) 'exactly one removal command'
Assert-Recovery (@($global:RecoveryCalls|Where-Object A -eq '-rp')[0].B -eq $global:RecoveryId) 'only the journal-owned GUID is removed'
Assert-Recovery ($global:RecoveryFixture.rows.Count -eq 1 -and $global:RecoveryFixture.rows[0].PolicyID -eq $global:OtherId) 'Windows-managed policy remains untouched'

Reset-RecoveryFixture;$global:RecoveryFixture.rootProtected=$false
Assert-RecoveryReject 'unprotected directory rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.rootAcl='O:BAG:SYD:P(A;;FA;;;WD)'
Assert-RecoveryReject 'unexpected account permission rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.fileAcl='O:S-1-5-21-100-200-300-400G:SYD:P(A;;FA;;;BA)'
Assert-RecoveryReject 'untrusted journal owner rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.rootReparse=$true
Assert-RecoveryReject 'directory junction rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.fileReparse=$true
Assert-RecoveryReject 'journal link rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.machine='machine-B'
Assert-RecoveryReject 'foreign machine journal rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.state.version=6
Assert-RecoveryReject 'earlier journal rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.state.appAttempted=$false
Assert-RecoveryReject 'unattempted deployment rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.state.appPlan.originalInventory=@($global:RecoveryFixture.row)
Assert-RecoveryReject 'pre-existing policy identifier rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.state.appPlan.originalInventory=$null
Assert-RecoveryReject 'null original inventory rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.row.IsSystemPolicy=$true
Assert-RecoveryReject 'Windows-managed identifier rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.row.IsSystemPolicy='False'
Assert-RecoveryReject 'string ownership flag rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.row.IsSignedPolicy=$true
Assert-RecoveryReject 'signed policy rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.row.FriendlyName='Other deployment'
Assert-RecoveryReject 'changed deployment identity rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.row.BasePolicyID=$global:OtherId
Assert-RecoveryReject 'changed base identity rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.hash='b'*64
Assert-RecoveryReject 'different policy bytes rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.missingInventory=$true
Assert-RecoveryReject 'missing inventory rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.listNull=$true
Assert-RecoveryReject 'null inventory rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.rows+=@($global:RecoveryFixture.row)
Assert-RecoveryReject 'duplicate inventory identifier rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.other.PolicyID='{00000000-0000-0000-0000-000000000000}'
Assert-RecoveryReject 'empty saved or current inventory identifier rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.listExit=5
Assert-RecoveryReject 'native list failure rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.activeReparse=$true
Assert-RecoveryReject 'deployed policy link rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.missingFile=$true
Assert-RecoveryReject 'missing deployed bytes rejected'

Reset-RecoveryFixture;$global:RecoveryFixture.rows=@($global:RecoveryFixture.other);$global:RecoveryFixture.missingFile=$true
$code=Invoke-TgfrPolicyRecovery
Assert-Recovery ($code -eq 0 -and @($global:RecoveryCalls|Where-Object A -eq '-rp').Count -eq 0) 'already absent owned policy is idempotent'
Reset-RecoveryFixture;$global:RecoveryFixture.row.IsEnforced=$false;$global:RecoveryFixture.row.IsOnDisk=$false;$global:RecoveryFixture.missingFile=$true
$code=Invoke-TgfrPolicyRecovery
Assert-Recovery ($code -eq 0 -and @($global:RecoveryCalls|Where-Object A -eq '-rp').Count -eq 0) 'inactive fileless historical entry is already removed'
Reset-RecoveryFixture;$global:RecoveryFixture.row.IsOnDisk=$false;$global:RecoveryFixture.missingFile=$true
$code=Invoke-TgfrPolicyRecovery
Assert-Recovery ($code -eq 2 -and @($global:RecoveryCalls|Where-Object A -eq '-rp').Count -eq 0) 'active fileless policy reports pending restart without repeated removal'
Reset-RecoveryFixture;$global:RecoveryFixture.row.IsEnforced=$false;$global:RecoveryFixture.row.IsOnDisk=$false
Assert-RecoveryReject 'inactive metadata with remaining active file rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.rows=@($global:RecoveryFixture.other)
Assert-RecoveryReject 'absent inventory with remaining active file rejected'
Reset-RecoveryFixture;$global:RecoveryFixture.removeRows=@($global:RecoveryFixture.row,$global:RecoveryFixture.other)
$code=Invoke-TgfrPolicyRecovery
Assert-Recovery ($code -eq 2) 'accepted removal still active reports pending recovery'
Reset-RecoveryFixture;$global:RecoveryFixture.removeExit=5
$thrown=$false;try{$null=Invoke-TgfrPolicyRecovery}catch{$thrown=$true}
Assert-Recovery $thrown 'native removal failure is surfaced'
Reset-RecoveryFixture;$global:RecoveryFixture.removeResult=5
$thrown=$false;try{$null=Invoke-TgfrPolicyRecovery}catch{$thrown=$true}
Assert-Recovery $thrown 'nonzero native operation result is surfaced'
Assert-Recovery ($source -notmatch 'Set-Acl|Remove-Item|Set-ItemProperty|Start-Service|Stop-Service|shutdown|Clear-Content|Set-Content|WriteAll') 'recovery source has no unrelated mutation or journal deletion'
Write-Output ('ALL '+$global:RecoveryPass+' RECOVERY ASSERTIONS PASSED IN CONSTRAINEDLANGUAGE; Windows boundaries were simulated.')
Reset-RecoveryFixture
$env:TGFR_RECOVERY_SELF='BATfixture'
Write-Output 'Executing the exact packaged BAT PowerShell bootstrap in ConstrainedLanguage; its exit code is the final test result.'
Invoke-Expression $global:RecoveryBootstrap

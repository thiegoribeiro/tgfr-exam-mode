# TGFR Exam Mode 7.0: narrowly scoped policy recovery.
# Uses cmdlets and core PowerShell types so the command can run in
# ConstrainedLanguage without changing that language mode or any outside policy.
# The protected journal is deliberately retained for normal Restore afterward.

function Assert-TgfrRecoveryAcl {
    param([string]$Path,[bool]$Directory)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (([int]$item.Attributes -band 1024) -ne 0) { throw 'Recovery refuses a junction or symbolic link.' }
    if ([bool]$item.PSIsContainer -ne $Directory) { throw 'Unexpected recovery file or directory type.' }
    $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
    if ($Directory -and -not $acl.AreAccessRulesProtected) { throw 'The recovery directory inherits permissions and is not trusted.' }
    $sddl=[string]$acl.Sddl
    if ($sddl -notmatch '^O:(BA|SY|S-1-5-32-544|S-1-5-18)(?=[GDS]:)') { throw 'Recovery ownership is not Administrators or SYSTEM.' }
    $parts=$sddl -split 'D:',2
    if ($parts.Count -ne 2) { throw 'Recovery permissions do not contain a valid DACL.' }
    $dacl=($parts[1] -split 'S:',2)[0]
    $aces=[regex]::Matches($dacl,'\(([^()]*)\)')
    if ($aces.Count -eq 0 -or ($dacl -replace '\([^()]*\)','') -notmatch '^(P|AI|AR)*$') { throw 'Recovery permissions contain an unsupported DACL.' }
    foreach ($ace in $aces) {
        $fields=$ace.Groups[1].Value -split ';'
        if ($fields.Count -ne 6 -or $fields[0] -notin @('A','D') -or $fields[3] -or $fields[4]) { throw 'Recovery permissions contain an unsupported access rule.' }
        if ($fields[0] -eq 'A' -and $fields[5] -notin @('BA','SY','S-1-5-32-544','S-1-5-18')) { throw 'Recovery permissions allow an account other than Administrators or SYSTEM.' }
    }
}

function Get-TgfrRecoveryInventory {
    param([string]$Tool)
    $raw=@(& $Tool '-lp' '-json' 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('Policy inventory failed: '+($raw -join ' ')) }
    $data=($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($data.PSObject.Properties.Name -contains 'OperationResult' -and [long]$data.OperationResult -ne 0) { throw 'The policy inventory operation failed.' }
    if ($data.PSObject.Properties.Name -notcontains 'Policies' -or $null -eq $data.Policies) { throw 'Policy inventory is unavailable; no removal is permitted.' }
    $ids=@()
    foreach ($row in @($data.Policies)) {
        $id=([guid]$row.PolicyID).ToString('B').ToUpperInvariant()
        if ($id -eq '{00000000-0000-0000-0000-000000000000}') { throw 'Policy inventory contains an empty identifier.' }
        if ($ids -contains $id) { throw 'Policy inventory contains duplicate identifiers.' }
        $ids+=$id
    }
    return @($data.Policies)
}

function Get-TgfrRecoveryOwnedPolicy {
    param([object[]]$Inventory,[string]$PolicyId,[string]$PolicyName)
    $rows=@($Inventory | Where-Object { ([guid]$_.PolicyID).ToString('B').ToUpperInvariant() -eq $PolicyId })
    if ($rows.Count -eq 0) { return $null }
    if ($rows.Count -ne 1) { throw 'The owned policy is not uniquely identified.' }
    $row=$rows[0]
    foreach ($name in @('IsSystemPolicy','IsSignedPolicy','IsEnforced','IsOnDisk')) {
        if ($row.PSObject.Properties.Name -notcontains $name -or $row.$name -isnot [bool]) { throw ('Required policy metadata is unavailable: '+$name) }
    }
    if ($row.IsSystemPolicy -or $row.IsSignedPolicy) { throw 'The recorded policy is now Windows-managed or signed; no removal was attempted.' }
    if (([guid]$row.BasePolicyID).ToString('B').ToUpperInvariant() -ne $PolicyId -or $row.FriendlyName -cne $PolicyName) { throw 'Policy identity differs from the saved exam deployment; no removal was attempted.' }
    return $row
}

function Invoke-TgfrPolicyRecovery {
    if ($env:OS -ne 'Windows_NT') { throw 'Run this recovery tool on the affected Windows device.' }
    if (-not $env:ProgramData -or -not $env:SystemRoot) { throw 'Required Windows paths are unavailable.' }
    $stateRoot=Join-Path $env:ProgramData 'TGFR_ExamMode_v7'
    $statePath=Join-Path $stateRoot 'session.json'
    Assert-TgfrRecoveryAcl -Path $stateRoot -Directory $true
    Assert-TgfrRecoveryAcl -Path $statePath -Directory $false
    $file=Get-Item -LiteralPath $statePath -Force -ErrorAction Stop
    if ($file.Length -gt 16777216) { throw 'The recovery journal exceeds its supported size.' }
    $state=Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $machine=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
    if ($state.version -ne 7 -or $state.machineId -ne $machine -or $state.sessionId -notmatch '^[0-9a-fA-F]{32}$') { throw 'The journal is invalid or belongs to another machine.' }
    if ($state.appAttempted -isnot [bool] -or -not $state.appAttempted) { throw 'This journal records no attempted application-policy deployment.' }
    $plan=$state.appPlan
    if (-not $plan -or $plan.enabled -isnot [bool] -or -not $plan.enabled -or $plan.backend -ne 'AppControl' -or $plan.scope -ne 'Device') { throw 'The journal does not contain a supported owned application plan.' }
    $id=[string]$plan.policyId
    if ($id -notmatch '^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$') { throw 'The recorded policy identifier is invalid.' }
    $id=$id.ToUpperInvariant()
    $name='TGFR Exam Mode 7.0 '+$id
    if ($plan.policyName -cne $name -or $plan.binarySha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'The recorded policy name or fingerprint is invalid.' }
    if ($plan.PSObject.Properties.Name -notcontains 'originalInventory' -or $null -eq $plan.originalInventory) { throw 'The original policy inventory is missing.' }
    foreach ($old in @($plan.originalInventory)) {
        $oldId=([guid]$old.PolicyID).ToString('B').ToUpperInvariant()
        if ($oldId -eq '{00000000-0000-0000-0000-000000000000}') { throw 'The saved original inventory contains an empty identifier.' }
        if ($oldId -eq $id) { throw 'This policy existed before the exam session; it is not eligible for this recovery.' }
    }
    $folder='System32'
    if ($env:PROCESSOR_ARCHITEW6432) { $folder='Sysnative' }
    $tool=Join-Path $env:SystemRoot ($folder+'\CiTool.exe')
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'The Windows policy tool is unavailable.' }
    $active=Join-Path $env:SystemRoot ($folder+'\CodeIntegrity\CiPolicies\Active\'+$id+'.cip')
    $inventory=@(Get-TgfrRecoveryInventory -Tool $tool)
    $owned=Get-TgfrRecoveryOwnedPolicy -Inventory $inventory -PolicyId $id -PolicyName $name
    if (-not $owned -or (-not $owned.IsEnforced -and -not $owned.IsOnDisk)) {
        if (Test-Path -LiteralPath $active) { throw 'Windows reports the exam policy absent or inactive, but its active policy path still exists. Keep the journal and review that discrepancy; no removal was attempted.' }
        Write-Host 'The recorded exam policy is already absent or inactive without a policy file.'
        Write-Host 'The session journal was retained. Reopen the normal app and select Restore for networking and other saved settings.'
        return 0
    }
    if (-not $owned.IsOnDisk) {
        if (Test-Path -LiteralPath $active) { throw 'The active policy path exists despite fileless inventory metadata. No removal was attempted.' }
        Write-Warning 'The exam policy remains active after its file was removed. Restart Windows, then run normal Restore. The journal was retained.'
        return 2
    }
    if (-not (Test-Path -LiteralPath $active -PathType Leaf)) { throw 'The owned active policy file is unavailable for fingerprint checking. No removal was attempted.' }
    $item=Get-Item -LiteralPath $active -Force -ErrorAction Stop
    if (([int]$item.Attributes -band 1024) -ne 0) { throw 'The active policy file is a link; no removal was attempted.' }
    $hash=(Get-FileHash -LiteralPath $active -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($hash -ine $plan.binarySha256) { throw 'The deployed policy bytes differ from the saved exam policy. No removal was attempted.' }
    Write-Host ('Removing only the recorded exam policy: '+$id)
    $raw=@(& $tool '-rp' $id '-json' 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('Owned-policy removal failed: '+($raw -join ' ')) }
    $response=($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($response.PSObject.Properties.Name -contains 'OperationResult' -and [long]$response.OperationResult -ne 0) { throw 'The owned-policy removal operation did not complete.' }
    $after=@(Get-TgfrRecoveryInventory -Tool $tool)
    $left=Get-TgfrRecoveryOwnedPolicy -Inventory $after -PolicyId $id -PolicyName $name
    if ($left -and ($left.IsEnforced -or $left.IsOnDisk)) {
        Write-Warning 'Removal was requested, but Windows still reports the exam policy. Restart Windows if required, then run normal Restore. The journal was retained.'
        return 2
    }
    if (Test-Path -LiteralPath $active) {
        Write-Warning 'The policy is no longer active in the inventory, but its active file path remains. Keep the journal and review the removal result before normal Restore.'
        return 2
    }
    Write-Host 'The owned exam policy is no longer active or installed.'
    Write-Host 'The session journal was retained. Close this window, reopen the normal app, and select Restore for networking and other saved settings.'
    return 0
}

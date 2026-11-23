# TGFR Exam Mode 7.0. Windows PowerShell 5.1; separate v7 machine journal.
# This file is concatenated into the downloadable BAT. It has no startup actions.
$script:TgfrStateRoot = if ($env:ProgramData) { Join-Path $env:ProgramData 'TGFR_ExamMode_v7' } else { '' }
$script:TgfrStatePath = if ($script:TgfrStateRoot) { Join-Path $script:TgfrStateRoot 'session.json' } else { '' }
$script:TgfrLogLines = [System.Collections.Generic.List[string]]::new()

function Write-TgfrLog([string]$Message) {
    $script:TgfrLogLines.Add(('{0:HH:mm:ss}  {1}' -f (Get-Date), $Message))
}
function Assert-TgfrAdmin {
    $p = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Close this window and run the BAT as administrator. Application restrictions apply to all users of this computer.'
    }
}
function Get-TgfrMachineId {
    (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
}
function Initialize-TgfrStateDirectory {
    Assert-TgfrAdmin
    [void][IO.Directory]::CreateDirectory($script:TgfrStateRoot)
    $item = Get-Item -LiteralPath $script:TgfrStateRoot -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The state directory must not be a junction or symbolic link.' }
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-32-544', 'S-1-5-18')) {
        $id = [Security.Principal.SecurityIdentifier]::new($sid)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($id, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        [void]$acl.AddAccessRule($rule)
    }
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    Set-Acl -LiteralPath $script:TgfrStateRoot -AclObject $acl -ErrorAction Stop
}
function Save-TgfrState($State, [switch]$New) {
    $text = $State | ConvertTo-Json -Depth 35
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    $tmp = Join-Path $script:TgfrStateRoot ([guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $stream = [IO.File]::Open($tmp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        Protect-TgfrStateFile -Path $tmp
        if ($New) { [IO.File]::Move($tmp, $script:TgfrStatePath) }
        else { [IO.File]::Replace($tmp, $script:TgfrStatePath, [NullString]::Value) }
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}
function Protect-TgfrStateFile([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'The recovery journal must be an ordinary file.'}
    $acl=[Security.AccessControl.FileSecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-32-544','S-1-5-18')) {
        $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','Allow')
        [void]$acl.AddAccessRule($rule)
    }
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
function Assert-TgfrStateFileTrusted {
    $item=Get-Item -LiteralPath $script:TgfrStatePath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'The recovery journal must be an ordinary file.'}
    if ($item.Length -gt 16777216) {throw 'The recovery journal exceeds its supported size.'}
    $acl=Get-Acl -LiteralPath $script:TgfrStatePath -ErrorAction Stop
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-32-544','S-1-5-18')) {throw 'The recovery journal owner is not Administrators or SYSTEM.'}
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-32-544','S-1-5-18')) {throw 'The recovery journal allows an unexpected account access.'}
    }
}
function Assert-TgfrStateDirectoryTrusted {
    $item=Get-Item -LiteralPath $script:TgfrStateRoot -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'The session directory must not be a junction or symbolic link.'}
    $acl=Get-Acl -LiteralPath $script:TgfrStateRoot -ErrorAction Stop
    $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if (-not $acl.AreAccessRulesProtected -or $owner -notin @('S-1-5-32-544','S-1-5-18')) {throw 'The existing recovery directory is not administrator protected. Its contents will not be used for privileged restoration.'}
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-32-544','S-1-5-18')) {throw 'The recovery directory allows an unexpected account access. Review its ownership and permissions first.'}
    }
}
function Read-TgfrState {
    if (-not [IO.File]::Exists($script:TgfrStatePath)) { return $null }
    Assert-TgfrStateDirectoryTrusted
    Assert-TgfrStateFileTrusted
    $state = [IO.File]::ReadAllText($script:TgfrStatePath) | ConvertFrom-Json
    if ($state.version -ne 7 -or $state.machineId -ne (Get-TgfrMachineId) -or -not $state.sessionId) { throw 'Invalid or foreign session journal. Keep the file and inspect it before recovery.' }
    $state
}
function Close-TgfrState($State) {
    $State.phase = 'Restored'
    Save-TgfrState $State
    $archive = Join-Path $script:TgfrStateRoot ('restored-' + $State.sessionId + '.json')
    [IO.File]::Move($script:TgfrStatePath, $archive)
}
function Get-TgfrRegistryRoot([string]$Hive) {
    $h = switch ($Hive) { 'HKLM' {[Microsoft.Win32.RegistryHive]::LocalMachine} default {throw 'Unsupported registry hive.'} }
    [Microsoft.Win32.RegistryKey]::OpenBaseKey($h, [Microsoft.Win32.RegistryView]::Registry64)
}
function Get-TgfrRegValue([string]$Hive, [string]$Path, [string]$Name) {
    $root = Get-TgfrRegistryRoot $Hive
    $key = $null
    try {

        $key = $root.OpenSubKey($Path,$false)
        if ($null -eq $key) { return @{exists=$false; keyExists=$false} }
        if ($key.GetValueNames() -notcontains $Name) { return @{exists=$false; keyExists=$true} }
        $value = $key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = $key.GetValueKind($Name).ToString()
        if ($kind -in @('Binary','None')) { $value = [Convert]::ToBase64String([byte[]]$value) }
        @{exists=$true; keyExists=$true; kind=$kind; value=$value}
    } finally { if ($key) {$key.Dispose()}; $root.Dispose() }
}
function Set-TgfrRegValue([string]$Hive, [string]$Path, [string]$Name, $Snapshot) {
    $root = Get-TgfrRegistryRoot $Hive
    $key = $null
    try {

        if ($Snapshot.exists) {
            $key = $root.CreateSubKey($Path)
            $kind = [Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$Snapshot.kind)
            $value = $Snapshot.value
            switch ([string]$Snapshot.kind) {
                'DWord' {$value=[int]$value}
                'QWord' {$value=[long]$value}
                'MultiString' {$value=[string[]]@($value)}
                'Binary' {$value=[Convert]::FromBase64String([string]$value)}
                'None' {$value=[Convert]::FromBase64String([string]$value)}
                default {$value=[string]$value}
            }
            $key.SetValue($Name,$value,$kind)
        } else {
            $key = $root.OpenSubKey($Path,$true)
            if ($key) { $key.DeleteValue($Name,$false) }
        }
    } finally { if ($key) {$key.Dispose()}; $root.Dispose() }
}
function Test-TgfrRegEqual($A,$B) {
    if ([bool]$A.exists -ne [bool]$B.exists) { return $false }
    if (-not $A.exists) { return $true }
    ($A.kind -eq $B.kind) -and (($A.value | ConvertTo-Json -Compress) -ceq ($B.value | ConvertTo-Json -Compress))
}
function New-TgfrVpnChange {
    # Settings Page Visibility is a device-level preference, not a traffic block.
    $path = 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $old = Get-TgfrRegValue HKLM $path 'SettingsPageVisibility'
    $new = 'hide:network-vpn'
    if ($old.exists) {
        if ($old.kind -ne 'String') { throw 'The existing SettingsPageVisibility value has an unexpected type.' }
        $existing = [string]$old.value
        if ($existing.StartsWith('hide:',[StringComparison]::OrdinalIgnoreCase)) {
            $parts = @($existing.Substring(5).Split(';') | Where-Object {$_})
            if ($parts -notcontains 'network-vpn') { $parts += 'network-vpn' }
            $new = 'hide:' + ($parts -join ';')
        } elseif ($existing.StartsWith('showonly:',[StringComparison]::OrdinalIgnoreCase)) {
            $parts = @($existing.Substring(9).Split(';') | Where-Object {$_})
            if ($parts -notcontains 'network-vpn') { $new=$existing }
            else { throw 'An existing showonly Settings policy includes VPN. Adjust that policy centrally before selecting this option.' }
        } elseif ($existing) { throw 'An existing Settings visibility policy cannot be safely merged.' }
    }
    @{hive='HKLM';path=$path;name='SettingsPageVisibility';old=$old;new=@{exists=$true;kind='String';value=$new};attempted=$false}
}
function Get-TgfrAdapterEnabled($Adapter) {
    if ([string]$Adapter.AdminStatus -in @('Up','1')) { return $true }
    if ([string]$Adapter.AdminStatus -in @('Down','2')) { return $false }
    if ([string]$Adapter.Status -eq 'Disabled') {return $false}
    if ([string]$Adapter.Status -in @('Up','Disconnected','Not Present','NotPresent')) {return $true}
    throw ('Cannot determine administrative state for adapter ' + $Adapter.Name)
}
function Get-TgfrAdapterById([string]$Guid) {
    $guidValue = [guid]$Guid
    $matches = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object { $_.InterfaceGuid -and ([guid]$_.InterfaceGuid -eq $guidValue) })
    if ($matches.Count -ne 1) { throw ('Expected one adapter with GUID ' + $Guid + '; found ' + $matches.Count) }
    $matches[0]
}
function New-TgfrNetworkPlan($Options) {
    $result=@()
    if (-not ($Options.Wifi -or $Options.Ethernet)) { return $result }
    foreach ($a in @(Get-NetAdapter -Physical -IncludeHidden -ErrorAction Stop)) {
        $medium = [int]$a.NdisPhysicalMedium
        $type = [int]$a.InterfaceType
        if (-not $type -and $a.ifType) { $type = [int]$a.ifType }
        $kind = ''
        if ($type -eq 71 -or $medium -in @(1,9)) { $kind='Wifi' }
        elseif (($type -eq 6 -or $medium -eq 14) -and $medium -ne 10) {$kind='Ethernet'}
        if ($kind -and [bool]$Options[$kind]) {
            $result += @{guid=([guid]$a.InterfaceGuid).ToString();name=[string]$a.Name;kind=$kind;originalEnabled=(Get-TgfrAdapterEnabled $a);attempted=$false}
        }
    }
    foreach ($kind in @('Wifi','Ethernet')) {
        if ($Options[$kind] -and -not @($result | Where-Object kind -eq $kind).Count) { throw ('No physical ' + $kind + ' adapter was detected. Clear that option to continue.') }
    }
    $result
}
function Assert-TgfrAppsClosed($Options,$Plan=$null) {
    $names=@()
    if ($Options.Calculator) {$names+=@('CalculatorApp.exe','Calculator.exe','calc.exe','win32calc.exe')}
    if ($Options.Store) {$names+=@('WinStore.App.exe','Microsoft.WindowsStore.exe')}
    if ($Options.Excel) {$names+='EXCEL.EXE'}
    if ($Plan -and $Plan.blockedProcessNames) {
        foreach($name in @($Plan.blockedProcessNames)) {
            $value=[string]$name
            if (-not $value.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase)) {$value+='.exe'}
            $names+=$value
        }
    }
    if (-not $names.Count) {return}
    $running=@(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {$names -contains $_.Name} | Select-Object -ExpandProperty Name -Unique)
    if ($running.Count) {throw ('Close these apps in ALL signed-in sessions before enabling: ' + ($running -join ', ') + '. Existing processes must be closed; the new policy governs subsequent launches.')}
}
function Get-TgfrEarlierStatePaths {
    $found=[Collections.Generic.List[string]]::new()
    if ($env:ProgramData) {
        $old=Join-Path $env:ProgramData 'TGFR_ExamMode_v6\session.json'
        if ([IO.File]::Exists($old)) {$found.Add($old)}
    }
    foreach($profile in @(Get-CimInstance Win32_UserProfile -ErrorAction Stop)) {
        if ($profile.Special -or -not $profile.LocalPath) {continue}
        $old=Join-Path $profile.LocalPath 'AppData\Local\TGFR_Exam_Mode_GUI\original_state.json'
        if ([IO.File]::Exists($old)) {$found.Add($old)}
    }
    return $found.ToArray()
}
function Assert-TgfrNoEarlierSession {
    $old=@(Get-TgfrEarlierStatePaths)
    if ($old.Count) {throw ('An earlier TGFR release has an active recovery file. Restore that session with its original release before using version 7. Keep the recovery file: '+($old -join '; '))}
}
function Get-TgfrSessionInfo {
    try {
        $state=Read-TgfrState
        if ($state) {return @{Active=$true;Phase=$state.phase;WordPath=$(if ($state.word) {$state.word.Path} else {''});Message=('Saved session: '+$state.phase+'. Use Verify to check current settings.');Options=$state.options}}
        $legacy=@(Get-TgfrEarlierStatePaths)
        $message='Ready. No v7 session has been applied.'
        if ($legacy.Count) {$message='Earlier-version recovery file found. Restore that session with its original release first.'}
        @{Active=$false;Phase='Ready';Message=$message;Options=@{}}
    } catch { @{Active=$true;Phase='Recovery required';Message=$_.Exception.Message;Options=@{}} }
}
function Get-TgfrVerification {
    $lines=[System.Collections.Generic.List[string]]::new()
    $ok=$true
    $state=Read-TgfrState
    if (-not $state) {return @{Ok=$false;Message='No active v7 session to verify.';Lines=@('Existing restrictions from other software are not assessed.')}}
    if ($state.phase -ne 'Active') {$ok=$false;$lines.Add('Session phase: '+$state.phase+'; restore/recovery may be required.')}
    if ($state.appPlan) {
        $check=Test-TgfrAppPlan -Plan $state.appPlan
        if (-not $check.Ok) {$ok=$false}
        foreach($line in @($check.Details)) {$lines.Add([string]$line)}
        try {Assert-TgfrAppsClosed $state.options $state.appPlan} catch {$ok=$false;$lines.Add($_.Exception.Message)}
    }
    foreach($change in @($state.registryChanges)) {
        try {
            if (-not (Test-TgfrRegEqual (Get-TgfrRegValue $change.hive $change.path $change.name) $change.new)) {throw 'value differs'}
            $lines.Add('VPN Settings page visibility value matches. VPN connections and clients are not blocked by this option.')
        } catch {$ok=$false;$lines.Add('VPN settings: '+$_.Exception.Message)}
    }
    foreach($adapter in @($state.adapters)) {
        try {
            $a=Get-TgfrAdapterById $adapter.guid
            if (Get-TgfrAdapterEnabled $a) {throw 'still enabled'}
            $lines.Add($adapter.kind+' / '+$adapter.name+': administratively disabled.')
        } catch {$ok=$false;$lines.Add($adapter.name+': '+$_.Exception.Message)}
    }
    if ($state.word) {
        try {
            $check=Test-TgfrWordExamCopy -Path $state.word.Path
            if (-not $check.Ok) {$ok=$false}
            foreach($line in @($check.Details)) {$lines.Add([string]$line)}
        } catch {$ok=$false;$lines.Add('Word copy: '+$_.Exception.Message)}
    }
    $message='Configuration checks passed. Test the selected functions and any prepared exam document.'
    if ($state.appPlan -and $state.appPlan.enabled) {$message+=' Application policy applies to all users; test new app launches.'}
    if (-not $ok) {$message='Verification incomplete or configuration changed. Read the Diagnostics tab.'}
    @{Ok=$ok;Message=$message;Lines=@($lines.ToArray())}
}
function Undo-TgfrSession($State) {
    $errors=[System.Collections.Generic.List[string]]::new()
    # Restore connectivity first, even if a later application-policy conflict remains.
    foreach ($adapter in @($State.adapters)) {
        if (-not $adapter.attempted) {continue}
        try {
            $a=Get-TgfrAdapterById $adapter.guid
            if ((Get-TgfrAdapterEnabled $a) -ne [bool]$adapter.originalEnabled) {
                if ($adapter.originalEnabled) {Enable-NetAdapter -InputObject $a -Confirm:$false -ErrorAction Stop | Out-Null}
                else {Disable-NetAdapter -InputObject $a -Confirm:$false -ErrorAction Stop | Out-Null}
            }
            if ((Get-TgfrAdapterEnabled (Get-TgfrAdapterById $adapter.guid)) -ne [bool]$adapter.originalEnabled) {throw 'restore verification failed'}
        } catch {$errors.Add($adapter.name+': '+$_.Exception.Message)}
    }
    foreach($change in @($State.registryChanges)) {
        if (-not $change.attempted) {continue}
        try {
            $now=Get-TgfrRegValue $change.hive $change.path $change.name
            if (Test-TgfrRegEqual $now $change.old) {continue}
            if (-not (Test-TgfrRegEqual $now $change.new)) {throw 'value changed outside this tool; preserved for review'}
            Set-TgfrRegValue $change.hive $change.path $change.name $change.old
            if (-not (Test-TgfrRegEqual (Get-TgfrRegValue $change.hive $change.path $change.name) $change.old)) {throw 'restore verification failed'}
        } catch {$errors.Add($change.name+': '+$_.Exception.Message)}
    }
    if ($State.appAttempted -and $State.appPlan) {
        try {
            $result = Undo-TgfrAppPlan -Plan $State.appPlan
            if (-not $result.Ok) { throw ($result.Details -join '; ') }
            foreach ($line in @($result.Details)) { Write-TgfrLog ([string]$line) }
        } catch {$errors.Add('Application policy: '+$_.Exception.Message)}
    }
    # Deliberately retain the exam copy. It may contain the candidate's work.
    @($errors.ToArray())
}
function Invoke-TgfrEnableCore([hashtable]$Options,[string]$WordSource,[string]$WordDestination) {
    Assert-TgfrAdmin
    if (Read-TgfrState) {throw 'Restore the existing session before applying a different selection.'}
    Assert-TgfrNoEarlierSession
    if (-not @($Options.Values | Where-Object {$_ -eq $true}).Count) {throw 'Select at least one option.'}
    Assert-TgfrAppsClosed $Options
    $appPlan=$null
    if ($Options.Calculator -or $Options.Store -or $Options.Excel) {
        Write-TgfrLog 'Preparing device-wide application restrictions with Windows App Control.'
        $appPlan=New-TgfrAppPlan -Options $Options
        foreach ($line in @($appPlan['planningDetails'])) {
            if ($line) { Write-TgfrLog ([string]$line) }
        }
    }
    $changes=@()
    if ($Options.Vpn) {$changes+=New-TgfrVpnChange}
    $adapters=@(New-TgfrNetworkPlan $Options)
    if ($Options.Proofing) {
        if (-not $WordDestination -or [IO.Path]::GetExtension($WordDestination) -ine '.docx') {throw 'Choose a new .docx output on the Word document tab.'}
        if ([IO.File]::Exists($WordDestination)) {throw 'The Word output already exists. Choose another filename to preserve the existing work.'}
        if (($Options.Wifi -or $Options.Ethernet) -and $WordDestination.StartsWith('\\')) {throw 'Save the Word exam copy on a local disk before disconnecting networking.'}
    }
    Initialize-TgfrStateDirectory
    $state=@{version=7;sessionId=[guid]::NewGuid().ToString('N');machineId=(Get-TgfrMachineId);createdUtc=[DateTime]::UtcNow.ToString('o');scope='Device';options=$Options;phase='Prepared';appPlan=$appPlan;appAttempted=$false;registryChanges=$changes;adapters=$adapters;word=$null}
    Save-TgfrState $state -New
    try {
        $state.phase='Applying';Save-TgfrState $state
        if ($Options.Proofing) {
            Write-TgfrLog 'Preparing a separate Word exam document with NoProofing enabled.'
            $state.word=New-TgfrWordExamCopy -SourcePath $WordSource -DestinationPath $WordDestination
            Save-TgfrState $state
        }
        if ($appPlan) {Assert-TgfrAppsClosed $Options $appPlan;$state.appAttempted=$true;Save-TgfrState $state;Invoke-TgfrAppPlan -Plan $appPlan | ForEach-Object {Write-TgfrLog ([string]$_)}}
        foreach($change in $state.registryChanges) {
            if (-not (Test-TgfrRegEqual (Get-TgfrRegValue $change.hive $change.path $change.name) $change.old)) {throw 'VPN visibility policy changed during preflight.'}
            $change.attempted=$true;Save-TgfrState $state
            Set-TgfrRegValue $change.hive $change.path $change.name $change.new
        }
        foreach($adapter in $state.adapters) {
            if (-not $adapter.originalEnabled) {continue}
            $adapter.attempted=$true;Save-TgfrState $state
            Write-TgfrLog ('Disabling '+$adapter.name+'.')
            Disable-NetAdapter -InputObject (Get-TgfrAdapterById $adapter.guid) -Confirm:$false -ErrorAction Stop | Out-Null
        }
        $state.phase='Active';Save-TgfrState $state
        $check=Get-TgfrVerification
        foreach($line in $check.Lines) {Write-TgfrLog $line}
        if (-not $check.Ok) {throw $check.Message}
        $check.Message
    } catch {
        $reason=$_.Exception.Message
        Write-TgfrLog ('Apply failed: '+$reason+' Restoring attempted machine changes.')
        $errors=@(Undo-TgfrSession $state)
        if (-not $errors.Count) {Close-TgfrState $state;throw ($reason+' Attempted machine changes were restored. Any prepared Word copy was retained.')}
        $state.phase='Recovery required';Save-TgfrState $state
        throw ($reason+' Recovery incomplete; backup retained. '+($errors -join ' | '))
    }
}
function Invoke-TgfrRestoreCore {
    Assert-TgfrAdmin
    $state=Read-TgfrState
    if (-not $state) {return 'No v7 session is active.'}
    $state.phase='Restoring';Save-TgfrState $state
    $errors=@(Undo-TgfrSession $state)
    if ($errors.Count) {$state.phase='Recovery required';Save-TgfrState $state;throw ($errors -join [Environment]::NewLine)}
    Close-TgfrState $state
    $message='Recorded machine settings restored. Exam documents and candidate work were kept.'
    if ($state.appPlan -and $state.appPlan.enabled) {$message+=' This app''s owned application policy is no longer active or installed.'}
    return $message
}

function Invoke-TgfrWithMutationLock([scriptblock]$Operation) {
    $mutex = [Threading.Mutex]::new($false, 'Global\TGFR_ExamModeV7_Mutation')
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Another Exam Mode operation is running. Wait for that operation to finish.' }
        & $Operation
    } finally { if ($acquired) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
function Invoke-TgfrEnable([hashtable]$Options,[string]$WordSource,[string]$WordDestination) {
    Invoke-TgfrWithMutationLock { Invoke-TgfrEnableCore -Options $Options -WordSource $WordSource -WordDestination $WordDestination }
}
function Invoke-TgfrRestore { Invoke-TgfrWithMutationLock { Invoke-TgfrRestoreCore } }

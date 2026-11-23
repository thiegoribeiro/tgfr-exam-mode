# TGFR Exam Mode 7.0 application control. Windows PowerShell 5.1.
# Defines functions only. Planning writes disposable compiler files, never policy.
# Persist the returned plan in the protected machine journal before Invoke-*.

function Write-TgfrCiLog {
    param([string]$Message)
    if (Get-Command Write-TgfrLog -ErrorAction SilentlyContinue) { Write-TgfrLog $Message }
    else { Write-Verbose $Message }
}
function Get-TgfrCiDigest {
    param([byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function ConvertFrom-TgfrCiXml {
    param([string]$Text)
    $settings=[Xml.XmlReaderSettings]::new(); $settings.DtdProcessing='Prohibit'; $settings.XmlResolver=$null
    $stream=[IO.StringReader]::new($Text); $reader=[Xml.XmlReader]::Create($stream,$settings)
    try { $doc=[Xml.XmlDocument]::new(); $doc.XmlResolver=$null; $doc.Load($reader) }
    finally { $reader.Dispose(); $stream.Dispose() }
    if ($doc.DocumentElement.LocalName -ne 'SiPolicy' -or $doc.DocumentElement.NamespaceURI -ne 'urn:schemas-microsoft-com:sipolicy') { throw 'Unexpected App Control policy XML root/namespace.' }
    return ,$doc
}
function Get-TgfrCiNs {
    param([xml]$Doc)
    $ns=[Xml.XmlNamespaceManager]::new($Doc.NameTable); $ns.AddNamespace('ci','urn:schemas-microsoft-com:sipolicy')
    return ,$ns
}
function Get-TgfrCiToolPath {
    $folder='System32'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $folder='Sysnative' }
    $path=Join-Path $env:SystemRoot ($folder+'\CiTool.exe')
    if (-not [IO.File]::Exists($path)) { throw 'Windows CiTool.exe is unavailable. Application restrictions need Windows 11 22H2 or later with its built-in App Control tools.' }
    return $path
}
function Invoke-TgfrCiTool {
    param([ValidateSet('List','Install','Remove')][string]$Operation,[string]$Value='')
    $tool=Get-TgfrCiToolPath
    $argsForTool=switch ($Operation) {
        'List' { @('-lp','-json') }
        'Install' {
            if (-not [IO.File]::Exists($Value)) { throw 'The prepared policy file is missing.' }
            @('-up',$Value,'-json')
        }
        'Remove' { @('-rp',([guid]$Value).ToString('B'),'-json') }
    }
    $output=@(& $tool @argsForTool 2>&1); $code=$LASTEXITCODE
    if ($code -ne 0) { throw ('CiTool '+$Operation+' failed (exit '+$code+'): '+($output -join ' ')) }
    $text=$output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($text)) { throw ('CiTool '+$Operation+' returned no JSON result.') }
    try { $data=$text | ConvertFrom-Json -ErrorAction Stop }
    catch { throw ('CiTool '+$Operation+' returned invalid JSON: '+$_.Exception.Message) }
    if ($data.PSObject.Properties['OperationResult'] -and [long]$data.OperationResult -ne 0) { throw ('CiTool '+$Operation+' operation result: '+$data.OperationResult) }
    return $data
}
function Get-TgfrCiInventory {
    $data=Invoke-TgfrCiTool -Operation List
    if (-not $data.PSObject.Properties['Policies'] -or $null -eq $data.Policies) { throw 'CiTool policy inventory is unavailable; no deployment/removal is permitted.' }
    $seen=@{}; $result=[Collections.Generic.List[object]]::new()
    foreach ($row in @($data.Policies)) {
        try { $id=([guid]$row.PolicyID).ToString('B').ToUpperInvariant() }
        catch { throw 'CiTool returned a policy without a valid GUID.' }
        if ($seen.ContainsKey($id)) { throw ('Duplicate policy ID returned by CiTool: '+$id) }
        $seen[$id]=$true
        if (-not $row.PSObject.Properties['IsSystemPolicy'] -or $row.IsSystemPolicy -isnot [bool]) { throw ('CiTool ownership metadata is unavailable for '+$id+'. No policy was changed.') }
        $result.Add($row)
    }
    return $result.ToArray()
}
function Get-TgfrCiInventorySignature {
    param([object[]]$Inventory,[string]$ExcludeId='')
    $lines=foreach ($row in @($Inventory)) {
        $id=([guid]$row.PolicyID).ToString('B')
        if ($ExcludeId -and [guid]$id -eq [guid]$ExcludeId) { continue }
        $fields=foreach ($name in @('PolicyID','BasePolicyID','FriendlyName','Version','VersionString','IsSystemPolicy','IsSignedPolicy','IsEnforced','IsOnDisk','IsAuthorized')) {
            $value='(absent)'
            if ($row.PSObject.Properties[$name]) { $value=[string]$row.$name }
            $name+'='+$value
        }
        $fields -join '|'
    }
    return (@($lines | Sort-Object) -join "`n")
}
function Assert-TgfrCiPlatform {
    if ($env:OS -ne 'Windows_NT') { throw 'Application restrictions require the affected Windows device.' }
    $os=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $build=[int]$os.CurrentBuildNumber
    if ($build -lt 22621 -or [string]$os.InstallationType -ne 'Client') { throw 'This application-control backend requires Windows 11 22H2 or later. Network and Word options can be used separately.' }
    [void](Get-TgfrCiToolPath)
    Import-Module ConfigCI -ErrorAction Stop
    foreach ($cmd in @('New-CIPolicyRule','Merge-CIPolicy','Set-CIPolicyIdInfo','ConvertFrom-CIPolicy','Get-AppxPackage')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw ('Required Windows component is unavailable: '+$cmd) }
    }
    $template=Join-Path $env:SystemRoot 'schemas\CodeIntegrity\ExamplePolicies\AllowAll.xml'
    if (-not [IO.File]::Exists($template)) { throw 'The built-in Windows AllowAll App Control template is missing.' }
    return @{build=$build;template=$template}
}
function Get-TgfrCiTargets {
    param([hashtable]$Options)
    $packages=[Collections.Generic.List[object]]::new(); $paths=[Collections.Generic.List[string]]::new()
    $processes=[Collections.Generic.List[string]]::new(); $notes=[Collections.Generic.List[string]]::new()
    $targets=@()
    if ($Options.Calculator) { $targets+='Microsoft.WindowsCalculator'; foreach ($n in @('Calculator','CalculatorApp','calc','win32calc')) { $processes.Add($n) } }
    if ($Options.Store) { $targets+='Microsoft.WindowsStore'; foreach ($n in @('WinStore.App','Microsoft.WindowsStore')) { $processes.Add($n) } }
    foreach ($name in $targets) {
        $installed=@(Get-AppxPackage -AllUsers -Name $name -ErrorAction Stop)
        $pfns=@($installed | ForEach-Object { [string]$_.PackageFamilyName } | Sort-Object -Unique)
        if ($pfns.Count -eq 0) {
            # These exact inbox family identities also cover later installation.
            $pfns=@($name+'_8wekyb3d8bbwe')
            $notes.Add($name+' is not installed; its standard inbox family identity will still be denied.')
        }
        foreach ($pfn in $pfns) {
            if ($pfn -notmatch ('^'+[regex]::Escape($name)+'_[A-Za-z0-9]+$')) { throw ('Unexpected package family identity for '+$name) }
            $packages.Add(@{name=$name;pfn=$pfn;installed=($installed.Count -gt 0)})
        }
    }
    if ($Options.Calculator) {
        foreach ($dir in @('System32','SysWOW64')) {
            foreach ($name in @('calc.exe','win32calc.exe')) {
                $p=Join-Path $env:SystemRoot ($dir+'\'+$name)
                if ([IO.File]::Exists($p) -and -not $paths.Contains($p)) { $paths.Add($p) }
            }
        }
    }
    if ($Options.Excel) {
        $processes.Add('EXCEL')
        if (@(Get-AppxPackage -AllUsers -Name 'Microsoft.Office.Desktop' -ErrorAction Stop).Count -gt 0) {
            throw 'Packaged Microsoft Office Desktop is installed. This package-rule design cannot isolate Excel from Word inside the same package. Use the ordinary desktop Office installation for Excel-only restriction, or leave Excel unselected; no broad Office package block was applied.'
        }
        $excel=[Collections.Generic.List[string]]::new()
        foreach ($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryHive]::CurrentUser)) {
            foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
                $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                try {
                    $key=$base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe',$false)
                    if ($key) { try { $p=[string]$key.GetValue(''); if ($p) { $excel.Add($p.Trim('"')) } } finally { $key.Dispose() } }
                } finally { $base.Dispose() }
            }
        }
        foreach ($root in @($env:ProgramFiles,${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
            foreach ($suffix in @('Microsoft Office\root\Office16\EXCEL.EXE','Microsoft Office\Office16\EXCEL.EXE','Microsoft Office\Office15\EXCEL.EXE','Microsoft Office\Office14\EXCEL.EXE')) { $excel.Add((Join-Path $root $suffix)) }
        }
        $existing=@($excel | Where-Object { [IO.File]::Exists($_) } | Sort-Object -Unique)
        if ($existing.Count -eq 0) { throw 'Excel is selected, but its desktop executable could not be found in App Paths or standard Office locations. Install/register desktop Excel or leave that option unselected.' }
        foreach ($p in $existing) {
            if ([IO.Path]::GetFileName($p) -ine 'EXCEL.EXE') { throw ('An Excel App Paths registration points to a different executable: '+$p+'. Correct the registration before restricting Excel.') }
            if ($p -match '[\\/]WindowsApps[\\/]') { throw 'Excel is installed inside a package; an Excel-only desktop file rule cannot be claimed to block that packaged suite.' }
            if (-not $paths.Contains($p)) { $paths.Add($p) }
        }
    }
    return @{packages=@($packages.ToArray());exePaths=@($paths.ToArray());blockedProcessNames=@($processes.ToArray());notes=@($notes.ToArray())}
}
function Assert-TgfrCiExecutableIdentity {
    param([string]$Path,[string]$OriginalFilename)
    $leaf=[IO.Path]::GetFileName($Path)
    $allowed=switch ($leaf.ToLowerInvariant()) {
        'excel.exe' { @('EXCEL.EXE') }
        'calc.exe' { @('calc.exe','win32calc.exe','calc.exe.mui','win32calc.exe.mui') }
        'win32calc.exe' { @('calc.exe','win32calc.exe','calc.exe.mui','win32calc.exe.mui') }
        default { throw ('Unexpected executable selected for application restriction: '+$Path) }
    }
    $original=$OriginalFilename.Trim().Trim([char]0)
    if ($original -and $allowed -notcontains $original) { throw ('Executable identity mismatch: '+$Path+' declares OriginalFilename='+$original+'. No rule for that unrelated program was generated.') }
    return $original
}
function Get-TgfrCiExpectedFileIdentities {
    param([string]$Path,[string]$OriginalFilename)
    $original=Assert-TgfrCiExecutableIdentity -Path $Path -OriginalFilename $OriginalFilename
    if (-not $original) { return @() }
    if ([IO.Path]::GetFileName($Path) -in @('calc.exe','win32calc.exe')) {
        # Localised Calculator version resources can expose the MUI identity;
        # ConfigCI may use the corresponding neutral executable identity.
        $canonical=$original -replace '(?i)\.mui$',''
        return @($canonical,($canonical+'.mui'))
    }
    return @($original)
}
function Add-TgfrCiPackageRules {
    param([xml]$Doc,[object[]]$Packages)
    if (@($Packages).Count -eq 0) { return }
    $ns=Get-TgfrCiNs $Doc; $uri=$Doc.DocumentElement.NamespaceURI
    $files=$Doc.SelectSingleNode('/ci:SiPolicy/ci:FileRules',$ns)
    $product=$Doc.SelectSingleNode('/ci:SiPolicy/ci:SigningScenarios/ci:SigningScenario[@Value="12"]/ci:ProductSigners',$ns)
    if (-not $files -or -not $product) { throw 'The policy template lacks its user-mode rule containers.' }
    $refs=$product.SelectSingleNode('ci:FileRulesRef',$ns)
    if (-not $refs) { $refs=$Doc.CreateElement('FileRulesRef',$uri); [void]$product.AppendChild($refs) }
    $allow=$Doc.CreateElement('Allow',$uri); $allow.SetAttribute('ID','ID_ALLOW_TGFR_PACKAGES')
    $allow.SetAttribute('FriendlyName','Other package families remain allowed by this policy')
    $allow.SetAttribute('PackageFamilyName','*'); $allow.SetAttribute('PackageVersion','0.0.0.0'); [void]$files.AppendChild($allow)
    $ref=$Doc.CreateElement('FileRuleRef',$uri); $ref.SetAttribute('RuleID',$allow.GetAttribute('ID')); [void]$refs.AppendChild($ref)
    $index=0
    foreach ($package in @($Packages)) {
        $index++; $deny=$Doc.CreateElement('Deny',$uri); $deny.SetAttribute('ID',('ID_DENY_TGFR_PACKAGE_'+$index))
        $deny.SetAttribute('FriendlyName','TGFR '+[string]$package.name)
        $deny.SetAttribute('PackageFamilyName',[string]$package.pfn); $deny.SetAttribute('PackageVersion','65535.65535.65535.65535'); [void]$files.AppendChild($deny)
        $ref=$Doc.CreateElement('FileRuleRef',$uri); $ref.SetAttribute('RuleID',$deny.GetAttribute('ID')); [void]$refs.AppendChild($ref)
    }
}
function Set-TgfrCiOwnedOptions {
    param([xml]$Doc)
    $ns=Get-TgfrCiNs $Doc; $uri=$Doc.DocumentElement.NamespaceURI
    $rules=$Doc.SelectSingleNode('/ci:SiPolicy/ci:Rules',$ns)
    if (-not $rules) { throw 'The App Control template lacks Rules.' }
    $rules.RemoveAll()
    foreach ($option in @('Enabled:UMCI','Enabled:Unsigned System Integrity Policy','Disabled:Script Enforcement','Required:Enforce Store Applications','Enabled:Update Policy No Reboot')) {
        $r=$Doc.CreateElement('Rule',$uri); $o=$Doc.CreateElement('Option',$uri); $o.InnerText=$option; [void]$r.AppendChild($o); [void]$rules.AppendChild($r)
    }
    $hvci=$Doc.SelectSingleNode('/ci:SiPolicy/ci:HvciOptions',$ns)
    if ($hvci) { $hvci.InnerText='0' }
    $version=$Doc.SelectSingleNode('/ci:SiPolicy/ci:VersionEx',$ns)
    if (-not $version) { throw 'The policy template lacks VersionEx.' }
    $version.InnerText='1.0.0.0'
    $settings=$Doc.SelectSingleNode('/ci:SiPolicy/ci:Settings',$ns)
    if (-not $settings) { $settings=$Doc.CreateElement('Settings',$uri); [void]$Doc.DocumentElement.AppendChild($settings) }
    foreach ($old in @($settings.SelectNodes('ci:Setting[@Provider="AllHostIds" and @Key="AllKeys" and @ValueName="EnterpriseDefinedClsId"]',$ns))) { [void]$settings.RemoveChild($old) }
    $com=$Doc.CreateElement('Setting',$uri); $com.SetAttribute('Provider','AllHostIds'); $com.SetAttribute('Key','AllKeys'); $com.SetAttribute('ValueName','EnterpriseDefinedClsId')
    $value=$Doc.CreateElement('Value',$uri); $boolean=$Doc.CreateElement('Boolean',$uri); $boolean.InnerText='true'
    [void]$value.AppendChild($boolean); [void]$com.AppendChild($value); [void]$settings.AppendChild($com)
    # Settings are ordered as required by the policy schema/compiler.
    $ordered=@($settings.SelectNodes('ci:Setting',$ns) | Sort-Object @{Expression={$_.GetAttribute('Provider')}},@{Expression={$_.GetAttribute('Key')}},@{Expression={$_.GetAttribute('ValueName')}})
    foreach ($setting in $ordered) { [void]$settings.RemoveChild($setting); [void]$settings.AppendChild($setting) }
    foreach ($attribute in @($Doc.SelectNodes('/ci:SiPolicy/ci:FileRules/ci:FileAttrib',$ns))) {
        # A deny must cover older and future versions of this exact file identity.
        $attribute.SetAttribute('MinimumFileVersion','0.0.0.0'); $attribute.SetAttribute('MaximumFileVersion','65535.65535.65535.65535')
    }
}
function Assert-TgfrCiOwnedXml {
    param([xml]$Doc,[string]$PolicyId,[object[]]$Packages=@(),[string[]]$ExpectedFileNames=@())
    $ns=Get-TgfrCiNs $Doc; $root=$Doc.DocumentElement
    if ($root.GetAttribute('PolicyType') -ne 'Base Policy') { throw 'Only a separate base policy is accepted.' }
    $id=$Doc.SelectSingleNode('/ci:SiPolicy/ci:PolicyID',$ns); $base=$Doc.SelectSingleNode('/ci:SiPolicy/ci:BasePolicyID',$ns)
    if (-not $id -or -not $base -or [guid]$id.InnerText -ne [guid]$PolicyId -or [guid]$base.InnerText -ne [guid]$PolicyId -or [guid]$PolicyId -eq [guid]::Empty) { throw 'The owned policy IDs do not agree.' }
    if ($Doc.SelectNodes('/ci:SiPolicy/ci:PolicyTypeID',$ns).Count) { throw 'Legacy single-policy format is not accepted.' }
    $wanted=@('Enabled:UMCI','Enabled:Unsigned System Integrity Policy','Disabled:Script Enforcement','Required:Enforce Store Applications','Enabled:Update Policy No Reboot')
    $options=@($Doc.SelectNodes('/ci:SiPolicy/ci:Rules/ci:Rule/ci:Option',$ns) | ForEach-Object { $_.InnerText })
    if ($options.Count -ne $wanted.Count -or @(Compare-Object $wanted $options).Count) { throw 'Unexpected policy options. This policy must be unsigned, enforced, and leave script enforcement disabled.' }
    if ($Doc.SelectNodes('/ci:SiPolicy/ci:UpdatePolicySigners/* | /ci:SiPolicy/ci:SupplementalPolicySigners/*',$ns).Count) { throw 'Signing/update authorisations are not permitted in this temporary unsigned policy.' }
    $hvci=$Doc.SelectSingleNode('/ci:SiPolicy/ci:HvciOptions',$ns)
    if ($hvci -and $hvci.InnerText -ne '0') { throw 'This exam policy must not change memory integrity settings.' }
    $com=$Doc.SelectSingleNode('/ci:SiPolicy/ci:Settings/ci:Setting[@Provider="AllHostIds" and @Key="AllKeys" and @ValueName="EnterpriseDefinedClsId"]/ci:Value/ci:Boolean',$ns)
    if (-not $com -or $com.InnerText -cne 'true') { throw 'The standalone exam policy must leave COM object registration unrestricted.' }
    $ids=@{}
    foreach ($node in @($Doc.SelectNodes('//*[@ID]',$ns))) {
        $value=$node.GetAttribute('ID'); if ($ids.ContainsKey($value)) { throw ('Duplicate policy element ID: '+$value) }; $ids[$value]=$node
    }
    foreach ($value in @('12','131')) {
        $scenario=@($Doc.SelectNodes('/ci:SiPolicy/ci:SigningScenarios/ci:SigningScenario',$ns) | Where-Object { $_.GetAttribute('Value') -eq $value })
        if ($scenario.Count -ne 1) { throw ('Expected exactly one signing scenario '+$value) }
        $allowAll=$false
        foreach ($ref in @($scenario[0].SelectNodes('ci:ProductSigners/ci:FileRulesRef/ci:FileRuleRef',$ns))) {
            $rid=$ref.GetAttribute('RuleID'); if (-not $ids.ContainsKey($rid)) { throw 'A signing scenario references an absent file rule.' }
            $rule=$ids[$rid]
            if ($rule.LocalName -eq 'Allow' -and $rule.GetAttribute('FileName') -eq '*' -and $rule.Attributes.Count -le 3) { $allowAll=$true }
            if ($value -eq '131' -and $rule.LocalName -ne 'Allow') { throw 'Kernel-mode deny rules are not permitted in this exam policy.' }
        }
        if (-not $allowAll) { throw ('The standalone policy lacks its broad allow baseline for scenario '+$value+'. It must not be deployed.') }
        if ($value -eq '131' -and $scenario[0].SelectNodes('.//ci:DeniedSigners/*',$ns).Count) { throw 'Kernel-mode denied signers are not permitted.' }
    }
    $userRefs=@($Doc.SelectNodes('/ci:SiPolicy/ci:SigningScenarios/ci:SigningScenario[@Value="12"]/ci:ProductSigners/ci:FileRulesRef/ci:FileRuleRef',$ns) | ForEach-Object { $_.GetAttribute('RuleID') })
    $pfns=@($Packages | ForEach-Object { [string]$_.pfn }); $foundPfns=@()
    foreach ($deny in @($Doc.SelectNodes('/ci:SiPolicy/ci:FileRules/ci:Deny',$ns))) {
        if ($userRefs -notcontains $deny.GetAttribute('ID')) { throw 'A deny file rule is not referenced in user mode.' }
        $pfn=$deny.GetAttribute('PackageFamilyName'); $hash=$deny.GetAttribute('Hash')
        if ($pfn) {
            if ($pfns -notcontains $pfn -or $pfn -match '[*?]' -or $deny.GetAttribute('PackageVersion') -ne '65535.65535.65535.65535') { throw 'A package deny is broad, unexpected or version-limited.' }
            $foundPfns+=$pfn
        } elseif ($hash -notmatch '^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64}|[0-9a-fA-F]{128})$') { throw 'Only exact package identities or executable hashes are permitted as direct deny rules.' }
    }
    if ((@($pfns | Sort-Object -Unique) -join '|') -cne (@($foundPfns | Sort-Object -Unique) -join '|')) { throw 'A selected package deny is missing.' }
    if ($pfns.Count -gt 0) {
        $allows=@($Doc.SelectNodes('/ci:SiPolicy/ci:FileRules/ci:Allow[@PackageFamilyName="*"]',$ns))
        if ($allows.Count -ne 1 -or $allows[0].GetAttribute('PackageVersion') -ne '0.0.0.0' -or $userRefs -notcontains $allows[0].GetAttribute('ID')) { throw 'The complete package-family allow baseline is missing.' }
    }
    $deniedSignerRefs=@($Doc.SelectNodes('/ci:SiPolicy/ci:SigningScenarios/ci:SigningScenario[@Value="12"]/ci:ProductSigners/ci:DeniedSigners/ci:DeniedSigner',$ns))
    foreach ($ref in $deniedSignerRefs) {
        $sid=$ref.GetAttribute('SignerId'); if (-not $ids.ContainsKey($sid)) { throw 'A denied signer is absent.' }
        $signer=$ids[$sid]
        $attrs=@($signer.SelectNodes('ci:FileAttribRef',$ns))
        if ($attrs.Count -eq 0 -or -not $signer.SelectSingleNode('ci:CertRoot',$ns)) { throw 'A broad publisher deny was generated; deployment was stopped.' }
        foreach ($a in $attrs) {
            $aid=$a.GetAttribute('RuleID'); if (-not $ids.ContainsKey($aid)) { throw 'A denied signer attribute is absent.' }
            $attr=$ids[$aid]; $name=$attr.GetAttribute('FileName')
            if (-not $name -or $name -match '[*?\\/]' -or $ExpectedFileNames -notcontains $name -or
                $attr.GetAttribute('MinimumFileVersion') -ne '0.0.0.0' -or $attr.GetAttribute('MaximumFileVersion') -ne '65535.65535.65535.65535') { throw 'The executable publisher deny is not restricted to the expected file identity and full version range.' }
        }
    }
    if ($Doc.SelectNodes('/ci:SiPolicy/ci:FileRules/ci:Deny',$ns).Count -eq 0 -and $deniedSignerRefs.Count -eq 0) { throw 'No application deny rules were generated.' }
}
function New-TgfrAppPlan {
    param([hashtable]$Options)
    if (-not ($Options.Calculator -or $Options.Store -or $Options.Excel)) { return @{enabled=$false} }
    $platform=Assert-TgfrCiPlatform; $inventory=@(Get-TgfrCiInventory)
    Write-TgfrCiLog ('Windows build '+$platform.build+'; application-control scope is this entire device.')
    Write-TgfrCiLog ('App Control inventory: '+$inventory.Count+' existing policies; all existing IDs will be preserved.')
    $targets=Get-TgfrCiTargets $Options
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('TGFR_CI_Build_'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    try {
        $xmlPath=Join-Path $temp 'Exam.xml'; $binPath=Join-Path $temp 'Exam.cip'
        $rules=[Collections.Generic.List[object]]::new(); $expectedNames=[Collections.Generic.List[string]]::new()
        foreach ($path in @($targets.exePaths)) {
            $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($path)
            $original=Assert-TgfrCiExecutableIdentity -Path $path -OriginalFilename ([string]$info.OriginalFilename)
            if ($original) {
                foreach ($identity in @(Get-TgfrCiExpectedFileIdentities -Path $path -OriginalFilename $original)) { if (-not $expectedNames.Contains($identity)) { $expectedNames.Add($identity) } }
                $generated=@(New-CIPolicyRule -DriverFilePath $path -Level FilePublisher -Fallback Hash -SpecificFileNameLevel OriginalFileName -Deny -ErrorAction Stop)
            } else {
                # Missing signed file-name metadata must never produce a publisher-only deny.
                $generated=@(New-CIPolicyRule -DriverFilePath $path -Level Hash -Deny -ErrorAction Stop)
            }
            $userRules=@($generated | Where-Object { $_.UserMode -eq $true })
            if ($userRules.Count -eq 0) { throw ('No user-mode identity rule was generated for '+$path) }
            foreach ($rule in $userRules) { $rules.Add($rule) }
        }
        if ($rules.Count -gt 0) { Merge-CIPolicy -PolicyPaths $platform.template -Rules $rules.ToArray() -OutputFilePath $xmlPath -ErrorAction Stop | Out-Null }
        else { [IO.File]::Copy($platform.template,$xmlPath,$false) }
        Set-CIPolicyIdInfo -FilePath $xmlPath -ResetPolicyID -PolicyName 'TGFR Exam Mode 7.0' -ErrorAction Stop | Out-Null
        $doc=ConvertFrom-TgfrCiXml ([IO.File]::ReadAllText($xmlPath)); $ns=Get-TgfrCiNs $doc
        $policyId=([guid]$doc.SelectSingleNode('/ci:SiPolicy/ci:PolicyID',$ns).InnerText).ToString('B').ToUpperInvariant()
        if (@($inventory | Where-Object { [guid]$_.PolicyID -eq [guid]$policyId }).Count) { throw 'The new policy ID already exists; no deployment was attempted.' }
        $policyName='TGFR Exam Mode 7.0 '+$policyId
        Set-CIPolicyIdInfo -FilePath $xmlPath -PolicyName $policyName -ErrorAction Stop | Out-Null
        $doc=ConvertFrom-TgfrCiXml ([IO.File]::ReadAllText($xmlPath))
        Set-TgfrCiOwnedOptions $doc
        Add-TgfrCiPackageRules -Doc $doc -Packages @($targets.packages)
        Assert-TgfrCiOwnedXml -Doc $doc -PolicyId $policyId -Packages @($targets.packages) -ExpectedFileNames @($expectedNames.ToArray())
        $doc.Save($xmlPath)
        ConvertFrom-CIPolicy -XmlFilePath $xmlPath -BinaryFilePath $binPath -ErrorAction Stop | Out-Null
        $bytes=[IO.File]::ReadAllBytes($binPath)
        if ($bytes.Length -lt 64 -or $bytes.Length -gt 16777216) { throw 'The policy compiler produced an unexpected binary size.' }
        $details=@('Application restrictions use an independent device-wide App Control policy. All users, including administrators, are in scope.',
            ('Windows build: '+$platform.build+'.'),
            ('Owned policy ID: '+$policyId),('Existing policy inventory count: '+$inventory.Count+'. Existing policies are not rewritten.'),
            'The policy is enforced and unsigned; script enforcement is disabled in this policy.',
            'Configuration verification does not replace actual launch tests. Browser and third-party calculators are outside the named targets.')+@($targets.notes)
        $details+=('Selected package families: '+@($targets.packages).Count+'. Executable paths: '+@($targets.exePaths).Count+'.')
        foreach ($package in @($targets.packages)) { $details+=('Package deny: '+$package.pfn) }
        foreach ($path in @($targets.exePaths)) { $details+=('Executable deny target: '+$path) }
        if ($platform.build -lt 26100) { $details+='This Windows version may require a restart to finish removing the unsigned policy. Restore retains recovery until absence or an inactive, unpersisted state is verified.' }
        $finalNs=Get-TgfrCiNs $doc
        if ($doc.SelectNodes('/ci:SiPolicy/ci:FileRules/ci:Deny[@Hash]',$finalNs).Count -gt 0) { $details+='Executable hash fallback rules are present. They cover the current file bytes; after application updates, restore and create a fresh exam plan, then test launches again.' }
        return @{enabled=$true;backend='AppControl';scope='Device';policyId=$policyId;policyName=$policyName;policyXml=$doc.OuterXml;
            binaryBase64=[Convert]::ToBase64String($bytes);binarySha256=(Get-TgfrCiDigest $bytes);packages=@($targets.packages);exePaths=@($targets.exePaths);
            expectedFileNames=@($expectedNames.ToArray());blockedProcessNames=@($targets.blockedProcessNames);windowsBuild=$platform.build;
            originalInventory=@($inventory);originalInventorySignature=(Get-TgfrCiInventorySignature $inventory);planningDetails=$details}
    } finally { if ([IO.Directory]::Exists($temp)) { [IO.Directory]::Delete($temp,$true) } }
}
function Assert-TgfrCiPlan {
    param($Plan)
    if ([string]$Plan.backend -ne 'AppControl' -or [string]$Plan.scope -ne 'Device') { throw 'This is not a supported version 7 device policy plan.' }
    $id=([guid]$Plan.policyId).ToString('B').ToUpperInvariant()
    if ([string]$Plan.policyName -cne ('TGFR Exam Mode 7.0 '+$id)) { throw 'The saved policy ownership name does not match its recorded ID.' }
    $doc=ConvertFrom-TgfrCiXml ([string]$Plan.policyXml)
    Assert-TgfrCiOwnedXml -Doc $doc -PolicyId $id -Packages @($Plan.packages) -ExpectedFileNames @($Plan.expectedFileNames)
    $ns=Get-TgfrCiNs $doc
    $name=$doc.SelectSingleNode('/ci:SiPolicy/ci:Settings/ci:Setting[@Provider="PolicyInfo" and @Key="Information" and @ValueName="Name"]/ci:Value/ci:String',$ns)
    if (-not $name -or $name.InnerText -cne [string]$Plan.policyName) { throw 'The saved XML policy name differs from the deployment record.' }
    $bytes=[Convert]::FromBase64String([string]$Plan.binaryBase64)
    if ($bytes.Length -lt 64 -or (Get-TgfrCiDigest $bytes) -cne [string]$Plan.binarySha256) { throw 'The saved compiled policy fingerprint does not match.' }
    if (@($Plan.originalInventory | Where-Object { [guid]$_.PolicyID -eq [guid]$id }).Count) { throw 'The saved ID was present before this session and is not owned by it.' }
}
function Get-TgfrCiOwnedEntry {
    param($Plan,[object[]]$Inventory)
    $matches=@($Inventory | Where-Object { [guid]$_.PolicyID -eq [guid]$Plan.policyId })
    if ($matches.Count -gt 1) { throw 'Duplicate owned policy IDs were returned.' }
    if ($matches.Count -eq 0) { return $null }
    $row=$matches[0]
    if ($row.IsSystemPolicy -isnot [bool] -or $row.IsSystemPolicy) { throw 'The recorded policy is Windows-managed or ownership is unavailable; it was not changed.' }
    if (-not $row.PSObject.Properties['IsSignedPolicy'] -or $row.IsSignedPolicy -isnot [bool] -or $row.IsSignedPolicy) { throw 'The recorded policy is signed or its signature state is unavailable; this unsigned-policy restore will not modify it.' }
    if ([guid]$row.BasePolicyID -ne [guid]$Plan.policyId -or [string]$row.FriendlyName -cne [string]$Plan.policyName) { throw 'The deployed policy identity differs from the saved deployment record; no removal was attempted.' }
    return $row
}
function Get-TgfrCiInstalledFile {
    param($Plan)
    return Join-Path $env:SystemRoot ('System32\CodeIntegrity\CiPolicies\Active\'+([guid]$Plan.policyId).ToString('B')+'.cip')
}
function Assert-TgfrCiInstalledFingerprint {
    param($Plan,$Entry)
    $path=Get-TgfrCiInstalledFile $Plan
    if ([IO.File]::Exists($path)) {
        if ((Get-TgfrCiDigest ([IO.File]::ReadAllBytes($path))) -cne [string]$Plan.binarySha256) { throw 'The deployed policy file changed outside this session. Its policy ID was left untouched; keep the recovery journal for review.' }
        return $true
    }
    if ($Entry.PSObject.Properties['IsOnDisk'] -and $Entry.IsOnDisk -is [bool] -and -not $Entry.IsOnDisk) { return $false }
    throw 'The recorded policy exists, but its installed file cannot be verified. No update or removal was attempted.'
}
function Test-TgfrCiPolicyRetired {
    param($Plan,$Entry)
    return ($Entry.PSObject.Properties['IsEnforced'] -and $Entry.IsEnforced -is [bool] -and -not $Entry.IsEnforced -and
        $Entry.PSObject.Properties['IsOnDisk'] -and $Entry.IsOnDisk -is [bool] -and -not $Entry.IsOnDisk -and
        -not [IO.File]::Exists((Get-TgfrCiInstalledFile $Plan)))
}
function Invoke-TgfrAppPlan {
    param($Plan)
    if (-not $Plan.enabled) { return }
    Assert-TgfrCiPlan $Plan
    $inventory=@(Get-TgfrCiInventory)
    if (@($inventory | Where-Object { [guid]$_.PolicyID -eq [guid]$Plan.policyId }).Count) { throw 'The planned policy ID is already present; no policy was overwritten.' }
    if ((Get-TgfrCiInventorySignature $inventory) -cne [string]$Plan.originalInventorySignature) { throw 'The device policy inventory changed after planning. Refresh and retry; no exam policy was deployed.' }
    if (-not [IO.Directory]::Exists($script:TgfrStateRoot)) { throw 'The protected session directory must exist before deployment.' }
    $folder=Join-Path $script:TgfrStateRoot ('Policy-'+([guid]$Plan.policyId).ToString('N'))
    if ([IO.Directory]::Exists($folder)) { throw 'The owned policy staging directory already exists. Restore the saved session before applying another.' }
    [void][IO.Directory]::CreateDirectory($folder)
    $cip=Join-Path $folder (([guid]$Plan.policyId).ToString('B')+'.cip')
    $xml=Join-Path $folder 'ExamPolicy.xml'
    [IO.File]::WriteAllBytes($cip,[Convert]::FromBase64String([string]$Plan.binaryBase64))
    [IO.File]::WriteAllText($xml,[string]$Plan.policyXml,[Text.UTF8Encoding]::new($false))
    if ((Get-TgfrCiDigest ([IO.File]::ReadAllBytes($cip))) -cne [string]$Plan.binarySha256) { throw 'The staged policy file failed its fingerprint check.' }
    Write-TgfrCiLog ('Deploying owned device policy '+$Plan.policyId+'.')
    [void](Invoke-TgfrCiTool -Operation Install -Value $cip)
    $result=Test-TgfrAppPlan $Plan
    if (-not $result.Ok) { throw ('Application policy verification failed: '+($result.Details -join '; ')) }
}
function Test-TgfrAppPlan {
    param($Plan)
    if (-not $Plan.enabled) { return @{Ok=$true;Details=@('Application restrictions were not selected.')} }
    $details=[Collections.Generic.List[string]]::new(); $ok=$true
    try {
        Assert-TgfrCiPlan $Plan
        $inventory=@(Get-TgfrCiInventory); $entry=Get-TgfrCiOwnedEntry -Plan $Plan -Inventory $inventory
        if (-not $entry) { throw 'The owned exam policy is absent from the Windows policy inventory.' }
        if ($entry.IsEnforced -isnot [bool] -or -not $entry.IsEnforced) { $ok=$false; $details.Add('The owned policy is not currently active. A restart or management-policy review may be needed.') }
        if (-not (Assert-TgfrCiInstalledFingerprint -Plan $Plan -Entry $entry)) { $ok=$false; $details.Add('The owned policy file is no longer on disk; runtime removal may be awaiting a restart.') }
        if ((Get-TgfrCiInventorySignature -Inventory $inventory -ExcludeId $Plan.policyId) -cne [string]$Plan.originalInventorySignature) {
            $details.Add('Other policy inventory details changed after this session began. Those policies were left untouched; review the external change separately.')
        }
        $details.Add('Owned policy ID: '+$Plan.policyId+'. Scope: all users of this device.')
        if ($ok) { $details.Add('The recorded enforced-policy XML, compiled file fingerprint and active Windows inventory entry agree.') }
        $details.Add('This is a configuration check. Close and actually launch each selected app under the exam account to validate blocking.')
    } catch { $ok=$false; $details.Add($_.Exception.Message) }
    return @{Ok=$ok;Details=@($details.ToArray())}
}
function Undo-TgfrAppPlan {
    param($Plan)
    if (-not $Plan.enabled) { return @{Ok=$true;Details=@()} }
    $details=[Collections.Generic.List[string]]::new()
    Assert-TgfrCiPlan $Plan
    $inventory=@(Get-TgfrCiInventory); $entry=Get-TgfrCiOwnedEntry -Plan $Plan -Inventory $inventory
    if (-not $entry) {
        if ([IO.File]::Exists((Get-TgfrCiInstalledFile $Plan))) {
            return @{Ok=$false;Details=@('The owned policy ID is absent from the inventory, but its installed policy file still exists. Recovery is retained because that file could activate later. No removal command or file deletion was attempted without inventory ownership metadata; review the inconsistent Windows policy state, then retry Restore.')}
        }
        return @{Ok=$true;Details=@('The owned exam policy is already absent from both inventory and its installed file location. Other device policies were not changed.')}
    }
    if (-not (Assert-TgfrCiInstalledFingerprint -Plan $Plan -Entry $entry)) {
        if (Test-TgfrCiPolicyRetired -Plan $Plan -Entry $entry) { return @{Ok=$true;Details=@('The owned exam policy is no longer active or persisted. An inactive inventory record remains; other device policies were not changed.')} }
        return @{Ok=$false;Details=@('The owned policy is still listed but its file has been removed. Restart Windows, then run Restore again; the recovery journal is retained. Other policies were not changed.')}
    }
    Write-TgfrCiLog ('Removing only owned device policy '+$Plan.policyId+'.')
    [void](Invoke-TgfrCiTool -Operation Remove -Value ([string]$Plan.policyId))
    $after=@(Get-TgfrCiInventory)
    $remaining=Get-TgfrCiOwnedEntry -Plan $Plan -Inventory $after
    if (-not $remaining -and [IO.File]::Exists((Get-TgfrCiInstalledFile $Plan))) {
        return @{Ok=$false;Details=@('Windows accepted removal and no longer lists the owned policy ID, but its installed file still exists. Recovery is retained until both states agree. No additional removal command or file deletion was attempted; review the inconsistent Windows policy state, then retry Restore.')}
    }
    if ($remaining -and -not (Test-TgfrCiPolicyRetired -Plan $Plan -Entry $remaining)) { return @{Ok=$false;Details=@('Windows accepted the removal request, but the owned policy remains active or persisted. Restart Windows and run Restore again. The recovery journal is retained; no other policy was removed.')} }
    $details.Add('The owned exam policy is absent or no longer active/persisted. Existing organisation and Windows policies were preserved.')
    if ((Get-TgfrCiInventorySignature $inventory $Plan.policyId) -cne (Get-TgfrCiInventorySignature $after $Plan.policyId)) {
        $details.Add('External policy inventory details also changed during restore; the tool issued no update/removal command for those IDs.')
    }
    return @{Ok=$true;Details=@($details.ToArray())}
}

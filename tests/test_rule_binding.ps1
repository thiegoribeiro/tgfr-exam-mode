param(
    [string]$SourcePath=(Join-Path $PSScriptRoot '../src/app_control.ps1'),
    [switch]$ExpectOriginalFailure
)
$ErrorActionPreference='Stop'
. $SourcePath
$script:passed=0
function Assert-T([bool]$Condition,[string]$Message) {
    if(-not $Condition){throw ('FAIL: '+$Message)}
    $script:passed++; Write-Output ('PASS: '+$Message)
}
function Assert-Throws([scriptblock]$Action,[string]$Pattern,[string]$Message) {
    $caught='';try{& $Action | Out-Null}catch{$caught=$_.Exception.Message}
    Assert-T ($caught -match $Pattern) ($Message+' [matched: '+$caught+']')
}

# Representative native object identity and strict array-binding contract. This is
# NOT the Windows ConfigCI implementation; no policy is deployed by this test.
Add-Type -TypeDefinition @'
namespace Microsoft.SecureBoot.UserConfig {
    public class Rule {
        public bool UserMode { get; set; }
        public string Tag { get; set; }
    }
}
'@
function New-FixtureRule([bool]$UserMode,[string]$Tag) {
    $r=[Microsoft.SecureBoot.UserConfig.Rule]::new();$r.UserMode=$UserMode;$r.Tag=$Tag
    return $r
}
$script:root=Join-Path ([IO.Path]::GetTempPath()) ('TGFR_rules_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:root)
$script:templatePath=Join-Path $script:root 'AllowAll.xml'
$script:exePath=Join-Path $script:root 'EXCEL.EXE'
$script:secondExePath=Join-Path $script:root 'calc.exe'
[IO.File]::WriteAllText($script:exePath,'Test fixture, not an executable.')
[IO.File]::WriteAllText($script:secondExePath,'Second test fixture, not an executable.')
[IO.File]::WriteAllText($script:templatePath,@'
<SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy" PolicyType="Base Policy">
 <VersionEx>1.0.0.0</VersionEx><PolicyID>{11111111-1111-1111-1111-111111111111}</PolicyID><BasePolicyID>{11111111-1111-1111-1111-111111111111}</BasePolicyID>
 <PlatformID>{2E07F7E4-194C-4D20-B7C9-6F44A6C5A234}</PlatformID><Rules><Rule><Option>Enabled:Audit Mode</Option></Rule></Rules><EKUs/>
 <FileRules><Allow ID="ID_ALLOW_K" FriendlyName="Kernel" FileName="*"/><Allow ID="ID_ALLOW_U" FriendlyName="User" FileName="*"/></FileRules><Signers/>
 <SigningScenarios><SigningScenario Value="131" ID="ID_SC_K"><ProductSigners><FileRulesRef><FileRuleRef RuleID="ID_ALLOW_K"/></FileRulesRef></ProductSigners></SigningScenario><SigningScenario Value="12" ID="ID_SC_U"><ProductSigners><FileRulesRef><FileRuleRef RuleID="ID_ALLOW_U"/></FileRulesRef></ProductSigners></SigningScenario></SigningScenarios>
 <UpdatePolicySigners/><CiSigners/><HvciOptions>0</HvciOptions><Settings><Setting Provider="PolicyInfo" Key="Information" ValueName="Name"><Value><String>Template</String></Value></Setting></Settings>
</SiPolicy>
'@)
$script:shape='TypedList';$script:identity='';$script:mergeCalls=0;$script:compilerCalls=0;$script:mutationCalls=0;$script:secondTarget=$false
$script:boundRules=@();$script:emittedUsers=@();$script:requestedLevel=''
function Assert-TgfrCiPlatform { @{build=22631;template=$script:templatePath} }
function Get-TgfrCiInventory { return @() }
function Get-TgfrCiTargets {
    param($Options)
    $paths=@($script:exePath);if($script:secondTarget){$paths+=@($script:secondExePath)}
    @{packages=@();exePaths=$paths;blockedProcessNames=@('EXCEL');notes=@()}
}
# PE metadata varies by host. Only this identity lookup is mocked; the planner,
# collection conversion, policy post-processing and ownership validation are real.
function Assert-TgfrCiExecutableIdentity { param($Path,$OriginalFilename) return $script:identity }
function Invoke-TgfrCiTool { param($Operation,$Value) $script:mutationCalls++;throw 'Unexpected native mutation during planning.' }
function New-CIPolicyRule {
    [CmdletBinding()]
    param($DriverFilePath,$Level,$Fallback,$SpecificFileNameLevel,[switch]$Deny)
    $script:requestedLevel=$Level
    if(-not $Deny){throw 'Fixture expected deny rule generation.'}
    $u1=New-FixtureRule $true 'User1';$u2=New-FixtureRule $true 'User2';$k=New-FixtureRule $false 'Kernel'
    $script:emittedUsers=@($u1,$u2)
    $list=[Collections.Generic.List[Microsoft.SecureBoot.UserConfig.Rule]]::new()
    $list.Add($u1);$list.Add($k);$list.Add($u2)
    if($script:secondTarget -and $DriverFilePath -eq $script:secondExePath) { $list.Clear();$list.Add($k);Write-Output -NoEnumerate $list;return }
    switch($script:shape) {
        'Scalar' { $script:emittedUsers=@($u1);return $u1 }
        'Pipeline' { return @($u1,$k,$u2) }
        'RuleArray' { Write-Output -NoEnumerate ([Microsoft.SecureBoot.UserConfig.Rule[]]@($u1,$k,$u2));return }
        'TypedList' { Write-Output -NoEnumerate $list;return }
        'NestedList' {
            $outer=[Collections.Generic.List[object]]::new();$outer.Add($list)
            $inner=[Collections.ArrayList]::new();[void]$inner.Add((New-FixtureRule $false 'NestedKernel'))
            $u3=New-FixtureRule $true 'User3';[void]$inner.Add($u3);$script:emittedUsers+=@($u3)
            $outer.Add($inner);Write-Output -NoEnumerate $outer;return
        }
        'OnlyKernel' { $list.Clear();$list.Add($k);$script:emittedUsers=@();Write-Output -NoEnumerate $list;return }
        'EmptyCollection' { $list.Clear();$script:emittedUsers=@();Write-Output -NoEnumerate $list;return }
        'Null' { $script:emittedUsers=@();return $null }
        'UnexpectedObject' { $script:emittedUsers=@();return [pscustomobject]@{UserMode=$true;Tag='Not a native rule'} }
        'String' { $script:emittedUsers=@();return 'Not a native rule' }
        'Dictionary' { $script:emittedUsers=@();return @{UserMode=$true;Tag='Not a native rule'} }
        'SelfCycle' { $cycle=[Collections.ArrayList]::new();[void]$cycle.Add($cycle);Write-Output -NoEnumerate $cycle;return }
        default { throw 'Unknown fixture shape.' }
    }
}
function Merge-CIPolicy {
    [CmdletBinding()]
    param([string[]]$PolicyPaths,[Microsoft.SecureBoot.UserConfig.Rule[]]$Rules,[string]$OutputFilePath)
    $script:mergeCalls++;$script:boundRules=$Rules
    $d=ConvertFrom-TgfrCiXml ([IO.File]::ReadAllText($PolicyPaths[0]));$n=Get-TgfrCiNs $d;$uri=$d.DocumentElement.NamespaceURI
    for($i=0;$i -lt $Rules.Count;$i++) {
        if(-not $Rules[$i].UserMode){throw 'Kernel rule incorrectly passed to merge.'}
        $deny=$d.CreateElement('Deny',$uri);$deny.SetAttribute('ID',('ID_DENY_'+$i));$deny.SetAttribute('FriendlyName',$Rules[$i].Tag);$deny.SetAttribute('Hash',('A'*64))
        [void]$d.SelectSingleNode('/ci:SiPolicy/ci:FileRules',$n).AppendChild($deny)
        $ref=$d.CreateElement('FileRuleRef',$uri);$ref.SetAttribute('RuleID',('ID_DENY_'+$i))
        [void]$d.SelectSingleNode('//ci:SigningScenario[@Value="12"]/ci:ProductSigners/ci:FileRulesRef',$n).AppendChild($ref)
    }
    $d.Save($OutputFilePath)
}
function Set-CIPolicyIdInfo {
    [CmdletBinding()]
    param($FilePath,[switch]$ResetPolicyID,$PolicyName)
    $d=ConvertFrom-TgfrCiXml ([IO.File]::ReadAllText($FilePath));$n=Get-TgfrCiNs $d
    if($ResetPolicyID){$id=[guid]::NewGuid().ToString('B');$d.SelectSingleNode('/ci:SiPolicy/ci:PolicyID',$n).InnerText=$id;$d.SelectSingleNode('/ci:SiPolicy/ci:BasePolicyID',$n).InnerText=$id}
    $d.SelectSingleNode('/ci:SiPolicy/ci:Settings/ci:Setting[@ValueName="Name"]/ci:Value/ci:String',$n).InnerText=$PolicyName;$d.Save($FilePath)
}
function ConvertFrom-CIPolicy {
    [CmdletBinding()]
    param($XmlFilePath,$BinaryFilePath)
    $script:compilerCalls++
    [IO.File]::WriteAllBytes($BinaryFilePath,[Text.Encoding]::UTF8.GetBytes(('Mock compiler '+[IO.File]::ReadAllText($XmlFilePath))))
}
function Invoke-FixturePlan {
    $script:mergeCalls=0;$script:compilerCalls=0;$script:boundRules=@()
    return New-TgfrAppPlan -Options @{Calculator=$false;Store=$false;Excel=$true}
}
try {
    if($ExpectOriginalFailure) {
        Assert-Throws {Invoke-FixturePlan} 'Cannot convert.*System.Collections.Generic.List.*Microsoft.SecureBoot.UserConfig.Rule' 'original planner reproduces the reported generic-list parameter binding failure'
        Assert-T ($script:mergeCalls -eq 0 -and $script:compilerCalls -eq 0 -and $script:mutationCalls -eq 0) 'original failure occurs during binding, before merge/compiler/deployment'
        Write-Output ('ALL '+$script:passed+' BASELINE REPRODUCTION ASSERTIONS PASSED.')
        return
    }
    foreach($identity in @('','EXCEL.EXE')) {
        $script:identity=$identity;$level=if($identity){'FilePublisher'}else{'Hash'}
        foreach($shape in @('Scalar','Pipeline','RuleArray','TypedList','NestedList')) {
            $script:shape=$shape;$plan=Invoke-FixturePlan
            Assert-T ($plan.enabled -and $script:mergeCalls -eq 1 -and $script:compilerCalls -eq 1) ($level+'/'+$shape+': full executable planning reaches merge and compiler once')
            Assert-T ($script:requestedLevel -eq $level) ($level+'/'+$shape+': correct generation branch selected')
            Assert-T ($script:boundRules.Count -eq $script:emittedUsers.Count -and @($script:boundRules | Where-Object{-not $_.UserMode}).Count -eq 0) ($level+'/'+$shape+': only individual user-mode rules reach typed array parameter')
            for($i=0;$i -lt $script:boundRules.Count;$i++) {
                Assert-T ([object]::ReferenceEquals($script:boundRules[$i],$script:emittedUsers[$i])) ($level+'/'+$shape+': rule '+$i+' retains native type, identity and order')
            }
            Assert-T ($script:mutationCalls -eq 0) ($level+'/'+$shape+': planning makes no deployment/removal calls')
            Assert-TgfrCiPlan $plan
            Assert-T $true ($level+'/'+$shape+': resulting plan passes real ownership validation')
        }
    }
    foreach($shape in @('OnlyKernel','EmptyCollection','Null','UnexpectedObject','String','Dictionary','SelfCycle')) {
        $script:shape=$shape
        Assert-Throws {Invoke-FixturePlan} '(?i)rule|unsupported|unexpected|invalid' ($shape+': invalid or unusable output is rejected')
        Assert-T ($script:mergeCalls -eq 0 -and $script:compilerCalls -eq 0 -and $script:mutationCalls -eq 0) ($shape+': rejection precedes merge, compilation and deployment')
    }
    $script:shape='TypedList';$script:identity='';$script:secondTarget=$true
    Assert-Throws {Invoke-FixturePlan} 'No user-mode identity rule.*calc.exe' 'a valid first executable cannot mask a kernel-only second executable'
    Assert-T ($script:mergeCalls -eq 0 -and $script:compilerCalls -eq 0 -and $script:mutationCalls -eq 0) 'missing user-mode rules for any executable stop the complete plan before merge, compilation and deployment'
    Write-Output ('ALL '+$script:passed+' RULE BINDING ASSERTIONS PASSED; ConfigCI return shapes and native parameter contract are simulated, not Windows compilation/enforcement.')
} finally { if([IO.Directory]::Exists($script:root)){[IO.Directory]::Delete($script:root,$true)} }

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
# Representative ConfigCI types and Windows boundaries. This fixture does not
# establish native ConfigCI's implementation or change Windows file permissions.
Add-Type -TypeDefinition @'
namespace Microsoft.SecureBoot.UserConfig {
    public class Rule { public bool UserMode { get; set; } }
}
'@
$script:root=Join-Path ([IO.Path]::GetTempPath()) ('TGFR_template_tests_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:root)
$script:templatePath=Join-Path $script:root 'ProtectedAllowAll.xml'
$script:exePath=Join-Path $script:root 'EXCEL.EXE'
[IO.File]::WriteAllText($script:exePath,'Test fixture, not an executable.')
$template=@'
<SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy" PolicyType="Base Policy">
 <VersionEx>1.0.0.0</VersionEx><PolicyID>{11111111-1111-1111-1111-111111111111}</PolicyID><BasePolicyID>{11111111-1111-1111-1111-111111111111}</BasePolicyID>
 <PlatformID>{2E07F7E4-194C-4D20-B7C9-6F44A6C5A234}</PlatformID><Rules><Rule><Option>Enabled:Audit Mode</Option></Rule></Rules><EKUs/>
 <FileRules><Allow ID="ID_ALLOW_K" FriendlyName="Kernel" FileName="*"/><Allow ID="ID_ALLOW_U" FriendlyName="User" FileName="*"/></FileRules><Signers/>
 <SigningScenarios><SigningScenario Value="131" ID="ID_SC_K"><ProductSigners><FileRulesRef><FileRuleRef RuleID="ID_ALLOW_K"/></FileRulesRef></ProductSigners></SigningScenario><SigningScenario Value="12" ID="ID_SC_U"><ProductSigners><FileRulesRef><FileRuleRef RuleID="ID_ALLOW_U"/></FileRulesRef></ProductSigners></SigningScenario></SigningScenarios>
 <UpdatePolicySigners/><CiSigners/><HvciOptions>0</HvciOptions><Settings><Setting Provider="PolicyInfo" Key="Information" ValueName="Name"><Value><String>Template</String></Value></Setting></Settings>
</SiPolicy>
'@
$script:originalBytes=([Text.UTF8Encoding]::new($true).GetPreamble()+[Text.Encoding]::UTF8.GetBytes($template.Replace("`n","`r`n")))
[IO.File]::WriteAllBytes($script:templatePath,$script:originalBytes)
[IO.File]::SetAttributes($script:templatePath,[IO.FileAttributes]::ReadOnly)
$script:originalAttributes=[IO.File]::GetAttributes($script:templatePath)
$script:packageOnly=$false;$script:injectMergeFailure=$false;$script:mutationCalls=0
$script:mergeCalls=0;$script:ruleCalls=0;$script:idCalls=0;$script:compilerCalls=0
$script:mergeInput='';$script:outputPath='';$script:stagedBytesMatch=$false;$script:stagedWritable=$false
function Assert-TgfrCiPlatform { @{build=22631;template=$script:templatePath} }
function Get-TgfrCiInventory { return @() }
function Get-TgfrCiTargets {
    param($Options)
    if($script:packageOnly){return @{packages=@(@{name='Microsoft.WindowsStore';pfn='Microsoft.WindowsStore_8wekyb3d8bbwe';installed=$true});exePaths=@();blockedProcessNames=@('WinStore.App');notes=@()}}
    return @{packages=@();exePaths=@($script:exePath);blockedProcessNames=@('EXCEL');notes=@()}
}
function Invoke-TgfrCiTool { param($Operation,$Value) $script:mutationCalls++;throw 'Unexpected deployment/removal in planner test.' }
function New-CIPolicyRule {
    [CmdletBinding()]
    param($DriverFilePath,$Level,$Fallback,$SpecificFileNameLevel,[switch]$Deny)
    $script:ruleCalls++;$r=[Microsoft.SecureBoot.UserConfig.Rule]::new();$r.UserMode=$true;return $r
}
function Merge-CIPolicy {
    [CmdletBinding()]
    param([string[]]$PolicyPaths,[Microsoft.SecureBoot.UserConfig.Rule[]]$Rules,[string]$OutputFilePath)
    $script:mergeCalls++;$script:mergeInput=$PolicyPaths[0];$script:outputPath=$OutputFilePath
    # Simulate a ConfigCI boundary that requires writable/exclusive access.
    # Do not rely on root's Linux permissions to emulate a Windows system ACL.
    if($PolicyPaths[0] -eq $script:templatePath){throw [UnauthorizedAccessException]::new(('Access to the path '''+$PolicyPaths[0]+''' is denied.'))}
    if(([IO.File]::GetAttributes($PolicyPaths[0]) -band [IO.FileAttributes]::ReadOnly) -ne 0){throw 'The staged template inherited ReadOnly.'}
    $script:stagedBytesMatch=([Convert]::ToBase64String([IO.File]::ReadAllBytes($PolicyPaths[0])) -ceq [Convert]::ToBase64String($script:originalBytes))
    $file=[IO.File]::Open($PolicyPaths[0],[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$script:stagedWritable=$file.CanWrite}finally{$file.Dispose()}
    $d=ConvertFrom-TgfrCiXml ([IO.File]::ReadAllText($PolicyPaths[0]));$n=Get-TgfrCiNs $d;$uri=$d.DocumentElement.NamespaceURI
    # Exercise isolation even if a native tool rewrites its input file.
    [IO.File]::AppendAllText($PolicyPaths[0],"`n<!-- simulated input rewrite -->")
    if($script:injectMergeFailure){throw 'Injected merge failure after touching only the staged template.'}
    $deny=$d.CreateElement('Deny',$uri);$deny.SetAttribute('ID','ID_DENY_FIXTURE');$deny.SetAttribute('Hash',('A'*64))
    [void]$d.SelectSingleNode('/ci:SiPolicy/ci:FileRules',$n).AppendChild($deny)
    $ref=$d.CreateElement('FileRuleRef',$uri);$ref.SetAttribute('RuleID','ID_DENY_FIXTURE')
    [void]$d.SelectSingleNode('//ci:SigningScenario[@Value="12"]/ci:ProductSigners/ci:FileRulesRef',$n).AppendChild($ref)
    $d.Save($OutputFilePath)
}
function Set-CIPolicyIdInfo {
    [CmdletBinding()]
    param($FilePath,[switch]$ResetPolicyID,$PolicyName)
    $script:idCalls++;$script:outputPath=$FilePath
    if($FilePath -eq $script:templatePath){throw 'Protected template passed to identity writer.'}
    if(([IO.File]::GetAttributes($FilePath) -band [IO.FileAttributes]::ReadOnly) -ne 0){throw 'The output XML inherited ReadOnly.'}
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
    $script:mergeCalls=0;$script:ruleCalls=0;$script:idCalls=0;$script:compilerCalls=0
    $script:mergeInput='';$script:outputPath='';$script:stagedBytesMatch=$false;$script:stagedWritable=$false
    return New-TgfrAppPlan -Options @{Calculator=$false;Store=$script:packageOnly;Excel=(-not $script:packageOnly)}
}
function Assert-OriginalUnchanged([string]$Scenario) {
    Assert-T (([Convert]::ToBase64String([IO.File]::ReadAllBytes($script:templatePath))) -ceq [Convert]::ToBase64String($script:originalBytes)) ($Scenario+': original template bytes unchanged')
    Assert-T ([IO.File]::GetAttributes($script:templatePath) -eq $script:originalAttributes) ($Scenario+': original template attributes unchanged')
}
try {
    if($ExpectOriginalFailure){
        Assert-Throws {Invoke-FixturePlan} 'Access to the path.*ProtectedAllowAll.xml.*denied' 'original planner reproduces protected-input access denial at simulated ConfigCI boundary'
        Assert-T ($script:mergeCalls -eq 1 -and $script:compilerCalls -eq 0 -and $script:mutationCalls -eq 0) 'original failure precedes compilation and deployment'
        Assert-OriginalUnchanged 'Original failure'
        Write-Output ('ALL '+$script:passed+' TEMPLATE BASELINE ASSERTIONS PASSED; native Windows file access was simulated.')
        return
    }
    $plan=Invoke-FixturePlan
    Assert-T ($script:mergeCalls -eq 1 -and $script:compilerCalls -eq 1 -and $plan.enabled) 'executable plan reaches merge and compiler with working copy'
    Assert-T ($script:mergeInput -ne $script:templatePath -and [IO.Path]::GetDirectoryName($script:mergeInput) -eq [IO.Path]::GetDirectoryName($script:outputPath)) 'merge input and output are inside the disposable build directory'
    Assert-T $script:stagedBytesMatch 'staging preserves exact original bytes, including BOM and line endings'
    Assert-T $script:stagedWritable 'staged template supports writable exclusive open without inherited ReadOnly'
    Assert-T (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($script:outputPath))) 'successful executable plan removes disposable build directory'
    Assert-TgfrCiPlan $plan;Assert-T $true 'executable plan passes real XML and ownership validation'
    Assert-OriginalUnchanged 'Executable success'
    $script:packageOnly=$true;$plan=Invoke-FixturePlan
    Assert-T ($script:mergeCalls -eq 0 -and $script:ruleCalls -eq 0 -and $script:compilerCalls -eq 1) 'package-only plan uses writable staged template without executable rule generation'
    Assert-TgfrCiPlan $plan;Assert-T $true 'package-only plan passes real XML and ownership validation'
    Assert-T (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($script:outputPath))) 'successful package-only plan removes disposable build directory'
    Assert-OriginalUnchanged 'Package success'
    $script:packageOnly=$false;$script:injectMergeFailure=$true
    Assert-Throws {Invoke-FixturePlan} 'Injected merge failure' 'merge failure propagates after staged input rewrite'
    Assert-T ($script:compilerCalls -eq 0 -and -not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($script:mergeInput))) 'merge failure cleans temporary files and never compiles'
    Assert-OriginalUnchanged 'Merge failure'
    $script:injectMergeFailure=$false
    $before=@([IO.Directory]::GetDirectories([IO.Path]::GetTempPath(),'TGFR_CI_Build_*'))
    $locked=[IO.File]::Open($script:templatePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {Assert-Throws {Invoke-FixturePlan} 'Could not read the Windows policy template.*ProtectedAllowAll.xml' 'source read failure names the original template and fails clearly'}finally{$locked.Dispose()}
    Assert-T ($script:ruleCalls -eq 0 -and $script:mergeCalls -eq 0 -and $script:idCalls -eq 0 -and $script:compilerCalls -eq 0) 'source read failure stops before all ConfigCI commands'
    $added=@([IO.Directory]::GetDirectories([IO.Path]::GetTempPath(),'TGFR_CI_Build_*') | Where-Object{$_ -notin $before})
    Assert-T ($added.Count -eq 0) 'source read failure leaves no new temporary build directory'
    Assert-OriginalUnchanged 'Read failure'
    $destination=Join-Path $script:root 'Existing.xml';[IO.File]::WriteAllText($destination,'Existing content must remain')
    Assert-Throws {New-TgfrCiTemplateCopy -SourcePath $script:templatePath -DestinationPath $destination} 'Could not create the writable policy-template copy' 'staging refuses to overwrite an existing destination'
    Assert-T ([IO.File]::ReadAllText($destination) -ceq 'Existing content must remain') 'failed staging preserves existing destination bytes'
    Assert-T ($script:mutationCalls -eq 0) 'all tested planning paths make no deployment or removal calls'
    Write-Output ('ALL '+$script:passed+' TEMPLATE ACCESS ASSERTIONS PASSED; native ConfigCI write requirements are simulated, not Windows compilation/enforcement.')
} finally {
    if([IO.File]::Exists($script:templatePath)){[IO.File]::SetAttributes($script:templatePath,[IO.FileAttributes]::Normal)}
    if([IO.Directory]::Exists($script:root)){[IO.Directory]::Delete($script:root,$true)}
}

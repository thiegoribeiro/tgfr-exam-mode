$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/app_control.ps1')
$script:pass=0
function Assert-T([bool]$Condition,[string]$Message) { if(-not $Condition){throw ('FAIL: '+$Message)}; $script:pass++; Write-Output ('PASS: '+$Message) }
function Assert-Throws([scriptblock]$Action,[string]$Pattern,[string]$Message) {
    $caught='';try{& $Action}catch{$caught=$_.Exception.Message}
    Assert-T ($caught -match $Pattern) ($Message+' [matched: '+$caught+']')
}
$script:root=Join-Path ([IO.Path]::GetTempPath()) ('TGFR_v7_tests_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:root)
$template=@'
<SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy" PolicyType="Base Policy">
 <VersionEx>1.0.0.0</VersionEx><PolicyID>{11111111-1111-1111-1111-111111111111}</PolicyID><BasePolicyID>{11111111-1111-1111-1111-111111111111}</BasePolicyID>
 <PlatformID>{2E07F7E4-194C-4D20-B7C9-6F44A6C5A234}</PlatformID><Rules><Rule><Option>Enabled:Audit Mode</Option></Rule></Rules><EKUs/>
 <FileRules><Allow ID="ID_ALLOW_K" FriendlyName="Kernel" FileName="*"/><Allow ID="ID_ALLOW_U" FriendlyName="User" FileName="*"/></FileRules><Signers/>
 <SigningScenarios><SigningScenario Value="131" ID="ID_SC_K"><ProductSigners><FileRulesRef><FileRuleRef RuleID="ID_ALLOW_K"/></FileRulesRef></ProductSigners></SigningScenario><SigningScenario Value="12" ID="ID_SC_U"><ProductSigners><FileRulesRef><FileRuleRef RuleID="ID_ALLOW_U"/></FileRulesRef></ProductSigners></SigningScenario></SigningScenarios>
 <UpdatePolicySigners/><CiSigners/><HvciOptions>0</HvciOptions><Settings><Setting Provider="PolicyInfo" Key="Information" ValueName="Name"><Value><String>Template</String></Value></Setting></Settings>
</SiPolicy>
'@
$script:templatePath=Join-Path $script:root 'AllowAll.xml'
[IO.File]::WriteAllText($script:templatePath,$template)
$script:systemId='{22222222-2222-2222-2222-222222222222}'
$script:system=[pscustomobject]@{PolicyID=$script:systemId;BasePolicyID=$script:systemId;FriendlyName='Windows system policy';IsSystemPolicy=$true;IsSignedPolicy=$true;IsEnforced=$true;IsOnDisk=$false;IsAuthorized=$true;VersionString='10.0.0.0'}
$script:inv=@($script:system);$script:calls=[Collections.Generic.List[object]]::new();$script:pending=$false;$script:active=$true;$script:installError=$false;$script:keepRemovedFile=$false
$script:installed=Join-Path $script:root 'installed.cip'
function Assert-TgfrCiPlatform { @{build=22631;template=$script:templatePath} }
function Get-TgfrCiTargets {
 param($Options)
 @{packages=@(@{name='Microsoft.WindowsStore';pfn='Microsoft.WindowsStore_8wekyb3d8bbwe';installed=$true});exePaths=@();blockedProcessNames=@('WinStore.App');notes=@()}
}
function Set-CIPolicyIdInfo {
 param($FilePath,[switch]$ResetPolicyID,$PolicyName,$ErrorAction)
 $d=ConvertFrom-TgfrCiXml ([IO.File]::ReadAllText($FilePath));$n=Get-TgfrCiNs $d
 if($ResetPolicyID){$id=[guid]::NewGuid().ToString('B');$d.SelectSingleNode('/ci:SiPolicy/ci:PolicyID',$n).InnerText=$id;$d.SelectSingleNode('/ci:SiPolicy/ci:BasePolicyID',$n).InnerText=$id}
 $d.SelectSingleNode('/ci:SiPolicy/ci:Settings/ci:Setting[@ValueName="Name"]/ci:Value/ci:String',$n).InnerText=$PolicyName;$d.Save($FilePath)
}
function ConvertFrom-CIPolicy {
 param($XmlFilePath,$BinaryFilePath,$ErrorAction)
 # Compiler boundary only is mocked; generation/validation/lifecycle functions are real.
 [IO.File]::WriteAllBytes($BinaryFilePath,[Text.Encoding]::UTF8.GetBytes(('Mock CIP HEADER '+[IO.File]::ReadAllText($XmlFilePath))))
}
function Get-TgfrCiInstalledFile { param($Plan) $script:installed }
function Invoke-TgfrCiTool {
 param($Operation,$Value)
 if($Operation -eq 'List'){return [pscustomobject]@{Policies=@($script:inv)}}
 $script:calls.Add(@{Operation=$Operation;Value=$Value})
 if($Operation -eq 'Install'){
  [IO.File]::Copy($Value,$script:installed,$true)
  $p=$script:currentPlan
  $script:inv+= [pscustomobject]@{PolicyID=$p.policyId;BasePolicyID=$p.policyId;FriendlyName=$p.policyName;IsSystemPolicy=$false;IsSignedPolicy=$false;IsEnforced=$script:active;IsOnDisk=$true;IsAuthorized=$true;Version=281474976710656}
  if($script:installError){throw 'Injected deployment error after policy installation'}
 } elseif($Operation -eq 'Remove'){
  if($script:pending){([object[]]$script:inv | Where-Object{[guid]$_.PolicyID -eq [guid]$Value})[0].IsOnDisk=$false}
  else{$script:inv=@($script:inv | Where-Object{[guid]$_.PolicyID -ne [guid]$Value})}
  if(-not $script:keepRemovedFile -and [IO.File]::Exists($script:installed)){[IO.File]::Delete($script:installed)}
 }
 return [pscustomobject]@{OperationResult=0}
}
function New-Fixture {
 $script:inv=@($script:system);$script:calls.Clear();$script:pending=$false;$script:active=$true;$script:installError=$false;$script:keepRemovedFile=$false
 $script:TgfrStateRoot=Join-Path $script:root ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($script:TgfrStateRoot)
 if([IO.File]::Exists($script:installed)){[IO.File]::Delete($script:installed)}
 $script:currentPlan=New-TgfrAppPlan -Options @{Store=$true;Calculator=$false;Excel=$false}
 return $script:currentPlan
}
function Clone-Doc($Plan){return ,(ConvertFrom-TgfrCiXml $Plan.policyXml)}
function Check-Doc($Doc,$Plan){Assert-TgfrCiOwnedXml -Doc $Doc -PolicyId $Plan.policyId -Packages $Plan.packages -ExpectedFileNames @('EXCEL.EXE')}
try {
 $plan=New-Fixture
 Assert-T ($plan.backend -eq 'AppControl' -and $plan.scope -eq 'Device') 'new plan uses device-scoped App Control backend'
 Assert-T ($script:calls.Count -eq 0) 'planning makes no deployment or removal calls'
 Assert-T ($plan.originalInventory.Count -eq 1 -and $plan.originalInventory[0].IsSystemPolicy) 'pre-existing Windows policy recorded without modification'
 $doc=Clone-Doc $plan;$ns=Get-TgfrCiNs $doc
 Assert-T ($doc.SelectNodes('//ci:Option[text()="Enabled:Audit Mode"]',$ns).Count -eq 0) 'generated policy is enforced rather than audit'
 Assert-T ($doc.SelectNodes('//ci:Option[text()="Disabled:Script Enforcement"]',$ns).Count -eq 1) 'own policy leaves script enforcement disabled'
 Assert-T ($doc.SelectNodes('//ci:Option[text()="Required:Enforce Store Applications"]',$ns).Count -eq 1) 'packaged application enforcement option included'
 Assert-T ($doc.SelectNodes('//ci:Setting[@Provider="AllHostIds"]/ci:Value/ci:Boolean[text()="true"]',$ns).Count -eq 1) 'own policy keeps COM registrations allowed'
 Assert-T ($doc.SelectNodes('//ci:Allow[@PackageFamilyName="*" and @PackageVersion="0.0.0.0"]',$ns).Count -eq 1) 'package allowance baseline prevents implicit denial of unrelated packages'
 Assert-T ($doc.SelectNodes('//ci:Deny[@PackageFamilyName="Microsoft.WindowsStore_8wekyb3d8bbwe" and @PackageVersion="65535.65535.65535.65535"]',$ns).Count -eq 1) 'selected package denied across full version range'
 Assert-T ($plan.planningDetails -join ' ' -match 'restart') 'older Windows build removal caveat retained in planning details'
 Assert-T ($plan.blockedProcessNames -contains 'WinStore.App') 'target process names returned for existing-app preflight'
 Assert-TgfrCiPlan $plan; Assert-T $true 'saved plan ownership, XML and compiler fingerprint validated'
 Assert-T ((Assert-TgfrCiExecutableIdentity '/Office/EXCEL.EXE' 'EXCEL.EXE') -ceq 'EXCEL.EXE') 'matching Excel original identity accepted'
 Assert-T ((Assert-TgfrCiExecutableIdentity '/Windows/calc.exe' 'calc.exe') -ceq 'calc.exe') 'matching classic Calculator original identity accepted'
 $calcIdentities=@(Get-TgfrCiExpectedFileIdentities '/Windows/calc.exe' 'CALC.EXE.MUI')
 Assert-T ($calcIdentities -contains 'CALC.EXE' -and $calcIdentities -contains 'CALC.EXE.MUI' -and $calcIdentities.Count -eq 2) 'localised Calculator resource identity permits only its neutral and MUI identities'
 Assert-Throws {Get-TgfrCiExpectedFileIdentities '/Office/EXCEL.EXE' 'EXCEL.EXE.MUI'} 'identity mismatch' 'Calculator MUI compatibility does not broaden Excel identity'
 Assert-T ((Assert-TgfrCiExecutableIdentity '/Office/EXCEL.EXE' '') -ceq '') 'missing original identity produces hash-only selection'
 Assert-Throws {Assert-TgfrCiExecutableIdentity '/Office/EXCEL.EXE' 'WINWORD.EXE'} 'identity mismatch' 'renamed Word executable cannot become an Excel publisher deny'
 Assert-Throws {Assert-TgfrCiExecutableIdentity '/Office/WINWORD.EXE' 'WINWORD.EXE'} 'Unexpected executable' 'wrong App Paths target executable is rejected'

 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$r=$d.SelectSingleNode('//ci:Allow[@ID="ID_ALLOW_K"]',$n);[void]$r.ParentNode.RemoveChild($r)
 Assert-Throws {Check-Doc $d $plan} 'absent|baseline' 'missing kernel allowance is refused'
 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$d.SelectSingleNode('//ci:Allow[@ID="ID_ALLOW_U"]',$n).SetAttribute('FileName','Word.exe')
 Assert-Throws {Check-Doc $d $plan} 'baseline' 'narrow user allowance cannot replace standalone allow baseline'
 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$d.SelectSingleNode('//ci:Allow[@PackageFamilyName="*"]',$n).SetAttribute('PackageFamilyName','OtherPackage')
 Assert-Throws {Check-Doc $d $plan} 'package-family allow baseline' 'missing wildcard package allowance is refused'
 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$d.SelectSingleNode('//ci:Deny[@PackageFamilyName]',$n).SetAttribute('PackageFamilyName','Microsoft.*')
 Assert-Throws {Check-Doc $d $plan} 'broad' 'broad package deny is refused'
 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$d.SelectSingleNode('//ci:Deny[@PackageFamilyName]',$n).SetAttribute('PackageVersion','1.0.0.0')
 Assert-Throws {Check-Doc $d $plan} 'version-limited' 'version-limited package deny is refused'
 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$d.SelectSingleNode('//ci:Rule/ci:Option',$n).InnerText='Enabled:Audit Mode'
 Assert-Throws {Check-Doc $d $plan} 'Unexpected policy options' 'audit or other policy-option drift is refused'
 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$d.SelectSingleNode('//ci:HvciOptions',$n).InnerText='2'
 Assert-Throws {Check-Doc $d $plan} 'memory integrity' 'policy cannot change HVCI setting'
 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$d.SelectSingleNode('//ci:Setting[@Provider="AllHostIds"]/ci:Value/ci:Boolean',$n).InnerText='false'
 Assert-Throws {Check-Doc $d $plan} 'COM object' 'policy cannot silently introduce COM restrictions'
 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$d.SelectSingleNode('/ci:SiPolicy/ci:BasePolicyID',$n).InnerText=$script:systemId
 Assert-Throws {Check-Doc $d $plan} 'IDs do not agree' 'cannot modify a different base policy through a supplemental ID'
 Assert-Throws {ConvertFrom-TgfrCiXml '<!DOCTYPE x [<!ENTITY x SYSTEM "file:///etc/passwd">]><SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy">&x;</SiPolicy>'} 'DTD|DTD' 'DTD and external-entity input prohibited'

 # Narrow signer denies are accepted only with an exact expected file attribute.
 $d=Clone-Doc $plan;$n=Get-TgfrCiNs $d;$uri=$d.DocumentElement.NamespaceURI
 $attr=$d.CreateElement('FileAttrib',$uri);$attr.SetAttribute('ID','ID_FILE_EXCEL');$attr.SetAttribute('FileName','EXCEL.EXE');$attr.SetAttribute('MinimumFileVersion','0.0.0.0');$attr.SetAttribute('MaximumFileVersion','65535.65535.65535.65535');[void]$d.SelectSingleNode('/ci:SiPolicy/ci:FileRules',$n).AppendChild($attr)
 $signer=$d.CreateElement('Signer',$uri);$signer.SetAttribute('ID','ID_SIGNER_EXCEL');$cert=$d.CreateElement('CertRoot',$uri);$cert.SetAttribute('Type','TBS');$cert.SetAttribute('Value',('A'*64));[void]$signer.AppendChild($cert)
 $a=$d.CreateElement('FileAttribRef',$uri);$a.SetAttribute('RuleID','ID_FILE_EXCEL');[void]$signer.AppendChild($a);[void]$d.SelectSingleNode('/ci:SiPolicy/ci:Signers',$n).AppendChild($signer)
 $denies=$d.CreateElement('DeniedSigners',$uri);$dr=$d.CreateElement('DeniedSigner',$uri);$dr.SetAttribute('SignerId','ID_SIGNER_EXCEL');[void]$denies.AppendChild($dr);[void]$d.SelectSingleNode('//ci:SigningScenario[@Value="12"]/ci:ProductSigners',$n).AppendChild($denies)
 Check-Doc $d $plan;Assert-T $true 'narrow expected Excel publisher attribute accepted'
 $attr.SetAttribute('FileName','*');Assert-Throws {Check-Doc $d $plan} 'not restricted' 'wildcard executable publisher deny refused'
 $attr.SetAttribute('FileName','EXCEL.EXE');[void]$signer.RemoveChild($a);Assert-Throws {Check-Doc $d $plan} 'broad publisher deny' 'publisher-only deny refused'

 $plan=New-Fixture;Invoke-TgfrAppPlan $plan
 Assert-T ($script:calls.Count -eq 1 -and $script:calls[0].Operation -eq 'Install') 'apply invokes one deployment for the compiled owned policy'
 Assert-T ([IO.File]::Exists($script:calls[0].Value) -and $script:calls[0].Value.StartsWith($script:TgfrStateRoot)) 'compiled policy staged under protected state root'
 Assert-T ((Test-TgfrAppPlan $plan).Ok) 'configuration verification succeeds when owned file and active inventory agree'
 $restored=Undo-TgfrAppPlan $plan
 Assert-T ($restored.Ok -and $script:calls[-1].Operation -eq 'Remove' -and [guid]$script:calls[-1].Value -eq [guid]$plan.policyId) 'restore removes only the journal-owned policy ID'
 Assert-T ($script:inv.Count -eq 1 -and [guid]$script:inv[0].PolicyID -eq [guid]$script:systemId) 'Windows system policy remains present after restore'
 $count=$script:calls.Count;Assert-T ((Undo-TgfrAppPlan $plan).Ok -and $script:calls.Count -eq $count) 'repeated restore is idempotent without removal commands'
 $plan=New-Fixture;[IO.File]::WriteAllBytes($script:installed,[Convert]::FromBase64String($plan.binaryBase64));$restore=Undo-TgfrAppPlan $plan
 Assert-T (-not $restore.Ok -and $restore.Details -join ' ' -match 'still exists') 'absent inventory entry with persisted policy file retains recovery'
 Assert-T ($script:calls.Count -eq 0 -and [IO.File]::Exists($script:installed)) 'missing inventory metadata prevents removal and file deletion'
 $plan=New-Fixture;Invoke-TgfrAppPlan $plan;$script:keepRemovedFile=$true;$restore=Undo-TgfrAppPlan $plan
 Assert-T (-not $restore.Ok -and [IO.File]::Exists($script:installed)) 'post-removal persisted file prevents a false restore success'
 $count=$script:calls.Count;Assert-T (-not (Undo-TgfrAppPlan $plan).Ok -and $script:calls.Count -eq $count) 'retry with orphaned persisted file issues no additional native mutation'

 $plan=New-Fixture;$script:inv+= [pscustomobject]@{PolicyID=$plan.policyId;BasePolicyID=$plan.policyId;FriendlyName='Pre-existing unexpected policy';IsSystemPolicy=$false}
 Assert-Throws {Invoke-TgfrAppPlan $plan} 'already present' 'policy ID collision prevents overwrite';Assert-T ($script:calls.Count -eq 0) 'collision causes no native mutation'
 $plan=New-Fixture;$script:inv+= [pscustomobject]@{PolicyID='{33333333-3333-3333-3333-333333333333}';IsSystemPolicy=$false;FriendlyName='External policy'}
 Assert-Throws {Invoke-TgfrAppPlan $plan} 'inventory changed' 'external inventory drift before apply stops deployment';Assert-T ($script:calls.Count -eq 0) 'inventory drift causes no mutation'

 $plan=New-Fixture;$script:active=$false;Assert-Throws {Invoke-TgfrAppPlan $plan} 'not currently active' 'inactive deployed policy is not claimed to be enforced'
 Assert-T ((Undo-TgfrAppPlan $plan).Ok) 'owned inactive deployment remains recoverable'
 $plan=New-Fixture;$script:installError=$true;Assert-Throws {Invoke-TgfrAppPlan $plan} 'Injected' 'post-install native error surfaces'
 Assert-T ((Undo-TgfrAppPlan $plan).Ok) 'rollback can remove owned policy installed before an error'

 $plan=New-Fixture;Invoke-TgfrAppPlan $plan;$script:pending=$true;$restore=Undo-TgfrAppPlan $plan
 Assert-T (-not $restore.Ok -and $restore.Details -join ' ' -match 'Restart') 'pending removal requires restart and retained recovery'
 $count=$script:calls.Count;$restore=Undo-TgfrAppPlan $plan
 Assert-T (-not $restore.Ok -and $script:calls.Count -eq $count) 'pending in-memory removal does not repeatedly issue remove or bypass file protection'
 $script:inv=@($script:system);Assert-T ((Undo-TgfrAppPlan $plan).Ok) 'restore completes after restart removes runtime entry'
 $plan=New-Fixture;Invoke-TgfrAppPlan $plan;$script:pending=$true;$null=Undo-TgfrAppPlan $plan;$script:inv[-1].IsEnforced=$false;$count=$script:calls.Count
 Assert-T ((Undo-TgfrAppPlan $plan).Ok -and $script:calls.Count -eq $count) 'inactive unpersisted inventory record is recognised as completed removal'

 $plan=New-Fixture;Invoke-TgfrAppPlan $plan;[IO.File]::AppendAllText($script:installed,'external change');$count=$script:calls.Count
 Assert-T (-not (Test-TgfrAppPlan $plan).Ok) 'external policy-file change fails verification'
 Assert-Throws {Undo-TgfrAppPlan $plan} 'changed outside' 'external policy-file change prevents destructive removal';Assert-T ($script:calls.Count -eq $count) 'no removal of externally modified binary'
 $plan=New-Fixture;Invoke-TgfrAppPlan $plan;$script:inv[-1].IsSystemPolicy=$true
 Assert-Throws {Undo-TgfrAppPlan $plan} 'Windows-managed' 'system-owned matching ID cannot be removed'
 $plan=New-Fixture;Invoke-TgfrAppPlan $plan;$script:inv[-1].IsSignedPolicy=$true
 Assert-Throws {Undo-TgfrAppPlan $plan} 'signed' 'signed replacement cannot use unsigned recovery'
 $plan=New-Fixture;Invoke-TgfrAppPlan $plan;$script:inv[-1].FriendlyName='Changed owner'
 Assert-Throws {Undo-TgfrAppPlan $plan} 'identity differs' 'changed deployed policy identity cannot be removed'
 $plan=New-Fixture;$plan.binarySha256='0'*64
 Assert-Throws {Invoke-TgfrAppPlan $plan} 'fingerprint' 'corrupt saved binary cannot be applied'
 $plan=New-Fixture;$plan.originalInventory+= [pscustomobject]@{PolicyID=$plan.policyId;IsSystemPolicy=$false}
 Assert-Throws {Undo-TgfrAppPlan $plan} 'not owned' 'journal cannot claim ownership of a pre-existing ID'

 $script:inv=@([pscustomobject]@{PolicyID=$script:systemId;IsSystemPolicy='false'})
 Assert-Throws {Get-TgfrCiInventory} 'ownership metadata' 'string false is not treated as authoritative system-ownership metadata'
 $script:inv=@($script:system,$script:system)
 Assert-Throws {Get-TgfrCiInventory} 'Duplicate policy ID' 'duplicate inventory IDs refused'
 $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/app_control.ps1'))
 Assert-T ($source -notmatch '(?i)AppLocker|AppIDSvc|Image File Execution Options|takeown|icacls|Set-Acl|Remove-AppxPackage|Stop-Process') 'backend contains none of the prohibited old dependencies or invasive fallback mechanisms'
 Assert-T ($source -notmatch 'start=|Set-ItemProperty|Remove-Item.*CodeIntegrity') 'backend does not change service startup or delete operating-system policy files'
 Write-Output ('ALL '+$script:pass+' APP CONTROL ASSERTIONS PASSED; native Windows compiler and enforcement were not executed.')
} finally { if([IO.Directory]::Exists($script:root)){[IO.Directory]::Delete($script:root,$true)} }

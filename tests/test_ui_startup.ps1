# Execute the actual Shown-handler arithmetic with monitor and form test doubles.
# Uses real System.Drawing.Size/Point; does not simulate Windows rendering.
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/ui.ps1'))
$pattern='(?s)\$form\.Add_Shown\(\{\r?\n(?<body>.*?)\r?\n    \}\.GetNewClosure\(\)\)'
$matched=[regex]::Matches($source,$pattern)
if($matched.Count -ne 1){throw 'Expected exactly one production Shown handler.'}
$body=$matched[0].Groups['body'].Value.Replace(
    '$screen = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea',
    '$screen = $testWorkingArea')
$handler=[scriptblock]::Create($body)
$refresh={ $script:refreshCount++ }

# Confirm that this fixture detects the exact original bug, not only a generic error.
$screen=[System.Drawing.Rectangle]::new(0,0,1024,740)
$form=[pscustomobject]@{Width=780;Height=650}
$reproduced=$false
try {
    $null=New-Object System.Drawing.Point($screen.Left + [Math]::Max(0,[int](($screen.Width-$form.Width)/2)), $screen.Top + [Math]::Max(0,[int](($screen.Height-$form.Height)/2)))
} catch { $reproduced=$_.Exception.Message -match 'System.Object\[\].*op_Addition' }
if(-not $reproduced){throw 'The original startup exception was not reproduced.'}
Write-Output 'PASS: exact original Object[] op_Addition error reproduced'

$cases=@(
    @{Name='1024x740';Rect=[System.Drawing.Rectangle]::new(0,0,1024,740);W=780;H=650},
    @{Name='1024x728 with taskbar';Rect=[System.Drawing.Rectangle]::new(0,0,1024,728);W=780;H=650},
    @{Name='1366x728';Rect=[System.Drawing.Rectangle]::new(0,0,1366,728);W=780;H=650},
    @{Name='1920x1040';Rect=[System.Drawing.Rectangle]::new(0,0,1920,1040);W=780;H=650},
    @{Name='800x560 small desktop';Rect=[System.Drawing.Rectangle]::new(0,0,800,560);W=780;H=650},
    @{Name='640x440 small working area';Rect=[System.Drawing.Rectangle]::new(0,0,640,440);W=780;H=650},
    @{Name='Monitor left of primary';Rect=[System.Drawing.Rectangle]::new(-1280,0,1280,984);W=780;H=650},
    @{Name='Monitor right of primary';Rect=[System.Drawing.Rectangle]::new(1920,0,1920,1040);W=780;H=650},
    @{Name='Monitor above primary';Rect=[System.Drawing.Rectangle]::new(0,-900,1600,900);W=780;H=650},
    @{Name='Oversized window and left taskbar';Rect=[System.Drawing.Rectangle]::new(40,0,1326,728);W=2000;H=1500}
)
foreach($case in $cases){
    $testWorkingArea=$case.Rect
    $form=[pscustomobject]@{Size=[System.Drawing.Size]::new($case.W,$case.H);MinimumSize=[System.Drawing.Size]::Empty;Location=[System.Drawing.Point]::Empty}
    $form|Add-Member -MemberType ScriptProperty -Name Width -Value {$this.Size.Width}
    $form|Add-Member -MemberType ScriptProperty -Name Height -Value {$this.Size.Height}
    $script:refreshCount=0
    & $handler
    if($form.Location -isnot [System.Drawing.Point]){throw ('Not a Point: '+$case.Name)}
    if($form.Location.X -lt $testWorkingArea.Left -or $form.Location.Y -lt $testWorkingArea.Top -or
        ($form.Location.X+$form.Width) -gt $testWorkingArea.Right -or ($form.Location.Y+$form.Height) -gt $testWorkingArea.Bottom){throw ('Window exceeds working area: '+$case.Name)}
    if($form.MinimumSize.Width -gt $form.Width -or $form.MinimumSize.Height -gt $form.Height){throw ('Minimum size exceeds current size: '+$case.Name)}
    if($script:refreshCount -ne 1){throw 'The Shown handler must still refresh session controls.'}
    Write-Output ('PASS: '+$case.Name+' -> '+$form.Location.ToString()+' / '+$form.Size.ToString())
}
$logLine=[regex]::Match($source,'(?m)^\s*\$lines = @\(''TGFR Exam Mode.*$').Value
& ([scriptblock]::Create($logLine+'; if ($lines.Count -ne 2 -or $lines[1] -notmatch ''^Generated: \d{4}-'') {throw ''Diagnostics header split unexpectedly''}'))
Write-Output 'PASS: diagnostics heading has exactly two complete lines'
Write-Output 'ALL STARTUP REGRESSION CHECKS PASSED'

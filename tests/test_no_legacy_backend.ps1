# Regression gate for the user's required backend removal. It checks production
# source and optionally the final BAT payload; it never executes either.
param(
    [string]$ProductionDirectory = (Join-Path $PSScriptRoot '../src'),
    [string]$PackagedBatPath = ''
)
$ErrorActionPreference='Stop'
$checks=0
$files=@(Get-ChildItem -LiteralPath $ProductionDirectory -Filter '*.ps1' -File)
if ($files.Count -lt 5) { throw 'Expected all five v7 production modules before running this gate.' }
$required=@('word_exam.ps1','app_control.ps1','engine.ps1','ui.ps1','main.ps1')
foreach ($name in $required) {
    if (@($files | Where-Object Name -eq $name).Count -ne 1) { throw ('Missing production module: '+$name) }
}

function Test-TgfrBackendSource {
    param([string]$Name,[string]$Text)
    # Search literals as well as commands to catch stale help, service names,
    # registry/service references, aliases and native service configuration.
    $forbidden='(?i)AppLocker|AppIDSvc|Application Identity|\bsc\.exe\b|\bServiceController\b|\bWin32_Service\b'
    if ($Text -match $forbidden) { throw ($Name+': forbidden former-backend or service reference: '+$Matches[0]) }
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($Name+': PowerShell parse error: '+($errors | Out-String)) }
    $commands=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))
    foreach ($command in $commands) {
        $commandName=$command.GetCommandName()
        if ($commandName) { $commandName=($commandName -split '\\')[-1] }
        if ($commandName -and $commandName -match '(?i)^(?:Start|Stop|Set|New|Remove|Restart|Suspend|Resume)-Service$|^(?:sc|sc\.exe|sasv|spsv|rsv|Set-AppLockerPolicy|Get-AppLockerPolicy|New-AppLockerPolicy|Test-AppLockerPolicy)$') {
            throw ($Name+': service or former-policy command: '+$commandName)
        }
        if ($commandName -match '(?i)^(?:net|net\.exe)$' -and $command.Extent.Text -match '(?i)\b(start|stop)\b') {
            throw ($Name+': native service start/stop command was found.')
        }
    }
    $script:checks++
    Write-Output ('PASS: '+$Name+' parses and has no former backend/service operations')
}

foreach ($file in $files) { Test-TgfrBackendSource -Name $file.Name -Text ([IO.File]::ReadAllText($file.FullName)) }
if ($PackagedBatPath) {
    $text=[IO.File]::ReadAllText($PackagedBatPath)
    $marker=[regex]::Matches($text,'(?m)^# TGFR_POWERSHELL_START\r?$')
    if ($marker.Count -ne 1) { throw 'The final BAT must contain exactly one embedded-payload marker.' }
    $payload=$text.Substring($marker[0].Index+$marker[0].Length).TrimStart([char[]]"`r`n")
    Test-TgfrBackendSource -Name ([IO.Path]::GetFileName($PackagedBatPath)) -Text $payload
}
Write-Output ('BACKEND-REMOVAL GATE PASSED: '+$checks+' production sources/payloads checked; none executed.')

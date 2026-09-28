[CmdletBinding()]
param(
    [ValidateSet('path', 'system32')]
    [string]$CurlSelection = 'path'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Exit 22 is expected in one test and is asserted explicitly below.
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
if ($CurlSelection -eq 'system32') {
    $env:PATH = (Join-Path $env:SystemRoot 'System32') + ';' + $env:PATH
}
$curlCommand = Get-Command curl.exe -CommandType Application | Select-Object -First 1
$curlAlias = Get-Alias curl -ErrorAction SilentlyContinue
$os = Get-CimInstance Win32_OperatingSystem
$versionOutput = @(curl.exe --version)
if ($LASTEXITCODE -ne 0) { throw 'curl --version failed' }
if ($versionOutput[0] -notmatch '^curl (\d+\.\d+\.\d+)') { throw 'Unknown curl version format' }
if ([version]$Matches[1] -lt [version]'7.82.0') { throw 'This validation requires curl >= 7.82.0' }
$metadata = [ordered]@{
    os = $os.Caption
    osVersion = $os.Version
    osBuild = $os.BuildNumber
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    powershellEdition = $PSVersionTable.PSEdition
    curlSelection = $CurlSelection
    curlPath = $curlCommand.Source
    curlVersion = $versionOutput[0]
    curlAlias = if ($curlAlias) { $curlAlias.Definition } else { $null }
    checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
}
Write-Output ('ENVIRONMENT ' + ($metadata | ConvertTo-Json -Compress))

$outputDir = Join-Path $repoRoot 'test-output'
$null = New-Item -ItemType Directory -Path $outputDir -Force
$checks = New-Object 'System.Collections.Generic.List[object]'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Record-Check([string]$Name, [int]$ExitCode, [int]$Status, [string]$Response) {
    $result = [pscustomobject][ordered]@{
        name = $Name; result = 'PASS'; exitCode = $ExitCode; httpStatus = $Status
    }
    $checks.Add($result)
    [IO.File]::WriteAllText((Join-Path $outputDir ($Name + '.txt')), $Response, (New-Object Text.UTF8Encoding($false)))
    Write-Output ('CHECK ' + ($result | ConvertTo-Json -Compress))
    Write-Output ('RESPONSE ' + ($Response | ConvertTo-Json -Compress))
}

function Read-HttpResponse([string]$Text) {
    $statuses = [regex]::Matches($Text, '(?m)^HTTP/\S+\s+(\d{3})')
    Assert-True ($statuses.Count -gt 0) 'No HTTP status line in response'
    $bodyMatch = [regex]::Match($Text, '(?s)\r?\n\r?\n([\{\[].*)$')
    Assert-True $bodyMatch.Success 'No JSON body following response headers'
    return [pscustomobject]@{
        Status = [int]$statuses[$statuses.Count - 1].Groups[1].Value
        Body = $bodyMatch.Groups[1].Value
    }
}

try {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $repoRoot 'request.json'))
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) 'request.json must not have a UTF-8 BOM'
    $request = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    Assert-True ($request.title -eq 'curl practice' -and $request.body -eq 'hello API' -and $request.userId -eq 1) 'Unexpected dummy request data'

    # The command lines below use the article's literal arguments. Only stdout
    # is captured for assertions; no retry, insecure flag, or real secret is added.
    $raw = curl.exe --max-time 30 "https://jsonplaceholder.typicode.com/posts/1"
    $exitCode = $LASTEXITCODE
    $text = $raw -join "`n"
    Assert-True ($exitCode -eq 0) 'GET did not exit 0'
    $data = $text | ConvertFrom-Json
    Assert-True ($data.id -eq 1 -and $data.userId -eq 1) 'Unexpected GET response'
    # No status was requested by this exact command; 0 means not captured.
    Record-Check 'get-body' $exitCode 0 $text

    $raw = curl.exe --max-time 30 -i "https://jsonplaceholder.typicode.com/posts/1"
    $exitCode = $LASTEXITCODE
    $text = $raw -join "`n"
    $response = Read-HttpResponse $text
    Assert-True ($exitCode -eq 0 -and $response.Status -eq 200) 'GET with headers was not HTTP 200 / exit 0'
    Assert-True (($response.Body | ConvertFrom-Json).id -eq 1) 'GET with headers has wrong body'
    Assert-True ($text -match '(?im)^content-type:\s*application/json') 'GET response lacks JSON Content-Type'
    Record-Check 'get-headers' $exitCode $response.Status $text

    $raw = curl.exe --max-time 30 -I "https://jsonplaceholder.typicode.com/posts/1"
    $exitCode = $LASTEXITCODE
    $text = $raw -join "`n"
    $statuses = [regex]::Matches($text, '(?m)^HTTP/\S+\s+(\d{3})')
    Assert-True ($exitCode -eq 0 -and $statuses.Count -gt 0) 'HEAD failed'
    $status = [int]$statuses[$statuses.Count - 1].Groups[1].Value
    Assert-True ($status -eq 200 -and $text -notmatch '(?m)^\s*\{') 'HEAD did not return headers only'
    Record-Check 'head-headers-only' $exitCode $status $text

    $raw = curl.exe --max-time 30 --get --data-urlencode "userId=1" "https://jsonplaceholder.typicode.com/posts"
    $exitCode = $LASTEXITCODE
    $text = $raw -join "`n"
    Assert-True ($exitCode -eq 0) 'Query GET did not exit 0'
    $data = @($text | ConvertFrom-Json)
    Assert-True ($data.Count -eq 10) 'Query did not return 10 posts'
    Assert-True (@($data | Where-Object { $_.userId -ne 1 }).Count -eq 0) 'Query contains a different userId'
    Record-Check 'get-query' $exitCode 0 $text

    $raw = curl.exe --max-time 30 -i --json "@request.json" "https://jsonplaceholder.typicode.com/posts"
    $exitCode = $LASTEXITCODE
    $text = $raw -join "`n"
    $response = Read-HttpResponse $text
    Assert-True ($exitCode -eq 0 -and $response.Status -eq 201) 'JSON POST was not HTTP 201 / exit 0'
    $data = $response.Body | ConvertFrom-Json
    Assert-True ($data.id -eq 101 -and $data.title -eq $request.title -and $data.body -eq $request.body -and $data.userId -eq 1) 'JSON POST altered request fields'
    Record-Check 'post-json-file' $exitCode $response.Status $text

    $raw = curl.exe --max-time 30 -i -H "Content-Type: application/json" -H "Accept: application/json" --data-binary "@request.json" "https://jsonplaceholder.typicode.com/posts"
    $exitCode = $LASTEXITCODE
    $text = $raw -join "`n"
    $response = Read-HttpResponse $text
    Assert-True ($exitCode -eq 0 -and $response.Status -eq 201) 'Explicit-header POST was not HTTP 201 / exit 0'
    $data = $response.Body | ConvertFrom-Json
    Assert-True ($data.id -eq 101 -and $data.title -eq $request.title -and $data.body -eq $request.body -and $data.userId -eq 1) 'Explicit-header POST altered request fields'
    Record-Check 'post-data-binary' $exitCode $response.Status $text

    $raw = curl.exe --max-time 30 -i "https://jsonplaceholder.typicode.com/posts/999999"
    $exitCode = $LASTEXITCODE
    $text = $raw -join "`n"
    $response = Read-HttpResponse $text
    Assert-True ($exitCode -eq 0 -and $response.Status -eq 404) 'Default HTTP 404 did not exit 0'
    Assert-True ($response.Body.Trim() -eq '{}') 'Unexpected HTTP 404 body'
    Record-Check '404-default' $exitCode $response.Status $text

    $raw = curl.exe --max-time 30 --fail-with-body -i "https://jsonplaceholder.typicode.com/posts/999999"
    $exitCode = $LASTEXITCODE
    $text = $raw -join "`n"
    $response = Read-HttpResponse $text
    Assert-True ($exitCode -eq 22 -and $response.Status -eq 404) '--fail-with-body did not produce HTTP 404 / exit 22'
    Assert-True ($response.Body.Trim() -eq '{}') '--fail-with-body did not preserve the error body'
    Record-Check '404-fail-with-body' $exitCode $response.Status $text

    Assert-True ($checks.Count -eq 8) 'Not all eight checks completed'
    Write-Output 'VALIDATION PASSED: 8/8 checks'
}
finally {
    $report = [ordered]@{ environment = $metadata; checks = @($checks.ToArray()) }
    $json = $report | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $outputDir 'results.json'), $json, (New-Object Text.UTF8Encoding($false)))
    if ($env:GITHUB_STEP_SUMMARY) {
        $summary = @('# Windows curl validation', '', '```json', $json, '```') -join "`n"
        [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $summary, (New-Object Text.UTF8Encoding($false)))
    }
}
# Avoid propagating the expected exit 22 to the GitHub Actions wrapper.
exit 0

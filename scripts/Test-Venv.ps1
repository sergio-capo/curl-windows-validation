$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$testRoot = Join-Path $env:RUNNER_TEMP ('venv-check-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
Set-Location $testRoot
$originalPath = $env:PATH
$passed = New-Object 'System.Collections.Generic.List[string]'
function Check-Exit([string]$Name) {
    if ($LASTEXITCODE -ne 0) { throw "$Name failed: exit $LASTEXITCODE" }
}
function Pass([string]$Name) { $passed.Add($Name); Write-Output "PASS $Name" }
py --version
Check-Exit 'py --version'
$baseVersion = py -c "import sys; print(sys.version.split()[0]); assert sys.version_info[:2] == (3, 14); assert sys.prefix == sys.base_prefix"
Check-Exit 'base Python'
$os = (Get-CimInstance Win32_OperatingSystem).Caption
$meta = [ordered]@{os=$os; powershell=$PSVersionTable.PSVersion.ToString(); python=$baseVersion; requests=$null; requirementsUtf8Bom=$null}
Write-Output ('ENVIRONMENT ' + ($meta | ConvertTo-Json -Compress))
Get-ExecutionPolicy -List
try {
    py -m venv .venv
    Check-Exit 'venv creation'
    if (-not (Test-Path .venv\pyvenv.cfg)) { throw 'Missing pyvenv.cfg' }
    Pass 'create'

    .\.venv\Scripts\Activate.ps1
    python -c "import sys; print(sys.executable); assert sys.prefix != sys.base_prefix; assert '.venv' in sys.executable"
    Check-Exit 'active interpreter'
    python -m pip --version
    Check-Exit 'pip version'
    Pass 'activate-and-interpreter'

    python -m pip install requests
    Check-Exit 'install requests'
    $meta.requests = python -c "import requests; print(requests.__version__)"
    Check-Exit 'import requests'
    python -m pip check
    Check-Exit 'pip check'
    python -m pip list
    Check-Exit 'pip list'
    python -m pip show requests
    Check-Exit 'pip show'
    Pass 'install-import-list-show-check'

    deactivate
    if ($env:PATH -cne $originalPath) { throw 'deactivate did not restore PATH' }
    if (-not (Test-Path .venv\pyvenv.cfg)) { throw 'deactivate removed the environment' }
    Pass 'deactivate-restores-path-and-keeps-venv'

    .\.venv\Scripts\python.exe -c "import sys, requests; print(requests.__version__); assert sys.prefix != sys.base_prefix"
    Check-Exit 'direct execution without activate'
    .\.venv\Scripts\python.exe -m pip list
    Check-Exit 'direct pip'
    Pass 'direct-execution-and-package-persistence'

    .\.venv\Scripts\Activate.ps1
    python -c "import requests; print(requests.__version__)"
    Check-Exit 'reactivation'
    Pass 'reactivate'

    python -m pip freeze | Set-Content -Encoding utf8 requirements.txt
    Check-Exit 'freeze'
    $bytes = [IO.File]::ReadAllBytes((Join-Path $testRoot 'requirements.txt'))
    $meta.requirementsUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    $frozen = @(Get-Content requirements.txt)
    if (-not ($frozen -match '^requests==')) { throw 'requests missing from requirements' }
    Pass 'freeze-utf8'
    deactivate

    py -m venv .venv-rebuild
    Check-Exit 'rebuild creation'
    .\.venv-rebuild\Scripts\Activate.ps1
    python -m pip install -r requirements.txt
    Check-Exit 'rebuild install'
    python -m pip check
    Check-Exit 'rebuilt pip check'
    $rebuilt = @(python -m pip freeze)
    Check-Exit 'rebuilt freeze'
    if (Compare-Object $frozen $rebuilt) { throw 'Rebuilt package list differs' }
    Pass 'requirements-rebuild-exact-packages'

    # This is a disposable environment created in this job, never user data.
    python -m pip uninstall -y requests
    Check-Exit 'uninstall requests'
    python -c "import importlib.util; assert importlib.util.find_spec('requests') is None; import urllib3, certifi, idna, charset_normalizer; print('dependencies remain')"
    Check-Exit 'uninstall retains dependencies'
    Pass 'uninstall-only-requested-package'
    deactivate

    py -m venv .venv-delete-demo
    Check-Exit 'disposable deletion example'
    $deletePath = Join-Path $testRoot '.venv-delete-demo'
    if (-not (Test-Path (Join-Path $deletePath 'pyvenv.cfg'))) { throw 'Deletion target is not the newly created venv' }
    Remove-Item -LiteralPath $deletePath -Recurse -WhatIf
    Remove-Item -LiteralPath $deletePath -Recurse -Confirm:$false
    if (Test-Path $deletePath) { throw 'Disposable venv was not deleted' }
    if (-not (Test-Path .venv\pyvenv.cfg)) { throw 'Unrelated environment was removed' }
    Pass 'guarded-disposable-venv-delete'
    if ($passed.Count -ne 10) { throw 'Incomplete checks' }
    Write-Output 'VALIDATION PASSED: 10/10'
} finally {
    $summary = [ordered]@{environment=$meta; passed=@($passed.ToArray()); count=$passed.Count} | ConvertTo-Json -Depth 5
    Write-Output $summary
    if ($env:GITHUB_STEP_SUMMARY) {
        $markdown = @('# Python venv validation', '', '```json', $summary, '```') -join "`n"
        [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $markdown, (New-Object Text.UTF8Encoding($false)))
    }
}
exit 0

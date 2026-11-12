# Runs the Docker tests for the setup scripts. Needs Docker Desktop running (Linux containers).
#   powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1            # both tests
#   powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Only stub # quick Mac-branch test only
param([ValidateSet('all','stub','intel','full','exits','uninstall')][string]$Only = 'all')
$src = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
docker build --label vibe.project=freeAIsetup -t metascience-setup-test (Join-Path $src 'tests')
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL docker build'; exit 1 }
$failed = @()   # a test that fails must fail this script too (its exit code), not only print RESULT ... fail=N
if ($Only -in 'all','stub') { docker run --rm --label vibe.project=freeAIsetup --label vibe.ephemeral=true -v "${src}:/src:ro" metascience-setup-test bash /src/tests/mac-stub.sh; if ($LASTEXITCODE -ne 0) { $failed += 'mac-stub' } }
if ($Only -in 'all','intel') { docker run --rm --label vibe.project=freeAIsetup --label vibe.ephemeral=true -v "${src}:/src:ro" metascience-setup-test bash /src/tests/mac-stub-intel.sh; if ($LASTEXITCODE -ne 0) { $failed += 'mac-stub-intel' } }
if ($Only -in 'all','exits') { docker run --rm --label vibe.project=freeAIsetup --label vibe.ephemeral=true -v "${src}:/src:ro" metascience-setup-test bash /src/tests/exit-paths.sh; if ($LASTEXITCODE -ne 0) { $failed += 'exit-paths' } }
if ($Only -in 'all','uninstall') { docker run --rm --label vibe.project=freeAIsetup --label vibe.ephemeral=true -v "${src}:/src:ro" metascience-setup-test bash /src/tests/uninstall.sh; if ($LASTEXITCODE -ne 0) { $failed += 'uninstall' } }
if ($Only -in 'all','full') { docker run --rm --label vibe.project=freeAIsetup --label vibe.ephemeral=true -v "${src}:/src:ro" metascience-setup-test bash /src/tests/linux-full.sh; if ($LASTEXITCODE -ne 0) { $failed += 'linux-full' } }
if ($failed) { Write-Host "FAILED: $($failed -join ', ')"; exit 1 }
exit 0

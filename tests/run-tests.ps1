# Runs the Docker tests for the setup scripts. Needs Docker Desktop running (Linux containers).
#   powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1            # both tests
#   powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Only stub # quick Mac-branch test only
param([ValidateSet('all','stub','full')][string]$Only = 'all')
$src = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
docker build -t metascience-setup-test (Join-Path $src 'tests')
if ($Only -in 'all','stub') { docker run --rm -v "${src}:/src:ro" metascience-setup-test bash /src/tests/mac-stub.sh }
if ($Only -in 'all','full') { docker run --rm -v "${src}:/src:ro" metascience-setup-test bash /src/tests/linux-full.sh }

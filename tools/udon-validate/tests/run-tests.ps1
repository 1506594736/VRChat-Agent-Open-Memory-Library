<#
.SYNOPSIS
    Self-test for the PowerShell validator.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\udon-validate\tests\run-tests.ps1
#>
$ErrorActionPreference = 'Continue'

$TestsDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolDir   = Split-Path -Parent $TestsDir
$Validator = Join-Path $ToolDir 'udon-validate.ps1'

$script:Pass = 0
$script:Fail = 0

function Invoke-Case {
    param(
        [string]$Name,
        [string]$File,
        [int]$WantExit,
        [string]$Must,
        [string]$MustNot,
        [string[]]$Extra = @()
    )

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Validator, $File) + $Extra
    $out = & powershell @argList 2>&1 | Out-String
    $code = $LASTEXITCODE

    $ok = ($code -eq $WantExit)
    if ($ok -and $Must)    { $ok = $out.Contains($Must) }
    if ($ok -and $MustNot) { $ok = -not $out.Contains($MustNot) }

    if ($ok) {
        Write-Output "  PASS  $Name"
        $script:Pass++
    }
    else {
        Write-Output "  FAIL  $Name (exit=$code, wanted $WantExit)"
        if ($Must -and -not $out.Contains($Must))       { Write-Output "        expected to contain: $Must" }
        if ($MustNot -and $out.Contains($MustNot))      { Write-Output "        expected NOT to contain: $MustNot" }
        $script:Fail++
    }
}

Write-Output ""
Write-Output "udon-validate self-test (PowerShell)"
Write-Output "===================================="

$bad  = Join-Path $TestsDir 'BadExample.cs'
$good = Join-Path $TestsDir 'GoodExample.cs'
$plain= Join-Path $TestsDir 'PlainCSharp.cs'

# --- violations are caught -------------------------------------------------

Invoke-Case 'async is blocked'                  $bad 1 'async methods are not supported' ''
Invoke-Case 'try/catch is blocked'              $bad 1 'try/catch is not supported' ''
Invoke-Case 'coroutine is blocked'              $bad 1 'yield return (coroutines)' ''
Invoke-Case 'StartCoroutine blocked'            $bad 1 'StartCoroutine is not available' ''
Invoke-Case 'AddListener blocked'               $bad 1 'AddListener() takes a delegate' ''
Invoke-Case 'System.IO blocked'                 $bad 1 'System.IO' ''
Invoke-Case 'multi-dim array blocked'           $bad 1 'Multi-dimensional arrays' ''
Invoke-Case 'missing RequestSerialization flagged' $bad 1 'never calls RequestSerialization()' ''
Invoke-Case 'missing ownership guard flagged'   $bad 1 'no ownership check' ''

# --- false positives are suppressed ----------------------------------------

Invoke-Case 'compliant file passes'             $good 0 'PASS' 'BLOCKED'
Invoke-Case 'comments do not trip rules'        $good 0 'PASS' 'List<T> is not supported'
Invoke-Case 'strings do not trip rules'         $good 0 'PASS' 'Lambda expressions'
Invoke-Case 'plain C# skips udon rules'         $plain 0 'PASS' 'async methods are not supported'

# --- flags ------------------------------------------------------------------

Invoke-Case '--ErrorsOnly hides warnings'       $bad 1 'BLOCKED' 'WARNING' @('-ErrorsOnly')
Invoke-Case '--NoExitCode returns 0'            $bad 0 'BLOCKED/ERROR' '' @('-NoExitCode')

# --- directory mode ---------------------------------------------------------

$dirOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Validator $TestsDir -ErrorsOnly 2>&1 | Out-String
$dirCode = $LASTEXITCODE
if ($dirCode -eq 1 -and $dirOut.Contains('BLOCKED')) {
    Write-Output "  PASS  directory mode scans recursively"
    $script:Pass++
}
else {
    Write-Output "  FAIL  directory mode scans recursively (exit=$dirCode)"
    $script:Fail++
}

# --- bad input --------------------------------------------------------------

& powershell -NoProfile -ExecutionPolicy Bypass -File $Validator (Join-Path $TestsDir 'does-not-exist.cs') *> $null
if ($LASTEXITCODE -eq 2) { Write-Output "  PASS  missing path exits 2"; $script:Pass++ }
else { Write-Output "  FAIL  missing path exits 2"; $script:Fail++ }

& powershell -NoProfile -ExecutionPolicy Bypass -File $Validator (Join-Path $TestsDir 'run-tests.ps1') *> $null
if ($LASTEXITCODE -eq 2) { Write-Output "  PASS  non-.cs file exits 2"; $script:Pass++ }
else { Write-Output "  FAIL  non-.cs file exits 2"; $script:Fail++ }

Write-Output ""
if ($script:Fail -eq 0) {
    Write-Output "all $script:Pass checks passed"
    exit 0
}
Write-Output "$script:Pass passed, $script:Fail FAILED"
exit 1

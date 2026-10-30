<#
.SYNOPSIS
    UdonSharp static validator for Windows. Zero dependencies.

.DESCRIPTION
    Checks .cs files for Udon runtime constraint violations. Reads rules from
    rules.tsv in the same directory — this script is a generic engine, so
    adding or correcting a rule does not require editing it.

    Requires only PowerShell 5.1, which ships with Windows 10/11. No jq, no
    python, no network access.

.PARAMETER Path
    A .cs file, or a directory to scan recursively.

.PARAMETER ErrorsOnly
    Report BLOCKED/ERROR only, suppress warnings.

.PARAMETER NoExitCode
    Always exit 0, even when violations are found.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\udon-validate\udon-validate.ps1 Scripts\MyBehaviour.cs

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\udon-validate\udon-validate.ps1 Assets\MyWorld\Scripts -ErrorsOnly

.OUTPUTS
    Exit 0 = pass, or warnings only
    Exit 1 = BLOCKED/ERROR findings
    Exit 2 = bad input or missing rules file
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [switch]$ErrorsOnly,

    [switch]$NoExitCode
)

$ErrorActionPreference = 'Stop'

$RulesFile = Join-Path $PSScriptRoot 'rules.tsv'
if (-not (Test-Path -LiteralPath $RulesFile)) {
    [Console]::Error.WriteLine("udon-validate: rules file missing: $RulesFile")
    exit 2
}

if (-not (Test-Path -LiteralPath $Path)) {
    [Console]::Error.WriteLine("udon-validate: no such path: $Path")
    exit 2
}

# ---- collect target files -------------------------------------------------

$item = Get-Item -LiteralPath $Path
if ($item.PSIsContainer) {
    $targets = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Filter '*.cs' |
                 Select-Object -ExpandProperty FullName | Sort-Object)
    if ($targets.Count -eq 0) {
        [Console]::Error.WriteLine("udon-validate: no .cs files under: $Path")
        exit 2
    }
}
elseif ($item.Extension -eq '.cs') {
    $targets = @($item.FullName)
}
else {
    [Console]::Error.WriteLine("udon-validate: not a .cs file: $Path")
    exit 2
}

# ---- masking --------------------------------------------------------------
#
# Replace comments and string/char literals with spaces, preserving every
# offset so line structure stays intact. Conservative scanner: getting this
# wrong in the permissive direction means false positives, which is the
# failure mode that makes people stop trusting the tool.

function Get-MaskedSource {
    param([string]$Text)

    $sb = New-Object System.Text.StringBuilder ($Text.Length)
    $i = 0
    $n = $Text.Length

    while ($i -lt $n) {
        $c = $Text[$i]

        # line comment
        if ($c -eq '/' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '/') {
            while ($i -lt $n -and $Text[$i] -ne "`n") { [void]$sb.Append(' '); $i++ }
            continue
        }

        # block comment
        if ($c -eq '/' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '*') {
            [void]$sb.Append('  '); $i += 2
            while ($i -lt $n) {
                if ($Text[$i] -eq '*' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '/') {
                    [void]$sb.Append('  '); $i += 2; break
                }
                if ($Text[$i] -eq "`n") { [void]$sb.Append("`n") } else { [void]$sb.Append(' ') }
                $i++
            }
            continue
        }

        # verbatim string  @"..."
        if ($c -eq '@' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '"') {
            [void]$sb.Append('  '); $i += 2
            while ($i -lt $n) {
                if ($Text[$i] -eq '"') {
                    if (($i + 1) -lt $n -and $Text[$i + 1] -eq '"') {
                        [void]$sb.Append('  '); $i += 2; continue
                    }
                    [void]$sb.Append(' '); $i++; break
                }
                if ($Text[$i] -eq "`n") { [void]$sb.Append("`n") } else { [void]$sb.Append(' ') }
                $i++
            }
            continue
        }

        # regular string
        if ($c -eq '"') {
            [void]$sb.Append(' '); $i++
            while ($i -lt $n) {
                if ($Text[$i] -eq '\') { [void]$sb.Append('  '); $i += 2; continue }
                if ($Text[$i] -eq '"') { [void]$sb.Append(' '); $i++; break }
                if ($Text[$i] -eq "`n") { [void]$sb.Append("`n") } else { [void]$sb.Append(' ') }
                $i++
            }
            continue
        }

        # char literal
        if ($c -eq "'") {
            [void]$sb.Append(' '); $i++
            while ($i -lt $n) {
                if ($Text[$i] -eq '\') { [void]$sb.Append('  '); $i += 2; continue }
                if ($Text[$i] -eq "'") { [void]$sb.Append(' '); $i++; break }
                if ($Text[$i] -eq "`n") { [void]$sb.Append("`n") } else { [void]$sb.Append(' ') }
                $i++
            }
            continue
        }

        [void]$sb.Append($c)
        $i++
    }

    return $sb.ToString()
}

# ---- load rules -----------------------------------------------------------

$rules = @()
foreach ($line in Get-Content -LiteralPath $RulesFile -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line.StartsWith('#')) { continue }

    $parts = $line -split "`t"
    if ($parts.Count -lt 7) { continue }

    # rules.tsv uses POSIX ERE so the bash engine can consume it directly.
    # .NET regex does not understand POSIX character classes, so translate the
    # ones we use; everything else passes through unchanged.
    $pattern = $parts[4]
    $absent  = $parts[5].Trim()

    $pattern = $pattern -replace '\[\[:space:\]\]', '\s'
    $pattern = $pattern -replace '\[\[:alpha:\]\]', '[A-Za-z]'
    $pattern = $pattern -replace '\[\[:digit:\]\]', '\d'
    $pattern = $pattern -replace '\[\[:alnum:\]\]', '[A-Za-z0-9_]'

    if ($absent -ne '-' -and $absent -ne '') {
        $absent = $absent -replace '\[\[:space:\]\]', '\s'
        $absent = $absent -replace '\[\[:alpha:\]\]', '[A-Za-z]'
        $absent = $absent -replace '\[\[:digit:\]\]', '\d'
        $absent = $absent -replace '\[\[:alnum:\]\]', '[A-Za-z0-9_]'
    }

    $rules += [pscustomobject]@{
        Level   = $parts[0].Trim()
        Id      = $parts[1].Trim()
        Scope   = $parts[2].Trim()
        Kind    = $parts[3].Trim()
        Pattern = $pattern
        Absent  = $absent
        Message = $parts[6].Trim()
    }
}

if ($rules.Count -eq 0) {
    [Console]::Error.WriteLine("udon-validate: no rules parsed from $RulesFile")
    exit 2
}

# ---- run ------------------------------------------------------------------

$totalFiles = 0
$reportedFiles = 0
$blockedCount = 0
$warnCount = 0

foreach ($file in $targets) {
    $totalFiles++

    $raw = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
    $masked = Get-MaskedSource -Text $raw

    # Scope detection on masked text: a comment mentioning UdonSharpBehaviour
    # must not make a plain C# file count as Udon code.
    $isUdon = $masked.Contains('UdonSharpBehaviour')

    $out = @()
    foreach ($r in $rules) {
        if ($r.Scope -eq 'udon' -and -not $isUdon) { continue }
        if ($r.Level -eq 'WARNING' -and $ErrorsOnly) { continue }

        $hit = $false
        if ($r.Kind -eq 'literal') {
            $hit = $masked.Contains($r.Pattern)
        }
        else {
            $hit = [regex]::IsMatch($masked, $r.Pattern)
        }

        # "present but missing X" — without this, a rule such as [UdonSynced]
        # fires on every correct file and the output stops being read.
        if ($hit -and $r.Absent -ne '-' -and $r.Absent -ne '') {
            if ([regex]::IsMatch($masked, $r.Absent)) { $hit = $false }
        }

        if ($hit) {
            if ($r.Level -eq 'WARNING') { $warnCount++ }
            else { $blockedCount++ }
            $out += ('  {0,-8} {1}' -f $r.Level, $r.Message)
        }
    }

    if ($out.Count -gt 0) {
        $reportedFiles++
        $rel = $file
        if ($rel.StartsWith($PWD.Path)) { $rel = $rel.Substring($PWD.Path.Length).TrimStart('\', '/') }
        Write-Output ""
        Write-Output "-- $rel"
        $out | ForEach-Object { Write-Output $_ }
    }
}

# ---- summary --------------------------------------------------------------

Write-Output ""
if ($blockedCount -eq 0 -and $warnCount -eq 0) {
    Write-Output "udon-validate: PASS - $totalFiles file(s), no findings"
    exit 0
}

if ($ErrorsOnly) {
    Write-Output "udon-validate: $reportedFiles/$totalFiles file(s) - BLOCKED/ERROR $blockedCount"
}
else {
    Write-Output "udon-validate: $reportedFiles/$totalFiles file(s) - BLOCKED/ERROR $blockedCount, WARNING $warnCount"
}

if ($NoExitCode) { exit 0 }
if ($blockedCount -gt 0) { exit 1 }
exit 0

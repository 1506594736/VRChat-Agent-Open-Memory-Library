<#
.SYNOPSIS
    UdonSharp 代码校验器 —— 命令行入口。

.DESCRIPTION
    对指定的 UdonSharp (.cs) 文件或目录运行约束校验，输出违规清单，并以退出码反映结果。

    核心校验逻辑来自 vendor/niaka3dayo/validate-udonsharp.ps1（MIT 协议）。原脚本是
    PostToolUse hook，协议为「从 stdin 读 JSON、把警告写到 stderr、原样回显 stdin 到 stdout」。
    本文件只负责把这套 hook 协议包装成可直接调用的 CLI，不修改其任何校验规则。

.PARAMETER Path
    要校验的 .cs 文件，或包含 .cs 的目录（递归）。

.PARAMETER ErrorsOnly
    只报告 BLOCKED / ERROR 级问题，屏蔽 WARNING。

.PARAMETER NoExitCode
    即使发现违规也返回 0（用于只想看报告、不想中断流程的场景）。

.EXAMPLE
    powershell -File udon-guard/validate.ps1 Scripts/MyBehaviour.cs

.EXAMPLE
    powershell -File udon-guard/validate.ps1 Assets/MyWorld/Scripts

.EXAMPLE
    powershell -File udon-guard/validate.ps1 Scripts/MyBehaviour.cs -ErrorsOnly

.OUTPUTS
    退出码 0 = 通过（或仅有 WARNING）
    退出码 1 = 存在 BLOCKED / ERROR 级问题
    退出码 2 = 参数或环境错误
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [switch]$ErrorsOnly,

    [switch]$NoExitCode
)

$ErrorActionPreference = 'Stop'

$VendorScript = Join-Path $PSScriptRoot 'vendor/niaka3dayo/validate-udonsharp.ps1'
if (-not (Test-Path -LiteralPath $VendorScript)) {
    [Console]::Error.WriteLine("udon-guard: 找不到核心校验脚本: $VendorScript")
    exit 2
}

$VendorScript = (Resolve-Path -LiteralPath $VendorScript).Path
$psExe = (Get-Process -Id $PID).Path

# ------------------------------------------------------------------
# 在子进程里运行原 hook。
# 关键点：原脚本用 Write-Error 输出，Windows PowerShell 会给每条消息加上
# 脚本路径前缀、CategoryInfo 噪音并硬折行。因此用 -Command 包一层，
# 把 2>&1 合并后只取 ErrorRecord 的 Message，得到干净的单行消息。
# ------------------------------------------------------------------
$escapedVendor = $VendorScript -replace "'", "''"
$runnerCommand = "& '$escapedVendor' 2>&1 | ForEach-Object { if (`$_ -is [System.Management.Automation.ErrorRecord]) { `$_.Exception.Message } else { `$_.ToString() } }"

function Resolve-TargetFiles {
    param([string]$InputPath)

    if (-not (Test-Path -LiteralPath $InputPath)) {
        [Console]::Error.WriteLine("udon-guard: 路径不存在: $InputPath")
        exit 2
    }

    $item = Get-Item -LiteralPath $InputPath
    if ($item.PSIsContainer) {
        $found = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Filter '*.cs' |
                   Select-Object -ExpandProperty FullName | Sort-Object)
        if ($found.Count -eq 0) {
            [Console]::Error.WriteLine("udon-guard: 目录中没有 .cs 文件: $InputPath")
            exit 2
        }
        return $found
    }

    if ($item.Extension -ne '.cs') {
        [Console]::Error.WriteLine("udon-guard: 不是 .cs 文件: $InputPath")
        exit 2
    }

    return @($item.FullName)
}

function Invoke-Validator {
    param([string]$FilePath)

    $payload = @{ tool_input = @{ file_path = $FilePath } } |
        ConvertTo-Json -Depth 5 -Compress

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$runnerCommand`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Write($payload)
    $proc.StandardInput.Close()

    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $null = $stderrTask.Result
    $proc.WaitForExit()

    return $stdout
}

# ---- 主流程 ----

$files = Resolve-TargetFiles -InputPath $Path

$totalBlocked = 0
$totalWarn = 0
$reportedFiles = 0

foreach ($file in $files) {
    $text = Invoke-Validator -FilePath $file
    if ([string]::IsNullOrWhiteSpace($text)) { continue }

    # 每条消息形如： [UdonSharp] BLOCKED: ...  /  [UdonSharp] WARNING: ...
    $rules = [regex]::Matches(
        $text,
        '(?m)\[UdonSharp\]\s+(BLOCKED|ERROR|WARNING|SYNC-BLOAT|VALIDATOR-WARNING):\s*(.+?)\s*$'
    )
    if ($rules.Count -eq 0) { continue }

    $out = @()
    foreach ($m in $rules) {
        $level = $m.Groups[1].Value
        $msg = $m.Groups[2].Value.Trim()

        switch ($level) {
            'WARNING'           { $totalWarn++;    if (-not $ErrorsOnly) { $out += "  WARNING  $msg" } }
            'VALIDATOR-WARNING' { $totalWarn++;    if (-not $ErrorsOnly) { $out += "  WARNING  $msg" } }
            'SYNC-BLOAT'        { $totalWarn++;    if (-not $ErrorsOnly) { $out += "  WARNING  [同步膨胀] $msg" } }
            default             { $totalBlocked++; $out += "  BLOCKED  $msg" }
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

# ---- 汇总 ----

Write-Output ""
if ($totalBlocked -eq 0 -and $totalWarn -eq 0) {
    Write-Output "udon-guard: PASS - $($files.Count) 个文件未发现违规"
    exit 0
}

$summary = "udon-guard: $reportedFiles/$($files.Count) 个文件有问题 - BLOCKED/ERROR $totalBlocked 项"
if (-not $ErrorsOnly) { $summary += "，WARNING $totalWarn 项" }
Write-Output $summary

if ($NoExitCode) { exit 0 }
if ($totalBlocked -gt 0) { exit 1 }
exit 0

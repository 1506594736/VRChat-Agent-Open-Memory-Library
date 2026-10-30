# udon-guard 自测：验证校验器本身是否正常工作。
# 用法： powershell -NoProfile -ExecutionPolicy Bypass -File udon-guard/tests/run-tests.ps1
# 注意：校验器对错误输入会往 stderr 写消息并以 2 退出，这是预期行为，
# 因此本脚本不能使用 Stop 模式，否则会被原生命令的 stderr 打断。
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$validator = Join-Path $root 'udon-guard/validate.ps1'
$tests = Join-Path $root 'udon-guard/tests'

$failures = 0

function Invoke-Case {
    param([string]$Name, [string]$FileArg, [string[]]$ExtraArgs, [int]$ExpectExit, [string]$ExpectContains)

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $validator, $FileArg) + $ExtraArgs
    $output = & powershell @argList 2>&1 | Out-String
    $code = $LASTEXITCODE

    $ok = ($code -eq $ExpectExit)
    if ($ok -and $ExpectContains) { $ok = $output.Contains($ExpectContains) }

    if ($ok) {
        Write-Output "  PASS  $Name"
    } else {
        Write-Output "  FAIL  $Name (exit=$code, expected=$ExpectExit)"
        if ($ExpectContains -and -not $output.Contains($ExpectContains)) {
            Write-Output "        缺少预期内容: $ExpectContains"
        }
        $script:failures++
    }
}

Write-Output ""
Write-Output "udon-guard 自测"
Write-Output "================"

# 违规样例：必须返回 1，且报出关键规则
Invoke-Case -Name '违规样例被拦截 (async)' -FileArg (Join-Path $tests 'BadExample.cs') `
    -ExtraArgs @() -ExpectExit 1 -ExpectContains 'async/await not supported'
Invoke-Case -Name '违规样例被拦截 (try/catch)' -FileArg (Join-Path $tests 'BadExample.cs') `
    -ExtraArgs @() -ExpectExit 1 -ExpectContains 'try/catch'
Invoke-Case -Name '违规样例被拦截 (StartCoroutine)' -FileArg (Join-Path $tests 'BadExample.cs') `
    -ExtraArgs @() -ExpectExit 1 -ExpectContains 'StartCoroutine'
Invoke-Case -Name '违规样例被拦截 (System.IO)' -FileArg (Join-Path $tests 'BadExample.cs') `
    -ExtraArgs @() -ExpectExit 1 -ExpectContains 'System.Net/System.IO'
# 同步膨胀在包装层被译为中文标签「同步膨胀」，消息正文仍保留原文
Invoke-Case -Name '违规样例被拦截 (同步膨胀)' -FileArg (Join-Path $tests 'BadExample.cs') `
    -ExtraArgs @() -ExpectExit 1 -ExpectContains '同步膨胀'
Invoke-Case -Name '-ErrorsOnly 屏蔽警告' -FileArg (Join-Path $tests 'BadExample.cs') `
    -ExtraArgs @('-ErrorsOnly') -ExpectExit 1 -ExpectContains 'BLOCKED'

# 合规样例：注释里的关键字不得误报
Invoke-Case -Name '合规样例通过（注释不误报）' -FileArg (Join-Path $tests 'GoodExample.cs') `
    -ExtraArgs @() -ExpectExit 0

# 目录模式
Invoke-Case -Name '目录递归扫描' -FileArg $tests -ExtraArgs @('-ErrorsOnly') -ExpectExit 1

# -NoExitCode
Invoke-Case -Name '-NoExitCode 返回 0' -FileArg (Join-Path $tests 'BadExample.cs') `
    -ExtraArgs @('-NoExitCode', '-ErrorsOnly') -ExpectExit 0

# 错误输入
Invoke-Case -Name '不存在路径返回 2' -FileArg (Join-Path $tests 'nope.cs') -ExtraArgs @() -ExpectExit 2
Invoke-Case -Name '非 .cs 文件返回 2' -FileArg (Join-Path $tests 'run-tests.ps1') -ExtraArgs @() -ExpectExit 2

Write-Output ""
if ($failures -eq 0) {
    Write-Output "全部通过"
    exit 0
} else {
    Write-Output "$failures 项失败"
    exit 1
}

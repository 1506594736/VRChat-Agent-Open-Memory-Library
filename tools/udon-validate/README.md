# udon-validate

UdonSharp 静态校验器。**零依赖**，**不绑定任何 AI 平台**。

检查 `.cs` 文件里有没有踩到 Udon 运行时的硬性限制：一类是会直接编译失败的写法，另一类是**编译能过、运行时静默失效**的写法（后者更危险，单机测试永远发现不了）。

---

## 为什么放在 `tools/` 而不是 skill 目录

三个约束，都验证过：

| 约束 | 怎么保证 |
|---|---|
| **不与上游冲突** | 上游仓库根目录只有 `.gitignore`、`Auxiliary script`、`CHANGELOG.md`、`CONTRIBUTING.md`、`LICENSE`、`README.md`、`Training data`、`memoryV5.0.0`、`reports`。`tools/` 不在其中，上游永远不会有这个路径。 |
| **不覆盖** | 同上，合并 `upstream/main` 时 `tools/` 只会被保留。 |
| **可独立更新** | `engine/` 和 `rules.tsv` 都与仓库其他部分无耦合，换掉不影响任何东西。 |

**合并上游后自检：**

```bash
git merge upstream/main
git status --short tools/     # 应当没有任何输出
```

---

## 零依赖是什么意思

| 平台 | 需要什么 | 是否需要安装 |
|---|---|---|
| Linux / macOS | `bash` + `awk` + `grep` | 系统自带 |
| Windows | PowerShell 5.1 | Win10/11 自带 |
| WSL / Git Bash | 同 Linux | 已有 bash 即可 |

**不需要**：`jq`、`python`、`node`、`npm`、任何网络访问、任何 AI 平台 SDK。

> 这一点和上游 `agent-skills-vrc-udon` 不同：它的 bash 版本硬依赖 `jq`，没装就跳过校验。这一版去掉了那层依赖，JSON 解析由各语言入口自己处理，根本没用到。

---

## 用法

### Windows

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\udon-validate\udon-validate.ps1 Scripts\MyBehaviour.cs
powershell -NoProfile -ExecutionPolicy Bypass -File tools\udon-validate\udon-validate.ps1 Assets\MyWorld\Scripts
```

### Linux / macOS / WSL / Git Bash

```bash
./tools/udon-validate/udon-validate.sh Scripts/MyBehaviour.cs
./tools/udon-validate/udon-validate.sh Assets/MyWorld/Scripts
```

### 参数

| 参数 | 作用 |
|---|---|
| `<路径>` | `.cs` 文件，或包含 `.cs` 的目录（递归） |
| `--errors-only` / `-ErrorsOnly` | 只报 BLOCKED/ERROR，屏蔽 WARNING |
| `--no-exit-code` / `-NoExitCode` | 发现问题也返回 0（报告场景） |

### 退出码

| 码 | 含义 |
|---|---|
| `0` | 通过，或仅有 WARNING |
| `1` | 存在 BLOCKED / ERROR |
| `2` | 参数或环境错误 |

---

## 输出示例

```
-- Scripts/MyBehaviour.cs
  BLOCKED  async methods are not supported in Udon. Use SendCustomEventDelayedSeconds() to schedule work.
  BLOCKED  StartCoroutine is not available in Udon. Use SendCustomEventDelayedSeconds().
  WARNING  This file writes [UdonSynced] fields but never calls RequestSerialization(). Under Manual sync the change stays local and other players never see it.

udon-validate: 1/1 file(s) - BLOCKED/ERROR 2, WARNING 1
```

---

## 怎么让 AI 用上它

**不绑定平台**，任何能执行命令的 agent 都可以。在项目约定文件里写一句即可：

- Claude Code / DSH → `CLAUDE.md` 或 `AGENTS.md`
- Cursor → `.cursorrules` / `.cursor/rules/`
- Copilot → `.github/copilot-instructions.md`
- 其他 → 任何会被读进上下文的说明文件

```markdown
写完或修改任何 UdonSharp `.cs` 文件后，运行：

  bash tools/udon-validate/udon-validate.sh <路径>     # Linux/macOS/WSL
  powershell -File tools/udon-validate/udon-validate.ps1 <路径>   # Windows

退出码 1 表示有 BLOCKED/ERROR，必须修完重跑，不得交付。
退出码 0 但有 WARNING 时，仍要逐条确认，尤其是缺少 RequestSerialization 或 ownership 检查的。
```

**没有 hook 机制的平台也能用**——它就是个普通命令，人跑、脚本跑、CI 跑都行。

---

## 修改规则

**只需要动 `rules.tsv`，不用改脚本。**

格式见文件头部注释，七列，其中 `absent` 列是关键：

```
WARNING  U0201  udon  literal  [UdonSynced]  RequestSerialization  <提示语>
                 └ 出现 [UdonSynced]          └ 但如果已经有 RequestSerialization 就不报
```

没有 `absent` 列的话，`[UdonSynced]` 会在每个正确的文件上触发，很快就没人看输出了。

### 当前规则（21 条）

| 类别 | 编号 | 内容 |
|---|---|---|
| 编译必失败 | U0001–U0012 | `async`/`await`、`try`/`catch`/`finally`、`yield return`、`StartCoroutine`、`AddListener`、`System.IO`、`System.Net`、多维数组、`GetComponent<UdonBehaviour>` |
| 运行期静默失效 | U0101–U0104 | `List<T>`、`Dictionary<K,V>`、LINQ、lambda |
| 网络正确性 | U0201–U0203 | 缺 `RequestSerialization`、缺 ownership 检查、`NoVariableSync` 冲突 |

---

## 误报抑制

匹配前会先把**注释和字符串字面量替换成空格**（保持偏移量，行号仍然准确）。所以：

```csharp
// 不要用 List<T>、async、try-catch
private const string Note = "avoid List<T> and System.IO";
```

**这些一行都不会触发规则。** 自测里专门有这两条用例。

---

## 规则来源

- 语言限制：v5 知识库 `concepts/rules/udonsharp-language-limits.md`、`concepts/rules/udonsharp-deep-pitfalls.md`
- 规则思路交叉验证：[niaka3dayo/agent-skills-vrc-udon](https://github.com/niaka3dayo/agent-skills-vrc-udon)（MIT）
  - 它的规则集帮助我们确认了哪些写法是高频错误
  - **本目录的实现和规则表都是重新写的**：引擎用 bash/awk 和 PowerShell 各实现一遍（它只有 jq 依赖的 bash 版和 hook 协议版），规则表加了 `absent` 列
  - 只保留了 `engine/LICENSE` 作为许可证致谢，**没有移植它的代码**

---

## 自测

```bash
bash tools/udon-validate/tests/run-tests.sh          # Linux/macOS/WSL/Git Bash
powershell -File tools/udon-validate/tests/run-tests.ps1   # Windows
```

18 项检查，覆盖：违规能抓到、合规不误报、注释和字符串不误报、非 Udon 的普通 C# 不受 udon 作用域规则影响、参数和退出码、目录递归。

---

## 已知边界

**只做静态文本检查，不是 Roslyn 编译。** 它抓的是已知高频错误模式，不是完备类型检查。

**通过 ≠ 能编译。** 最终仍要 Unity 编译一遍。它的价值是编译前的第一道筛子，尤其是把"运行时静默失效"这类单机测试发现不了的问题提前暴露。

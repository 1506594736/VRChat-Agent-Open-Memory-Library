# udon-guard

UdonSharp 代码的**静态校验器**，用于在 AI（或人）写完 `.cs` 文件后，自动检查有没有踩到 Udon 运行时的硬性限制。

---

## 这个目录为什么独立存在

本目录与知识库（`memoryV5.0.0/`、`.github/skills/`、`skill/`）**没有任何路径交叠**，原因是：

1. 知识库源自上游仓库 `RhineLab-magellan/VRChat-Agent-Creator-Library`，会随上游更新；
2. 校验器是本仓库独有的增强，上游**不存在**这个目录；
3. 放在顶层独立目录，`git merge upstream/main` 时不会产生冲突，也不会被覆盖。

**合并上游前后的自检：**

```bash
git merge upstream/main
git status --short udon-guard/    # 应当没有任何输出
```

---

## 它解决什么问题

知识库能告诉 AI「`List<T>` 在 Udon 里不能用」，但**不能阻止它写出来**。
`validate.ps1` 把这条知识变成了**可执行检查**——写完就扫，发现问题立刻报出来。

两类问题它能抓：

| 类型 | 例子 |
|---|---|
| 编译期会失败 | `async/await`、`try/catch`、`StartCoroutine`、`AddListener`、LINQ、多维数组、`System.IO` |
| 运行时静默失效 | `[UdonSynced]` 但没调 `RequestSerialization()`、没检查 ownership、同步变量膨胀 |

**"静默失效"这一类尤其重要**——它不会报错，只会在多人环境下莫名不工作，单机测试永远发现不了。

---

## 用法

### 单个文件

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File udon-guard/validate.ps1 Scripts/MyBehaviour.cs
```

### 整个目录（递归）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File udon-guard/validate.ps1 Assets/MyWorld/Scripts
```

### 只看致命问题，忽略警告

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File udon-guard/validate.ps1 Scripts/ -ErrorsOnly
```

### 参数

| 参数 | 作用 |
|---|---|
| `<Path>` | `.cs` 文件或目录（必填） |
| `-ErrorsOnly` | 只报告 BLOCKED / ERROR，屏蔽 WARNING |
| `-NoExitCode` | 发现问题也返回 0（报告场景用） |

### 退出码

| 码 | 含义 |
|---|---|
| `0` | 通过，或仅有 WARNING |
| `1` | 存在 BLOCKED / ERROR 级问题 |
| `2` | 参数或环境错误 |

---

## 输出示例

```
-- Scripts/MyBehaviour.cs
  BLOCKED  async/await not supported. Use SendCustomEventDelayedSeconds() instead.
  BLOCKED  StartCoroutine not available. Use SendCustomEventDelayedSeconds() instead.
  WARNING  [UdonSynced] found but no RequestSerialization(). Required for Manual sync mode.

udon-guard: 1/1 个文件有问题 - BLOCKED/ERROR 2 项，WARNING 1 项
```

---

## 与知识库的对应关系

校验器报出的每一条，在知识库里都有对应的展开说明：

| 校验器规则 | 知识库对应页面 |
|---|---|
| `List<T>` / LINQ / lambda 限制 | `entities/world/udon/udonsharp/index.md`、`concepts/rules/udonsharp-language-limits.md` |
| `async` / `try-catch` / `StartCoroutine` | 同上 |
| `[UdonSynced]` 同步问题 | `entities/api/networking.md`、`concepts/rules/networking-rules.md` |
| 同步膨胀 | `entities/world/udon/networking/network-details.md` |
| `System.IO` / `System.Net` | `entities/world/udon/image-loading.md`、`entities/world/udon/external-urls.md` |
| 多维数组 → DataContainer | `entities/world/udon/data-containers/byte-and-bit-operations.md` |

**校验器给出"错了"，知识库给出"为什么错、怎么改"。**

---

## 让 AI 自动使用它

在项目级 agent 配置（`CLAUDE.md` / `AGENTS.md` / `.cursorrules` 等）里加一条：

```markdown
写完或修改任何 UdonSharp (.cs) 文件后，必须运行：
powershell -NoProfile -ExecutionPolicy Bypass -File udon-guard/validate.ps1 <文件路径>
若退出码为 1（出现 BLOCKED/ERROR），必须修复后重新校验，不得直接交付。
遇到不理解的规则，到知识库查证后再改，不要凭猜测绕过。
```

---

## 已知边界

- **只做静态文本检查**，不做真正的 Roslyn 编译。它抓的是"已知的高频错误模式"，不是完备的类型检查。
- **注释和字符串会被打码**，所以注释里提到 `List<T>` 不会误报；但反过来，把代码写在字符串里也不会被检查。
- **规则是英文的**，来自上游项目；不影响使用，但阅读时需要一点英语。
- **不替代编译器**——最终还是要 Unity 编译通过。它是"编译前的第一道筛子"。

---

## 来源与许可

核心校验逻辑来自 [niaka3dayo/agent-skills-vrc-udon](https://github.com/niaka3dayo/agent-skills-vrc-udon)
的 `skills/unity-vrc-udon-sharp/hooks/validate-udonsharp.ps1`（v4.1.1，MIT 协议）。

- 原文件完整保留在 `vendor/niaka3dayo/`，**未修改任何校验规则**
- 许可证原文见 `vendor/niaka3dayo/LICENSE`
- 本目录的 `validate.ps1` 只是把原 hook 的 stdin/stdout 协议包装成命令行用法

如果上游更新了校验规则，可以直接替换 `vendor/niaka3dayo/validate-udonsharp.ps1`，
`validate.ps1` 无需改动。

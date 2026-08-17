# Xiaomi HyperConnect Compatibility

让非官方支持机型从小米官网下载、安装并运行小米电脑管家与超级小爱的非官方兼容工具。仓库同时提供可以直接下载的 DLL，以及一份能交给 AI 使用的安装与 DLL 生成 Skill。

> [!CAUTION]
> 本项目与小米无关，也不受小米支持。兼容方式会让应用加载未签名 DLL，并可选择替换一个签名已失效的旧版小爱组件。请先阅读[安全说明](SECURITY.md)和[第三方声明](THIRD_PARTY_NOTICES.md)，不要在不匹配的版本上强行使用文件。

## 两种使用方式

### 方式一：下载 DLL，跟教程手动安装

适合不使用 AI 的用户。前往 [Latest Release](https://github.com/YangJR08/xiaomi-hyperconnect-compat/releases/latest) 下载：

- [`msimg32.dll`](https://github.com/YangJR08/xiaomi-hyperconnect-compat/releases/latest/download/msimg32.dll)
- [`wtsapi32.dll`](https://github.com/YangJR08/xiaomi-hyperconnect-compat/releases/latest/download/wtsapi32.dll)
- [`SHA256SUMS.txt`](https://github.com/YangJR08/xiaomi-hyperconnect-compat/releases/latest/download/SHA256SUMS.txt)

然后按照下方的[手动安装教程](#手动安装教程)移动文件。默认发布的 `wtsapi32.dll` 会模拟 `TIMI / TM2425`，也是目前实际测试过的版本。

### 方式二：把 Skill 交给 AI

适合希望让 AI 完成诊断、安装、回滚或生成指定机型 DLL 的用户。Skill 位于：

```text
skills/install-xiaomi-hyperconnect/
```

它能指导 AI：

- 从小米官网获取安装包并验证 Xiaomi 数字签名；
- 准备安装器目录、安装运行时 DLL、验证结果和回滚；
- 按指定的 `TMxxxx` 机型代码生成 `msimg32.dll + wtsapi32.dll`；
- 从仓库内置源码重新编译 `msimg32.dll` 代理；
- 区分电脑管家、超级小爱和仅限 3.5.0.220 的旧版补丁边界。

Codex 可以把该目录安装为个人 Skill 后用 `$install-xiaomi-hyperconnect` 调用。其他 AI Agent 如果兼容 Codex/OpenAI Skill 目录，也可以直接导入；不兼容自动导入时，让它完整阅读 [`SKILL.md`](skills/install-xiaomi-hyperconnect/SKILL.md) 即可。仓库根目录的 [`AGENTS.md`](AGENTS.md) 也会提示支持该约定的 Agent 自动读取这份 Skill。

示例提示词：

```text
使用 $install-xiaomi-hyperconnect，从小米官网下载并安装小米电脑管家。先验证签名，修改前备份，最后验证兼容文件。
```

```text
使用 $install-xiaomi-hyperconnect，为 TIMI / TM2430 生成一套兼容 DLL，只生成到新目录，不要安装。
```

不支持 Skill 的 AI 可以使用：

```text
请先完整阅读 skills/install-xiaomi-hyperconnect/SKILL.md 和其中引用的资料，
然后为 TIMI / TM2430 生成兼容 DLL。只写入 generated/TM2430，不要安装或改动系统目录。
```

## 先从小米官网下载

只从小米官方的 [Xiaomi HyperConnect 跨端智联页面](https://hyperos.mi.com/continuity)下载安装包，不要从网盘、论坛附件或软件下载站获取。

截至 2026-08-17，官网页面提供小米电脑管家 5.8.1.121 和超级小爱 3.5.0.227。版本会更新，本仓库不附带也不重新分发任何小米安装包。脚本会验证安装包的 Authenticode 状态和 Xiaomi 签名者。

## 解决了什么问题

在非小米电脑上，官方安装器或程序可能显示：

- “暂不支持本设备”；
- “非常抱歉暂不支持该机型”；
- 超级小爱 3.5.0.220 的“组件加载异常，请检测您的运行环境”。

仓库包含三个兼容文件：

| 文件 | 用途 | 范围 |
| --- | --- | --- |
| `msimg32.dll` | 转发系统图形接口并加载同目录的机型 Hook | 电脑管家/超级小爱安装器；电脑管家运行时 |
| `wtsapi32.dll` | 将相关 WMI 主板查询结果覆盖为 `TIMI / TM2425`，也可生成其他等长 `TMxxxx` 版本 | 两款软件的安装与运行时 |
| `XiaoaiHost.dll` | 屏蔽 3.5.0.220 的 `InfoCheckerService.OnFail()` 失败路径 | **只能用于超级小爱 3.5.0.220** |

所有仓库内置发布文件的 SHA-256 见 [`checksums.sha256`](checksums.sha256)。

## 手动安装教程

先完全退出相关进程，并核对 `SHA256SUMS.txt`。这些 DLL 只放在安装包或应用目录，**不要复制到 `C:\Windows`**。

### 1. 绕过官方安装器的机型检查

将两个 DLL 放到小米官方安装包所在目录，再运行安装包：

```text
下载目录\
  官方安装包.exe
  msimg32.dll
  wtsapi32.dll
```

安装结束并关闭安装器后，可以删除安装包旁的两个 DLL。

### 2. 小米电脑管家运行时

将同一对 `msimg32.dll` 和 `wtsapi32.dll` 放到实际版本目录：

```text
C:\Program Files\MI\XiaomiPCManager\<版本号>\
```

软件升级通常会创建新的版本目录；升级后需要重新诊断和放置，不要覆盖未知版本文件。

### 3. 超级小爱运行时

只需将同一份 `wtsapi32.dll` 分别放到：

```text
C:\Program Files\MI\XiaoaiAgent\<版本号>\
C:\Program Files\MI\XiaoaiAgent\<版本号>\app\
```

`msimg32.dll` 不需要放进超级小爱运行目录。`XiaoaiHost.dll` 只允许由脚本在版本与原文件哈希都匹配 3.5.0.220 时安装，不要手动复制到其他版本。

## 用脚本自动安装和回滚

需要 PowerShell 7。先克隆或下载仓库。

### 准备官方安装器

先用 `-WhatIf` 预览，再执行并启动安装器：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Prepare-OfficialInstaller.ps1' `
  -Product PcManager `
  -InstallerPath 'D:\下载\XiaomiPCManager\官方安装包.exe' `
  -WhatIf

pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Prepare-OfficialInstaller.ps1' `
  -Product PcManager `
  -InstallerPath 'D:\下载\XiaomiPCManager\官方安装包.exe' `
  -Launch
```

超级小爱将 `-Product` 改为 `Xiaoai`。

### 安装运行时兼容文件

以管理员身份打开 PowerShell 7：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Install-RuntimeCompatibility.ps1' -Product PcManager
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Install-RuntimeCompatibility.ps1' -Product Xiaoai
```

如果且仅如果超级小爱 3.5.0.220 仍显示“组件加载异常”，才可执行：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Install-RuntimeCompatibility.ps1' `
  -Product Xiaoai `
  -EnableLegacyInfoCheckerPatch
```

官网 3.5.0.227 不满足旧补丁条件，脚本会拒绝替换 `XiaoaiHost.dll`。

### 验证与回滚

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Test-RuntimeCompatibility.ps1' -Product PcManager
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Test-RuntimeCompatibility.ps1' -Product Xiaoai
```

回滚需要管理员权限：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Remove-RuntimeCompatibility.ps1' -Product PcManager
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Remove-RuntimeCompatibility.ps1' -Product Xiaoai
```

清理安装包旁的兼容文件：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Remove-InstallerCompatibility.ps1' `
  -InstallerPath 'D:\下载\XiaomiPCManager\官方安装包.exe'
```

回滚脚本只处理哈希完全匹配的文件。3.5.0.220 原版 `XiaoaiHost.dll` 会备份到 `%ProgramData%\XiaomiHyperConnectCompat\backups` 后再替换。

## 生成指定机型的 DLL

默认 DLL 使用 `TIMI / TM2425`。如果需要其他六位 `TMxxxx` 型号，例如 `TM2430`：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\New-ModelCompatibilityBundle.ps1' `
  -ModelCode TM2430 `
  -OutputDirectory '.\generated\TM2430'
```

生成目录包含：

```text
generated\TM2430\
  msimg32.dll
  wtsapi32.dll
  SHA256SUMS.txt
```

脚本从已校验的 TM2425 Hook 精确替换唯一一个 UTF-16LE 机型标记，保持 PE 文件长度不变，并为结果生成新 SHA-256。它不会自动安装，也不会修改仓库内置文件。生成的 DLL 仍是未签名兼容层；自定义机型只改变模拟型号，不代表该机型或全部硬件功能已经验证。

如需从源码重新构建通用的 `msimg32.dll` 代理，可在 x64 GCC/MSYS2 UCRT64 环境运行：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Build-Msimg32Proxy.ps1' `
  -OutputDirectory '.\build\skill-proxy'
```

`wtsapi32.dll` 的完整可重编译源码目前不在仓库中，所以生成器做的是受控机型标记派生，不应描述成从零编译 Hook。它也不会生成可用于任意超级小爱新版的 `XiaoaiHost.dll`。

## 安装或导入 Skill

Codex 用户可以让 `$skill-installer` 从以下 GitHub 目录安装：

```text
https://github.com/YangJR08/xiaomi-hyperconnect-compat/tree/main/skills/install-xiaomi-hyperconnect
```

也可以手动复制：

```powershell
git clone https://github.com/YangJR08/xiaomi-hyperconnect-compat.git
$source = '.\xiaomi-hyperconnect-compat\skills\install-xiaomi-hyperconnect'
$destination = Join-Path $env:USERPROFILE '.codex\skills\install-xiaomi-hyperconnect'
Copy-Item -LiteralPath $source -Destination $destination -Recurse
```

重启 Codex 后，用 `$install-xiaomi-hyperconnect` 明确调用。Skill 自带脚本、已校验 DLL、代理源码和技术说明，因此整个 Skill 目录单独导入后仍能安装或生成文件。

对于其他 Agent：是否能“一键导入”取决于其产品是否支持这种 Skill 格式；但 `SKILL.md` 是普通 Markdown，任何能读取仓库文件并运行 PowerShell 的 Agent 都能按其工作流执行。执行安装和系统修改前仍应由用户确认目标与 UAC。

## 技术原理

```text
官方安装器加载本地 msimg32.dll
        ↓
代理转发全部 5 个 msimg32 导出到 System32 原版
        ↓
代理显式加载同目录 wtsapi32.dll
        ↓
wtsapi32 Hook fastprox/CWbemObject::Get
        ↓
主板厂商/型号查询得到 TIMI / TMxxxx
```

旧 Hook 单独放在新版安装器旁不会生效，因为安装器已不再直接加载 `wtsapi32.dll`；`msimg32` 代理恢复了可靠的加载入口。代理源码位于 [`src/msimg32-proxy`](src/msimg32-proxy)，Skill 内也保留一份可独立构建副本。

超级小爱 3.5.0.220 的第二个弹窗与离线模型无关。该版本的 `InfoCheckerService.OnFail()` 会记录失败并把 `MainHelper.IsLegal` 设为 `false`。旧版补丁只将该方法改为立即返回。详细分析、版本边界和验证指标见 [`technical-notes.md`](skills/install-xiaomi-hyperconnect/references/technical-notes.md)。

## 兼容性与限制

- 已验证环境：Windows 11 x64、电脑管家 5.8.1.121、超级小爱 3.5.0.220。
- 官网 3.5.0.227 的安装包入口已确认，但旧版 `XiaoaiHost.dll` **未声明兼容**。
- TM2425 Hook 经用户测试可同时用于两款软件；自定义 `TMxxxx` 生成能力不等于每个型号都已经实机验证。
- 不建议在非小米硬件上使用性能模式、驱动、热键、ICC、固件或底层硬件控制功能。
- 软件升级会切换版本目录；升级后重新诊断，不要盲目复制旧文件。

## 开发和验证

```powershell
pwsh -File '.\src\msimg32-proxy\Build-Proxy.ps1'
pwsh -File '.\tests\Test-Repository.ps1'
```

Skill 另外使用官方 `skill-creator` 的 `quick_validate.py` 校验目录结构和 frontmatter。

## License

新编写的源码、脚本与文档使用 [MIT License](LICENSE)。三个二进制文件不受 MIT 许可覆盖，详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

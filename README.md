# Xiaomi HyperConnect Compatibility

让非官方支持机型从小米官网安装并运行小米电脑管家与超级小爱的非官方兼容工具。

> [!CAUTION]
> 本项目与小米无关，也不受小米支持。它会让应用加载未签名 DLL，并可选择替换一个签名已失效的旧版小爱组件。请先阅读[安全说明](SECURITY.md)和[第三方声明](THIRD_PARTY_NOTICES.md)。不要在不匹配的版本上强行使用文件。

## 先从官网下载

只从小米官方的 [Xiaomi HyperConnect 跨端智联页面](https://hyperos.mi.com/continuity)下载安装包，不要从网盘、论坛附件或软件下载站获取。

截至 2026-08-17，官网页面提供：

- 小米电脑管家 5.8.1.121；
- 超级小爱 3.5.0.227。

版本会更新，本仓库不附带也不重新分发任何小米安装包。脚本会验证安装包的 Authenticode 状态和 Xiaomi 签名者。

## 解决了什么问题

在非小米电脑上，官方安装器或程序可能显示：

- “暂不支持本设备”；
- “非常抱歉暂不支持该机型”；
- 超级小爱 3.5.0.220 的“组件加载异常，请检测您的运行环境”。

本项目包含三个兼容文件：

| 文件 | 用途 | 范围 |
| --- | --- | --- |
| `msimg32.dll` | 转发系统图形接口并加载同目录的机型 Hook | 电脑管家/超级小爱安装器；电脑管家运行时 |
| `wtsapi32.dll` | 将相关 WMI 主板查询结果覆盖为 `TIMI / TM2425` | 两款软件的安装与运行时 |
| `XiaoaiHost.dll` | 屏蔽 3.5.0.220 的 `InfoCheckerService.OnFail()` 失败路径 | **只能用于超级小爱 3.5.0.220** |

所有发布文件的 SHA-256 见 [`checksums.sha256`](checksums.sha256)。

## 推荐方法：使用脚本

需要 PowerShell 7。先克隆或下载本仓库，然后在普通终端中执行安装器准备脚本。

### 小米电脑管家

```powershell
$skill = '.\skills\install-xiaomi-hyperconnect'
pwsh -File "$skill\scripts\Prepare-OfficialInstaller.ps1" `
  -Product PcManager `
  -InstallerPath 'D:\下载\XiaomiPCManager\官方安装包.exe' `
  -WhatIf

pwsh -File "$skill\scripts\Prepare-OfficialInstaller.ps1" `
  -Product PcManager `
  -InstallerPath 'D:\下载\XiaomiPCManager\官方安装包.exe' `
  -Launch
```

安装成功后，以管理员身份打开 PowerShell 7：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Install-RuntimeCompatibility.ps1' `
  -Product PcManager
```

### 超级小爱

```powershell
$skill = '.\skills\install-xiaomi-hyperconnect'
pwsh -File "$skill\scripts\Prepare-OfficialInstaller.ps1" `
  -Product Xiaoai `
  -InstallerPath 'D:\下载\XiaomiPCManager\官方超级小爱安装包.exe' `
  -Launch
```

安装成功后，以管理员身份执行：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Install-RuntimeCompatibility.ps1' `
  -Product Xiaoai
```

如果且仅如果安装的是 3.5.0.220，并且仍出现“组件加载异常”，才能启用旧版补丁：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Install-RuntimeCompatibility.ps1' `
  -Product Xiaoai `
  -EnableLegacyInfoCheckerPatch
```

脚本会校验版本和原文件哈希。官网当前的 3.5.0.227 不满足条件，脚本会拒绝替换 `XiaoaiHost.dll`。

### 验证与回滚

验证不需要管理员权限：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Test-RuntimeCompatibility.ps1' -Product PcManager
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Test-RuntimeCompatibility.ps1' -Product Xiaoai
```

回滚需要管理员权限：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Remove-RuntimeCompatibility.ps1' -Product PcManager
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Remove-RuntimeCompatibility.ps1' -Product Xiaoai
```

清理下载目录中为安装器准备的 DLL：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Remove-InstallerCompatibility.ps1' `
  -InstallerPath 'D:\下载\XiaomiPCManager\官方安装包.exe'
```

回滚脚本只处理哈希完全匹配的文件。3.5.0.220 原版 `XiaoaiHost.dll` 会备份到 `%ProgramData%\XiaomiHyperConnectCompat\backups` 后再替换。

## 手动放置 DLL

不使用脚本时，先自行核对哈希，并完全退出相关进程。

### 安装器目录

将以下两个文件放到官方安装包所在目录，再运行安装包：

```text
官方安装包.exe
msimg32.dll
wtsapi32.dll
```

安装结束后可删除安装包旁的两个 DLL；它们不是系统文件，不要复制到 `C:\Windows`。

### 电脑管家运行目录

将 `msimg32.dll` 与 `wtsapi32.dll` 放到：

```text
C:\Program Files\MI\XiaomiPCManager\<版本号>\
```

### 超级小爱运行目录

只需把同一份 `wtsapi32.dll` 分别放到：

```text
C:\Program Files\MI\XiaoaiAgent\<版本号>\
C:\Program Files\MI\XiaoaiAgent\<版本号>\app\
```

`msimg32.dll` 不需要放进超级小爱运行目录。旧版 `XiaoaiHost.dll` 不允许手动复制到未知版本。

## 安装 Codex Skill

本仓库包含一个自带脚本和兼容文件的 Skill：`install-xiaomi-hyperconnect`。

先克隆仓库：

```powershell
git clone https://github.com/YangJR08/xiaomi-hyperconnect-compat.git
Set-Location '.\xiaomi-hyperconnect-compat'
```

也可以在 Codex 中让 `$skill-installer` 从下面的 GitHub 目录安装：

```text
https://github.com/YangJR08/xiaomi-hyperconnect-compat/tree/main/skills/install-xiaomi-hyperconnect
```

将整个 Skill 目录复制到个人 Skills 目录：

```powershell
$source = '.\skills\install-xiaomi-hyperconnect'
$destination = Join-Path $env:USERPROFILE '.codex\skills\install-xiaomi-hyperconnect'
Copy-Item -LiteralPath $source -Destination $destination -Recurse
```

重新启动 Codex 后，可以这样调用：

```text
使用 $install-xiaomi-hyperconnect 从小米官网下载并安装小米电脑管家。
```

```text
使用 $install-xiaomi-hyperconnect 检查超级小爱是否需要兼容层，并保留可回滚备份。
```

Skill 会先诊断和验证，再说明 UAC 影响；不会替用户确认 UAC，也不会把旧版补丁复制到未知版本。

## 技术原理

简要流程：

```text
官方安装器加载本地 msimg32.dll
        ↓
代理转发全部 5 个 msimg32 导出到 System32 原版
        ↓
代理显式加载同目录 wtsapi32.dll
        ↓
wtsapi32 Hook fastprox/CWbemObject::Get
        ↓
主板厂商/型号查询得到 TIMI / TM2425
```

旧 Hook 单独放在新版安装器旁不会生效，因为安装器已不再直接加载 `wtsapi32.dll`；`msimg32` 代理恢复了可靠的加载入口。代理源码完整保存在 `src/msimg32-proxy`。

超级小爱 3.5.0.220 的第二个弹窗与离线模型无关。该版本的 `InfoCheckerService.OnFail()` 会记录失败并把 `MainHelper.IsLegal` 设为 `false`。旧版补丁只将这个小方法改为立即返回。更详细的分析、版本边界和验证指标见 [`technical-notes.md`](skills/install-xiaomi-hyperconnect/references/technical-notes.md)。

## 兼容性与限制

- 已验证环境：Windows 11 x64、电脑管家 5.8.1.121、超级小爱 3.5.0.220。
- 官网 3.5.0.227 的安装包入口已确认，但旧版 `XiaoaiHost.dll` **未声明兼容**。
- TM2425 Hook 经用户测试可同时用于两款软件，但这不等于所有硬件功能都兼容。
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

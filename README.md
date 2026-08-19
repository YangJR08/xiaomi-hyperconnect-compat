# Xiaomi HyperConnect Compatibility

让非官方支持机型从小米官网下载、安装并运行小米电脑管家与超级小爱的非官方兼容工具。仓库同时提供可以直接下载的 DLL，以及一份能交给 AI 使用的安装与 DLL 生成 Skill。

> [!CAUTION]
> 本项目与小米无关，也不受小米支持。兼容方式会让应用加载未签名 DLL，并可选择替换一个签名已失效的旧版小爱组件。请先阅读[安全说明](SECURITY.md)和[第三方声明](THIRD_PARTY_NOTICES.md)，不要在不匹配的版本上强行使用文件。

## 两种使用方式

### 方式一：下载 DLL，跟教程手动安装

适合不使用 AI 的用户。前往 [Latest Release](https://github.com/YangJR08/xiaomi-hyperconnect-compat/releases/latest)，根据要安装的软件只下载其中一套：

- [小米电脑管家 `TM2425` 安装器 bundle](https://github.com/YangJR08/xiaomi-hyperconnect-compat/releases/latest/download/XiaomiPCManager-TM2425.zip)
- [超级小爱 `TM2430` 安装器 bundle](https://github.com/YangJR08/xiaomi-hyperconnect-compat/releases/latest/download/SuperXiaoAI-TM2430.zip)
- [发布附件 SHA-256](https://github.com/YangJR08/xiaomi-hyperconnect-compat/releases/latest/download/SHA256SUMS.txt)

解压所选 bundle，再按照下方的[手动安装教程](#手动安装教程)操作。两套文件只用于各自产品的安装器检查，不能混用；安装完成后的运行时部署仍以兼容清单和脚本校验结果为准。

### 方式二：把 Skill 交给 AI

适合希望让 AI 完成诊断、安装、回滚或生成指定机型 DLL 的用户。Skill 位于：

```text
skills/install-xiaomi-hyperconnect/
```

它能指导 AI：

- 从小米官网获取安装包并验证 Xiaomi 数字签名；
- 准备安装器目录、安装运行时 DLL、验证结果和回滚；
- 一次生成电脑管家 `TM2425` 和超级小爱 `TM2430` 两套产品专用 bundle，或按指定 `TMxxxx` 生成高级自定义 bundle；
- 从仓库内置源码重新编译 `msimg32.dll` 代理；
- 区分电脑管家、超级小爱和仅限 3.5.0.220 的旧版补丁边界。

Codex 可以把该目录安装为个人 Skill 后用 `$install-xiaomi-hyperconnect` 调用。其他 AI Agent 如果兼容 Codex/OpenAI Skill 目录，也可以直接导入；不兼容自动导入时，让它完整阅读 [`SKILL.md`](skills/install-xiaomi-hyperconnect/SKILL.md) 即可。仓库根目录的 [`AGENTS.md`](AGENTS.md) 也会提示支持该约定的 Agent 自动读取这份 Skill。

示例提示词：

```text
使用 $install-xiaomi-hyperconnect，从小米官网下载并安装小米电脑管家。先验证签名，修改前备份，最后验证兼容文件。
```

```text
使用 $install-xiaomi-hyperconnect，在 build 下生成电脑管家 TM2425 和超级小爱 TM2430 两套产品专用兼容 bundle，只生成，不要安装。
```

不支持 Skill 的 AI 可以使用：

```text
请先完整阅读 skills/install-xiaomi-hyperconnect/SKILL.md 和其中引用的资料，
然后生成电脑管家 TM2425 和超级小爱 TM2430 两套产品专用兼容 bundle。只写入 build，不要安装或改动系统目录。
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
| [`XiaoaiHost.dll`](skills/install-xiaomi-hyperconnect/assets/bin/legacy/xiaoai-3.5.0.220/XiaoaiHost.dll) | 屏蔽 3.5.0.220 的 `InfoCheckerService.OnFail()` 失败路径 | **只能用于超级小爱 3.5.0.220，且只能通过校验脚本安装** |

所有仓库内置发布文件的 SHA-256 见 [`checksums.sha256`](checksums.sha256)。

## 手动安装教程

不需要 AI 也能完成。安装器旁的 DLL 可以手动放置；安装完成后的运行时文件和 `XiaoaiHost.dll` 补丁，为了校验版本、哈希和备份，需要由用户在管理员终端中运行仓库脚本。所有 DLL 都只能放在安装包或应用目录，**不要复制到 `C:\Windows`**。

### 小米电脑管家

1. 新建一个只放电脑管家安装文件的目录。
2. 将官方安装包以及下载并解压后的 `XiaomiPCManager-TM2425` 中的 `msimg32.dll`、`wtsapi32.dll` 放在同一目录；从源码生成时，对应目录是 `build\XiaomiPCManager-TM2425`。
3. 运行官方安装包；安装完成并关闭安装器后，可删除安装包旁的两个 DLL。
4. 完全退出电脑管家，把清单内 TM2425 的同一对运行时 DLL 放入实际版本目录：

   ```text
   C:\Program Files\MI\XiaomiPCManager\<版本号>\
   ```

   不要覆盖哈希未知的同名文件。软件升级创建新版本目录后需要重新检查。

### 超级小爱 3.5.0.220：从安装到不再弹“组件加载异常”

1. 新建一个只放超级小爱安装文件的目录。
2. 将官方 3.5.0.220 安装包以及下载并解压后的 `SuperXiaoAI-TM2430` 中的 `msimg32.dll`、`wtsapi32.dll` 放在同一目录；从源码生成时，对应目录是 `build\SuperXiaoAI-TM2430`。
3. 运行官方安装包。安装结束后完全退出超级小爱及其搜索栏；安装器旁的两个 DLL 可以删除。
4. 不要把安装器 bundle 中的 TM2430 DLL 继续手动复制到运行目录，也不要直接覆盖 `XiaoaiHost.dll`。
5. 以管理员身份打开 **PowerShell 7**，进入本仓库根目录，先预览安装后的全部运行时操作：

   ```powershell
   pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Install-RuntimeCompatibility.ps1' `
     -Product Xiaoai `
     -InstallRoot 'C:\Program Files\MI\XiaoaiAgent\3.5.0.220' `
     -EnableLegacyInfoCheckerPatch `
     -WhatIf
   ```

6. 如果预览没有报版本或哈希错误，原样再次执行，并删除最后一行的 `-WhatIf`。这一个命令会同时完成三件事：

   - 将已验证的 TM2425 `wtsapi32.dll` 放入版本根目录；
   - 将同一文件放入 `app` 子目录；
   - 备份原版 `XiaoaiHost.dll`，再安装 3.5.0.220 专用补丁，阻止环境检查失败弹窗。

7. 启动超级小爱并验证文件状态：

   ```powershell
   pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\Test-RuntimeCompatibility.ps1' `
     -Product Xiaoai `
     -InstallRoot 'C:\Program Files\MI\XiaoaiAgent\3.5.0.220' `
     -AsJson
   ```

   输出中的两个 `wtsapi32.dll` 应为 `Matches: True`，`LegacyXiaoaiHost.State` 应为 `PatchedLegacyFile`，最终 `Compatible` 应为 `True`。

`XiaoaiHost.dll` 补丁仓库路径为 `skills\install-xiaomi-hyperconnect\assets\bin\legacy\xiaoai-3.5.0.220\XiaoaiHost.dll`，安装目标为 `C:\Program Files\MI\XiaoaiAgent\3.5.0.220\XiaoaiHost.dll`。脚本只接受原版哈希 `AB5961C45DEA2FF9C46019B3E8E5A88A26DFC745E7C57586B8EB4F2E8C4B9323`，补丁哈希为 `D80F3C3BAE5C028C02208C3B5148ED0F0965F25AF03DFAA135906E5F2A5A0194`，备份位置为 `%ProgramData%\XiaomiHyperConnectCompat\Xiaoai\3.5.0.220\backups\XiaoaiHost.dll`。3.5.0.227 或未知版本不能使用这个补丁。

### AI 与手动操作的区别

AI 不是安装所必需的。普通用户可以照上面的步骤自行复制文件，并把预览、正式安装和验证命令依次粘贴到 PowerShell；AI 只是代替用户完成同样的签名、哈希、备份和验证工作。AI Agent 应完整遵循 [`skills/install-xiaomi-hyperconnect/SKILL.md`](skills/install-xiaomi-hyperconnect/SKILL.md)，不能跳过 `-WhatIf` 或替用户静默确认 UAC。

## 生成两套产品专用 DLL

当前验证配置是电脑管家使用 `TIMI / TM2425`，超级小爱使用 `TIMI / TM2430`。一次生成两套：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\New-ProductInstallerBundles.ps1' `
  -OutputRoot '.\build'
```

生成目录为：

```text
build\
  XiaomiPCManager-TM2425\
    BUNDLE.json
    msimg32.dll
    wtsapi32.dll
    SHA256SUMS.txt
  SuperXiaoAI-TM2430\
    BUNDLE.json
    msimg32.dll
    wtsapi32.dll
    SHA256SUMS.txt
```

`BUNDLE.json` 标记适用产品和 `installer` 用途并纳入校验和，准备脚本会拒绝跨产品使用。这两套目录用于安装器机型检查，不代表对应型号的运行时功能已验证。脚本只生成文件，不会自动安装或修改系统目录。

如需研究其他六位 `TMxxxx`，仍可使用高级自定义生成器，并通过 `-Product` 标记目标产品：

```powershell
pwsh -File '.\skills\install-xiaomi-hyperconnect\scripts\New-ModelCompatibilityBundle.ps1' `
  -Product Xiaoai `
  -ModelCode TM2430 `
  -OutputDirectory '.\generated\Xiaoai-TM2430'
```

生成器从已校验的 TM2425 Hook 精确替换唯一一个 UTF-16LE 机型标记，保持 PE 文件长度不变，并为结果生成新 SHA-256。生成的 DLL 仍是未签名兼容层；自定义机型只改变模拟型号，不代表该机型或全部硬件功能已经验证。

生成完成后，普通用户按前面的手动教程把对应目录中的两个 DLL 放到安装器旁；AI Agent 则把该目录传给 `Prepare-OfficialInstaller.ps1 -BundleDirectory`。不要仅把 DLL 留在生成目录后直接运行其他目录中的安装器。

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

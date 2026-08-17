---
name: install-xiaomi-hyperconnect
description: Install, diagnose, validate, and roll back the unofficial compatibility layer for Xiaomi PC Manager and Super XiaoAI on unsupported Windows PCs. Use when Codex needs to obtain Xiaomi HyperConnect software from Xiaomi's official site, handle an unsupported-device or unsupported-model dialog, place or verify msimg32.dll/wtsapi32.dll, apply the version-locked XiaoaiHost.dll 3.5.0.220 patch, or safely remove these changes.
---

# Install Xiaomi HyperConnect

Use only official Xiaomi installers and the bundled, hash-locked artifacts. Diagnose before changing the system, request approval before UAC, and preserve a verified rollback path.

## Workflow

1. Read `references/technical-notes.md` when diagnosing a new version, a changed error, or an unexpected hash.
2. Direct the user to `https://hyperos.mi.com/continuity`. Do not download installers from mirrors and do not redistribute Xiaomi installers.
3. Inspect the local installer with `Get-AuthenticodeSignature`. Require `Valid` status and a signer subject containing `Xiaomi Communications Co., Ltd.`.
4. Run `scripts/Prepare-OfficialInstaller.ps1` with `-WhatIf`, review the exact directory and hashes, then rerun without `-WhatIf`. Add `-Launch` only when the user wants the verified installer started.
5. After installation, run `scripts/Install-RuntimeCompatibility.ps1 -WhatIf`. Explain that Program Files will be modified and that unsigned DLLs will be loaded. Request UAC approval before the real run.
6. Run `scripts/Test-RuntimeCompatibility.ps1` and report product version, exact hashes, cached model when available, and responding processes. Do not copy raw logs containing account or authentication fields.
7. If the user requests rollback, run `scripts/Remove-RuntimeCompatibility.ps1 -WhatIf` first, then the elevated real run. Restore only verified backups and remove only exact project hashes.

## Product routing

- For Xiaomi PC Manager, prepare the installer with both common DLLs. Install the runtime pair into the detected version directory.
- For Super XiaoAI, prepare the installer with both common DLLs. Install only `wtsapi32.dll` into the detected version root and its `app` subdirectory.
- Never put `msimg32.dll` into the Super XiaoAI runtime directory.
- Apply `-EnableLegacyInfoCheckerPatch` only for Super XiaoAI 3.5.0.220 when the target `XiaoaiHost.dll` matches the manifest's original hash. Never force this patch on 3.5.0.227 or any unknown version.

## Safety rules

- Treat the artifact manifest as authoritative. Stop on a size, hash, signature, destination, or version mismatch.
- Do not write to `C:\Windows`, alter SMBIOS globally, disable Windows security, or weaken DLL policies.
- Do not assume unsupported hardware-control features are safe. Recommend device-interconnection functions only.
- Do not silently accept UAC, overwrite unknown files, or delete unverified files.
- Keep backups under `%ProgramData%\XiaomiHyperConnectCompat`; never publish those backups or raw client logs.
- Re-diagnose after every Xiaomi update because version directories and checks may change.

## Commands

Prepare an installer:

```powershell
pwsh -File '<skill-dir>\scripts\Prepare-OfficialInstaller.ps1' -Product PcManager -InstallerPath 'D:\path\official.exe' -WhatIf
```

Install runtime compatibility from an elevated PowerShell 7 terminal:

```powershell
pwsh -File '<skill-dir>\scripts\Install-RuntimeCompatibility.ps1' -Product Xiaoai -WhatIf
```

Validate:

```powershell
pwsh -File '<skill-dir>\scripts\Test-RuntimeCompatibility.ps1' -Product Xiaoai -AsJson
```

Resolve `<skill-dir>` to this Skill directory. Use the bundled scripts instead of recreating deployment logic. Patch them only when adding a newly analyzed, explicitly supported version with new hashes and rollback tests.

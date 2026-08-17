---
name: install-xiaomi-hyperconnect
description: Install, diagnose, generate, validate, and roll back Xiaomi PC Manager and Super XiaoAI compatibility DLLs on unsupported Windows PCs. Use when an AI agent needs to obtain Xiaomi HyperConnect software from Xiaomi's official site, handle unsupported-device/model dialogs, safely place msimg32.dll or wtsapi32.dll, generate a custom TIMI/TMxxxx compatibility bundle, build the msimg32 proxy from source, apply the version-locked XiaoaiHost.dll 3.5.0.220 patch, or remove these changes.
---

# Install or Generate Xiaomi HyperConnect Compatibility

Use this Skill in one of two modes: install verified bundled files, or generate a user-requested compatibility bundle without installing it. Keep generation and system deployment as separate approvals.

## Route the request

- For installation or repair, follow **Install workflow**.
- For a requested `TMxxxx` model DLL, follow **Generate workflow**.
- For a clean rebuild of the generic proxy, follow **Build workflow**.
- For a new Xiaomi version or unknown hash, read `references/technical-notes.md` and diagnose. Do not reuse the legacy host patch by assumption.

## Install workflow

1. Direct the user to `https://hyperos.mi.com/continuity`. Do not use mirrors or redistribute Xiaomi installers.
2. Require a `Valid` Authenticode signature whose signer contains `Xiaomi Communications Co., Ltd.`.
3. Run `scripts/Prepare-OfficialInstaller.ps1 -WhatIf`, review exact files, then run it for real. Add `-Launch` only when requested.
4. After installation, run `scripts/Install-RuntimeCompatibility.ps1 -WhatIf`. Explain unsigned DLL loading, backups, Program Files changes, and UAC before the real run.
5. Run `scripts/Test-RuntimeCompatibility.ps1`. Report version, hashes, cached model when available, and responding processes without exposing raw authentication-bearing logs.
6. For rollback, preview `scripts/Remove-RuntimeCompatibility.ps1 -WhatIf`, then run elevated. Restore only verified backups.

## Generate workflow

1. Ask for or infer the exact six-character code matching `TM\d{4}`. Default to the bundled and tested `TM2425` only when the user has no model preference.
2. Run:

   ```powershell
   pwsh -File '<skill-dir>\scripts\New-ModelCompatibilityBundle.ps1' -ModelCode TM2430 -OutputDirectory '<output-dir>'
   ```

3. Return the generated `msimg32.dll`, `wtsapi32.dll`, `SHA256SUMS.txt`, selected model code, and hashes. Do not install them unless the user separately requests installation.
4. Explain that changing the model token does not guarantee the selected code is accepted by a future Xiaomi product version. Prefer a code from that installer's official support list.

The generator uses the verified bundled TM2425 hook, requires exactly one UTF-16LE model token, preserves file length, refuses the Windows and Skill asset directories, and will not overwrite an unexpected output without `-Force`.

## Build workflow

Run the self-contained source build when the user wants a freshly compiled generic `msimg32.dll`:

```powershell
pwsh -File '<skill-dir>\scripts\Build-Msimg32Proxy.ps1' -OutputDirectory '<output-dir>'
```

Require an x64 GCC toolchain such as MSYS2 UCRT64. The script compiles the proxy and smoke test, copies the verified hook, validates all five exports, and reports hashes. A new build can differ byte-for-byte from the released proxy because of linker metadata.

## Product routing

- Xiaomi PC Manager installer: use both common DLLs. Runtime: put both in the selected version directory.
- Super XiaoAI installer: use both common DLLs. Runtime: put only `wtsapi32.dll` in the version root and `app` subdirectory.
- Never put `msimg32.dll` into the Super XiaoAI runtime directory.
- Apply `-EnableLegacyInfoCheckerPatch` only for 3.5.0.220 with the manifest's exact original `XiaoaiHost.dll` hash. Never force it onto 3.5.0.227 or an unknown version.

## Safety rules

- Treat the manifest as authoritative. Stop on a size, hash, signature, destination, or version mismatch.
- Never write to `C:\Windows`, alter SMBIOS globally, disable security controls, or overwrite unknown files.
- Do not silently accept UAC. Limit advice on unsupported hardware to device-interconnection features.
- Keep backups under `%ProgramData%\XiaomiHyperConnectCompat`; never publish them or raw client logs.
- Re-diagnose after Xiaomi updates.

Use the bundled scripts rather than recreating fragile byte-patching or deployment logic.

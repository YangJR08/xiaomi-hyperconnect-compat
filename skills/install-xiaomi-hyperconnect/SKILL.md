---
name: install-xiaomi-hyperconnect
description: Install, diagnose, generate, validate, uninstall, and roll back Xiaomi PC Manager and Super XiaoAI compatibility DLLs on unsupported Windows PCs. Use when an AI agent needs to obtain Xiaomi HyperConnect software from Xiaomi's official site, handle unsupported-device/model dialogs, safely place msimg32.dll or wtsapi32.dll, generate a custom TIMI/TMxxxx compatibility bundle, build either proxy from source, repair an uninstaller blocked by the legacy runtime hook, apply the version-locked XiaoaiHost.dll 3.5.0.220 patch, or remove these changes.
---

# Install or Generate Xiaomi HyperConnect Compatibility

Use this Skill in one of two modes: install verified bundled files, or generate a user-requested compatibility bundle without installing it. Keep generation and system deployment as separate approvals.

## Route the request

- For installation or repair, follow **Install workflow**.
- For a requested `TMxxxx` model DLL, follow **Generate workflow**.
- For a clean rebuild of the generic proxy, follow **Build workflow**.
- When the official `Uninstall.exe` silently exits, follow **Uninstall workflow**.
- For a new Xiaomi version or unknown hash, read `references/technical-notes.md` and diagnose. Do not reuse the legacy host patch by assumption.

## Install workflow

1. Direct the user to `https://hyperos.mi.com/continuity`. Do not use mirrors or redistribute Xiaomi installers.
2. Require a `Valid` Authenticode signature whose signer contains `Xiaomi Communications Co., Ltd.`.
3. Run `scripts/Prepare-OfficialInstaller.ps1 -WhatIf`, review exact files, then run it for real. For a generated product bundle, pass its directory with `-BundleDirectory`; the script validates the deterministic model-token change, product metadata, and checksums before copying. Add `-Launch` only when requested.
4. After installation, run `scripts/Install-RuntimeCompatibility.ps1 -WhatIf`. Explain unsigned DLL loading, backups, Program Files changes, and UAC before the real run.
5. Run `scripts/Test-RuntimeCompatibility.ps1`. Report version, hashes, cached model when available, and responding processes without exposing raw authentication-bearing logs.
6. For rollback, preview `scripts/Remove-RuntimeCompatibility.ps1 -WhatIf`, then run elevated. Restore only verified backups.

## Generate workflow

1. Prefer the currently validated product profiles: Xiaomi PC Manager uses `TM2425`; Super XiaoAI uses `TM2430`. To generate both under one output root, run:

   ```powershell
   pwsh -File '<skill-dir>\scripts\New-ProductInstallerBundles.ps1' -OutputRoot '<output-root>'
   ```

2. For an explicitly requested custom six-character code matching `TM\d{4}`, run `New-ModelCompatibilityBundle.ps1` with `-Product`, `-ModelCode`, and a separate output directory. Do not replace either validated profile by inference.
3. Return each bundle's `BUNDLE.json`, `msimg32.dll`, `wtsapi32.dll`, `SHA256SUMS.txt`, product, model code, and hashes. Do not install them unless the user separately requests installation. When authorized later, pass the selected product directory to `Prepare-OfficialInstaller.ps1 -BundleDirectory` instead of manually trusting its files.
4. Explain that changing the model token does not guarantee it is accepted by another Xiaomi product or future version. Never mix the two product directories.

The generators use the verified bundled TM2425 hook, require exactly one UTF-16LE model token, preserve file length, refuse the Windows and Skill asset directories, and will not overwrite an unexpected output without `-Force`. Product metadata is included in `SHA256SUMS.txt`.

## Build workflow

Run the self-contained source build when the user wants a freshly compiled generic `msimg32.dll`:

```powershell
pwsh -File '<skill-dir>\scripts\Build-Msimg32Proxy.ps1' -OutputDirectory '<output-dir>'
```

Require an x64 GCC toolchain such as MSYS2 UCRT64. The script stages source in an ASCII temporary path, fixes linker metadata for reproducibility with the same toolchain, validates all five exports, verifies that a normal process loads the sibling compatibility layer, and verifies that a process named `Uninstall.exe` skips it. PC Manager runtime deployment must use the current artifact; the v0.3.0 proxy did not contain this guard.

For the runtime WTS proxy that keeps the official uninstaller functional, run:

```powershell
pwsh -File '<skill-dir>\scripts\Build-Wtsapi32Proxy.ps1' -OutputDirectory '<output-dir>'
```

This build stages source in an ASCII temporary path for MSYS2 compatibility, fixes build metadata for reproducibility with the same toolchain, validates all 69 legacy exports, verifies that a normal process loads `XiaomiHyperConnectModelHook.dll`, and verifies that a process named `Uninstall.exe` skips the model hook while WTS calls still work.

## Uninstall workflow

1. Diagnose before changing files. Verify that the registered `Uninstall.exe` exists, has a `Valid` Xiaomi signature, and imports `WTSAPI32.dll`.
2. Run `Install-RuntimeCompatibility.ps1 -WhatIf` for the installed product. A legacy layout will show the old model-hook hash being replaced by `wtsapi32_runtime_proxy` and a renamed `XiaomiHyperConnectModelHook.dll` being added.
3. Run the runtime installer elevated, then validate all runtime targets. This is an in-place compatibility upgrade; do not manually delete `XiaoaiHost.dll` or an unknown same-name file. For PC Manager the script records, temporarily disables, and restores services whose executable path is inside the selected version directory, because several of them keep the runtime DLL mapped.
4. Launch the official uninstaller normally. Both guarded proxies avoid the model layer in `Uninstall.exe`; the WTS proxy initializes only the three imports verified in the Xiaomi uninstallers. Windows Settings and direct double-click uninstall remain usable for both products.
5. If uninstall still fails, stop and collect sanitized process, signature, exit-code, and Application-event evidence. Do not weaken hashes or delete the installation tree manually.

## Product routing

- Xiaomi PC Manager installer: use both DLLs from the `PcManager/TM2425` installer bundle.
- Super XiaoAI installer: use both DLLs from the `Xiaoai/TM2430` installer bundle.
- Runtime deployment remains separately validated. PC Manager receives `msimg32.dll`, the guarded runtime `wtsapi32.dll` proxy, and `XiaomiHyperConnectModelHook.dll`. Super XiaoAI receives the runtime proxy plus renamed model hook in both the version root and `app` subdirectory. Do not infer runtime support from an installer bundle.
- `Prepare-OfficialInstaller.ps1` must reject a bundle whose `BUNDLE.json` product differs from `-Product`.
- Never put `msimg32.dll` into the Super XiaoAI runtime directory.
- Never copy an installer bundle's model Hook directly to a runtime `wtsapi32.dll` destination. The old layout is proven to prevent Xiaomi's official `Uninstall.exe` from opening; use `Install-RuntimeCompatibility.ps1` to migrate it safely.
- Apply `-EnableLegacyInfoCheckerPatch` only for 3.5.0.220 with the manifest's exact original `XiaoaiHost.dll` hash. Never force it onto 3.5.0.227 or an unknown version.
- The patched legacy file is stored at `assets/bin/legacy/xiaoai-3.5.0.220/XiaoaiHost.dll`; it is not an installer-bundle file. Even for a human-driven install, use `Install-RuntimeCompatibility.ps1 -EnableLegacyInfoCheckerPatch` so the script verifies the original hash and creates the recoverable backup. Never instruct the user to copy it over the installed file manually.

## Safety rules

- Treat the manifest as authoritative. Stop on a size, hash, signature, destination, or version mismatch.
- Never write to `C:\Windows`, alter SMBIOS globally, disable security controls, or overwrite unknown files.
- Do not silently accept UAC. Limit advice on unsupported hardware to device-interconnection features.
- Keep backups under `%ProgramData%\XiaomiHyperConnectCompat`; never publish them or raw client logs.
- Re-diagnose after Xiaomi updates.

Use the bundled scripts rather than recreating fragile byte-patching or deployment logic.

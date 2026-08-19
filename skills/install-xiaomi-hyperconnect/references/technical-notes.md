# Technical notes

## Contents

- [Support boundary](#support-boundary)
- [Installer loading chain](#installer-loading-chain)
- [Model hook](#model-hook)
- [Product profiles](#product-profiles)
- [Super XiaoAI runtime](#super-xiaoai-runtime)
- [Legacy InfoChecker patch](#legacy-infochecker-patch)
- [Diagnostic workflow](#diagnostic-workflow)
- [Rollback invariants](#rollback-invariants)

## Support boundary

This project was validated on Windows 11 x64 with Xiaomi PC Manager 5.8.1.121
and Super XiaoAI 3.5.0.220. On 2026-08-17 Xiaomi's official HyperConnect
page exposed Super XiaoAI 3.5.0.227. The common model hook may continue to
work, but the legacy `XiaoaiHost.dll` artifact is not compatible by inference.
Require explicit version and original-hash support before patching it.

Product-specific installer testing on 2026-08-19 found that the generated
`TM2430` hook passed the Super XiaoAI installer but did not pass the Xiaomi PC
Manager installer on the tested system. The `TM2425` hook did pass Xiaomi PC
Manager. Treat these as separate product profiles rather than assuming a
higher model number is universally accepted.

The compatibility layer is intended for Xiaomi device-interconnection
features. Do not treat OEM-specific performance modes, drivers, firmware,
hotkeys, ICC profiles, or hardware control as validated on a non-Xiaomi PC.

## Installer loading chain

The older model hook was named `wtsapi32.dll`. Newer TinySetup-based Xiaomi
installers did not load it directly, so merely placing it beside the installer
stopped affecting the model check. The same installer did load `msimg32.dll`
through normal application-local DLL lookup.

The included x64 proxy therefore:

1. resolves the real `%SystemRoot%\System32\msimg32.dll` by absolute path;
2. forwards all five public exports (`vSetDdrawflag`, `AlphaBlend`,
   `DllInitialize`, `GradientFill`, and `TransparentBlt`);
3. resolves its own directory and explicitly loads the sibling
   `wtsapi32.dll` with `LOAD_WITH_ALTERED_SEARCH_PATH`;
4. fails initialization when the system DLL, an export, or the sibling hook
   cannot be loaded.

No system DLL is replaced, and no file should be copied into `C:\Windows`.

## Model hook

The hook loads the system WMI implementation in
`C:\Windows\System32\wbem\fastprox.dll` and intercepts the relevant
`CWbemObject::Get` result. For the baseboard query it returns:

```text
Manufacturer = TIMI
Product      = TM2425
```

The public binary is an equal-length derivative of an older `TM2205` build.
`src/patchers/patch_model_code.py` requires the exact input SHA-256, exactly
one UTF-16LE model token, and equal encoded lengths. Its purpose is to prevent
an accidental broad binary replacement.

The hook is unsigned and its upstream source/license could not be recovered.
Do not describe it as original source from this repository.

## Product profiles

The generated release candidates are intentionally split:

```text
XiaomiPCManager-TM2425  -> product PcManager, model TM2425
SuperXiaoAI-TM2430      -> product Xiaoai, model TM2430
```

Each product directory includes `BUNDLE.json` with `purpose: installer`. Its
purpose, product, and model fields are covered by `SHA256SUMS.txt`; installer
preparation rejects a product mismatch. Generic custom-model generation remains
available for research, but it is not evidence that another Xiaomi product or
the installed runtime accepts that model.

## Super XiaoAI runtime

The actual WMI model query is hosted by `XiaoaiHost.exe` in the version root,
not only by `app\XiaoaiAgent.exe`. For that reason, the same model hook is
needed in both locations:

```text
<version>\wtsapi32.dll
<version>\app\wtsapi32.dll
```

A successful 3.5.0.220 validation showed the application cache and client
logic reporting `TM2425`, `bShowKnowledgeBase:True`, and an AIVS user-agent
beginning with `TM2425`. Editing only the registry cache is not durable because
the next WMI query overwrites it.

Missing offline model IDs 2001, 2003, 2004, and 2005 are not proof of a broken
environment. They are optional downloads and may legitimately remain absent.

## Legacy InfoChecker patch

After the model gate passed in 3.5.0.220, the client repeatedly logged:

```text
App-InfoCheckerService,OnFail
```

Static .NET IL analysis resolved the method as
`XiaoaiAgent.Services.UI.Interface.InfoCheckerService.OnFail()`. Its effective
behavior was to log the failure and set `MainHelper.IsLegal` to `false`, which
the UI later used for the “component loading exception” dialog.

The patch changes only that small method body to `ret` plus padding, preserving
the file length. The patch invalidates Xiaomi's Authenticode signature. The
installer script requires all of the following:

- selected product is Super XiaoAI;
- selected version is exactly 3.5.0.220;
- installed original SHA-256 is
  `AB5961C45DEA2FF9C46019B3E8E5A88A26DFC745E7C57586B8EB4F2E8C4B9323`;
- bundled patched SHA-256 is
  `D80F3C3BAE5C028C02208C3B5148ED0F0965F25AF03DFAA135906E5F2A5A0194`;
- a verified original backup is created before replacement.

The patched repository asset is
`assets/bin/legacy/xiaoai-3.5.0.220/XiaoaiHost.dll`; the installed destination
is `<Xiaoai 3.5.0.220 root>\XiaoaiHost.dll`. It is deliberately excluded from
the product installer bundles. Do not document direct manual replacement;
human users should run the same guarded runtime installation script as an AI.

Do not weaken these checks to support another version. Analyze the new
assembly and add a separate manifest entry and test instead.

## Diagnostic workflow

1. Verify the installer source and Authenticode signer.
2. Record product version and hashes before making changes.
3. Use `-WhatIf` to show destinations and replacement decisions.
4. Stop only the product-specific processes.
5. Install and re-hash every destination.
6. Validate process responsiveness and application-local module loading.
7. For Super XiaoAI, read only the cached PC model and narrowly filtered error
   indicators. Never publish raw logs containing account or authentication
   configuration fields.
8. Check Windows Application events for new crashes after the launch time.

## Rollback invariants

- Never remove a target whose hash differs from the project manifest.
- Restore a prior file only when its backup hash equals the recorded prior
  hash.
- Leave a compatibility file in place when it predated the tracked install.
- Never delete a patched `XiaoaiHost.dll` without the verified original
  backup.
- Keep backups after rollback for manual recovery; remove only the completed
  state record.

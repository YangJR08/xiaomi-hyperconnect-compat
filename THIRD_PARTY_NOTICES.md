# Third-party notices

This is an unofficial compatibility project and is not affiliated with,
endorsed by, or supported by Xiaomi.

The MIT License in this repository covers only the newly written source code,
scripts, tests, and documentation. It does **not** grant rights to the
following binary artifacts.

The source-built proxies at
`skills/install-xiaomi-hyperconnect/assets/bin/common/msimg32.dll` and
`skills/install-xiaomi-hyperconnect/assets/bin/runtime/wtsapi32.dll` are new
project code covered by the MIT License. The runtime WTS proxy is distinct
from the model Hook described below, even though installer bundles use the
same filename for that Hook.

## `wtsapi32.dll`

- Path: `skills/install-xiaomi-hyperconnect/assets/bin/common/wtsapi32.dll`
- SHA-256: `8938C3DA6EC67396B353A7B855BE7E706D3BAEEEB80726680A3BE58F60905772`
- Status: unsigned x64 binary.
- Provenance: derived from an old compatibility DLL supplied by a user. The
  original upstream project and license could no longer be identified.
- Local modification: one equal-length UTF-16LE model token was changed from
  `TM2205` to `TM2425`; see `src/patchers/patch_model_code.py`.

The file is redistributed for compatibility and archival purposes without a
claim of authorship. If you are the rights holder and want the artifact
removed or attributed differently, open an issue.

## `XiaoaiHost.dll`

- Path: `skills/install-xiaomi-hyperconnect/assets/bin/legacy/xiaoai-3.5.0.220/XiaoaiHost.dll`
- SHA-256: `D80F3C3BAE5C028C02208C3B5148ED0F0965F25AF03DFAA135906E5F2A5A0194`
- Base product version: Super XiaoAI 3.5.0.220.
- Status: modified Xiaomi binary; its original Authenticode signature is no
  longer valid.
- Local modification: the small .NET method
  `InfoCheckerService.OnFail()` was changed to return immediately; see
  `src/patchers/patch_info_checker.py`.

This legacy artifact is version- and hash-locked. It must not be applied to
3.5.0.227 or any other version. Xiaomi retains all rights in its original
binary.

## Names and trademarks

Xiaomi, HyperOS, Xiaomi HyperConnect, Xiaomi PC Manager, and Super XiaoAI are
names or trademarks of their respective owners. Their use here is solely to
describe interoperability.

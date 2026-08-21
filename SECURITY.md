# Security policy

## Important risk notice

This project intentionally uses application-local DLL loading to run Xiaomi
software on hardware outside the official support list. Treat all included
binaries as security-sensitive:

- `msimg32.dll`, the runtime `wtsapi32.dll` proxy, and the renamed model Hook
  are unsigned.
- the legacy `XiaoaiHost.dll` has an invalidated Xiaomi signature because it
  was modified after signing;
- DLL side-loading can also be abused by malware, so never replace these
  files with copies from mirrors or file-sharing sites;
- unsupported hardware control, driver, performance, hotkey, and display
  features may behave incorrectly.

Verify every SHA-256 value against `checksums.sha256` before use. The included
scripts refuse unknown versions and unknown same-name files.

Do not copy an installer bundle's `wtsapi32.dll` directly into an installed
version directory. The official Xiaomi uninstaller imports that name and the
legacy model Hook prevents it from opening. Runtime deployment must use the
guarded proxy plus `XiaomiHyperConnectModelHook.dll`.

PC Manager services and `OSDUtility.exe` can keep the compatibility DLLs
mapped. Use the bundled install/remove scripts so their original service state
is recorded and restored; do not delete the installation tree to work around
a sharing violation.

## Reporting

Do not post account tokens, cookies, raw application logs, registry exports,
or personally identifying information in a public issue. Provide product
version, file hashes, sanitized error text, and reproduction steps instead.

## Updates

An application update may replace or move files. Do not copy an old patch into
a new version directory. Re-run the read-only validation and wait for the
compatibility manifest to explicitly support the new version.

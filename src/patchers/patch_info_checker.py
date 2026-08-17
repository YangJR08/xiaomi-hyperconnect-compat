from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


EXPECTED_INPUT_SHA256 = "AB5961C45DEA2FF9C46019B3E8E5A88A26DFC745E7C57586B8EB4F2E8C4B9323"
EXPECTED_OFFSET = 0x184D2

# Tiny CIL method header (34-byte body), followed by the original OnFail body.
ORIGINAL = bytes.fromhex(
    "8A "
    "7E 46 00 00 04 "          # ldsfld LogConsts.AppTag
    "72 26 C4 00 70 "          # ldstr 'InfoCheckerService,OnFail'
    "72 5A C4 00 70 "          # ldstr 'OnFail'
    "1F 13 "                   # ldc.i4.s 19
    "28 2F 01 00 06 "          # call LogHelper.Info
    "28 4D 06 00 06 "          # call MainHelper.GetInstance
    "16 "                      # ldc.i4.0
    "7D 83 03 00 04 "          # stfld MainHelper.IsLegal
    "2A"                       # ret
)

# Preserve the tiny header and method-body length. Return immediately, then pad
# the now-unreachable remainder with nop instructions so no metadata moves.
PATCHED = bytes([0x8A, 0x2A]) + bytes(len(ORIGINAL) - 2)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Disable only InfoCheckerService.OnFail in XiaoaiHost.dll 3.5.0.220."
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    source_data = args.source.read_bytes()
    source_hash = sha256(source_data)
    if source_hash != EXPECTED_INPUT_SHA256:
        raise SystemExit(
            f"Refusing unexpected input hash: {source_hash}; expected {EXPECTED_INPUT_SHA256}"
        )

    hits = []
    start = 0
    while True:
        offset = source_data.find(ORIGINAL, start)
        if offset < 0:
            break
        hits.append(offset)
        start = offset + 1

    if hits != [EXPECTED_OFFSET]:
        raise SystemExit(f"Unexpected method-body matches: {[hex(x) for x in hits]}")

    patched_data = bytearray(source_data)
    patched_data[EXPECTED_OFFSET : EXPECTED_OFFSET + len(ORIGINAL)] = PATCHED
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_bytes(patched_data)

    print(f"source_sha256={source_hash}")
    print(f"patched_offset=0x{EXPECTED_OFFSET:X}")
    print(f"patched_length={len(ORIGINAL)}")
    print(f"destination_sha256={sha256(patched_data)}")


if __name__ == "__main__":
    main()

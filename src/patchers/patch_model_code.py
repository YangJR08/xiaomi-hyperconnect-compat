"""Create a model-specific copy of the legacy WMI hook DLL.

Only one UTF-16LE model token is replaced, and the input hash plus equal byte
length are required so this cannot silently modify an unexpected DLL build.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--old-model", required=True)
    parser.add_argument("--new-model", required=True)
    args = parser.parse_args()

    source = args.input.read_bytes()
    actual_hash = sha256(source)
    if actual_hash != args.expected_sha256.upper():
        raise SystemExit(
            f"Input hash mismatch: expected {args.expected_sha256.upper()}, got {actual_hash}"
        )

    old_token = args.old_model.encode("utf-16le")
    new_token = args.new_model.encode("utf-16le")
    if len(old_token) != len(new_token):
        raise SystemExit("Model codes must have equal UTF-16LE byte length")

    occurrence_count = source.count(old_token)
    if occurrence_count != 1:
        raise SystemExit(f"Expected exactly one old model token; found {occurrence_count}")

    patched = source.replace(old_token, new_token, 1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(patched)
    print(f"input_sha256={actual_hash}")
    print(f"output_sha256={sha256(patched)}")
    print(f"replacement={args.old_model}->{args.new_model}")
    print(f"output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Release tool for the freeAIsetup pack.

  uv run --with cryptography python tools/release.py keygen
      Creates the signing key (once) OUTSIDE the repo and outside Dropbox:
      %USERPROFILE%\\.freeaisetup\\release-key.pem (keep a backup copy, e.g. on a USB stick).
      Writes the matching public keys into update/pubkey.xml (Windows) and update/pubkey.pem (Mac/Linux).

  uv run --with cryptography python tools/release.py manifest --version 2026.11.8.1 --notes "..."
      Writes VERSION, release/manifest.json (SHA-256 of every pack file) and release/manifest.sig.
      Then commit, tag v<version>, and push the tag (see docs/releasing.md).

The installed pack refuses any update whose manifest signature does not match update/pubkey.*,
so even someone who takes over the GitHub account cannot push code to students.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACK = ["install-windows.cmd", "setup-windows.ps1", "setup-mac.sh", "VERSION", "lib", "course-kit", "doctor", "guide", "update"]
SKIP = ("__pycache__", ".pyc", ".bak", ".DS_Store")
KEY = pathlib.Path(os.environ.get("FREEAISETUP_KEY", pathlib.Path.home() / ".freeaisetup" / "release-key.pem"))


def pack_files() -> list[pathlib.Path]:
    out = []
    for k in PACK:
        p = ROOT / k
        for f in ([p] if p.is_file() else sorted(p.rglob("*"))):
            if f.is_file() and not any(s in f.as_posix() for s in SKIP):
                out.append(f)
    return out


def keygen() -> None:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    if KEY.exists():
        sys.exit(f"{KEY} already exists; refusing to overwrite the signing key")
    KEY.parent.mkdir(parents=True, exist_ok=True)
    k = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    KEY.write_bytes(k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                    serialization.NoEncryption()))
    write_public(k.public_key())
    print(f"signing key written to {KEY}  -- keep a backup copy; never commit it")


def write_public(pub) -> None:
    from cryptography.hazmat.primitives import serialization
    nums = pub.public_numbers()
    b = lambda n: base64.b64encode(n.to_bytes((n.bit_length() + 7) // 8, "big")).decode()
    (ROOT / "update").mkdir(exist_ok=True)
    (ROOT / "update" / "pubkey.xml").write_text(
        f"<RSAKeyValue><Modulus>{b(nums.n)}</Modulus><Exponent>{b(nums.e)}</Exponent></RSAKeyValue>\n", encoding="ascii")
    (ROOT / "update" / "pubkey.pem").write_bytes(
        pub.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))


def manifest(version: str, notes: str, key: pathlib.Path = KEY, out_dir: pathlib.Path | None = None) -> pathlib.Path:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    priv = serialization.load_pem_private_key(key.read_bytes(), password=None)
    (ROOT / "VERSION").write_text(version + "\n", encoding="ascii", newline="\n")
    files = {f.relative_to(ROOT).as_posix(): hashlib.sha256(f.read_bytes()).hexdigest() for f in pack_files()}
    doc = {"version": version, "published": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "notes": notes, "files": dict(sorted(files.items()))}
    data = (json.dumps(doc, indent=1, ensure_ascii=False) + "\n").encode("utf-8")
    sig = priv.sign(data, padding.PKCS1v15(), hashes.SHA256())
    out = out_dir or (ROOT / "release")
    out.mkdir(parents=True, exist_ok=True)
    (out / "manifest.json").write_bytes(data)
    (out / "manifest.sig").write_text(base64.b64encode(sig).decode() + "\n", encoding="ascii", newline="\n")
    print(f"release {version}: {len(files)} files signed -> {out / 'manifest.json'}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("keygen")
    m = sub.add_parser("manifest")
    m.add_argument("--version", required=True)
    m.add_argument("--notes", default="")
    a = ap.parse_args()
    keygen() if a.cmd == "keygen" else manifest(a.version, a.notes)

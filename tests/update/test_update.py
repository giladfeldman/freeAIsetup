"""End-to-end test of the pack updater against a local web server that plays the role of GitHub.

  uv run --with cryptography python tests/update/test_update.py            (Windows: update.ps1)
  uv run --with cryptography python tests/update/test_update.py --shell    (Mac/Linux: update.sh)

Uses a throw-away signing key, never the real one. Each case prints PASS/FAIL; exit code = number of failures.
Cases: v1 -> v2 update (changed, added and removed files) · already up to date · bad signature refused ·
tampered file refused (checksum) · no network = quiet no-op · rollback · unsafe path refused.
"""
from __future__ import annotations

import argparse
import functools
import http.server
import os
import pathlib
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading

REPO = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import release  # noqa: E402

from cryptography.hazmat.primitives import serialization  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import rsa  # noqa: E402

FAILS: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(("PASS  " if ok else "FAIL  ") + name + (f"   ({detail})" if detail and not ok else ""))
    if not ok:
        FAILS.append(name)


def make_tree(dst: pathlib.Path, key: pathlib.Path) -> None:
    for item in release.PACK:
        src = REPO / item
        if src.is_dir():
            shutil.copytree(src, dst / item, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        elif src.exists():
            shutil.copy2(src, dst / item)
    (dst / "VERSION").write_text("0\n")


def publish(tree: pathlib.Path, srv: pathlib.Path, version: str, key: pathlib.Path) -> None:
    """Sign `tree` as `version` and lay it out like GitHub: main/release/manifest.* + v<version>/<files>."""
    release.ROOT = tree
    release.manifest(version, f"test {version}", key=key, out_dir=srv / "main" / "release")
    vdir = srv / f"v{version}"
    for f in release.pack_files():
        d = vdir / f.relative_to(tree)
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, d)


def serve(root: pathlib.Path) -> tuple[socketserver.TCPServer, int]:
    h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
    h.log_message = lambda *a, **k: None
    httpd = socketserver.TCPServer(("127.0.0.1", 0), h)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, httpd.server_address[1]


def run_updater(pack: pathlib.Path, home: pathlib.Path, sources: str, shell: bool, *args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, MS_UPDATE_SOURCES=sources, MS_UPDATE_NO_SETUP="1", METASCIENCE_DIR=str(home / "MetaScience"))
    if shell:
        cmd = [os.environ.get("FAS_BASH", "bash"), (pack / "update" / "update.sh").as_posix(), *args]
    else:
        cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(pack / "update" / "update.ps1"), *args]
    return subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=300)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--shell", action="store_true", help="test update.sh instead of update.ps1")
    a = ap.parse_args()
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="fas-upd-"))
    key = tmp / "test-key.pem"
    k = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    key.write_bytes(k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))

    # v1 = the pack as it is now, with the TEST public key
    v1 = tmp / "v1"; v1.mkdir()
    make_tree(v1, key)
    release.ROOT = v1
    release.write_public(k.public_key())
    srv = tmp / "srv"
    publish(v1, srv, "2026.1.1.1", key)
    home = tmp / "home"; pack = home / "MetaScience" / "pack"   # the installed pack
    shutil.copytree(v1, pack)
    httpd, port = serve(srv)
    base = f"http://127.0.0.1:{port}"
    sources = f"{base}/main/release/manifest.json|{base}/v{{V}}/{{P}}"
    shell = a.shell

    r = run_updater(pack, home, sources, shell)
    check("same version = up to date", "up to date" in (r.stdout + r.stderr), r.stdout + r.stderr)

    # v2: one file changed, one added, one removed
    v2 = tmp / "v2"; shutil.copytree(v1, v2)
    (v2 / "course-kit" / "prompts").mkdir(parents=True, exist_ok=True)
    (v2 / "course-kit" / "prompts" / "week2.md").write_text("new prompt for week 2\n")
    (v2 / "lib" / "course_setup.py").write_text((v2 / "lib" / "course_setup.py").read_text(encoding="utf-8") + "\n# v2\n", encoding="utf-8")
    victim = sorted((v2 / "guide").glob("*"))[0]
    victim.unlink()
    publish(v2, srv, "2026.1.2.1", key)
    r = run_updater(pack, home, sources, shell)
    out = r.stdout + r.stderr
    check("update v1 -> v2 applied", (pack / "VERSION").read_text().strip() == "2026.1.2.1", out)
    check("added file arrived", (pack / "course-kit" / "prompts" / "week2.md").is_file(), out)
    check("changed file updated", (pack / "lib" / "course_setup.py").read_text(encoding="utf-8").endswith("# v2\n"), out)
    check("removed file gone", not (pack / "guide" / victim.name).exists(), out)
    check("previous version kept", (home / "MetaScience" / "pack-previous" / "VERSION").read_text().strip() == "2026.1.1.1", out)

    # bad signature: v3 manifest edited after signing
    v3 = tmp / "v3"; shutil.copytree(v2, v3)
    (v3 / "lib" / "course_setup.py").write_text("print('evil')\n")
    publish(v3, srv, "2026.1.3.1", key)
    m = srv / "main" / "release" / "manifest.json"
    m.write_text(m.read_text(encoding="utf-8").replace("test 2026.1.3.1", "test 2026.1.3.1 tampered"), encoding="utf-8")
    r = run_updater(pack, home, sources, shell)
    check("tampered manifest refused", (pack / "VERSION").read_text().strip() == "2026.1.2.1" and "REFUSED" in (r.stdout + r.stderr), r.stdout + r.stderr)

    # valid signature, but a served file differs from the manifest
    publish(v3, srv, "2026.1.3.1", key)
    (srv / "v2026.1.3.1" / "lib" / "course_setup.py").write_text("print('swapped on the server')\n")
    r = run_updater(pack, home, sources, shell)
    check("swapped file refused (checksum)", (pack / "VERSION").read_text().strip() == "2026.1.2.1"
          and "checksum" in (r.stdout + r.stderr), r.stdout + r.stderr)
    check("pack untouched after refusal", (pack / "lib" / "course_setup.py").read_text(encoding="utf-8").endswith("# v2\n"))

    # signed by a different key
    other = tmp / "other.pem"
    k2 = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    other.write_bytes(k2.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    publish(v3, srv, "2026.1.4.1", other)
    r = run_updater(pack, home, sources, shell)
    check("wrong signing key refused", (pack / "VERSION").read_text().strip() == "2026.1.2.1", r.stdout + r.stderr)

    # no network
    r = run_updater(pack, home, "http://127.0.0.1:9/main/release/manifest.json|http://127.0.0.1:9/v{V}/{P}", shell)
    check("no network = quiet no-op", r.returncode == 0 and (pack / "VERSION").read_text().strip() == "2026.1.2.1", r.stdout + r.stderr)

    # rollback
    r = run_updater(pack, home, sources, shell, "--rollback" if shell else "-Rollback")
    check("rollback restores v1", (pack / "VERSION").read_text().strip() == "2026.1.1.1"
          and not (pack / "course-kit" / "prompts" / "week2.md").exists(), r.stdout + r.stderr)

    httpd.shutdown()
    print(f"\n{len(FAILS)} failure(s)" + (": " + ", ".join(FAILS) if FAILS else ""))
    shutil.rmtree(tmp, ignore_errors=True)
    return len(FAILS)


if __name__ == "__main__":
    sys.exit(main())

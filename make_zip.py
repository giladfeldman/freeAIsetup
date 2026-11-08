"""Builds dist/metascience-setup.zip (what students download): the pack, without tests and build files.
Run:  python make_zip.py [--out <path to zip>]"""
import argparse, pathlib, zipfile
here = pathlib.Path(__file__).resolve().parent
ap = argparse.ArgumentParser(); ap.add_argument("--out", default=str(here / "dist" / "metascience-setup.zip"))
out = pathlib.Path(ap.parse_args().out); out.parent.mkdir(parents=True, exist_ok=True)
keep = ["install-windows.cmd", "setup-windows.ps1", "setup-mac.sh", "VERSION", "lib", "course-kit", "doctor", "guide", "update"]
skip = ("__pycache__", ".pyc", ".bak", "walkthrough.md")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for k in keep:
        p = here / k
        for f in ([p] if p.is_file() else sorted(p.rglob("*"))):
            if f.is_file() and not any(s in str(f) for s in skip):
                info = zipfile.ZipInfo.from_file(f, "student-setup/" + f.relative_to(here).as_posix())
                if f.suffix == ".sh":
                    info.external_attr = 0o100755 << 16
                z.writestr(info, f.read_bytes(), zipfile.ZIP_DEFLATED)
print(f"Built {out} ({out.stat().st_size // 1024} KB, {len(zipfile.ZipFile(out).namelist())} files)")

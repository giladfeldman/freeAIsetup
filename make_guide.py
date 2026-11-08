"""Builds guide/walkthrough.docx from guide/walkthrough.md (pandoc), then adds table borders and bold header rows.
Run:  python student-setup/make_guide.py"""
import pathlib, subprocess
from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
g = pathlib.Path(__file__).resolve().parent / "guide"
out = g / "walkthrough.docx"
subprocess.run(["pandoc", str(g / "walkthrough.md"), "-o", str(out)], check=True)
d = Document(out)
for t in d.tables:
    pr = t._tbl.tblPr
    b = OxmlElement("w:tblBorders")
    for side in ("top", "left", "bottom", "right", "insideH", "insideV"):
        e = OxmlElement(f"w:{side}"); e.set(qn("w:val"), "single"); e.set(qn("w:sz"), "4"); e.set(qn("w:color"), "999999"); b.append(e)
    pr.append(b)
    for c in t.rows[0].cells:
        for p in c.paragraphs:
            for r in p.runs: r.bold = True
d.save(out); print("Built", out)

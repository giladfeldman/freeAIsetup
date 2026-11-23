"""The check's rows file (<log>.check.tsv) is written only when the setup asks for it (MS_RESULT_ROWS).

Sol review 2026-11-24: a check started on its own (-Check / --check, -Keys, or lib/course_setup.py by hand) left the
file behind in the temp or course folder, and nothing ever removed it.

  python tests/course-setup/test_check_rows.py      exit code = number of failures
"""
from __future__ import annotations

import contextlib
import io
import os
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "lib"))
import course_setup  # noqa: E402

FAILS = 0


def run(env_on: bool) -> bool:
    with tempfile.TemporaryDirectory() as d:
        course = pathlib.Path(d) / "course"
        course.mkdir()
        log = pathlib.Path(d) / "setup.log"
        if env_on:
            os.environ["MS_RESULT_ROWS"] = "1"
        else:
            os.environ.pop("MS_RESULT_ROWS", None)
        with contextlib.redirect_stdout(io.StringIO()):
            course_setup.check(course, True, log, ())
        return log.with_suffix(".check.tsv").is_file()


for name, env_on, want in (("check on its own: no rows file", False, False), ("check asked by the setup: rows file", True, True)):
    got = run(env_on)
    print(("PASS  " if got == want else "FAIL  ") + name)
    FAILS += got != want
os.environ.pop("MS_RESULT_ROWS", None)
sys.exit(FAILS)

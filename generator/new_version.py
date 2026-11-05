#!/usr/bin/env python3
"""Point the repository at a new published data version.

    generator/new_version.py v3            # after data/v3/ exists

Rewrites every reference to the previous version (paths, release tag,
defaults, the reader package's defaults and examples) to the new one,
moves the pending-changes list into the version table in data/README.md
as the new version's "what changed" entry, and resets pending-changes.json
to an empty list for the new version. publish_version.sh runs this last.

Rules: the previous version comes from pending-changes.json; a bare token
such as "v2" is replaced only where it stands alone (not "v2.06", not
"HL7 v2"); lines of the version table in data/README.md are history and
are never rewritten; docs/DESIGN.md is touched only in data paths.
"""
import datetime as dt
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Files where a standalone "vN" means the published data version.
TOKEN_FILES = [
    ".github/workflows/release.yml", "viewer/app.js", "erd/app.js", "README.md", "index.html", "data/README.md",
    "generator/preview.py", "generator/erd.py", "generator/build.py", "generator/README.md", "CLAUDE.md",
]
TOKEN_GLOBS = ["fakehospdata/R/*.R", "fakehospdata/man/*.Rd", "fakehospdata/tests/testthat/*.R", "fakehospdata/README.md"]
# Files where only data paths are rewritten.
PATH_FILES = ["docs/DESIGN.md"]


def main(new):
    if not re.fullmatch(r"v\d+", new):
        sys.exit(f"version must look like v3, got {new}")
    pending_path = ROOT / "pending-changes.json"
    pending = json.load(open(pending_path))
    old = pending["published_version"]
    if old == new:
        sys.exit(f"pending-changes.json already says {new}")
    if not (ROOT / "data" / new / "manifest.json").exists():
        sys.exit(f"data/{new}/manifest.json does not exist; build and copy the data first")
    token = re.compile(rf"(?<![\w.]){re.escape(old)}(?![\w.])")
    changed = []

    def rewrite(path, fn):
        p = ROOT / path
        if not p.exists():
            return
        s = p.read_text()
        t = fn(s)
        if t != s:
            p.write_text(t); changed.append(str(path))

    def token_sub(s):
        out = []
        for line in s.split("\n"):
            if "HL7" in line or line.startswith("| v"):
                out.append(line)
            else:
                out.append(token.sub(new, line))
        return "\n".join(out)

    files = list(TOKEN_FILES)
    for g in TOKEN_GLOBS:
        files += [str(p.relative_to(ROOT)) for p in sorted(ROOT.glob(g))]
    for f in files:
        rewrite(f, token_sub)
    for f in PATH_FILES:
        rewrite(f, lambda s: s.replace(f"data/{old}/", f"data/{new}/").replace(f"/{old}/sample", f"/{new}/sample").replace(f"/{old}/full", f"/{new}/full"))

    # version table: the pending changes become the new version's row
    today = dt.date.today().isoformat()
    what = " ".join(c.rstrip(".") + "." for c in pending["changes"]) or "Rebuilt with no listed generator changes."
    row = f"| {new} | {today} | {what} |\n"
    rewrite("data/README.md", lambda s: re.sub(r"(\| --- \| --- \| --- \|\n)", r"\1" + row.replace("\\", "\\\\"), s, count=1))

    pending.update({"published_version": new, "published_build": today,
                    "note": f"The generator has moved on since {new} was built. These changes are in the code but not in the published data; the dataset will be regenerated as the next version when the list is complete.",
                    "changes": []})
    pending_path.write_text(json.dumps(pending, indent=2) + "\n"); changed.append("pending-changes.json")
    print(f"{old} -> {new}: rewrote " + ", ".join(sorted(set(changed))))
    left = [f for f in files + PATH_FILES if (ROOT / f).exists() and token.search("\n".join(l for l in (ROOT / f).read_text().split("\n") if "HL7" not in l and not l.startswith("| v")))]
    if left:
        print("still mention the old version (check by hand):", left)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__))

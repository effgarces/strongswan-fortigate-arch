#!/usr/bin/env python3
"""Adds the pinned FortiGate patches to Arch's strongswan PKGBUILD.

usage: patch-pkgbuild.py <PKGBUILD> <patch-dir> [--lock patches.lock]

Edits: source=() + the checksum array, pkgrel (-> <pkgrel>.<PATCH_REV>) and
prepare() (patches applied in lock order, --fuzz=0).  If the PKGBUILD no
longer has the structure expected here, this exits non-zero instead of
guessing, so a changed upstream PKGBUILD can never yield a silently wrong build.
"""
import hashlib, pathlib, re, subprocess, sys

MARK = "FortiGate patches (added by strongswan-fortigate-arch)"


def die(msg):
    print(f"patch-pkgbuild: {msg}", file=sys.stderr)
    sys.exit(1)


def read_lock(path):
    rev, names = None, []
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("PATCH_REV="):
            rev = line.split("=", 1)[1]
        elif "=" in line.split()[0]:
            continue
        else:
            names.append(line.split()[0])
    if not rev or not re.fullmatch(r"\d+", rev):
        die("PATCH_REV missing or not a number in patches.lock")
    if not names:
        die("no patches listed in patches.lock")
    return rev, names


def find_array(text, name):
    """(start, end) of the inside of `name=( ... )`, honouring quotes; None if absent."""
    m = re.search(rf"^{name}=\(", text, re.M)
    if not m:
        return None
    i, quote = m.end(), None
    while i < len(text):
        c = text[i]
        if quote:
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == ")":
            return m.end(), i
        i += 1
    die(f"unterminated {name}=( array")


def b2(data):
    return hashlib.blake2b(data, digest_size=64).hexdigest()


def main():
    args = sys.argv[1:]
    lock = pathlib.Path(__file__).resolve().parent.parent / "patches.lock"
    if "--lock" in args:
        k = args.index("--lock")
        lock = pathlib.Path(args[k + 1])
        del args[k:k + 2]
    if len(args) != 2:
        die(__doc__)
    pkgbuild, patchdir = pathlib.Path(args[0]), pathlib.Path(args[1])
    rev, names = read_lock(lock)
    text = pkgbuild.read_text()
    if MARK in text:
        die("PKGBUILD already patched")

    # --- source=() ---
    span = find_array(text, "source")
    if not span:
        die("no source=( array found")
    s, e = span
    text = text[:e].rstrip() + "".join(f"\n        {n}.patch" for n in names) + text[e:]

    # --- checksum arrays (sha512sums / sha256sums / b2sums) ---
    algos = {"sha512sums": lambda d: hashlib.sha512(d).hexdigest(),
             "sha256sums": lambda d: hashlib.sha256(d).hexdigest(),
             "b2sums": b2}
    done = 0
    for arr, fn in algos.items():
        span = find_array(text, arr)
        if not span:
            continue
        s, e = span
        add = "".join(f"\n            '{fn((patchdir / (n + '.patch')).read_bytes())}'" for n in names)
        text = text[:e].rstrip() + add + text[e:]
        done += 1
    if not done:
        die("no sha512sums/sha256sums/b2sums array found")

    # --- pkgrel ---
    m = re.search(r"^pkgrel=(\S+)$", text, re.M)
    if not m or not re.fullmatch(r"\d+(\.\d+)*", m.group(1)):
        die("pkgrel line not found or not a plain number")
    old_rel = m.group(1)
    text = text[:m.start()] + f"pkgrel={old_rel}.{rev}" + text[m.end():]

    # --- prepare() ---
    block = (f"  # --- {MARK} ---\n"
             "  local _forti_patch\n"
             f"  for _forti_patch in {' '.join(names)}; do\n"
             '    patch -Np1 --fuzz=0 -i "${srcdir}/${_forti_patch}.patch"\n'
             "  done\n"
             "  # --- end FortiGate patches ---\n")
    pm = re.search(r"^prepare\(\) \{\n(\s*cd [^\n]*\n)", text, re.M)
    if pm:
        text = text[:pm.end()] + block + text[pm.end():]
    elif re.search(r"^prepare\(\)", text, re.M):
        die("prepare() exists but does not start with a cd line; refusing to guess")
    else:
        b = re.search(r"^build\(\) \{", text, re.M)
        if not b:
            die("no prepare() and no build() found")
        func = 'prepare() {\n  cd "${pkgname}-${pkgver}"\n' + block + "}\n\n"
        text = text[:b.start()] + func + text[b.start():]

    pkgbuild.write_text(text)
    r = subprocess.run(["bash", "-n", str(pkgbuild)], capture_output=True, text=True)
    if r.returncode:
        die("resulting PKGBUILD has a shell syntax error:\n" + r.stderr)
    ver = re.search(r"^pkgver=(\S+)$", text, re.M)
    print(f"patched PKGBUILD: pkgver={ver.group(1) if ver else '?'} "
          f"pkgrel={old_rel} -> {old_rel}.{rev}, {len(names)} patches")


if __name__ == "__main__":
    main()

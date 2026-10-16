#!/usr/bin/env python3
"""Pack the public build into the upload zip.

  make_release.py <build-public dir> <release dir> <zip name>

Layout (the one other Bingus Shared Loader mods use): manifest.json, README.txt
and Addon/ with the patch file and its two empty side files.
"""
import os
import sys
import zipfile

ARCHIVE = "9ba626afa44a3aa3"


def main():
    build, release, name = sys.argv[1:4]
    out = os.path.join(release, name)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for extra in ("manifest.json", "README.txt"):
            z.write(os.path.join(release, extra), extra)
        for suffix in ("", ".gpu_resources", ".stream"):
            f = ARCHIVE + ".patch_0" + suffix
            z.write(os.path.join(build, f), "Addon/" + f)
    print("wrote", out)


if __name__ == "__main__":
    main()

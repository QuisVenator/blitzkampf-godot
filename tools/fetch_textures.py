#!/usr/bin/env python3
"""Builds the CC0 ambientCG textures used by the maps into textures/ambientcg/.

Download the five zips ("1K-JPG", links are printed when one is missing) into a folder and
pass it: python3 tools/fetch_textures.py <folder with the zips>. ambientCG refuses scripted
Python downloads, so fetch them with a browser or curl.

Each texture becomes <name>.png (colour) and <name>_normal.png (OpenGL normal map, which
is what Godot expects), resized to 512 px. FuncGodot picks the *_normal file up by name and
TrenchBroom hides it from its texture browser. Reads straight out of the zips (nothing else
is extracted).
"""
import os
import sys
import zipfile

from PIL import Image

# our name -> ambientCG asset id (https://ambientcg.com/view?id=<id>)
TEXTURES = {
    "concrete": "Concrete034",
    "bricks": "Bricks059",
    "metal": "Metal032",
    "painted_metal": "PaintedMetal012",
    "tiles": "Tiles074",
}
SIZE = 512
OUT = os.path.join(os.path.dirname(__file__), "..", "textures", "ambientcg")


def main() -> None:
    source = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(OUT, exist_ok=True)
    for name, asset in TEXTURES.items():
        path = os.path.join(source, f"{asset}_1K-JPG.zip")
        if not os.path.exists(path):
            sys.exit(f"missing {path}: download https://ambientcg.com/get?file={asset}_1K-JPG.zip")
        archive = zipfile.ZipFile(path)
        for suffix, target in (("Color", name), ("NormalGL", name + "_normal")):
            with archive.open(f"{asset}_1K-JPG_{suffix}.jpg") as member:
                image = Image.open(member).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
            image.save(os.path.join(OUT, target + ".png"), optimize=True)
    with open(os.path.join(OUT, "LICENSE.txt"), "w") as f:
        f.write("These textures are from ambientCG.com, licensed CC0 1.0 (public domain).\n")
        f.write("https://creativecommons.org/publicdomain/zero/1.0/\n\n")
        for name, asset in TEXTURES.items():
            f.write(f"{name}.png: https://ambientcg.com/view?id={asset}\n")
        f.write("\nResized to 512 px by tools/fetch_textures.py.\n")


if __name__ == "__main__":
    main()

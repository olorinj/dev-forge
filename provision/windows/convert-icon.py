#!/usr/bin/env python3
"""Universal PNG to multi-resolution Windows ICO converter for dev-forge."""

import os
import struct
import sys
from pathlib import Path


def convert_with_pillow(png_path: Path, ico_path: Path) -> bool:
    try:
        from PIL import Image

        img = Image.open(png_path)
        sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
        img.save(ico_path, format="ICO", sizes=sizes)
        return True
    except Exception:
        return False


def convert_raw_png_to_ico(png_path: Path, ico_path: Path) -> bool:
    """Fallback: Embed PNG directly into Windows ICO container."""
    try:
        png_data = png_path.read_bytes()
        if not png_data.startswith(b"\x89PNG\r\n\x1a\n"):
            return False

        # Read width and height from IHDR chunk (bytes 16..24)
        width, height = struct.unpack(">II", png_data[16:24])
        w_byte = width if width < 256 else 0
        h_byte = height if height < 256 else 0

        # ICONDIR header: reserved(2) + type(2) + count(2)
        icondir = struct.pack("<HHH", 0, 1, 1)

        # ICONDIRENTRY: width(1) + height(1) + color_count(1) + reserved(1) +
        #               planes(2) + bit_count(2) + bytes_in_res(4) + offset(4)
        offset = 6 + 16  # len(icondir) + len(entry)
        direntry = struct.pack(
            "<BBBBHHII",
            w_byte,
            h_byte,
            0,
            0,
            1,
            32,
            len(png_data),
            offset,
        )

        ico_path.write_bytes(icondir + direntry + png_data)
        return True
    except Exception as e:
        print(f"Error in raw ICO fallback: {e}", file=sys.stderr)
        return False


def main():
    if len(sys.argv) < 3:
        print("Usage: convert-icon.py <input.png> <output.ico>", file=sys.stderr)
        sys.exit(1)

    png_path = Path(sys.argv[1])
    ico_path = Path(sys.argv[2])

    if not png_path.is_file():
        print(f"Error: input file '{png_path}' not found", file=sys.stderr)
        sys.exit(1)

    ico_path.parent.mkdir(parents=True, exist_ok=True)

    if convert_with_pillow(png_path, ico_path):
        print(f"[OK] Converted '{png_path}' to multi-layer ICO via Pillow: '{ico_path}'")
        sys.exit(0)

    if convert_raw_png_to_ico(png_path, ico_path):
        print(f"[OK] Converted '{png_path}' to PNG-embedded ICO: '{ico_path}'")
        sys.exit(0)

    print(f"Error: failed to convert '{png_path}' to ICO", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()

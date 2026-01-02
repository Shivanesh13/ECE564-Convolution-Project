#!/usr/bin/env python3
"""
img2svmem.py — Emit ONLY an addr-tagged 64-bit-per-line mem file with a 4x4 kernel header.

Mem layout (8 bytes per line, little-endian by default):
  @00000000  <8 kernel bytes>
  @00000008  <8 kernel bytes>
  @00000010  <image bytes begin>   # row-major u8 grayscale

Kernel source matches conv4x4:
  - Presets strictly in {-1,0,1}: box, edge, sharpen, emboss
  - Or --kernel-values / --kernel-csv, which are quantized to {-1,0,1}
  - Stored as int8 two’s-complement bytes (e.g., -1 -> FF, 0 -> 00, 1 -> 01)

Examples
  # Exact output filename, default kernel=box (all ones)
  python3 img2svmem.py 5.3.01.tiff -o sv_mem/5.3.01_u8.addr8.mem

  # Use the 'edge' kernel and force size first
  python3 img2svmem.py 5.3.01.tiff -o sv_mem/5.3.01_u8.addr8.mem \
      --kernel edge --target 1024x1024 --resize nearest

  # Use custom kernel values (quantized to {-1,0,1})
  python3 img2svmem.py frame.png -o mem/frame.addr8.mem \
      --kernel-values "1,0,-1,0; 1,0,-1,0; 1,0,-1,0; 1,0,-1,0"
"""

import os, sys, argparse, glob, re
from typing import Tuple, Optional, List
import numpy as np
from PIL import Image

# ----------------------------
# Utilities
# ----------------------------

def parse_target(s: Optional[str]) -> Optional[Tuple[int,int]]:
    if not s:
        return None
    s = s.lower()
    if 'x' in s:
        w, h = s.split('x', 1)
        return (int(w), int(h))
    raise argparse.ArgumentTypeError("Target must be WIDTHxHEIGHT, e.g. 1024x1024")

def ensure_dir(path: str):
    if path:
        os.makedirs(path, exist_ok=True)

def to_gray_u8(img: Image.Image) -> np.ndarray:
    if img.mode != 'L':
        img = img.convert('L')
    return np.array(img, dtype=np.uint8)

def resize_image(img: Image.Image, target: Tuple[int,int], method: str) -> Image.Image:
    w, h = target
    methods = {
        'nearest': Image.NEAREST,
        'bilinear': Image.BILINEAR,
        'bicubic' : Image.BICUBIC,
        'lanczos' : Image.LANCZOS,
    }
    if method not in methods:
        raise ValueError(f"Unknown resize method: {method}")
    return img.resize((w, h), methods[method])

def pad_or_truncate(u8: np.ndarray, target: Tuple[int,int], pad_where: str) -> np.ndarray:
    """
    Pad with zeros or truncate to fit target (W,H).
    pad_where: comma list from {left,right,top,bottom}; default right,bottom.
    """
    H, W = u8.shape
    Wt, Ht = target
    dx, dy = Wt - W, Ht - H
    x_left = x_right = y_top = y_bottom = 0
    pads = set(p.strip().lower() for p in pad_where.split(',')) if pad_where else {'right','bottom'}

    # Horizontal
    if dx >= 0:
        if 'left' in pads and 'right' in pads:
            x_left = dx // 2; x_right = dx - x_left
        elif 'left' in pads:
            x_left = dx
        else:
            x_right = dx
    else:
        if 'left' in pads and 'right' in pads:
            x_crop_left = (-dx) // 2; x_crop_right = (-dx) - x_crop_left
            u8 = u8[:, x_crop_left: W - x_crop_right]
        elif 'left' in pads:
            u8 = u8[:, -dx:]       # keep rightmost Wt
        else:
            u8 = u8[:, :Wt]        # keep leftmost Wt

    # Vertical
    H, W = u8.shape
    dy = Ht - H
    if dy >= 0:
        if 'top' in pads and 'bottom' in pads:
            y_top = dy // 2; y_bottom = dy - y_top
        elif 'top' in pads:
            y_top = dy
        else:
            y_bottom = dy
    else:
        if 'top' in pads and 'bottom' in pads:
            y_crop_top = (-dy) // 2; y_crop_bottom = (-dy) - y_crop_top
            u8 = u8[y_crop_top: H - y_crop_bottom, :]
        elif 'top' in pads:
            u8 = u8[-dy:, :]       # keep bottommost Ht
        else:
            u8 = u8[:Ht, :]        # keep topmost Ht

    if x_left or x_right or y_top or y_bottom:
        u8 = np.pad(u8, ((y_top, y_bottom), (x_left, x_right)), mode='constant', constant_values=0)
    return u8

# ----------------------------
# Kernel handling (match conv4x4)
# ----------------------------

def parse_kernel_values(s: str) -> np.ndarray:
    rows = [row.strip() for row in s.strip().split(";")]
    mat: List[List[float]] = []
    for r in rows:
        if not r:
            continue
        mat.append([float(x.strip()) for x in r.split(",") if x.strip()])
    k = np.array(mat, dtype=np.float32)
    if k.shape != (4, 4):
        raise ValueError(f"--kernel-values must define a 4x4 matrix, got {k.shape}")
    return k

def kernel_preset(name: str) -> np.ndarray:
    """All presets strictly use {-1,0,1} entries (float32, row-major)."""
    name = (name or "box").lower()
    if name == "box":
        k = np.ones((4,4), dtype=np.float32)
    elif name == "edge":
        k = np.array([
            [-1, -1, -1, -1],
            [ 0,  0,  0,  0],
            [ 1,  1,  1,  1],
            [ 0,  0,  0,  0]
        ], dtype=np.float32)
    elif name == "sharpen":
        k = np.array([
            [ 0, -1, -1,  0],
            [-1,  1,  1, -1],
            [-1,  1,  1, -1],
            [ 0, -1, -1,  0]
        ], dtype=np.float32)
    elif name == "emboss":
        k = np.array([
            [-1, -1,  0,  0],
            [-1,  0,  0,  1],
            [ 0,  0,  1,  1],
            [ 0,  1,  1,  1]
        ], dtype=np.float32)
    else:
        raise ValueError(f"Unknown kernel preset: {name}")
    return k

def quantize_kernel_to_trinary(k: np.ndarray) -> np.ndarray:
    """Force any kernel to {-1,0,1} via nearest thresholding."""
    q = np.zeros_like(k, dtype=np.float32)
    q[k >  0.5] =  1.0
    q[k < -0.5] = -1.0
    return q

def kernel_to_i8_bytes(k: np.ndarray) -> np.ndarray:
    """Row-major 4x4 -> 16 int8 coeffs, as raw two’s-complement bytes (np.uint8 view)."""
    k_q = quantize_kernel_to_trinary(k).astype(np.int8).reshape(-1)  # int8 in {-1,0,1}
    return k_q.view(np.uint8)  # reinterpret as bytes

# ----------------------------
# Writer (addr8 with kernel header)
# ----------------------------

def save_addr8_with_kernel(u8_image: np.ndarray,
                           output_path: str,
                           endian: str,
                           kernel_bytes_u8: np.ndarray) -> str:
    """
    Write two 64-bit lines of kernel (16 bytes total), then image bytes.
    Two spaces after @address. Always pad the final line to 8 bytes with 0x00.
    """
    flat_img = u8_image.reshape(-1).astype(np.uint8) + 128
    stream = np.concatenate([kernel_bytes_u8.astype(np.uint8), flat_img], axis=0)

    ensure_dir(os.path.dirname(output_path) or ".")
    with open(output_path, "w") as f:
        addr = 0
        for i in range(0, stream.size, 8):
            chunk = stream[i:i+8]
            # endianness transform: little -> reverse within the 64-bit word
            data = chunk[::-1] if endian.lower() == "little" else chunk
            if data.size < 8:
                pad = np.zeros(8 - data.size, dtype=np.uint8)
                data = np.concatenate([data, pad], axis=0)
            hexstr = "".join(f"{int(b):02x}" for b in data.tolist())
            f.write(f"@{addr:08x}  {hexstr}\n")
            addr += 8
    return output_path

# ----------------------------
# Pipeline
# ----------------------------

def process_one(path: str,
                out_path: Optional[str],
                out_dir: str,
                target: Optional[Tuple[int,int]],
                resize: Optional[str],
                pad_where: str,
                force_name: Optional[str],
                endian: str,
                kernel_name: str,
                kernel_values: Optional[str],
                kernel_csv: Optional[str]):

    # Determine output file path
    if out_path:
        output_path = out_path
    else:
        name = force_name if force_name else os.path.splitext(os.path.basename(path))[0]
        output_path = os.path.join(out_dir, f"{name}_u8.addr8.mem")

    # Load image -> u8
    img = Image.open(path)
    if resize and target:
        img = resize_image(img.convert('L'), target, resize)
        u8 = to_gray_u8(img)
    else:
        u8 = to_gray_u8(img)
        if target:
            u8 = pad_or_truncate(u8, target, pad_where)

    # Build kernel (float32), then to i8 bytes
    if kernel_values:
        k = parse_kernel_values(kernel_values)
    elif kernel_csv:
        import csv
        rows = []
        with open(kernel_csv, "r") as f:
            for r in csv.reader(f):
                if not r: continue
                rows.append([float(x) for x in r])
        k = np.array(rows, dtype=np.float32)
        if k.shape != (4,4):
            raise ValueError(f"--kernel-csv must be 4x4, got {k.shape}")
    else:
        k = kernel_preset(kernel_name)
    kernel_bytes = kernel_to_i8_bytes(k)  # length 16

    out_written = save_addr8_with_kernel(u8, output_path, endian=endian, kernel_bytes_u8=kernel_bytes)
    H, W = u8.shape
    print(f"[OK] {path} -> {out_written} (W={W}, H={H}, endian={endian})")
    print("     Header layout:")
    print("       @00000000  <8 kernel bytes>")
    print("       @00000008  <8 kernel bytes>")
    print("       @00000010  <image bytes begin>")

# ----------------------------
# CLI
# ----------------------------

def main():
    ap = argparse.ArgumentParser(description="Image -> addr8 MEM with 4x4 kernel header (row-major).")
    ap.add_argument("inputs", nargs="+", help="Input image paths or globs (e.g., frame*.png)")
    ap.add_argument("-o", "--out", default=None,
                    help="Exact output filename (e.g., sv_mem/5.3.01_u8.addr8.mem). Only with a single input.")
    ap.add_argument("-d", "--outdir", default="sv_mem",
                    help="Output directory (used when --out is not given).")

    ap.add_argument("--target", type=parse_target, default=None, help="Force target WxH (e.g., 1024x1024)")
    ap.add_argument("--pad", dest="pad_where", default="right,bottom",
                    help="Pad/crop preference: comma list from {left,right,top,bottom}.")
    ap.add_argument("--resize", choices=["nearest","bilinear","bicubic","lanczos"], default=None,
                    help="If set (with --target), resize to the target instead of pad/crop.")
    ap.add_argument("--name", default=None, help="Optional forced base name (single input only; ignored if --out is set)")

    ap.add_argument("--endian", choices=["little","big"], default="little",
                    help="Byte order within each 64-bit line (default: little).")

    # Kernel args (match conv4x4)
    ap.add_argument("--kernel", choices=["box","edge","sharpen","emboss"], default="box",
                    help="4x4 kernel preset (strictly in {-1,0,1}).")
    ap.add_argument("--kernel-values", default=None,
                    help='Explicit 4x4 matrix; e.g. "1,0,-1,0; 1,0,-1,0; 1,0,-1,0; 1,0,-1,0"')
    ap.add_argument("--kernel-csv", default=None,
                    help="CSV file with 4 rows × 4 columns for the kernel.")

    args = ap.parse_args()

    # Resolve inputs (globs)
    paths = []
    for p in args.inputs:
        m = glob.glob(p)
        paths.extend(m if m else [p])

    if args.out and len(paths) != 1:
        print("error: --out may only be used with a single input file", file=sys.stderr)
        sys.exit(2)

    if not args.out:
        ensure_dir(args.outdir)

    for p in paths:
        process_one(p,
                    out_path=args.out,
                    out_dir=args.outdir,
                    target=args.target,
                    resize=args.resize,
                    pad_where=args.pad_where,
                    force_name=args.name,
                    endian=args.endian,
                    kernel_name=args.kernel,
                    kernel_values=args.kernel_values,
                    kernel_csv=args.kernel_csv)

if __name__ == "__main__":
    main()


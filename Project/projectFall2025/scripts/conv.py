#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse, os, re
import numpy as np
from PIL import Image
from pathlib import Path

# =========================
# Hexdump I/O (8 bytes per line)
# =========================
# e.g.  @00000010  0011223344556677  // comment
_HEXLINE = re.compile(r'^\s*@([0-9A-Fa-f]+)\s+([0-9A-Fa-f\s]+)\s*$')



from pathlib import Path

def dump_int8_array(arr: np.ndarray,
                    path: str,
                    fmt: str = "csv",
                    map_to_u8: bool = False) -> None:
    """
    Dump a 2D int8 array.

    Parameters
    ----------
    arr : np.ndarray
        2D array, dtype int8 (will be cast if not).
    path : str
        Output file path. ('.csv' | '.bin' | '.npy' typically)
    fmt : str
        'csv'  -> comma-separated integers
        'bin'  -> raw bytes in row-major order
        'npy'  -> NumPy .npy file
    map_to_u8 : bool
        If True, map [-128..127] -> [0..255] via (x + 128).
        Useful when you want unsigned bytes in CSV or BIN.
    """
    if arr.ndim != 2:
        raise ValueError(f"Expected 2D array, got {arr.ndim}D.")

    if arr.dtype != np.int8:
        arr = arr.astype(np.int8, copy=False)

    fmt = fmt.lower()
    out = Path(path)

    if fmt == "csv":
        # For readability, write numbers (optionally mapped to 0..255)
        data = (arr.astype(np.int16) + 128) if map_to_u8 else arr.astype(np.int16)
        np.savetxt(out, data, delimiter=",", fmt="%d")
    elif fmt == "bin":
        # Raw bytes in row-major order
        if map_to_u8:
            data = (arr.astype(np.int16) + 128).astype(np.uint8, copy=False)
        else:
            # Bytes are identical either way; view as uint8 to avoid sign surprises.
            data = arr.view(np.uint8)
        data.tofile(out)
    elif fmt == "npy":
        np.save(out, arr, allow_pickle=False)
    else:
        raise ValueError(f"Unknown fmt '{fmt}'. Use 'csv', 'bin', or 'npy'.")



def _reverse_per8(b: bytes) -> bytes:
    # Reverse byte order inside each 8-byte word
    out = bytearray(len(b))
    for i in range(0, len(b), 8):
        chunk = b[i:i+8]
        out[i:i+8] = chunk[::-1]
    return bytes(out)

def load_hexdump_u8_little(path: str) -> np.ndarray:
    """
    Read @ADDR HEX hexdump where each line is a 64-bit word shown big-endian.
    Convert to a byte buffer in LITTLE-endian (reverse each 8B chunk).
    """
    with open(path, "rb") as f:
        lines = f.read().decode("utf-8", errors="ignore").splitlines()

    recs = []
    max_end = 0
    for raw in lines:
        line = raw.split("//", 1)[0].strip()
        if not line:
            continue
        m = _HEXLINE.match(line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        hex_str = ''.join(m.group(2).split())
        if len(hex_str) % 2 != 0:
            raise ValueError("Odd hex digit count at line: {}".format(raw))
        data_be = bytes.fromhex(hex_str)
        data_le = _reverse_per8(data_be)  # big->little per 64-bit word
        recs.append((addr, data_le))
        end = addr + len(data_le)
        if end > max_end:
            max_end = end

    if not recs:
        raise ValueError("No @ADDR HEX lines found.")

    buf = bytearray(max_end)
    for addr, data_le in recs:
        buf[addr:addr+len(data_le)] = data_le
    return np.frombuffer(bytes(buf), dtype=np.uint8)

def write_mem_addr8_from_u8(u8: np.ndarray, path: str, endian: str = "little"):
    flat = u8.reshape(-1).astype(np.uint8)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        addr = 0
        for i in range(0, flat.size, 8):
            chunk = flat[i:i+8]
            data = chunk[::-1] if endian == "little" else chunk
            if data.size < 8:
                pad = np.zeros(8 - data.size, dtype=np.uint8)
                data = np.concatenate([data, pad], axis=0)
            hexstr = "".join(f"{int(b):02x}" for b in data.tolist())
            f.write(f" @{addr:016x} {hexstr}\n")
            addr += 8

def write_mem_addr8_from_i8(i8: np.ndarray, path: str, endian: str = "little"):
    write_mem_addr8_from_u8(i8.view(np.uint8), path, endian=endian)

def write_hexdump_from_little(path: str, start_addr: int, raw_le: bytes,
                              bytes_per_line: int = 8, comment: str = ""):
    """
    Write LITTLE-endian bytes back to @ADDR HEX format with 64-bit addresses.
    - Each printed line represents 'bytes_per_line' bytes of memory.
    - Within the line, reverse each 8-byte WORD for big-endian text display.
    - The final (short) line is padded with 0x00 at higher addresses (end of memory chunk)
      BEFORE per-8B reversal, so printed order is correct.
    """
    if bytes_per_line % 8 != 0:
        raise ValueError("bytes_per_line must be a multiple of 8 (got {})".format(bytes_per_line))

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        addr = start_addr
        n = len(raw_le)
        for i in range(0, n, bytes_per_line):
            line_le = raw_le[i:i+bytes_per_line]
            # Pad tail with zeros to full bytes_per_line in MEMORY (little-endian):
            if len(line_le) < bytes_per_line:
                line_le = b"\x00" * (bytes_per_line - len(line_le)) + line_le 

            # Build big-endian text per 8-byte WORD (don’t reverse the whole line):
            be_hex_parts = []
            for w in range(0, len(line_le), 8):
                word_le = line_le[w:w+8]
                be_hex_parts.append(word_le[::-1].hex())  # reverse 8B only

            hexs = ''.join(be_hex_parts)
            line = " @{addr:016x} {hexs}".format(addr=addr, hexs=hexs)
            if comment and i == 0:
                line += "  // " + comment
            f.write(line + "\n")
            addr += bytes_per_line



# =========================
# Utilities
# =========================
def parse_dims(s: str):
    # "WIDTHxHEIGHT" -> (H, W)
    try:
        w, h = s.lower().split("x")
        return int(h), int(w)
    except Exception:
        raise argparse.ArgumentTypeError('use --dims "WIDTHxHEIGHT", e.g. "1024x1024"')

def parse_hex_or_int(v: str):
    v = v.strip().lower()
    return int(v, 16) if v.startswith("0x") else int(v, 10)

def read_kernel_i8(buf_u8: np.ndarray, kernel_offset: int) -> np.ndarray:
    end = kernel_offset + 16
    if end > buf_u8.size:
        raise ValueError("kernel past EOF (need 16 bytes at 0x{:x})".format(kernel_offset))
    return buf_u8[kernel_offset:end].view(np.int8).reshape(4, 4)

def read_image_i8(buf_u8: np.ndarray, img_offset: int, H: int, W: int) -> np.ndarray:
    end = img_offset + H * W
    if end > buf_u8.size:
        raise ValueError("image past EOF (need {} bytes at 0x{:x})".format(H*W, img_offset))
    return buf_u8[img_offset:end].view(np.int8).reshape(H, W)

def conv4x4_valid_i8_i8(img_i8: np.ndarray, ker_i8: np.ndarray) -> np.ndarray:
    """True 4x4 convolution, VALID, stride=1 (NumPy-old friendly)."""
    H, W = img_i8.shape
    if H < 4 or W < 4:
        raise ValueError("image must be at least 4x4")
    # Flip kernel for convolution without np.flip tuple-of-axes (compat)
    #k = ker_i8[::-1, ::-1].astype(np.int32)
    k = ker_i8.astype(np.int32)
    out_h, out_w = H - 3, W - 3
    out = np.zeros((out_h, out_w), dtype=np.int32)
    img16 = img_i8.astype(np.int32, copy=False)
    for dy in range(4):
        for dx in range(4):
            out += img16[dy:dy+out_h, dx:dx+out_w] * int(k[dy, dx])
    return out

# ---------- Integer helpers / ops ----------
def idiv_round_i32(x: np.ndarray, d: int) -> np.ndarray:
    if d <= 0: raise ValueError("divisor must be positive")
    x64 = x.astype(np.int64)
    half = d // 2
    pos = (x64 + half) // d
    neg = -(((-x64) + half) // d)
    return np.where(x64 >= 0, pos, neg).astype(np.int32)



def idiv_trunc_i32(x: np.ndarray, d: int) -> np.ndarray:
    """Integer divide by d, truncating toward zero (C-style)."""
    if d <= 0:
        raise ValueError("divisor must be positive")
    x64 = x.astype(np.int64, copy=False)
    q = x64 // d                              # floor division
    # Move floor toward zero for negatives with a remainder
    q += ((x64 < 0) & ((x64 % d) != 0)).astype(np.int32)
    return q.astype(np.int32)

def apply_activation(arr: np.ndarray, act: str, alpha: float):
    if not act or act.lower() == "none":
        return arr
    a = act.lower()
    if a == "relu":
        return np.maximum(arr, 0)
    if a in ("lrelu", "leaky", "leaky_relu", "leaky-relu"):
        return np.where(arr >= 0, arr, arr / int(4)).astype(np.int32)
    raise ValueError("unsupported --act {}".format(act))

def zero_pad(arr: np.ndarray, pad: int) -> np.ndarray:
    """Zero-pad 2D array equally on all sides by `pad`."""
    if pad <= 0:
        return arr
    H, W = arr.shape
    out = np.zeros((H + 1*pad, W + 1*pad), dtype=arr.dtype)
    out[0:H, 0:W] = arr
    return out

# ---------- truncate-toward-zero division for AVG pooling ----------
def div_ttz(a_int64: np.ndarray, b: int) -> np.ndarray:
    """Divide by positive integer b with truncation toward zero (vectorized)."""
    pos = a_int64 >= 0
    q = np.empty_like(a_int64)
    q[pos]  = a_int64[pos] / b
    q[~pos] = -((-a_int64[~pos]) / b)
    return q

def blocks2x2_grid(a: np.ndarray) -> np.ndarray:
    """
    Return a 4D view of non-overlapping 2x2 blocks.
    Shape: (N//2, N//2, 2, 2)
    Access: grid[br, bc] == a[2*br:2*br+2, 2*bc:2*bc+2]
    """
    if a.ndim != 2 or a.shape[0] != a.shape[1]:
        raise ValueError("Expected an N×N 2D array.")
    N = a.shape[0]
    if N % 2:
        raise ValueError("N must be even.")
    v = np.ascontiguousarray(a)
    return v.reshape(N//2, 2, N//2, 2).swapaxes(1, 2)

def sum_each_2x2(grid, out_dtype=None):
    """
    grid: array shaped (nb_r, nb_c, 2, 2)
    returns: (nb_r, nb_c) with the sum in each 2x2 block
    """
    grid = np.asarray(grid)
    if grid.ndim != 4 or grid.shape[-2:] != (2, 2):
        raise ValueError("Expected shape (.., 2, 2)")
    return grid.sum(axis=(-2, -1), dtype=out_dtype)


def pool_2x2_stride2_ttz_avg(arr: np.ndarray) -> np.ndarray:
    """
    2x2, stride 2 AVG with truncate-toward-zero integer division.
      1) truncate arr toward zero to integers
      2) sum 2x2 block in int64
      3) divide by 4 using div_ttz
    """
    H, W = arr.shape
    H2 = (H // 2) * 2
    W2 = (W // 2) * 2
    if H2 == 0 or W2 == 0:
        return np.trunc(arr).astype(np.int64, copy=False)
    ai = np.trunc(arr[:H2, :W2]).astype(np.int64, copy=False)
    blocks = ai.reshape(H2//2, 2, W2//2, 2)
    s = (blocks[:,0,:,0] + blocks[:,0,:,1] +
         blocks[:,1,:,0] + blocks[:,1,:,1]).astype(np.int64, copy=False)
    return div_ttz(s, 4)

def avg_pool_4x4_stride4_valid_i32(x_i32: np.ndarray) -> np.ndarray:
    H, W = x_i32.shape
    Ht = (H // 2) * 2
    Wt = (W // 2) * 2
    if Ht == 0 or Wt == 0:
        return np.zeros((0,0), dtype=np.int32)
    blocks = blocks2x2_grid(x_i32)
    sums = sum_each_2x2(blocks)
    avg = sums.astype(np.int32) / int(4) # idiv_trunc_i32(sums.astype(np.int32), 4)
    return avg.astype(np.int32)


def pool_2x2_stride2(arr: np.ndarray, mode: str):
    """
    2x2 stride-2 pooling:
      - 'avg' uses integer math with truncate-toward-zero division.
      - 'max' uses standard max.
      - 'none' returns input.
    """
    if not mode or mode.lower() == "none":
        return arr
    m = mode.lower()
    if m == "avg":
        return pool_2x2_stride2_ttz_avg(arr)
    if m == "max":
        H, W = arr.shape
        H2 = (H // 2) * 2
        W2 = (W // 2) * 2
        if H2 == 0 or W2 == 0:
            return arr
        blocks = arr[:H2, :W2].reshape(H2//2, 2, W2//2, 2)
        return blocks.max(axis=(1, 3))
    raise ValueError("unsupported --pool {}".format(mode))

# ---------- visualization & file helpers ----------
def save_png_u8(path: str, img_u8_2d: np.ndarray):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    Image.fromarray(img_u8_2d, mode="L").save(path)

def step_paths(out_png_path: str, out_dat_path: str or None, tag: str):
    root, ext = os.path.splitext(out_png_path)
    png = "{}.{}{}".format(root, tag, ext or ".png")
    dat = None
    if out_dat_path:
        rootd, extd = os.path.splitext(out_dat_path)
        dat = "{}.{}{}".format(rootd, tag, extd or ".dat")
    return png, dat

def viz_to_u8(arr_like) -> np.ndarray:
    """Visualization helper: round then clip to [0,255] for PNG display."""
    return np.clip(np.rint(arr_like), 0, 255).astype(np.uint8)

def clamp_final_to_int8(arr_like) -> np.ndarray:
    """Final-stage clamp: round then clamp to int8 [-128, 127]."""
    a = np.rint(arr_like).astype(np.int32, copy=False)
    a = np.clip(a, -128, 127).astype(np.int8, copy=False)
    return a

def write_png_clipped_int8(path: Path, arr_f: np.ndarray):
    """Clipped visualization: i8 = clip(round(arr_f), -128,127); u8 = i8 + 128."""
    i8 = np.clip(np.rint(arr_f), -128, 127).astype(np.int16)
    u8 = (i8 + 128).astype(np.uint8)
    Image.fromarray(u8, mode="L").save(path)

# =========================
# Main
# =========================
def main():
    ap = argparse.ArgumentParser(
        description="Run input→conv→act→(zero-pad)→pool on int8 image from @ADDR HEX hexdump. -o is final PNG (clamped). --emit outputs stage PNGs. DATs: input passthrough & final only. All DAT addresses start at 0x00."
    )
    ap.add_argument("input", help="hexdump text file in the form @ADDR HEX... // comment")
    ap.add_argument("-o", "--output", required=True, help="final PNG path (equals *.pool.png)")
    ap.add_argument("--out-mem", help="if set, writes final pool DAT here (hexdump). With --emit, also writes *.input.dat passthrough.")
    ap.add_argument("--emit", action="store_true",
                    help="also emit per-stage PNGs: *.input.png, *.conv.png, *.act.png, *.pool.png (DATs: only *.input.dat and final *.pool.dat)")
    ap.add_argument("--dims", required=True, type=parse_dims, help='image dims "WIDTHxHEIGHT"')
    ap.add_argument("--offset", type=parse_hex_or_int, default="0x10", help="image start offset (default 0x10)")
    ap.add_argument("--kernel", type=parse_hex_or_int, default="0x00", help="kernel start offset (default 0x00)")
    ap.add_argument("--act", default="none", help="activation: none|relu|lrelu")
    ap.add_argument("--alpha", type=float, default=0.01, help="lrelu slope")
    ap.add_argument("--pool", default="none", help="pooling: none|avg|max (2x2 stride 2)")
    ap.add_argument("--padding", type=int, default=0, help="zero padding applied to activation output before pooling")
    args = ap.parse_args()

    H, W = args.dims
    img_bytes = H * W

    # Load buffer (64-bit BE text → LE bytes in memory)
    buf_u8 = load_hexdump_u8_little(args.input)

    # Byte window for the image
    start = args.offset
    end = start + img_bytes
    if end > buf_u8.size:
        raise ValueError("image extends past EOF (need {} bytes at 0x{:x})".format(img_bytes, start))

    # ===== Step 0: INPUT (passthrough PNG; DAT optional) =====
    img_i8 = buf_u8[start:end].view(np.int8).reshape(H, W)
    if args.emit:
        p_png, p_dat = step_paths(args.output, args.out_mem, "input")
        write_png_clipped_int8(p_png, img_i8)
        if p_dat:
            # Start output addresses at 0x00
            write_hexdump_from_little(p_dat, 0x00, bytes(buf_u8[start:end]),
                                      bytes_per_line=8, comment="image (input)")

    # ===== Step 1: CONV =====
    ker_i8 = read_kernel_i8(buf_u8, args.kernel)
    final_i8 = conv_arr = conv4x4_valid_i8_i8(img_i8, ker_i8).astype(np.int32)  # safe accum
    if args.emit:
        c_png, _ = step_paths(args.output, None, "conv")
        write_png_clipped_int8(c_png,conv_arr)
        #save_png_u8(c_png, clamp_final_to_int8(conv_arr).view(np.uint8))

    if args.act != 'none':
        #print("Con")
        #print(conv_arr)
        # ===== Step 2: ACT =====
        act_arr = apply_activation(conv_arr, args.act, args.alpha)
        #print("Act")
        #print(act_arr)
        if args.emit:
            a_png, _ = step_paths(args.output, None, "act")
            write_png_clipped_int8(a_png,act_arr)
            #save_png_u8(a_png, viz_to_u8(act_arr))

        # ===== Step 2.5: ZERO PADDING (before pooling) =====
        pad = max(0, int(args.padding))
        act_arr_padded = act_arr if pad == 0 else zero_pad(act_arr, pad)

        # ===== Step 3: POOL (avg uses TTZ) =====
        #final_i8 = pool_2x2_stride2(act_arr_padded, args.pool)
        final_i8 = avg_pool_4x4_stride4_valid_i32(act_arr_padded)
        #print("Out")
        #print(final_i8)
        

    # Always write final -o PNG (equals *.pool.png)
    #save_png_u8(args.output, final_i8.view(np.uint8))
    write_png_clipped_int8(args.output,final_i8)

    # Also write *.pool.png and final DAT (addresses start at 0x00) when --emit
        # If no --emit but --out-mem was provided, write a single final DAT here (addresses start at 0x00)
    if args.out_mem:

        out_i8 = np.clip(final_i8, -128, 127).astype(np.int8)
        write_mem_addr8_from_i8(out_i8, args.out_mem, endian="little")
        #write_hexdump_from_little(args.out_mem, 0x00, final_i8.tobytes(order="C"),
        #                          bytes_per_line=8, comment="image (final, int8 clamped)")

    # Console summary
    print("=== pipeline summary ===")
    print("input          :", args.input)
    print("dims (HxW)     : {}x{}".format(H, W))
    print("image @        : 0x{:x}".format(args.offset))
    print("kernel @       : 0x{:x}".format(args.kernel))
    print("act            :", args.act)
    print("pool           :", args.pool)
    print("final PNG      :", args.output)
    if args.emit:
        print("stage PNGs     : emitted (.input/.conv/.act/.pool)")
        if args.out_mem:
            print("DATs           : input.dat (0x00-based) and pool.dat (0x00-based)")
    else:
        print("stage PNGs     : not emitted (use --emit to enable)")
        if args.out_mem:
            print("final DAT      :", args.out_mem, "(0x00-based)")

if __name__ == "__main__":
    main()


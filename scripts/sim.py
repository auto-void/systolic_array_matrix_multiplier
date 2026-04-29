#!/usr/bin/env python3
"""
统一仿真入口脚本
Usage:
    python3 scripts/sim.py sim [--size MxKxN] [--width W]
    python3 scripts/sim.py debug [--size MxKxN]
    python3 scripts/sim.py verify
    python3 scripts/sim.py sizes
"""

import argparse
import subprocess
import sys
import os

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def cmd_sim(args):
    """运行 Verilog 仿真"""
    m, k, n = parse_size(args.size)
    cmd = ["make", "-C", ROOT_DIR, "sim",
           f"M={m}", f"K={k}", f"N={n}", f"W={args.width}"]
    print(f"Running: {' '.join(cmd)}")
    return subprocess.run(cmd).returncode


def cmd_debug(args):
    """运行 Python cycle-accurate 仿真"""
    script = os.path.join(ROOT_DIR, "scripts", "debug_sim.py")
    print(f"Running Python cycle-accurate simulation...")
    return subprocess.run([sys.executable, script]).returncode


def cmd_verify(args):
    """验证 FEED_CYCLES 修复（多尺寸）"""
    script = os.path.join(ROOT_DIR, "scripts", "verify_fix.py")
    print(f"Running multi-size verification...")
    return subprocess.run([sys.executable, script]).returncode


def cmd_sizes(args):
    """列出常用矩阵尺寸组合"""
    sizes = [
        (1, 1, 1), (2, 2, 2), (3, 3, 3), (4, 4, 4),
        (2, 3, 4), (3, 5, 7), (4, 2, 4), (8, 8, 8),
    ]
    print("常用矩阵尺寸（M×K × K×N）：")
    for m, k, n in sizes:
        fc = k + m + n - 2
        print(f"  {m}×{k} × {k}×{n}  FEED_CYCLES={fc}")
    print(f"\n运行指定尺寸：python3 scripts/sim.py sim --size MxKxN")


def parse_size(size_str):
    """解析 'MxKxN' 格式"""
    parts = size_str.lower().split("x")
    if len(parts) != 3:
        print(f"Error: invalid size format '{size_str}', expected 'MxKxN'")
        sys.exit(1)
    return int(parts[0]), int(parts[1]), int(parts[2])


def main():
    parser = argparse.ArgumentParser(description="Systolic Array 仿真工具")
    subparsers = parser.add_subparsers(dest="command", help="子命令")

    # sim
    p_sim = subparsers.add_parser("sim", help="运行 Verilog 仿真")
    p_sim.add_argument("--size", default="4x4x4", help="矩阵尺寸 MxKxN (default: 4x4x4)")
    p_sim.add_argument("--width", type=int, default=8, help="数据位宽 (default: 8)")

    # debug
    p_debug = subparsers.add_parser("debug", help="运行 Python cycle-accurate 仿真")
    p_debug.add_argument("--size", default="4x4x4", help="矩阵尺寸 MxKxN")

    # verify
    subparsers.add_parser("verify", help="验证 FEED_CYCLES 修复（多尺寸）")

    # sizes
    subparsers.add_parser("sizes", help="列出常用矩阵尺寸")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    cmds = {
        "sim": cmd_sim,
        "debug": cmd_debug,
        "verify": cmd_verify,
        "sizes": cmd_sizes,
    }
    sys.exit(cmds[args.command](args))


if __name__ == "__main__":
    main()

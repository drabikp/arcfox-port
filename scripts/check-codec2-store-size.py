#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
"""Check that the built libcodec2_hidl ComponentStore still fits the stock
Codec2 services' patched allocation (512 bytes).

sm8635-common's extract-files.py raises the allocation in
vendor.qti.media.c2{,audio}@1.0-service from 264 to 512 bytes, because our
libcodec2_hidl constructs a bigger ComponentStore than the Android 14 build the
services were compiled against. If AOSP grows the class past 512 bytes again,
the constructor overruns the heap chunk and the services crash at boot.

Run from the Android top after a build:
    arcfox-port/scripts/check-codec2-store-size.py [out/target/product/arcfox]
Exit status 1 if a ComponentStore does not fit, 2 if nothing could be measured.
"""
import os
import struct
import subprocess
import sys

LIMIT = 512
# c2audio constructs V1_0, c2 constructs V1_2.
VERSIONS = (0, 2)
READELF = 'prebuilts/clang/host/linux-x86/llvm-binutils-stable/llvm-readelf'


def component_store_size(lib: str, version: int) -> int:
    sym = f'_ZTVN7android8hardware5media2c24V1_{version}5utils14ComponentStoreE'
    syms = subprocess.run([READELF, '--dyn-syms', '--wide', lib],
                          capture_output=True, text=True, check=True).stdout
    addr = next(int(l.split()[1], 16) for l in syms.splitlines() if l.split()[-1:] == [sym])
    data = open(lib, 'rb').read()
    segs = subprocess.run([READELF, '-lW', lib], capture_output=True, text=True, check=True).stdout
    for line in segs.splitlines():
        p = line.split()
        if p and p[0] == 'LOAD':
            off, va, fsz = int(p[1], 16), int(p[2], 16), int(p[4], 16)
            if va <= addr < va + fsz:
                # The vtable group starts with the virtual-base (RefBase) offset;
                # RefBase (vptr + mRefs, 16 bytes) is laid out last.
                vbase = struct.unpack('<q', data[off + addr - va:off + addr - va + 8])[0]
                return vbase + 16
    raise ValueError(f'{sym} not in a LOAD segment of {lib}')


def main() -> int:
    product = sys.argv[1] if len(sys.argv) > 1 else 'out/target/product/arcfox'
    if not os.access(READELF, os.X_OK):
        print(f'{READELF} not found; run from the Android top')
        return 2
    measured, bad = 0, 0
    for v in VERSIONS:
        lib = os.path.join(product, f'vendor/lib64/libcodec2_hidl@1.{v}.so')
        if not os.path.isfile(lib):
            print(f'{lib}: not built')
            continue
        size = component_store_size(lib, v)
        measured += 1
        ok = size <= LIMIT
        bad += not ok
        print(f'libcodec2_hidl@1.{v}: ComponentStore needs {size} bytes, '
              f'{"fits" if ok else "does NOT fit"} in {LIMIT}')
    if not measured:
        return 2
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())

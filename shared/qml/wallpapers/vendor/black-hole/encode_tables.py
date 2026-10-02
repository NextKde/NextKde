#!/usr/bin/env python3
"""Encode upstream float bits in opaque PNGs; decoded once to GPU RGBA32F.

Uses only Python's standard library. PNG RGB stores three little-endian bytes,
then the next pixel's R stores the fourth. Alpha is opaque to avoid Qt image
premultiplication. Doppler's 64 depth slices are tiled in an 8x8 atlas.
"""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parent


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


def encode(name, width, height, channels, header=False, atlas=False):
    data = (ROOT / (name + '.dat')).read_bytes()
    if header:
        file_width, file_height = struct.unpack('<2f', data[:8])
        if (int(file_width), int(file_height)) != (width, height):
            raise ValueError('unexpected table dimensions: ' + name)
        data = data[8:]
    if len(data) != width * height * channels * 4:
        raise ValueError('unexpected table size: ' + name)
    rows = []
    for y in range(height):
        row = bytearray(b'\0')
        for x in range(width):
            index = ((y // 32) * 8 + x // 64) * (64 * 32) + (y % 32) * 64 + x % 64 if atlas else y * width + x
            for channel in range(channels):
                pos = (index * channels + channel) * 4
                a, b, c, d = data[pos:pos + 4]
                row.extend((a, b, c, 255, d, 0, 0, 255))
        rows.append(bytes(row))
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>2I5B', width * channels * 2, height, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(b''.join(rows), 9))
    png += chunk(b'IEND', b'')
    (ROOT / (name + '-float.png')).write_bytes(png)


if __name__ == '__main__':
    encode('deflection', 512, 512, 2, header=True)
    encode('inverse_radius', 64, 32, 2, header=True)
    encode('black_body', 128, 1, 3)
    encode('doppler', 512, 256, 3, atlas=True)

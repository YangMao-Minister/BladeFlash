#!/usr/bin/env python3
"""生成可平铺的FBM噪声贴图"""

import numpy as np
from PIL import Image
import math
import os

# ============ 配置 ============
L = 9
SIZE = 2**L  # 贴图分辨率
OCTAVES = 4  # FBM 八度数
FREQUENCY_0 = 2 ** -(L - 5)
A_0 = 1
LACUNARITY = 2.0  # 频率倍增因子
GAIN = 0.5  # 振幅衰减因子
SEED = 42  # 随机种子
OUTPUT_NAME = "noise_tile.png"  # 输出文件名
# =============================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def hash2d(ix, iy):
    """2D 哈希函数，返回 [0, 1)"""
    x = np.int32(ix)
    y = np.int32(iy)
    h = np.bitwise_xor(x * np.int32(374761393), y * np.int32(668265263))
    h = np.bitwise_xor(h, np.int32(h >> np.int32(13)))
    h = np.uint32(h * np.int32(1274126177))
    h = np.bitwise_xor(h, np.int32(h >> np.int32(16)))
    return h.astype(np.float32) / float(0xFFFFFFFF)


def hash3d(ix, iy, iz):
    """3D 哈希函数，返回 [0, 1)"""
    x = np.int32(ix)
    y = np.int32(iy)
    z = np.int32(iz)
    h = np.bitwise_xor(x * np.int32(374761393), y * np.int32(668265263))
    h = np.bitwise_xor(h, z * np.int32(1440672677))
    h = np.bitwise_xor(h, np.int32(h >> np.int32(13)))
    h = np.uint32(h * np.int32(1274126177))
    h = np.bitwise_xor(h, np.int32(h >> np.int32(16)))
    return h.astype(np.float32) / float(0xFFFFFFFF)


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise_periodic_2d(x, y, period):
    """周期性2D值噪声，period 为平铺周期"""
    x = np.asarray(x, dtype=np.float32)
    y = np.asarray(y, dtype=np.float32)

    ix = np.floor(x).astype(np.int32)
    iy = np.floor(y).astype(np.int32)
    fx = x - ix
    fy = y - iy

    fx = smoothstep(0.0, 1.0, fx)
    fy = smoothstep(0.0, 1.0, fy)

    px = np.int32(period)
    ix0 = ix % px
    ix1 = (ix + 1) % px
    iy0 = iy % px
    iy1 = (iy + 1) % px

    v00 = hash2d(ix0, iy0)
    v10 = hash2d(ix1, iy0)
    v01 = hash2d(ix0, iy1)
    v11 = hash2d(ix1, iy1)

    nx0 = v00 + (v10 - v00) * fx
    nx1 = v01 + (v11 - v01) * fx
    return nx0 + (nx1 - nx0) * fy


def fbm_periodic_2d(x, y, period, octaves=OCTAVES, lacunarity=LACUNARITY, gain=GAIN):
    """周期性2D FBM"""
    value = np.zeros_like(x, dtype=np.float32)
    amplitude = A_0
    frequency = FREQUENCY_0
    max_value = 0.0

    for i in range(octaves):
        value += amplitude * value_noise_periodic_2d(
            x * frequency, y * frequency, period * frequency
        )
        max_value += amplitude
        amplitude *= gain
        frequency *= lacunarity

    return value / max_value


def generate_noise_texture(
    size=SIZE, octaves=OCTAVES, lacunarity=LACUNARITY, gain=GAIN
):
    """生成可平铺的噪声贴图"""
    period = size // 4  # 平铺周期

    xs = np.linspace(0, period, size, endpoint=False, dtype=np.float32)
    ys = np.linspace(0, period, size, endpoint=False, dtype=np.float32)
    xv, yv = np.meshgrid(xs, ys)

    noise = fbm_periodic_2d(xv, yv, period, octaves, lacunarity, gain)

    noise = (noise - noise.min()) / (noise.max() - noise.min() + 1e-8)
    return (noise * 255).astype(np.uint8)


def generate_noise_texture_rgba(
    size=SIZE, octaves=OCTAVES, lacunarity=LACUNARITY, gain=GAIN
):
    """生成 RGBA 四通道可平铺噪声贴图（每个通道用不同种子/偏移）"""
    period = size // 4
    xs = np.linspace(0, period, size, endpoint=False, dtype=np.float32)
    ys = np.linspace(0, period, size, endpoint=False, dtype=np.float32)
    xv, yv = np.meshgrid(xs, ys)

    channels = []
    for offset in range(4):
        ox = xv + offset * 37.0
        oy = yv + offset * 73.0
        n = fbm_periodic_2d(ox, oy, period, octaves, lacunarity, gain)
        n = (n - n.min()) / (n.max() - n.min() + 1e-8)
        channels.append((n * 255).astype(np.uint8))

    return np.stack(channels, axis=-1)


if __name__ == "__main__":
    print(f"生成 {SIZE}x{SIZE} 噪声贴图...")
    print(f"  Octaves: {OCTAVES}, Lacunarity: {LACUNARITY}, Gain: {GAIN}")

    # 生成单通道灰度图
    noise_gray = generate_noise_texture_rgba(SIZE, OCTAVES, LACUNARITY, GAIN)
    img_gray = Image.fromarray(noise_gray, mode="RGBA")

    output_path = os.path.join(SCRIPT_DIR, OUTPUT_NAME)
    img_gray.save(output_path)
    print(f"已保存: {output_path}")

    print("完成！")

#!/usr/bin/env python3
"""生成可平铺的噪声贴图，支持多种噪声类型与 FBM。

支持的噪声类型:
  value   值噪声（默认，FBM）
  perlin  柏林/梯度噪声（FBM）
  worley  Worley/细胞噪声（FBM，支持 F1 / F2 / F2-F1）
  white   白噪声（逐像素，不支持 FBM）
  blue    蓝噪声（FFT 滤波 + 直方图整形，不支持 FBM）

示例:
  python gen.py                              # 默认: 值噪声 RGBA
  python gen.py --type perlin --mode gray
  python gen.py --type worley --worley-mode f2_f1
  python gen.py --type blue --blue-iterations 12 --mode gray
"""

import argparse
import math
import os

import numpy as np
from PIL import Image

# ============ 配置 ============
L = 9
SIZE = 2**L  # 贴图分辨率
OCTAVES = 4  # FBM 八度数
FREQUENCY_0 = 2 ** -(L - 5)  # FBM 初始频率
A_0 = 1  # FBM 初始振幅
LACUNARITY = 2.0  # 频率倍增因子
GAIN = 0.5  # 振幅衰减因子
SEED = 42  # 随机种子
NOISE_TYPE = "perlin"  # value / perlin / worley / white / blue

OUTPUT_NAME = f"noise_{NOISE_TYPE}.png"  # 输出文件名
MODE = "rgba"  # gray / rgba
WORLEY_MODE = "f1"  # f1 / f2 / f2_f1
WORLEY_POINTS = 1  # Worley 每个晶格内的特征点数
BLUE_ITERATIONS = 8  # 蓝噪声滤波迭代次数
BLUE_SIGMA = 0.4  # 蓝噪声高通滤波的高斯 sigma（频率已归一化到 0~0.5）
# =============================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

FRACTAL_NOISES = ("value", "perlin", "worley")
ALL_NOISES = FRACTAL_NOISES + ("white", "blue")


def hash2d(ix, iy, seed=SEED):
    """2D 哈希函数，返回 [0, 1)"""
    x = np.int32(ix)
    y = np.int32(iy)
    # 用 int64 做标量乘法再截断，避免标量溢出告警（数组乘法本身会静默回绕）
    s = np.int32(np.int64(seed) * np.int64(1440672677))
    h = np.bitwise_xor(x * np.int32(374761393), y * np.int32(668265263))
    h = np.bitwise_xor(h, s)
    h = np.bitwise_xor(h, np.int32(h >> np.int32(13)))
    h = np.uint32(h * np.int32(1274126177))
    h = np.bitwise_xor(h, np.int32(h >> np.int32(16)))
    return h.astype(np.float32) / float(0xFFFFFFFF)


def hash3d(ix, iy, iz, seed=SEED):
    """3D 哈希函数，返回 [0, 1)"""
    x = np.int32(ix)
    y = np.int32(iy)
    z = np.int32(iz)
    s = np.int32(np.int64(seed) * np.int64(1440672677) * np.int64(1015072437))
    h = np.bitwise_xor(x * np.int32(374761393), y * np.int32(668265263))
    h = np.bitwise_xor(h, z * np.int32(1440672677))
    h = np.bitwise_xor(h, s)
    h = np.bitwise_xor(h, np.int32(h >> np.int32(13)))
    h = np.uint32(h * np.int32(1274126177))
    h = np.bitwise_xor(h, np.int32(h >> np.int32(16)))
    return h.astype(np.float32) / float(0xFFFFFFFF)


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise_periodic_2d(x, y, period, seed=SEED):
    """周期性 2D 值噪声，period 为平铺周期"""
    x = np.asarray(x, dtype=np.float32)
    y = np.asarray(y, dtype=np.float32)

    ix = np.floor(x).astype(np.int32)
    iy = np.floor(y).astype(np.int32)
    fx = smoothstep(0.0, 1.0, x - ix)
    fy = smoothstep(0.0, 1.0, y - iy)

    px = np.int32(period)
    ix0 = ix % px
    ix1 = (ix + 1) % px
    iy0 = iy % px
    iy1 = (iy + 1) % px

    v00 = hash2d(ix0, iy0, seed)
    v10 = hash2d(ix1, iy0, seed)
    v01 = hash2d(ix0, iy1, seed)
    v11 = hash2d(ix1, iy1, seed)

    nx0 = v00 + (v10 - v00) * fx
    nx1 = v01 + (v11 - v01) * fx
    return nx0 + (nx1 - nx0) * fy


def perlin_noise_periodic_2d(x, y, period, seed=SEED):
    """周期性 2D 柏林(梯度)噪声，period 为平铺周期"""
    x = np.asarray(x, dtype=np.float32)
    y = np.asarray(y, dtype=np.float32)

    ix = np.floor(x).astype(np.int32)
    iy = np.floor(y).astype(np.int32)
    fx = x - ix
    fy = y - iy
    fx_s = smoothstep(0.0, 1.0, fx)
    fy_s = smoothstep(0.0, 1.0, fy)

    px = np.int32(period)
    ix0 = ix % px
    ix1 = (ix + 1) % px
    iy0 = iy % px
    iy1 = (iy + 1) % px

    two_pi = np.float32(2.0 * math.pi)

    def gradient(cx, cy):
        angle = hash2d(cx, cy, seed) * two_pi
        return np.cos(angle), np.sin(angle)

    g00x, g00y = gradient(ix0, iy0)
    g10x, g10y = gradient(ix1, iy0)
    g01x, g01y = gradient(ix0, iy1)
    g11x, g11y = gradient(ix1, iy1)

    n00 = g00x * fx + g00y * fy
    n10 = g10x * (fx - 1.0) + g10y * fy
    n01 = g01x * fx + g01y * (fy - 1.0)
    n11 = g11x * (fx - 1.0) + g11y * (fy - 1.0)

    nx0 = n00 + (n10 - n00) * fx_s
    nx1 = n01 + (n11 - n01) * fx_s
    value = nx0 + (nx1 - nx0) * fy_s

    # 梯度点积范围约 [-√2, √2]，归一化到 [0, 1]
    return (value / np.float32(math.sqrt(2.0)) + 1.0) * 0.5


def worley_noise_periodic_2d(x, y, period, seed=SEED, mode="f1", points=1):
    """周期性 2D Worley(细胞)噪声。

    mode:   f1 = 最近特征点距离, f2 = 次近特征点距离,
            f2_f1 = 两者之差（突出细胞边缘）
    points: 每个晶格内随机特征点的数量
    """
    x = np.asarray(x, dtype=np.float32)
    y = np.asarray(y, dtype=np.float32)

    ix = np.floor(x).astype(np.int32)
    iy = np.floor(y).astype(np.int32)
    px = np.int32(period)
    period_f = np.float32(period)

    d0 = np.full_like(x, np.inf)  # 最近距离
    d1 = np.full_like(x, np.inf)  # 次近距离

    for cy_off in (-1, 0, 1):
        for cx_off in (-1, 0, 1):
            cx = (ix + cx_off) % px
            cy = (iy + cy_off) % px
            for k in range(points):
                hx = hash2d(cx, cy, seed + k * 2)
                hy = hash2d(cx, cy, seed + k * 2 + 1)
                pxf = cx.astype(np.float32) + hx
                pyf = cy.astype(np.float32) + hy

                dx = x - pxf
                dy = y - pyf
                # 周期性回绕，保证平铺
                dx = dx - period_f * np.rint(dx / period_f)
                dy = dy - period_f * np.rint(dy / period_f)

                d2 = dx * dx + dy * dy
                new_min = np.minimum(d0, d2)
                d1 = np.minimum(d1, np.maximum(d0, d2))
                d0 = new_min

    max_dist = math.sqrt(2.0) * float(period) * 0.5
    if mode == "f1":
        return (np.sqrt(d0) / max_dist).astype(np.float32)
    if mode == "f2":
        return (np.sqrt(d1) / max_dist).astype(np.float32)
    if mode == "f2_f1":
        return ((np.sqrt(d1) - np.sqrt(d0)) / max_dist).astype(np.float32)
    raise ValueError(f"未知的 Worley mode: {mode}")


def white_noise_2d(size, seed=SEED):
    """逐像素白噪声：哈希直接作用在像素坐标上，天然可平铺"""
    ix = np.arange(size, dtype=np.int32)[None, :]
    iy = np.arange(size, dtype=np.int32)[:, None]
    return hash2d(ix, iy, seed)


def generate_blue_noise(size, seed=SEED, iterations=BLUE_ITERATIONS, sigma=BLUE_SIGMA):
    """可平铺蓝噪声：FFT 高通滤波 + 直方图整形迭代。

    FFT 自带周期边界所以结果可平铺；每轮先把频谱中的低频压下去，
    再用排序法把像素直方图拉回均匀分布，反复迭代得到蓝噪声。
    """
    rng = np.random.default_rng(seed)
    field = rng.random((size, size), dtype=np.float32)

    fy, fx = np.mgrid[0:size, 0:size].astype(np.float32)
    fx = np.where(fx > size * 0.5, fx - size, fx) / size
    fy = np.where(fy > size * 0.5, fy - size, fy) / size
    freq = np.sqrt(fx * fx + fy * fy)

    # 高通滤波：抑制低频、保留高频（频率已归一化到 0~0.5）
    filter_ = 1.0 - np.exp(-(freq * freq) / (2.0 * sigma * sigma))
    filter_[0, 0] = 0.0  # 去掉直流分量

    target = np.linspace(0.0, 1.0, size * size, dtype=np.float32)
    for _ in range(iterations):
        spectrum = np.fft.fft2(field)
        spectrum *= filter_
        field = np.fft.ifft2(spectrum).real
        # 直方图整形：把像素值按排序位置映射为均匀分布
        order = np.argsort(field, axis=None)
        field.ravel()[order] = target

    field -= field.min()
    field /= field.max() + 1e-8
    return (field * 255.0).astype(np.uint8)


def fbm_periodic_2d(
    base_func,
    x,
    y,
    period,
    octaves=OCTAVES,
    lacunarity=LACUNARITY,
    gain=GAIN,
    seed=SEED,
    **base_kwargs,
):
    """周期性 2D FBM：按频率/振幅叠加多个八度的基噪声。

    base_func: 接受 (x, y, period, seed, **base_kwargs) 的周期性噪声函数
    """
    value = np.zeros_like(x, dtype=np.float32)
    amplitude = A_0
    frequency = FREQUENCY_0
    max_value = 0.0

    for i in range(octaves):
        value += amplitude * base_func(
            x * frequency,
            y * frequency,
            period * frequency,
            seed=seed + i * 997,
            **base_kwargs,
        )
        max_value += amplitude
        amplitude *= gain
        frequency *= lacunarity

    return value / max_value


def _normalize_to_uint8(n):
    n = n.astype(np.float32)
    n = (n - n.min()) / (n.max() - n.min() + 1e-8)
    return (n * 255.0).astype(np.uint8)


def generate_noise_array(
    size=SIZE,
    noise_type=NOISE_TYPE,
    octaves=OCTAVES,
    lacunarity=LACUNARITY,
    gain=GAIN,
    seed=SEED,
    mode=MODE,
    worley_mode=WORLEY_MODE,
    worley_points=WORLEY_POINTS,
    blue_iterations=BLUE_ITERATIONS,
    blue_sigma=BLUE_SIGMA,
):
    """生成噪声数组。

    mode="gray" 返回 (size, size) 单通道；
    mode="rgba" 返回 (size, size, 4)，四个通道使用不同的种子/坐标偏移。
    """
    if size % 4 != 0:
        raise ValueError(f"size 必须是 4 的倍数，当前为 {size}")

    offsets = (0, 1013, 2027, 3041)
    if mode != "rgba":
        offsets = offsets[:1]

    if noise_type == "white":
        arrays = [white_noise_2d(size, seed + offset) for offset in offsets]
    elif noise_type == "blue":
        arrays = [
            generate_blue_noise(size, seed + offset, blue_iterations, blue_sigma)
            for offset in offsets
        ]
    elif noise_type in FRACTAL_NOISES:
        base = {
            "value": value_noise_periodic_2d,
            "perlin": perlin_noise_periodic_2d,
            "worley": worley_noise_periodic_2d,
        }[noise_type]
        base_kwargs = {}
        if noise_type == "worley":
            base_kwargs = {"mode": worley_mode, "points": worley_points}

        period = size // 4
        xs = np.linspace(0.0, period, size, endpoint=False, dtype=np.float32)
        ys = np.linspace(0.0, period, size, endpoint=False, dtype=np.float32)
        xv, yv = np.meshgrid(xs, ys)

        arrays = []
        for offset in offsets:
            n = fbm_periodic_2d(
                base,
                xv + offset * 37.0,
                yv + offset * 73.0,
                period,
                octaves=octaves,
                lacunarity=lacunarity,
                gain=gain,
                seed=seed,
                **base_kwargs,
            )
            arrays.append(_normalize_to_uint8(n))
    else:
        raise ValueError(
            f"未知的噪声类型: {noise_type}（可选: {', '.join(ALL_NOISES)}）"
        )

    if mode == "rgba":
        return np.stack(arrays, axis=-1)
    return arrays[0]


def generate_noise_texture(size=SIZE, octaves=OCTAVES, lacunarity=LACUNARITY, gain=GAIN, seed=SEED):
    """兼容旧接口：单通道值噪声 FBM 贴图"""
    return generate_noise_array(
        size=size, noise_type="value", octaves=octaves,
        lacunarity=lacunarity, gain=gain, seed=seed, mode="gray",
    )


def generate_noise_texture_rgba(size=SIZE, octaves=OCTAVES, lacunarity=LACUNARITY, gain=GAIN, seed=SEED):
    """兼容旧接口：RGBA 四通道值噪声 FBM 贴图"""
    return generate_noise_array(
        size=size, noise_type="value", octaves=octaves,
        lacunarity=lacunarity, gain=gain, seed=seed, mode="rgba",
    )


def parse_args():
    parser = argparse.ArgumentParser(
        description="生成可平铺的噪声贴图（value / perlin / worley / white / blue）",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--type", choices=ALL_NOISES, default=NOISE_TYPE, help="噪声类型")
    parser.add_argument("--mode", choices=("gray", "rgba"), default=MODE, help="单通道灰度 / 四通道 RGBA")
    parser.add_argument("--size", type=int, default=SIZE, help="贴图分辨率（4 的倍数）")
    parser.add_argument("--octaves", type=int, default=OCTAVES, help="FBM 八度数（仅 value/perlin/worley）")
    parser.add_argument("--lacunarity", type=float, default=LACUNARITY, help="FBM 频率倍增因子")
    parser.add_argument("--gain", type=float, default=GAIN, help="FBM 振幅衰减因子")
    parser.add_argument("--seed", type=int, default=SEED, help="随机种子")
    parser.add_argument("--output", default=OUTPUT_NAME, help="输出文件名")
    parser.add_argument("--worley-mode", choices=("f1", "f2", "f2_f1"), default=WORLEY_MODE, help="Worley 距离模式")
    parser.add_argument("--worley-points", type=int, default=WORLEY_POINTS, help="Worley 每晶格特征点数")
    parser.add_argument("--blue-iterations", type=int, default=BLUE_ITERATIONS, help="蓝噪声迭代次数")
    parser.add_argument("--blue-sigma", type=float, default=BLUE_SIGMA, help="蓝噪声高通滤波 sigma")
    return parser.parse_args()


def main():
    args = parse_args()
    print(f"生成 {args.size}x{args.size} {args.type} 噪声贴图（{args.mode}）")
    if args.type in FRACTAL_NOISES:
        print(f"  FBM: octaves={args.octaves}, lacunarity={args.lacunarity}, gain={args.gain}")
        if args.type == "worley":
            print(f"  Worley: mode={args.worley_mode}, points={args.worley_points}")
    elif args.octaves > 1:
        print(f"  提示: {args.type} 噪声不支持 FBM，octaves/lacunarity/gain 参数将被忽略")
    print(f"  seed={args.seed}")

    array = generate_noise_array(
        size=args.size,
        noise_type=args.type,
        octaves=args.octaves,
        lacunarity=args.lacunarity,
        gain=args.gain,
        seed=args.seed,
        mode=args.mode,
        worley_mode=args.worley_mode,
        worley_points=args.worley_points,
        blue_iterations=args.blue_iterations,
        blue_sigma=args.blue_sigma,
    )

    image = Image.fromarray(array)
    output_path = os.path.join(SCRIPT_DIR, args.output)
    image.save(output_path)
    print(f"已保存: {output_path}")
    print("完成！")


if __name__ == "__main__":
    main()

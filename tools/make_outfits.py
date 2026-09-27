#!/usr/bin/env python3
"""Bakes the eSper outfits into the Universal Base Characters' UV layout.

Every texel of the body texture is mapped back to the point of the body it covers in
the rest (T-) pose by rasterizing the mesh triangles in UV space. Knowing where each
texel sits on the body (height, side, front/back, arm/leg/torso) lets us paint an
original sporty suit - side panels, piping, glowing trims, knee pads, sneakers -
while keeping the original skin painting on the face and hands. The result moves
correctly with animation because it lives in the texture.

Outputs (per style) into game/assets/characters/esper/outfits/:
  <style>_albedo.png  base colour (sRGB)
  <style>_mask.png    R = glow/emission, G = roughness, B = metallic, A = clothes
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "characters", "esper")
SRC = os.path.join(ROOT, "src")
ART = os.path.join(os.path.dirname(__file__), "..", "art", "esper")
OUT = os.path.join(ROOT, "outfits")
SIZE = 512
# Painted at 2x and downsampled: anti-aliased stripe edges.
SS = 2

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_body(path):
    g = json.load(open(path))
    blob = open(os.path.join(os.path.dirname(path), g["buffers"][0]["uri"]), "rb").read()

    def acc(i):
        a = g["accessors"][i]
        bv = g["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        dt = np.dtype(CT[a["componentType"]])
        n = NC[a["type"]]
        stride = bv.get("byteStride", 0)
        cnt = a["count"]
        if stride and stride != dt.itemsize * n:
            raw = np.frombuffer(blob, dtype=np.uint8, count=stride * cnt, offset=off).reshape(cnt, stride)
            return raw[:, : dt.itemsize * n].copy().view(dt).reshape(cnt, n)
        return np.frombuffer(blob, dtype=dt, count=cnt * n, offset=off).reshape(cnt, n)

    body = max(g["meshes"], key=lambda m: g["accessors"][m["primitives"][0]["attributes"]["POSITION"]]["count"])
    prim = body["primitives"][0]
    pos = acc(prim["attributes"]["POSITION"]).astype(np.float64)
    nrm = acc(prim["attributes"]["NORMAL"]).astype(np.float64)
    uv = acc(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    idx = acc(prim["indices"]).reshape(-1, 3).astype(np.int64)
    # Joint positions in the bind pose (inverse of the inverse bind matrices).
    skin = g["skins"][0]
    ibm = acc(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    joints = {}
    for j, node in enumerate(skin["joints"]):
        m = np.linalg.inv(ibm[j])
        joints[g["nodes"][node]["name"]] = m[:3, 3]
    return pos, nrm, uv, idx, joints


def rasterize(pos, nrm, uv, idx, size):
    """Per-texel rest-pose position and normal, plus coverage."""
    P = np.zeros((size, size, 3))
    N = np.zeros((size, size, 3))
    cov = np.zeros((size, size), bool)
    px = uv * size - 0.5
    for tri in idx:
        a, b, c = px[tri[0]], px[tri[1]], px[tri[2]]
        x0 = int(max(np.floor(min(a[0], b[0], c[0])), 0))
        x1 = int(min(np.ceil(max(a[0], b[0], c[0])), size - 1))
        y0 = int(max(np.floor(min(a[1], b[1], c[1])), 0))
        y1 = int(min(np.ceil(max(a[1], b[1], c[1])), size - 1))
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        w0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / d
        w1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / d
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
        if not inside.any():
            continue
        yy, xx = ys[inside], xs[inside]
        W = np.stack([w0[inside], w1[inside], w2[inside]], 1)
        P[yy, xx] = W @ pos[tri]
        N[yy, xx] = W @ nrm[tri]
        cov[yy, xx] = True
    # Dilate into the gutters so mip-mapping never pulls in unpainted texels.
    _, (iy, ix) = ndimage.distance_transform_edt(~cov, return_indices=True)
    P = P[iy, ix]
    N = N[iy, ix]
    N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-6)
    return P, N, cov


def band(v, lo, hi, soft=0.004):
    """1 inside [lo, hi] with soft edges."""
    return np.clip((v - lo) / soft + 0.5, 0, 1) * np.clip((hi - v) / soft + 0.5, 0, 1)


def line(v, at, width, soft=0.002):
    return band(v, at - width * 0.5, at + width * 0.5, soft)


def srgb(c):
    return np.array([int(c[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])


def clean_face(skin, P, J, size):
    """Removes the painted stubble (young, clean-shaven look) but keeps the lips."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    nose_y = 1.657
    region = band(y, J["neck_01"][1] + 0.02, nose_y - 0.012, 0.02) * (z > -0.03) * (y > J["neck_01"][1])
    ref_mask = (np.abs(y - (nose_y + 0.012)) < 0.008) & (np.abs(x) > 0.03) & (np.abs(x) < 0.055) & (z > 0.06)
    ref = np.median(skin[ref_mask], axis=0)
    blur = ndimage.gaussian_filter(skin, sigma=(size / 170.0, size / 170.0, 0))
    lifted = blur * np.clip(ref.mean() / np.maximum(blur.mean(2), 1e-3), 1.0, 1.6)[..., None]
    lifted = lifted * 0.4 + ref * 0.6
    red = skin[..., 0] - skin[..., 1]
    lip = np.clip((red - 0.215) / 0.04, 0, 1) * (np.abs(x) < 0.03) * band(y, 1.608, 1.64, 0.004) * (z > 0.07)
    lip = ndimage.gaussian_filter(lip, size / 1024.0)
    w = np.clip(region * (1 - lip), 0, 1)[..., None]
    return skin * (1 - w) + lifted * w


def bake(style, gender):
    pos, nrm, uv, idx, J = load_body(os.path.join(SRC, "Superhero_%s_FullBody.gltf" % ("Male" if gender == "m" else "Female")))
    # Paint the head first so the body wins where the (hidden) mouth interior shares UVs with it.
    order = np.argsort(-pos[idx].mean(1)[:, 1])
    res = SIZE * SS
    P, N, _ = rasterize(pos, nrm, uv, idx[order], res)
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    ax = np.abs(x)
    ankle = J["foot_l"][1]
    knee = J["calf_l"][1]
    hip = J["thigh_l"][1]
    waist = (J["spine_01"][1] + J["spine_02"][1]) * 0.5
    chest = J["spine_03"][1]
    neck = J["neck_01"][1]
    wrist = abs(J["hand_l"][0])
    elbow = abs(J["lowerarm_l"][0])
    shoulder_x = abs(J["upperarm_l"][0])
    arm_y = J["upperarm_l"][1]
    arm_z = J["upperarm_l"][2]
    leg_x = abs(J["thigh_l"][0])
    leg_z = J["calf_l"][2]
    torso_z = J["spine_02"][2]

    g = "male" if gender == "m" else "female"
    skin_src = np.asarray(Image.open(os.path.join(ART, "skin_%s_%s.png" % (g, style["skin"]))).convert("RGB"), dtype=np.float64) / 255.0
    if gender == "m":
        Pf, _, _ = rasterize(pos, nrm, uv, idx[order], skin_src.shape[0])
        skin_src = clean_face(skin_src, Pf, J, skin_src.shape[0])
    skin_src = np.asarray(Image.fromarray((np.clip(skin_src, 0, 1) * 255 + 0.5).astype(np.uint8)).resize((res, res), Image.LANCZOS), dtype=np.float64) / 255.0
    rough_src = np.asarray(Image.open(os.path.join(ART, "rough_%s.png" % g)).resize((res, res), Image.LANCZOS), dtype=np.float64) / 255.0
    if rough_src.ndim == 3:
        rough_src = rough_src[..., 0]
    lum = skin_src.mean(2)
    shade = np.clip(1.0 + 0.4 * (lum / np.median(lum) - 1.0), 0.72, 1.12)

    is_arm = (ax > shoulder_x - 0.02) & (y > hip)
    is_hand = ax > wrist - 0.01
    fingers = ax > wrist + 0.085
    is_head = (y > neck + 0.035) & ~is_arm
    is_foot = y < ankle + 0.03
    legs = (y < hip + 0.02) & ~is_foot & ~is_arm
    torso = (y >= hip + 0.02) & ~is_arm & ~is_head
    arm = is_arm & ~is_hand
    front = z > torso_z
    # Angles around the limb axes: 0 = outer side at rest (top of the arm in T-pose,
    # outside of the leg), + towards the front.
    ang_leg = np.arctan2(z - leg_z, ax - leg_x)
    ang_arm = np.arctan2(z - arm_z, y - arm_y)

    # Clothes coverage (1 = clothes, 0 = skin) with soft edges and the style's cut-outs.
    suit = np.ones_like(y)
    suit *= 1.0 - band(y, neck + 0.035, 9.0, 0.008) * ~is_arm
    suit *= 1.0 - band(ax, wrist - 0.01, 9.0, 0.006) * (1.0 if not style.get("gloves") else band(ax, wrist + 0.085, 9.0, 0.006))
    if style.get("short_sleeves"):
        suit *= 1.0 - arm * band(ax, (shoulder_x + elbow) * 0.5, 9.0, 0.006)
    if style.get("crop_top"):
        suit *= 1.0 - band(y, waist - 0.035, chest - 0.085, 0.008) * (~is_arm)
    if style.get("shorts"):
        suit *= 1.0 - band(y, knee + 0.1, hip - 0.13, 0.008) * legs
    suit = np.clip(suit, 0, 1)

    jacket = srgb(style["jacket"])
    accent = srgb(style["accent"])
    dark = srgb(style.get("dark", "#1b1f2a"))
    pants = srgb(style.get("pants", "#1d2330"))
    trim = srgb(style.get("trim", "#f2f4f8"))
    panel = srgb(style["panel"]) if "panel" in style else dark
    collar = srgb(style["collar"]) if "collar" in style else dark
    cuff = srgb(style["cuff"]) if "cuff" in style else dark
    stripe = srgb(style["stripe"]) if "stripe" in style else trim
    yoke_c = srgb(style["yoke"]) if "yoke" in style else accent
    pad_c = srgb(style["pad"]) if "pad" in style else dark
    glow_c = srgb(style["glow"])
    col = np.zeros(P.shape)
    col[:] = jacket
    rough = np.full_like(y, style.get("roughness", 0.6))
    metal = np.full_like(y, 0.0)
    glow = np.zeros_like(y)

    def paint(mask, c, m=None, r=None):
        nonlocal col
        mask = np.clip(mask, 0, 1)[..., None]
        col = col * (1 - mask) + np.asarray(c) * mask
        if r is not None:
            rough[:] = rough * (1 - mask[..., 0]) + r * mask[..., 0]
        if m is not None:
            metal[:] = metal * (1 - mask[..., 0]) + m * mask[..., 0]

    def lit(mask, strength=1.0):
        mask = np.clip(mask, 0, 1)
        paint(mask, glow_c * 0.5 + 0.5, 0.0, 0.3)
        glow[:] = np.maximum(glow, mask * strength)

    # --- Pants: two side stripes (the inner one glows), knee pads, ankle cuffs.
    paint(legs, pants, 0.0, 0.75)
    paint(legs * band(ang_leg, -0.42, -0.2, 0.03), stripe, 0.0, 0.5)
    paint(legs * band(ang_leg, 0.2, 0.42, 0.03), stripe, 0.0, 0.5)
    lit(legs * band(ang_leg, -0.07, 0.07, 0.03) * (y < hip - 0.02), 0.8)
    pad = legs * band(ang_leg, 0.75, 2.4, 0.06) * band(y, knee - 0.055, knee + 0.075, 0.006)
    paint(pad, pad_c, 0.3, 0.35)
    paint(pad * band(ang_leg, 1.15, 2.0, 0.05) * band(y, knee - 0.03, knee + 0.05, 0.006), accent, 0.2, 0.35)
    paint(legs * band(y, ankle + 0.03, ankle + 0.075, 0.005), cuff, 0.0, 0.6)
    # --- Jacket: raglan shoulder yoke, side panels, zip, collar, hem, sleeves.
    yoke_line = chest + 0.05 + (ax - 0.05) * 0.35
    yoke = torso * band(y, yoke_line, 9.0, 0.006) + arm * band(ax, 0.0, shoulder_x + 0.07, 0.008) * band(ang_arm, -0.9, 0.9, 0.08)
    paint(yoke, yoke_c, 0.0, 0.55)
    paint(torso * line(y, yoke_line, 0.012), stripe, 0.0, 0.45)
    paint(torso * band(ax, 0.118, 1.0, 0.006), panel, 0.0, 0.6)
    paint(torso * line(ax, 0.118, 0.008), trim, 0.0, 0.45)
    paint(torso * front * line(ax, 0.0, 0.012) * (y < neck) * (y > hip + 0.07), dark, 0.5, 0.35)
    paint(torso * front * line(ax, 0.0, 0.004) * (y < neck) * (y > hip + 0.07), trim, 0.8, 0.25)
    paint(band(y, neck - 0.03, neck + 0.04, 0.005) * torso, collar, 0.0, 0.55)
    lit(torso * line(y, neck - 0.03, 0.008), 0.8)
    paint(band(y, hip + 0.065, hip + 0.1, 0.004) * torso, cuff, 0.0, 0.6)
    # Belt with a bright buckle.
    belt = band(y, hip + 0.02, hip + 0.065, 0.004) * ~is_arm * ~is_head
    paint(belt, srgb(style.get("belt", "#121419")), 0.2, 0.45)
    paint(belt * front * band(ax, -1, 0.028, 0.004), trim, 0.75, 0.25)
    # Emblem on the left chest (a ring with a dot).
    ex, ey = 0.068, chest + 0.03
    rr = np.sqrt((x - ex) ** 2 + (y - ey) ** 2)
    lit(torso * front * (line(rr, 0.02, 0.008) + (rr < 0.009)), 0.9)
    # Sleeves: two stripes down the outside, dark cuffs with a glowing edge.
    paint(arm * band(ang_arm, -0.46, -0.18, 0.04) * (ax > shoulder_x + 0.06), stripe, 0.0, 0.45)
    paint(arm * band(ang_arm, 0.18, 0.46, 0.04) * (ax > shoulder_x + 0.06), stripe, 0.0, 0.45)
    paint(arm * band(ax, wrist - 0.055, wrist, 0.005), cuff, 0.0, 0.55)
    lit(arm * line(ax, wrist - 0.055, 0.008), 0.8)
    # --- Fingerless gloves.
    if style.get("gloves"):
        glove = is_hand & ~fingers
        paint(glove, srgb(style.get("glove", "#1a1d24")), 0.1, 0.5)
        paint(glove * band(ax, wrist + 0.01, wrist + 0.035, 0.004) * (y > arm_y), accent, 0.2, 0.45)
    # --- Sneakers: coloured upper, white toe cap and heel, bright sole with a glowing edge.
    shoe = is_foot.astype(float)
    paint(shoe, srgb(style.get("shoe", style["accent"])), 0.0, 0.45)
    paint(shoe * (z > J["ball_l"][2] + 0.03), trim, 0.0, 0.45)
    paint(shoe * (z < J["foot_l"][2] - 0.035) * (y > 0.03), trim, 0.0, 0.45)
    paint(shoe * band(y, -1.0, 0.03, 0.004), srgb(style.get("sole", "#f2f4f8")), 0.0, 0.6)
    lit(shoe * line(y, 0.033, 0.008), 0.9)
    # Form shading from the original painting keeps folds and anatomy readable.
    col = col * (1.0 + (shade[..., None] - 1.0) * 0.25)
    # Skin where the clothes are cut away.
    s = suit[..., None]
    out = col * s + skin_src * (1 - s)
    rough_out = rough * suit + (0.35 + 0.5 * rough_src) * (1 - suit)
    metal_out = metal * suit
    glow_out = glow * suit
    # Alpha = clothes coverage (the shader flattens the anatomy normals under clothes).
    return out, np.stack([glow_out, rough_out, metal_out, suit], 2)


STYLES = {
    # Player (blue team): white tracksuit with blue collar, cuffs and stripes, white sneakers.
    "player": dict(gender="m", skin="light", jacket="#f1f4f8", accent="#2f7df0", dark="#1b2a4a", pants="#e9edf3",
                   glow="#35e6ff", panel="#cfd9ea", collar="#2f6fe0", cuff="#2f6fe0", stripe="#2f7df0",
                   yoke="#f1f4f8", pad="#2f6fe0", gloves=True, glove="#1c2130", shoe="#f4f6fa", sole="#2f6fe0"),
    # Female variant of the player's outfit.
    "player_f": dict(gender="f", skin="light", jacket="#f1f4f8", accent="#2f7df0", dark="#1b2a4a", pants="#e9edf3",
                     glow="#35e6ff", panel="#cfd9ea", collar="#2f6fe0", cuff="#2f6fe0", stripe="#2f7df0",
                     yoke="#f1f4f8", pad="#2f6fe0", gloves=True, glove="#1c2130", shoe="#f4f6fa", sole="#2f6fe0",
                     crop_top=True),
    # Rival team strikers: black crop jacket with red, shorts, gloves.
    "striker": dict(gender="f", skin="light", jacket="#23252d", accent="#e2344b", dark="#121318", pants="#16171c",
                    glow="#ff4a5c", panel="#3a1016", gloves=True, crop_top=True, shorts=True, shoe="#2a2d36", sole="#e2344b"),
    # Gunners: charcoal jacket with orange yoke, cargo-grey pants.
    "gunner": dict(gender="m", skin="dark", jacket="#30343d", accent="#ff8a1f", dark="#16181d", pants="#3a3f38",
                   glow="#ffb347", panel="#4a2a08", gloves=True, shoe="#1e2128", sole="#ff8a1f"),
    # Brutes: black heavy jacket with magenta panels.
    "brute": dict(gender="m", skin="dark", jacket="#1b1c22", accent="#b3238f", dark="#0e0f12", pants="#16171b",
                  glow="#ff4fd8", panel="#3a0d30", gloves=True, shoe="#101114", sole="#b3238f", roughness=0.45),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, st in STYLES.items():
        alb, mask = bake(st, st["gender"])
        alb_img = Image.fromarray((np.clip(alb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
        mask_img = Image.fromarray((np.clip(mask, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
        alb_img.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, name + "_albedo.png"), optimize=True)
        mask_img.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, name + "_mask.png"), optimize=True)
        print("baked", name)


if __name__ == "__main__":
    main()

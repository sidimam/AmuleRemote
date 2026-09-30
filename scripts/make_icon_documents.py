#!/usr/bin/env python3
"""Genera i documenti Icon Composer (`Icons/*.icon`) di aMule Remote: il mulo in
Liquid Glass traslucido sopra uno sfondo colorato, uno per ogni colore app.

Xcode 26+ compila i `.icon` per iOS/iPadOS 26+, macOS 26+ e watchOS 26+ e ricava
da solo le varianti scura, trasparente (Clear) e colorata (Tinted); sui sistemi
precedenti restano gli `.appiconset` con lo stesso nome.

Uso:  python3 scripts/make_icon_documents.py
      (livello del mulo con alpha: Vision/…/AppIcon.solidimagestack/Front/…/front.png)
Anteprima: "/Applications/Icon Composer.app/Contents/Executables/ictool" Icons/AppIcon.icon \
      --export-image --output-file /tmp/a.png --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
"""
import json, os, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MULE = os.path.join(ROOT, "Vision/Assets.xcassets/AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/front.png")
OUT = os.path.join(ROOT, "Icons")

# Stessi colori di Sources/AmuleRemote/IconColor.swift (tint dei colori app).
COLORS = {
    "AppIcon":           (0.24, 0.62, 0.34),   # verde originale
    "AppIcon-blu":       (0.18, 0.44, 0.89),
    "AppIcon-rosso":     (0.84, 0.27, 0.25),
    "AppIcon-arancione": (0.91, 0.35, 0.05),
    "AppIcon-viola":     (0.49, 0.30, 0.88),
    "AppIcon-teal":      (0.05, 0.64, 0.65),
    "AppIcon-grafite":   (0.35, 0.40, 0.45),
}

def document(rgb):
    r, g, b = rgb
    return {
        "design-generation": 26,
        "fill": {"automatic-gradient": f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"},
        "groups": [{
            "layers": [{
                "image-name": "mule.png",
                "name": "mulo",
                "glass": True,
                "position": {"scale": 0.9, "translation-in-points": [0, 0]},
            }],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.6},
            "specular": True,
            "blend-mode": "normal",
            "lighting": "individual",
        }],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }

os.makedirs(OUT, exist_ok=True)
for name, rgb in COLORS.items():
    d = os.path.join(OUT, name + ".icon")
    os.makedirs(os.path.join(d, "Assets"), exist_ok=True)
    shutil.copy(MULE, os.path.join(d, "Assets", "mule.png"))
    with open(os.path.join(d, "icon.json"), "w") as f:
        json.dump(document(rgb), f, indent=2)
        f.write("\n")
    print("scritto", d)

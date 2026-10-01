#!/usr/bin/env python3
"""Renders the SRLE Studio logo (assets/branding/logo.svg) and writes every
platform icon from it, plus the README wordmarks.

    python3 tool/branding/make_icons.py [path/to/chromium]

Needs Pillow and a Chromium (the SVG is rasterised by a headless browser).
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
BRAND = os.path.join(ROOT, 'assets', 'branding')


def shoot(chrome, html, size, out):
    subprocess.run([chrome, '--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
                    '--default-background-color=00000000', f'--window-size={size[0]},{size[1]}',
                    f'--screenshot={out}', 'file://' + html], check=True, capture_output=True)
    return Image.open(out).convert('RGBA')


def page(svg_path):
    with open(svg_path) as f:
        svg = f.read()
    fd, path = tempfile.mkstemp(suffix='.html', dir=BRAND)
    with os.fdopen(fd, 'w') as f:
        f.write(f'<html><body style="margin:0;background:transparent">{svg}</body></html>')
    return path


def main():
    chrome = sys.argv[1] if len(sys.argv) > 1 else (glob.glob('/opt/pw-browsers/chromium-*/chrome-linux/chrome') or ['chromium'])[0]
    tmp = tempfile.mkdtemp()
    pages = [page(os.path.join(BRAND, 'logo.svg')), page(os.path.join(BRAND, 'logo_square.svg'))]
    try:
        tile = shoot(chrome, pages[0], (1024, 1200), os.path.join(tmp, 'a.png')).crop((0, 0, 1024, 1024))
        square = shoot(chrome, pages[1], (1024, 1200), os.path.join(tmp, 'b.png')).crop((0, 0, 1024, 1024)).convert('RGB')
    finally:
        for p in pages:
            os.remove(p)
    tile.save(os.path.join(BRAND, 'logo_1024.png'), optimize=True)

    def save(img, n, rel):
        img.resize((n, n), Image.LANCZOS).save(os.path.join(ROOT, rel), optimize=True)

    save(tile, 256, 'assets/branding/logo_256.png')
    # macOS: the tile on Apple's icon grid (824 px inside 1024).
    mac = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    small = tile.resize((824, 824), Image.LANCZOS)
    mac.paste(small, (100, 100), small)
    for n in [16, 32, 64, 128, 256, 512, 1024]:
        save(mac, n, f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{n}.png')
    tile.save(os.path.join(ROOT, 'windows/runner/resources/app_icon.ico'),
              sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    save(tile, 192, 'web/icons/Icon-192.png')
    save(tile, 512, 'web/icons/Icon-512.png')
    save(square, 192, 'web/icons/Icon-maskable-192.png')
    save(square, 512, 'web/icons/Icon-maskable-512.png')
    save(tile, 32, 'web/favicon.png')
    for d, n in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        save(tile, n, f'android/app/src/main/res/mipmap-{d}/ic_launcher.png')
    for f in glob.glob(os.path.join(ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png')):
        m = re.search(r'Icon-App-([\d.]+)x[\d.]+@(\d)x', f)
        n = round(float(m.group(1)) * int(m.group(2)))
        square.resize((n, n), Image.LANCZOS).save(f, optimize=True)
    for name in ['wordmark', 'wordmark_light']:
        img = shoot(chrome, os.path.join(BRAND, f'{name}.html'), (1400, 480), os.path.join(tmp, f'{name}.png'))
        b = img.getbbox()
        out = 'wordmark_dark.png' if name == 'wordmark' else 'wordmark_light.png'
        img.crop((max(0, b[0] - 20), max(0, b[1] - 20), min(img.width, b[2] + 20), min(img.height, b[3] + 20))).save(
            os.path.join(BRAND, out))
    print('icons written')


if __name__ == '__main__':
    main()

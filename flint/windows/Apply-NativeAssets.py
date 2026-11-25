"""Install Flint's artwork and WebUI inputs into the pinned Chromium tree."""

import argparse
import shutil
from pathlib import Path


def apply_assets(source):
    assets = Path(__file__).resolve().parents[1] / 'native'
    theme = source / 'chrome/app/theme'
    brand = theme / 'chromium'
    new_tab = source / 'chrome/browser/resources/new_tab_page_third_party'
    if not (new_tab / 'BUILD.gn').is_file() or not (brand / 'BRANDING').is_file():
        raise ValueError(f'Expected a Chromium source tree in {source}')

    # These are the icon inputs referenced by chrome_exe.rc and chrome_dll.rc.
    images = {'flint.ico': [brand / 'win/chromium.ico', brand / 'win/app_list.ico'],
              'mark.svg': [brand / 'product_logo.svg', brand / 'product_logo_animation.svg'],
              'tile-600.png': [brand / 'win/tiles/Logo.png'],
              'tile-176.png': [brand / 'win/tiles/SmallLogo.png']}
    for size in (16, 24, 48, 64, 128, 256):
        images[f'mark-{size}.png'] = [brand / f'product_logo_{size}.png']
    images['mark-22.png'] = [brand / 'product_logo_22_mono.png']
    for scale in (1, 2):
        scaled = theme / f'default_{scale}00_percent/chromium'
        for size in (16, 32):
            images.setdefault(f'mark-{size * scale}.png', []).append(scaled / f'product_logo_{size}.png')
        for suffix in ('', '_white'):
            name = f'wordmark-{scale}x{suffix.replace("_", "-")}.png'
            images[name] = [scaled / f'product_logo_name_22{suffix}.png']

    for name, destinations in images.items():
        for target in destinations:
            if not target.is_file():
                raise FileNotFoundError(f'Chromium logo input moved: {target}')
            shutil.copyfile(assets / 'brand' / name, target)

    for item in (assets / 'newtab').iterdir():
        if item.is_file():
            shutil.copyfile(item, new_tab / item.name)
    shutil.copyfile(Path(__file__).with_name('initial_preferences'), source / 'chrome/app/flint_initial_preferences')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    apply_assets(parser.parse_args().source)

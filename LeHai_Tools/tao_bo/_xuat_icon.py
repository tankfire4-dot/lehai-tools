# Đồ DEV (tên có `_` nên release.py không phát xuống máy thợ). Xuất icon Tạo Bo PNG nền trong suốt từ _icon_{24,16}.svg
# bằng Chromium (máy không có PIL): python _xuat_icon.py  → ghi đè icons/tao_bo_24.png / icons/tao_bo_16.png.
# Màu theo bộ icon LeHai: mực 124,45,18 · nền 8% · cam 180,83,9; bản 16px vẽ riêng cho khỏi nhoè.
import pathlib
from playwright.sync_api import sync_playwright
here = pathlib.Path(__file__).parent
with sync_playwright() as pw:
    b = pw.chromium.launch()
    for n in (24, 16):
        pg = b.new_page(viewport={'width': n, 'height': n}, device_scale_factor=1)
        pg.set_content('<html><body style="margin:0;background:transparent">' + (here / f'_icon_{n}.svg').read_text(encoding='utf-8') + '</body></html>')
        pg.locator('svg').screenshot(path=str(here / 'icons' / f'tao_bo_{n}.png'), omit_background=True)
    b.close()
print('ok')

# -*- coding: utf-8 -*-
"""
release.py — phát hành LeHai Tools bằng 1 lệnh. Thay quy trình tay (LUAT_NHA mục 7).

Vì sao tồn tại: quy trình tay đã dính 3 loại sẹo — (1) PowerShell ghi file chèn
BOM làm chết auto-update, (2) QUÊN thêm file mới vào version.json → máy thợ
"cập nhật một phần", (3) heredoc PowerShell nuốt ngoặc kép làm hỏng commit.
Script này giết cả 3: ghi UTF-8 không BOM, TỰ QUÉT thư mục sinh ruby_files
(kèm báo diff thêm/bớt để mắt người soát), commit qua file message.

Cách dùng (chạy từ thư mục lehai-tools):
    python release.py 1.9.31 -m "mo ta ngan thay doi"
    python release.py 1.9.31 -m "..." --no-push   # chỉ build + commit, không push
    python release.py 1.9.31 -m "..." --dry-run   # xem trước, KHÔNG ghi gì
    python release.py 1.9.31 -m "..." --yes       # bỏ bước hỏi xác nhận (cho AI/CI)

Script KHÔNG nằm trong ruby_files → không bao giờ bị tải xuống máy thợ.
"""
import argparse
import io
import json
import os
import re
import subprocess
import sys
import zipfile

sys.stdout.reconfigure(encoding='utf-8')  # in tiếng Việt trên console Windows

ROOT       = os.path.dirname(os.path.abspath(__file__))
MAIN_RB    = os.path.join(ROOT, 'LeHai_Tools.rb')
PLUGIN_DIR = os.path.join(ROOT, 'LeHai_Tools')
VERSION_JS = os.path.join(ROOT, 'version.json')

# File không bao giờ được ship xuống máy thợ.
# Quy ước: file bắt đầu bằng "_" = đồ nội bộ/dev (vd _installed_version,
# _theme_preview.html) — không ship.
EXCLUDE_NAMES = {'Thumbs.db', '.DS_Store', 'desktop.ini'}
EXCLUDE_EXTS  = {'.pyc', '.rbz', '.zip', '.tmp', '.bak'}


def die(msg):
    print(f'✗ LỖI: {msg}')
    sys.exit(1)


def run(cmd, **kw):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                       encoding='utf-8', errors='replace', **kw)
    if r.returncode != 0:
        die(f'lệnh {" ".join(cmd)} thất bại:\n{r.stdout}\n{r.stderr}')
    return r.stdout.strip()


def scan_ruby_files():
    """Quét repo sinh danh sách ruby_files: LeHai_Tools.rb + mọi file trong LeHai_Tools/."""
    files = ['LeHai_Tools.rb']
    for dirpath, dirnames, filenames in os.walk(PLUGIN_DIR):
        dirnames[:] = [d for d in dirnames if not d.startswith('.') and d != '__pycache__']
        for fn in sorted(filenames):
            if fn.startswith('_') or fn in EXCLUDE_NAMES \
               or os.path.splitext(fn)[1].lower() in EXCLUDE_EXTS:
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace('\\', '/')
            files.append(rel)
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('version', help='version mới, vd 1.9.31')
    ap.add_argument('-m', '--message', required=True, help='mô tả ngắn cho commit')
    ap.add_argument('--no-push', action='store_true', help='không git push')
    ap.add_argument('--dry-run', action='store_true', help='chỉ xem trước, không ghi/không commit')
    ap.add_argument('--yes', action='store_true', help='bỏ bước hỏi xác nhận diff')
    a = ap.parse_args()

    if not re.fullmatch(r'\d+\.\d+\.\d+', a.version):
        die(f'version "{a.version}" sai dạng x.y.z')

    # ── 1. Đọc trạng thái hiện tại ──
    with io.open(MAIN_RB, 'r', encoding='utf-8') as f:
        main_src = f.read()
    m = re.search(r"ext\.version\s*=\s*'([\d.]+)'", main_src)
    if not m:
        die('không tìm thấy ext.version trong LeHai_Tools.rb')
    old_ver = m.group(1)

    with io.open(VERSION_JS, 'r', encoding='utf-8-sig') as f:  # -sig: tự lột BOM nếu lỡ có
        old_json = json.load(f)
    old_files = old_json.get('ruby_files', [])

    def ver_tuple(v):
        return tuple(int(x) for x in v.split('.'))
    if ver_tuple(a.version) <= ver_tuple(old_ver):
        die(f'version mới {a.version} phải LỚN hơn bản hiện tại {old_ver} '
            f'(updater máy thợ chỉ nhận version tăng)')

    # ── 2. Quét file + báo diff ──
    new_files = scan_ruby_files()
    added   = sorted(set(new_files) - set(old_files))
    removed = sorted(set(old_files) - set(new_files))

    print(f'Phát hành: v{old_ver}  →  v{a.version}')
    print(f'Số file ship: {len(old_files)} → {len(new_files)}')
    if added:
        print('  + THÊM MỚI (máy thợ sẽ tải):')
        for x in added:
            print(f'      + {x}')
    if removed:
        print('  - BỎ (chú ý: updater KHÔNG tự xóa file cũ trên máy thợ):')
        for x in removed:
            print(f'      - {x}')
    if not added and not removed:
        print('  (danh sách file không đổi)')

    if a.dry_run:
        print('\n[dry-run] Dừng ở đây, chưa ghi gì.')
        return

    if not a.yes:
        ans = input('\nTiếp tục? (y/n) ').strip().lower()
        if ans != 'y':
            print('Hủy.')
            return

    # ── 3. Ghi version vào 2 file (UTF-8 KHÔNG BOM) ──
    main_src = main_src.replace(f"ext.version     = '{old_ver}'",
                                f"ext.version     = '{a.version}'")
    with io.open(MAIN_RB, 'w', encoding='utf-8', newline='') as f:
        f.write(main_src)

    payload = {'version': a.version, 'ruby_files': new_files}
    with io.open(VERSION_JS, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write('\n')

    # ── 4. Kiểm BOM (an toàn 2 lớp) ──
    with open(VERSION_JS, 'rb') as f:
        b0 = f.read(1)
    if b0 != b'{':
        die(f'version.json byte đầu = {b0!r}, dính BOM! Đã dừng — kiểm lại.')
    print('✓ version.json sạch BOM (byte đầu 7B)')

    # ── 5. Build .rbz (xóa bản cũ) ──
    for fn in os.listdir(ROOT):
        if fn.endswith('.rbz'):
            os.remove(os.path.join(ROOT, fn))
    rbz = os.path.join(ROOT, f'LeHai_Tools-{a.version}.rbz')
    with zipfile.ZipFile(rbz, 'w', zipfile.ZIP_DEFLATED) as z:
        for rel in new_files:
            z.write(os.path.join(ROOT, rel), rel)
    print(f'✓ Build {os.path.basename(rbz)} ({os.path.getsize(rbz):,} bytes)')

    # ── 6. Git commit (message qua file — né lỗi PowerShell nuốt ngoặc) ──
    # File nháp để NGOÀI repo, không thì `git add -A` vơ luôn nó vào commit.
    import tempfile
    msg_file = os.path.join(tempfile.gettempdir(), 'lehai_release_msg.tmp')
    body = (f'v{a.version}: {a.message}\n\n'
            'Co-Authored-By: Claude <noreply@anthropic.com>\n')
    with io.open(msg_file, 'w', encoding='utf-8') as f:
        f.write(body)
    try:
        run(['git', 'add', '-A'])
        run(['git', 'commit', '-F', msg_file])
    finally:
        os.remove(msg_file)
    print(f'✓ Commit v{a.version}')

    # ── 7. Push ──
    if a.no_push:
        print('… BỎ QUA push (--no-push). Nhớ tự push để máy thợ nhận update.')
    else:
        run(['git', 'push', 'origin', 'master'])
        print('✓ Push GitHub — máy thợ sẽ tự update khi mở SketchUp.')

    print(f'\n★ Xong v{a.version}.')


if __name__ == '__main__':
    main()

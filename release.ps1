# release.ps1 — [LỖI THỜI, KHÔNG DÙNG] — xem CLAUDE.md mục "Phát hành version mới"
#
# Script này đã hỏng 3 tầng và bị thay bằng quy trình tay (LUAT_NHA.md mục 7):
#   1. Trỏ $src = Desktop\lehai_tools — thư mục KHÔNG tồn tại (repo thật ở claude_work\lehai-tools)
#   2. Cập nhật plugins.json / congty_loader — KHÔNG tồn tại (update thật qua version.json)
#   3. Ghi file bằng Set-Content -Encoding UTF8 — chèn BOM → làm hỏng auto-update (xem NHAT_KY.md)
# Giữ lại để tham khảo. Nếu cần tự động hóa lại thì viết script mới sạch.

param(
    [Parameter(Mandatory=$true)]
    [string]$Version
)

Write-Host "release.ps1 da LOI THOI, khong dung. Phat hanh bang tay theo LUAT_NHA.md muc 7." -ForegroundColor Yellow
exit 1

$src      = "C:\Users\tankf\Desktop\lehai_tools"
$manifest = "C:\Users\tankf\Desktop\congty_loader\plugins.json"
$rbzName  = "LeHai_Tools-$Version.rbz"

# 1. Xóa các .rbz cũ
Remove-Item "$src\LeHai_Tools-*.rbz" -Force -ErrorAction SilentlyContinue
Remove-Item "$src\LeHai_Tools-*.zip" -Force -ErrorAction SilentlyContinue

# 2. Cập nhật version trong LeHai_Tools.rb
$loader = Get-Content "$src\LeHai_Tools.rb" -Raw -Encoding UTF8
$loader = $loader -replace "ext\.version\s*=\s*'[^']*'", "ext.version     = '$Version'"
Set-Content "$src\LeHai_Tools.rb" -Value $loader -Encoding UTF8 -NoNewline

# 3. Build .rbz mới
Compress-Archive -Path "$src\LeHai_Tools.rb", "$src\LeHai_Tools" `
                 -DestinationPath "$src\LeHai_Tools-$Version.zip" -Force
Rename-Item "$src\LeHai_Tools-$Version.zip" $rbzName

# 4. Cập nhật plugins.json
$rawJson    = Get-Content $manifest -Raw -Encoding UTF8
$json       = $rawJson | ConvertFrom-Json
$plugin     = $json.plugins | Where-Object { $_.id -eq 'LeHai_Tools' }
if ($plugin) {
    $plugin.version = $Version
    $plugin.url     = "https://raw.githubusercontent.com/tankfire4-dot/lehai-tools/master/$rbzName"
} else {
    Write-Error "Không tìm thấy entry 'LeHai_Tools' trong plugins.json!"
    exit 1
}
$json | ConvertTo-Json -Depth 10 | Set-Content $manifest -Encoding UTF8

# 5. Commit + push lehai-tools
Set-Location $src
git add .
git commit -m "Release v$Version"
git push

# 6. Commit + push sketchup-plugins (manifest)
Set-Location (Split-Path $manifest -Parent)
git add plugins.json
git commit -m "Update manifest: LeHai_Tools v$Version"
git push

Write-Host ""
Write-Host "Done! Da phat hanh LeHai_Tools v$Version"
Write-Host "RBZ: $rbzName"
Write-Host "URL: https://raw.githubusercontent.com/tankfire4-dot/lehai-tools/master/$rbzName"

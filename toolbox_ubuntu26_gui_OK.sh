#!/bin/bash

# ══════════════════════════════════════════════════════════
# جعبه‌ابزار لینوکس - نسخه 3.10 با اصلاح حذف NetMon و گزارش عملیات
# تمام برنامه‌ها در همین یک فایل مدیریت می‌شوند
# ══════════════════════════════════════════════════════════

declare -a PROGRAM_IDS=("system_update" "netmon" "persian_keyboard" "persian_fonts" "useful_apps")
declare -A PROGRAM_NAMES=(
    ["system_update"]="بروزرسانی کامل سیستم"
    ["netmon"]="نمایشگر سرعت اینترنت"
    ["persian_keyboard"]="کیبورد استاندارد فارسی"
    ["persian_fonts"]="فونت‌های فارسی (وزیر، B، و...)"
    ["useful_apps"]="نرم‌افزارهای کاربردی"
)
declare -A PROGRAM_VERSIONS=(
    ["system_update"]="1.0.0"
    ["netmon"]="1.3.2"
    ["persian_keyboard"]="1.0.0"
    ["persian_fonts"]="1.0.0"
    ["useful_apps"]="1.0.0"
)
declare -A PROGRAM_DESCRIPTIONS=(
    ["system_update"]="اجرای مستقیم apt update و apt upgrade برای تازه نگه داشتن سیستم"
    ["netmon"]="نمایش زنده سرعت ارسال و دریافت در سیستم‌تری"
    ["persian_keyboard"]="نصب کیبورد استاندارد فارسی با سوئیچ Alt+Shift"
    ["persian_fonts"]="نصب کامل فونت‌های فارسی شامل وزیر، سری B، و فونت‌های محبوب"
    ["useful_apps"]="نصب برنامه‌ها و تنظیم مخازن ایرانی Ubuntu"
)

# ──────────────────────────────────────────────────────────
# توابع مربوط به بروزرسانی سیستم
# ──────────────────────────────────────────────────────────

system_update_status() {
    echo "installed"
}

system_update_install() {
    echo ""
    echo "این گزینه یک عملیات سیستمی است."
    echo "لطفاً از منوی داخلی، گزینه‌ی 1 (بروزرسانی) را انتخاب کنید."
    echo ""
}

system_update_update() {
    echo ""
    echo "در حال بروزرسانی کامل سیستم..."
    echo "─────────────────────────────────────"
    echo "  این مرحله ممکن است بسته به سرعت اینترنت و حجم آپدیت‌ها"
    echo "  چند دقیقه زمان ببرد. لطفاً صبر کنید..."
    echo ""
    
    sudo -A apt update && sudo -A apt upgrade -y
    
    echo ""
    echo "✅ عملیات بروزرسانی سیستم با موفقیت به پایان رسید."
    echo ""
}

system_update_uninstall() {
    echo ""
    echo "این گزینه یک ابزار سیستمی است و قابل حذف نیست."
    echo ""
}

# ──────────────────────────────────────────────────────────
# توابع مربوط به NetMon
# ──────────────────────────────────────────────────────────

netmon_status() {
    # dpkg -l also lists purged (rc) packages; count only fully installed state.
    if dpkg-query -W -f='${Status}' netmon-speed 2>/dev/null | grep -qx 'install ok installed'; then
        echo "installed"
    else
        echo "not_installed"
    fi
}

netmon_install() {
    echo ""
    echo "در حال نصب نمایشگر سرعت اینترنت..."
    echo "─────────────────────────────────────"
    
    local tmp_dir=$(mktemp -d)
    local deb_dir="$tmp_dir/netmon-deb"
    
    mkdir -p "$deb_dir/DEBIAN"
    mkdir -p "$deb_dir/usr/local/bin"
    mkdir -p "$deb_dir/usr/share/applications"
    mkdir -p "$deb_dir/etc/xdg/autostart"
    
    cat << 'EOF' > "$deb_dir/DEBIAN/control"
Package: netmon-speed
Version: 1.3.2
Architecture: amd64
Maintainer: Iraj <iraj@localhost>
Description: نمایشگر سرعت اینترنت با ترازبندی بهینه
Depends: python3, python3-pystray, python3-pil, fonts-dejavu-core
EOF
    
    cat << 'PYEOF' > "$deb_dir/usr/local/bin/netmon.py"
#!/usr/bin/env python3
import time, threading
import pystray
from PIL import Image, ImageDraw, ImageFont
import os

def get_net_stats():
    rx, tx = 0, 0
    try:
        with open('/proc/net/dev', 'r') as f:
            for line in f.readlines()[2:]:
                if ':' in line:
                    stats = line.split(':')[1].split()
                    rx += int(stats[0])
                    tx += int(stats[8])
    except Exception:
        pass
    return rx, tx

def format_speed(kbps):
    if kbps >= 1024:
        return f"{kbps / 1024:.1f} MB"
    return f"{kbps:.0f} KB"

def get_font(size):
    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf"
    ]
    for path in font_paths:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except:
                continue
    return ImageFont.load_default()

def update_loop(icon):
    last_rx, last_tx = get_net_stats()
    font = get_font(16)
    padding = 2

    while True:
        time.sleep(1)
        curr_rx, curr_tx = get_net_stats()
        speed_rx_kbps = (curr_rx - last_rx) / 1024
        speed_tx_kbps = (curr_tx - last_tx) / 1024
        last_rx, last_tx = curr_rx, curr_tx
        
        rx_str = format_speed(speed_rx_kbps)
        tx_str = format_speed(speed_tx_kbps)
        text = f"\u2191 {tx_str}  \u2193 {rx_str}"
        
        temp_img = Image.new('RGB', (1, 1))
        bbox = ImageDraw.Draw(temp_img).textbbox((0, 0), text, font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
        
        img_w = text_width + (padding * 2)
        img_h = text_height + (padding * 2)
        img = Image.new('RGB', (img_w, img_h), color=(25, 25, 25))
        draw = ImageDraw.Draw(img)
        draw.text((padding, padding - 2), text, fill=(0, 255, 120), font=font)
        icon.icon = img

def main():
    init_img = Image.new('RGB', (40, 24), color=(25, 25, 25))
    icon = pystray.Icon("netmon", init_img, "مانیتور شبکه‌ی ایرج")
    threading.Thread(target=update_loop, args=(icon,), daemon=True).start()
    icon.run()

if __name__ == "__main__":
    main()
PYEOF
    
    chmod +x "$deb_dir/usr/local/bin/netmon.py"
    
    cat << 'EOF' > "$deb_dir/usr/share/applications/netmon.desktop"
[Desktop Entry]
Name=NetMon Speed
Comment=نمایش سرعت اینترنت
Exec=python3 /usr/local/bin/netmon.py
Icon=network-workgroup
Terminal=false
Type=Application
Categories=Network;Monitor;
EOF
    
    cat << 'EOF' > "$deb_dir/etc/xdg/autostart/netmon.desktop"
[Desktop Entry]
Name=NetMon Speed
Exec=python3 /usr/local/bin/netmon.py
Terminal=false
Type=Application
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    
    dpkg-deb --build "$deb_dir" "$tmp_dir/netmon-speed_1.3.2_amd64.deb" 2>/dev/null
    sudo -A dpkg -i "$tmp_dir/netmon-speed_1.3.2_amd64.deb" 2>/dev/null
    sudo -A apt-get install -f -y 2>/dev/null
    
    echo ""
    echo "✓ نصب با موفقیت انجام شد!"
    
    echo "✓ در حال اجرای برنامه..."
    pkill -f netmon.py 2>/dev/null
    sleep 0.5
    nohup python3 /usr/local/bin/netmon.py > /dev/null 2>&1 &
    
    rm -rf "$tmp_dir"
    
    echo ""
    echo "✅ برنامه با موفقیت نصب و اجرا شد!"
    echo "   آیکون در سیستم‌تری ظاهر می‌شود."
    echo ""
}

netmon_uninstall() {
    echo ""
    echo "در حال حذف کامل نمایشگر سرعت اینترنت (NetMon)..."

    if ! dpkg-query -W -f='${Status}' netmon-speed 2>/dev/null | grep -qx 'install ok installed'; then
        echo "بستهٔ netmon-speed در وضعیت نصب‌شده نیست؛ بررسی فایل‌های متعلق به برنامه..."
    fi

    # Stop the generated XDG-autostart unit if systemd has registered it.
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user stop 'app-netmon@autostart.service' 2>/dev/null || true
    fi

    # Stop only the exact NetMon script, never a broad python process pattern.
    if pgrep -f '[/]usr/local/bin/netmon.py' >/dev/null 2>&1; then
        echo "متوقف‌کردن فرایند NetMon..."
        pkill -TERM -f '[/]usr/local/bin/netmon.py' 2>/dev/null || true
        for _ in {1..5}; do
            pgrep -f '[/]usr/local/bin/netmon.py' >/dev/null 2>&1 || break
            sleep 1
        done
        if pgrep -f '[/]usr/local/bin/netmon.py' >/dev/null 2>&1; then
            echo "فرایند با SIGTERM متوقف نشد؛ ارسال SIGKILL فقط به اسکریپت NetMon..."
            pkill -KILL -f '[/]usr/local/bin/netmon.py' 2>/dev/null || true
        fi
    else
        echo "فرایند در حال اجرای NetMon پیدا نشد."
    fi

    if dpkg-query -W -f='${Status}' netmon-speed 2>/dev/null | grep -qx 'install ok installed'; then
        echo "حذف بسته و فایل‌های پیکربندی ثبت‌شده توسط dpkg (بدون autoremove)..."
        sudo -A apt-get purge -y --no-auto-remove netmon-speed || {
            echo "خطا: apt نتوانست netmon-speed را حذف کند. خروجی بالا را بررسی کن."
            return 1
        }
    else
        echo "بسته نصب نیست؛ از حذف بسته‌ای صرف‌نظر شد."
    fi

    if dpkg-query -W -f='${Status}' netmon-speed 2>/dev/null | grep -qx 'install ok installed'; then
        echo "خطا: بسته پس از عملیات هنوز نصب‌شده گزارش می‌شود."
        return 1
    fi

    # These are the exact files shipped by this toolbox's NetMon package.
    # Remove leftovers only after dpkg confirms the package is no longer installed.
    local f leftovers=0
    for f in /usr/local/bin/netmon.py /etc/xdg/autostart/netmon.desktop /usr/share/applications/netmon.desktop; do
        if [ -e "$f" ]; then
            echo "فایل باقی‌مانده از NetMon پیدا شد: $f"
            if sudo -A rm -f -- "$f"; then
                echo "حذف شد: $f"
            else
                echo "خطا در حذف فایل باقی‌مانده: $f"
                leftovers=1
            fi
        fi
    done
    if [ "$leftovers" -ne 0 ]; then
        echo "خطا: حذف بعضی فایل‌های باقی‌مانده کامل نشد."
        return 1
    fi

    echo "تأیید نهایی: بستهٔ netmon-speed دیگر نصب نیست."
    echo "حذف NetMon کامل شد؛ وابستگی‌های مشترک و بسته‌های دیگر دست‌نخورده ماندند."
    echo ""
}

netmon_update() {
    echo ""
    echo "بررسی بروزرسانی..."
    echo "  نسخه فعلی: 1.3.2"
    echo "  آخرین نسخه: 1.3.2"
    echo ""
    echo "✓ شما از آخرین نسخه استفاده می‌کنید."
    echo ""
}

# ──────────────────────────────────────────────────────────
# نرم‌افزارهای کاربردی (Ubuntu 24/26)
# ──────────────────────────────────────────────────────────

useful_apps_status() {
    echo "installed"
}

app_is_installed() {
    case "$1" in
        remmina) command -v remmina >/dev/null 2>&1 || dpkg-query -W -f='${Status}' remmina 2>/dev/null | grep -q 'install ok installed' ;;
        vscode) dpkg-query -W -f='${Status}' code 2>/dev/null | grep -q 'install ok installed' || command -v code >/dev/null 2>&1 ;;
        chrome) dpkg-query -W -f='${Status}' google-chrome-stable 2>/dev/null | grep -q 'install ok installed' || command -v google-chrome >/dev/null 2>&1 ;;
        windscribe) dpkg-query -W -f='${Status}' windscribe 2>/dev/null | grep -q 'install ok installed' || command -v windscribe-cli >/dev/null 2>&1 || command -v windscribe >/dev/null 2>&1 ;;
        git) command -v git >/dev/null 2>&1 ;;
        npm) command -v npm >/dev/null 2>&1 ;;
        python) command -v python3 >/dev/null 2>&1 && command -v python3-venv >/dev/null 2>&1 || dpkg-query -W -f='${Status}' python3-venv 2>/dev/null | grep -q 'install ok installed' ;;
        *) return 1 ;;
    esac
}

useful_apps_install_one() {
    local app="$1" arch deb_url tmp_deb
    arch=$(dpkg --print-architecture 2>/dev/null)

    case "$app" in
        remmina)
            echo "در حال نصب/تعمیر Remmina از مخازن Ubuntu..."
            if command -v snap >/dev/null 2>&1 && snap list remmina >/dev/null 2>&1; then
                echo "نسخه Snap از قبل نصب است؛ برای جلوگیری از تداخل، آن را حذف می‌کنیم (بدون --purge)."
                sudo -A snap remove remmina || return 1
            fi
            sudo -A apt update && sudo -A apt install -y remmina remmina-plugin-rdp remmina-plugin-vnc remmina-plugin-secret gnome-keyring || return 1
            echo "اجرای Remmina..."
            (remmina >/dev/null 2>&1 &)
            ;;
        vscode)
            echo "در حال نصب Visual Studio Code از مخزن رسمی Microsoft..."
            if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
                sudo -A apt update && sudo -A apt install -y curl gpg ca-certificates
            fi
            sudo -A install -d -m 0755 /etc/apt/keyrings || return 1
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo -A gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg || return 1
            sudo -A chmod a+r /etc/apt/keyrings/microsoft.gpg
            printf '%s\n' 'Types: deb' 'URIs: https://packages.microsoft.com/repos/code' 'Suites: stable' 'Components: main' 'Architectures: amd64 arm64 armhf' 'Signed-By: /etc/apt/keyrings/microsoft.gpg' | sudo -A tee /etc/apt/sources.list.d/vscode.sources >/dev/null || return 1
            sudo -A apt update && sudo -A apt install -y code || return 1
            ;;
        chrome)
            case "$arch" in
                amd64) deb_url='https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb' ;;
                arm64) deb_url='https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb' ;;
                *) echo "معماری $arch برای Google Chrome در این اسکریپت پشتیبانی نشده است."; return 1 ;;
            esac
            echo "در حال دانلود و نصب Google Chrome از منبع رسمی Google..."
            tmp_deb=$(mktemp --suffix=.deb) || return 1
            if ! curl -fL --retry 2 "$deb_url" -o "$tmp_deb"; then rm -f "$tmp_deb"; return 1; fi
            sudo -A apt install -y "$tmp_deb"
            local result=$?
            rm -f "$tmp_deb"
            [ "$result" -eq 0 ] || return "$result"
            ;;
        git)
            echo "در حال نصب Git..."
            sudo -A apt-get update && sudo -A apt-get install -y git || return 1
            git --version
            ;;
        npm)
            echo "در حال نصب Node.js و npm از مخازن Ubuntu..."
            sudo -A apt-get update && sudo -A apt-get install -y nodejs npm || return 1
            node --version 2>/dev/null || true
            npm --version 2>/dev/null || true
            ;;
        python)
            echo "در حال نصب Python 3، pip و محیط مجازی..."
            sudo -A apt-get update && sudo -A apt-get install -y python3 python3-pip python3-venv python3-dev || return 1
            python3 --version
            ;;
        windscribe)
            case "$arch" in
                amd64) deb_url='https://windscribe.com/install/desktop/linux_deb_x64' ;;
                arm64) deb_url='https://windscribe.com/install/desktop/linux_deb_arm64' ;;
                *) echo "معماری $arch برای Windscribe در این اسکریپت پشتیبانی نشده است."; return 1 ;;
            esac
            echo "در حال دانلود و نصب برنامه رسمی Windscribe..."
            tmp_deb=$(mktemp --suffix=.deb) || return 1
            if ! curl -fL --retry 2 "$deb_url" -o "$tmp_deb"; then rm -f "$tmp_deb"; return 1; fi
            sudo -A apt install -y "$tmp_deb"
            local result=$?
            rm -f "$tmp_deb"
            [ "$result" -eq 0 ] || return "$result"
            ;;
        *) echo "نرم‌افزار ناشناخته است."; return 1 ;;
    esac
}

# بررسی خودکار آینه‌های ایران و انتخاب سریع‌ترین آینه سالم.
# فقط نشانی‌های مخازن رسمی Ubuntu تغییر می‌کنند؛ مخازن برنامه‌های دیگر دست‌نخورده می‌مانند.
iran_mirrors_menu() {
    local codename base test_url elapsed best_elapsed="" best_name="" best_url="" result
    local backup_dir file changed=0 failed=0
    codename=$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-}")
    if [ -z "$codename" ]; then
        echo "خطا: نام نسخه Ubuntu از /etc/os-release تشخیص داده نشد."
        return 1
    fi

    local -a mirror_names=("آروان‌کلاد" "پتیاک" "پردیسکو" "ایران‌سرور" "مخزن کشوری Ubuntu")
    local -a mirror_urls=(
        "https://mirror.arvancloud.ir/ubuntu"
        "https://archive.ubuntu.petiak.ir/ubuntu"
        "https://mirrors.pardisco.co/ubuntu"
        "https://mirror.iranserver.com/ubuntu"
        "https://ir.archive.ubuntu.com/ubuntu"
    )

    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║        افزودن مخازن ایران به اوبونتو       ║"
    echo "╚════════════════════════════════════════════╝"
    echo "نسخه شناسایی‌شده: Ubuntu ${VERSION_ID:-نامشخص} ($codename)"
    echo "همه آینه‌ها به‌صورت خودکار بررسی می‌شوند؛ لازم نیست یکی را دستی انتخاب کنی."
    echo ""

    if ! command -v curl >/dev/null 2>&1; then
        echo "برای بررسی آینه‌ها، ابتدا curl نصب می‌شود..."
        sudo -A apt-get update && sudo -A apt-get install -y curl || return 1
    fi

    for i in "${!mirror_urls[@]}"; do
        base="${mirror_urls[$i]}"
        test_url="${base%/}/dists/$codename/InRelease"
        printf 'در حال بررسی %-24s ' "${mirror_names[$i]}..."
        elapsed=$(curl -fLsS --connect-timeout 5 --max-time 12 -o /dev/null -w '%{time_total}' "$test_url" 2>/dev/null)
        result=$?
        if [ "$result" -eq 0 ] && [ -n "$elapsed" ]; then
            printf '✓ سالم (%.2f ثانیه)\n' "$elapsed"
            if [ -z "$best_elapsed" ] || awk -v a="$elapsed" -v b="$best_elapsed" 'BEGIN {exit !(a < b)}'; then
                best_elapsed="$elapsed"
                best_name="${mirror_names[$i]}"
                best_url="$base"
            fi
        else
            echo "✗ در دسترس نیست یا برای این نسخه پاسخ معتبر ندارد"
        fi
    done

    if [ -z "$best_url" ]; then
        echo ""
        echo "⚠ هیچ‌کدام از آینه‌ها پاسخ معتبر ندادند. هیچ تغییری در APT انجام نشد."
        return 1
    fi

    base="$best_url"
    echo ""
    echo "آینه انتخاب‌شده (سریع‌ترین پاسخ معتبر): $best_name"
    echo "$base"
    echo "فقط همین آینه فعال می‌شود؛ فعال‌کردن هم‌زمان چند آینه تکراری معمولاً لازم نیست و می‌تواند apt update را کندتر کند یا هشدار منابع تکراری بدهد."
    echo ""

    backup_dir="/var/backups/ubuntu-sources-iran-$(date +%Y%m%d-%H%M%S)"
    echo "از تنظیمات مخازن نسخه پشتیبان تهیه می‌شود: $backup_dir"
    sudo -A mkdir -p "$backup_dir" || return 1
    local source_files=()
    [ -f /etc/apt/sources.list ] && source_files+=(/etc/apt/sources.list)
    while IFS= read -r -d '' file; do source_files+=("$file"); done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print0 2>/dev/null)

    for file in "${source_files[@]}"; do
        if sudo -A grep -Eq '(^|[[:space:]])(https?://)?(archive\.ubuntu\.com/ubuntu|security\.ubuntu\.com/ubuntu|ports\.ubuntu\.com/ubuntu|[a-z]{2}\.archive\.ubuntu\.com/ubuntu)' "$file"; then
            local relative="${file#/etc/apt/}"
            sudo -A mkdir -p "$backup_dir/$(dirname "$relative")"
            sudo -A cp -a "$file" "$backup_dir/$relative" || { failed=1; break; }
            sudo -A sed -i -E \
                -e "s#https?://([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu/?#${base%/}/#g" \
                -e "s#https?://security\.ubuntu\.com/ubuntu/?#${base%/}/#g" \
                -e "s#https?://ports\.ubuntu\.com/ubuntu/?#${base%/}/#g" "$file" || { failed=1; break; }
            ((changed++))
        fi
    done

    if [ "$failed" -ne 0 ] || [ "$changed" -eq 0 ]; then
        echo "⚠ هیچ منبع رسمی قابل تغییر پیدا نشد یا تهیه پشتیبان/تغییر ناموفق بود."
        echo "فایل پشتیبان (در صورت ایجاد): $backup_dir"
        return 1
    fi

    echo "در حال بررسی فهرست بسته‌ها با آینه جدید..."
    if sudo -A apt-get update; then
        echo ""
        echo "✅ مخزن Ubuntu تغییر کرد و apt update موفق بود."
        echo "آینه انتخاب‌شده: $best_name ($base)"
        echo "نسخه پشتیبان: $backup_dir"
        echo "توجه: این تغییر مخازن APT را عوض می‌کند؛ محدودیت دسترسی به سایت‌های دیگر مثل Windscribe را لزوماً برطرف نمی‌کند."
        return 0
    else
        echo "⚠ apt update ناموفق بود؛ تنظیمات قبلی از پشتیبان بازگردانده می‌شوند..."
        for file in "${source_files[@]}"; do
            local relative="${file#/etc/apt/}"
            if sudo -A test -f "$backup_dir/$relative"; then sudo -A cp -a "$backup_dir/$relative" "$file"; fi
        done
        sudo -A apt-get update
        echo "تنظیمات قبلی بازگردانده شد. پشتیبان: $backup_dir"
        return 1
    fi
}

useful_apps_menu() {
    local choice app status
    while true; do
        clear
        echo "╔════════════════════════════════════════════╗"
        echo "║          نرم‌افزارهای کاربردی             ║"
        echo "╚════════════════════════════════════════════╝"
        echo ""
        local n=1
        for app in remmina vscode chrome windscribe; do
            case "$app" in
                remmina) label="Remmina - اتصال به دسکتاپ راه دور" ;;
                vscode) label="Visual Studio Code - برنامه‌نویسی" ;;
                chrome) label="Google Chrome - مرورگر وب" ;;
                windscribe) label="Windscribe - VPN" ;;
            esac
            if app_is_installed "$app"; then status="✓ نصب شده"; else status="✗ نصب نشده"; fi
            printf '  %s) %-42s [%s]\n' "$n" "$label" "$status"
            ((n++))
        done
        echo ""
        echo "  5) افزودن مخازن ایران به اوبونتو"
        echo ""
        echo "  با انتخاب هر برنامه، نصب یا تعمیر/به‌روزرسانی آن اجرا می‌شود."
        echo "  0) بازگشت به منوی اصلی"
        echo ""
        read -r -p "  شماره نرم‌افزار را وارد کنید: " choice
        case "$choice" in
            1) app=remmina ;;
            2) app=vscode ;;
            3) app=chrome ;;
            4) app=windscribe ;;
            5) iran_mirrors_menu; continue ;;
            0) return 0 ;;
            *) echo "گزینه نامعتبر است."; sleep 1; continue ;;
        esac
        echo ""
        if useful_apps_install_one "$app"; then
            echo ""
            echo "✅ عملیات نصب/به‌روزرسانی با موفقیت انجام شد."
        else
            echo ""
            echo "⚠ نصب کامل نشد. اتصال اینترنت و پیام‌های خطای بالا را بررسی کن."
        fi
        echo ""
        read -r -p "برای بازگشت به فهرست نرم‌افزارها Enter بزنید..."
    done
}

# ──────────────────────────────────────────────────────────
# توابع مربوط به کیبورد فارسی
# ──────────────────────────────────────────────────────────

persian_keyboard_status() {
    # وضعیت را از منابع ورودی واقعی GNOME بخوان؛ وجود فایل پشتیبان کافی نیست.
    local sources
    sources=$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null) || {
        echo "not_installed"
        return
    }

    if echo "$sources" | grep -Eq "['\"]xkb['\"], *['\"]ir['\"]"; then
        echo "installed"
    else
        echo "not_installed"
    fi
}

persian_keyboard_install() {
    echo ""
    echo "در حال فعال‌سازی کیبورد استاندارد فارسی در Ubuntu 26..."
    echo "─────────────────────────────────────"

    if ! command -v gsettings >/dev/null 2>&1 ||
       ! gsettings list-schemas 2>/dev/null | grep -qx "org.gnome.desktop.input-sources"; then
        echo "خطا: تنظیمات GNOME در این نشست در دسترس نیست."
        echo "اگر از محیط GNOME استفاده می‌کنید، وارد نشست گرافیکی خود شوید و دوباره تلاش کنید."
        echo ""
        return 1
    fi

    # فقط تنظیمات لازم را تغییر بده؛ فایل XKB سیستم یا کل dconf را دست‌کاری نکن.
    echo "  افزودن انگلیسی و فارسی به منابع ورودی..."
    if ! gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'ir')]"; then
        echo "خطا در تنظیم منابع ورودی GNOME."
        return 1
    fi

    echo "  تنظیم میانبر Alt+Shift..."
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Alt>Shift_L', '<Shift>Alt_L']" 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Alt>Shift_R', '<Shift>Alt_R']" 2>/dev/null || true

    # این گزینه برای X11 مفید است؛ در Wayland مدیریت سوئیچ را به GNOME می‌سپاریم.
    if [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
        local current_options
        current_options=$(gsettings get org.gnome.desktop.input-sources xkb-options 2>/dev/null || echo "[]")
        if ! echo "$current_options" | grep -q "grp:alt_shift_toggle"; then
            gsettings set org.gnome.desktop.input-sources xkb-options "['grp:alt_shift_toggle']" 2>/dev/null || true
        fi
    fi

    echo ""
    echo "✅ تنظیم کیبورد فارسی انجام شد."
    echo "  • چیدمان استاندارد فارسی خود اوبونتو استفاده می‌شود."
    echo "  • فایل‌های سیستمی XKB و تنظیمات دیگر GNOME بازنویسی نشدند."
    echo "  • برای تغییر زبان، Alt+Shift را امتحان کنید."
    echo "  • اگر زبان در نوار بالا ظاهر نشد، یک‌بار از نشست خارج شوید و دوباره وارد شوید."
    echo ""
}

persian_keyboard_uninstall() {
    echo ""
    echo "در حال حذف فارسی از منابع ورودی GNOME..."
    echo "─────────────────────────────────────"

    if ! command -v gsettings >/dev/null 2>&1; then
        echo "خطا: gsettings در دسترس نیست."
        return 1
    fi

    # حذف فقط ورودی فارسی، بدون تغییر فایل‌های سیستم و بدون پاک‌کردن همه تنظیمات GNOME.
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us')]" 2>/dev/null || {
        echo "خطا در تغییر منابع ورودی."
        return 1
    }
    gsettings set org.gnome.desktop.input-sources xkb-options "[]" 2>/dev/null || true

    echo ""
    echo "✅ چیدمان فارسی از منابع ورودی حذف شد."
    echo "توجه: فایل سیستمی کیبورد دست‌نخورده باقی مانده است."
    echo ""
}

persian_keyboard_update() {
    # اجرای مجدد نصب، تنظیمات منابع ورودی را ترمیم می‌کند.
    persian_keyboard_install
}

# ──────────────────────────────────────────────────────────
# توابع مربوط به فونت‌های فارسی
# ──────────────────────────────────────────────────────────

persian_fonts_status() {
    if fc-list | grep -qi "vazir" || [ -d "$HOME/.local/share/fonts/Vazir" ]; then
        echo "installed"
    else
        echo "not_installed"
    fi
}

persian_fonts_install() {
    echo ""
    echo "در حال آماده‌سازی نصب فونت‌های فارسی..."
    echo "─────────────────────────────────────"
    echo "  شامل: وزیر، سری B (BMitra, BNazanin, BHoma, ...)"
    echo "         Samim, Shabnam, Sahel, Parastoo, Gandom, Tanha"
    echo "         Iranian Sans, IranNastaliq و..."
    echo ""
    
    if ! ping -c 1 -W 3 github.com &>/dev/null; then
        echo "   خطا: اتصال به اینترنت برقرار نیست."
        echo "  لطفاً اتصال اینترنت خود را بررسی کنید."
        echo ""
        return 1
    fi
    
    if ! command -v curl &>/dev/null; then
        echo "   خطا: curl نصب نیست. لطفاً ابتدا curl را نصب کنید."
        echo "  sudo -A apt install curl"
        echo ""
        return 1
    fi
    
    echo "  دانلود اسکریپت نصب فونت..."
    local tmp_script=$(mktemp /tmp/persian_fonts_XXXXXX.sh)
    
    if ! curl -fsSL "https://raw.githubusercontent.com/fzerorubigd/persian-fonts-linux/master/farsifonts.sh" -o "$tmp_script"; then
        echo "   خطا در دانلود اسکریپت. لطفاً اتصال اینترنت را بررسی کنید."
        rm -f "$tmp_script"
        echo ""
        return 1
    fi
    
    chmod +x "$tmp_script"
    
    echo "  اجرای اسکریپت نصب..."
    echo "  (لطفاً طبق راهنمای داخل اسکریپت عمل کنید)"
    echo "  نکته: برای نصب همه فونت‌ها، معمولاً گزینه‌ی 1 یا All مناسب است."
    echo ""
    
    bash "$tmp_script"
    
    local install_result=$?
    rm -f "$tmp_script"
    
    if [ $install_result -eq 0 ]; then
        echo ""
        echo "  بروزرسانی کش فونت..."
        fc-cache -f -v 2>/dev/null | tail -5
        
        echo ""
        echo "✅ فونت‌های فارسی با موفقیت نصب شدند!"
        echo "   فونت‌های نصب شده:"
        echo "   • Vazir (وزیر)"
        echo "   • B Fonts (BMitra, BNazanin, BHoma, BYekan, BTitr, BLotus, ...)"
        echo "   • Samim, Shabnam, Sahel, Parastoo, Gandom, Tanha"
        echo "   • Iranian Sans, IranNastaliq"
        echo ""
        echo "   نکته: برای استفاده در برنامه‌ها، ممکن است نیاز به"
        echo "   راه‌اندازی مجدد برنامه داشته باشید."
        echo ""
    else
        echo ""
        echo "⚠ خطا در نصب فونت‌ها. لطفاً خروجی بالا را بررسی کنید."
        echo ""
    fi
}

persian_fonts_uninstall() {
    echo ""
    echo "در حال حذف فونت‌های فارسی..."
    echo "─────────────────────────────────────"
    
    local font_dir="$HOME/.local/share/fonts"
    local removed=0
    
    local font_folders=(
        "Vazir"
        "B-Fonts"
        "Iranian-Sans"
        "IranNastaliq"
        "Samim"
        "Shabnam"
        "Sahel"
        "Parastoo"
        "Gandom"
        "Tanha"
        "Estedad"
        "Dana"
    )
    
    for folder in "${font_folders[@]}"; do
        if [ -d "$font_dir/$folder" ]; then
            echo "  حذف $folder..."
            rm -rf "$font_dir/$folder"
            ((removed++))
        fi
    done
    
    for file in "$font_dir"/*.ttf "$font_dir"/*.otf; do
        if [ -f "$file" ]; then
            if fc-query "$file" 2>/dev/null | grep -qi "persian\|arabic\|farsi\|vazir\|bnazanin\|bmitra"; then
                echo "  حذف $(basename "$file")..."
                rm -f "$file"
                ((removed++))
            fi
        fi
    done
    
    if [ $removed -gt 0 ]; then
        echo ""
        echo "  بروزرسانی کش فونت..."
        fc-cache -f -v 2>/dev/null | tail -3
        
        echo ""
        echo "✅ $removed مجموعه فونت با موفقیت حذف شد."
    else
        echo ""
        echo "  هیچ فونت فارسی برای حذف یافت نشد."
    fi
    
    echo ""
}

persian_fonts_update() {
    echo ""
    echo "بررسی بروزرسانی فونت‌های فارسی..."
    echo "─────────────────────────────────────"
    persian_fonts_install
}

# ──────────────────────────────────────────────────────────
# اثر انگشت Validity / libfprint
# ──────────────────────────────────────────────────────────
fingerprint_install() {
    echo ""
    echo "نصب و راه‌اندازی اثر انگشت از مخازن رسمی Ubuntu"
    echo "──────────────────────────────────────────────────"
    sudo -A apt-get update && sudo -A apt-get install -y fprintd libfprint-2-2 || return 1

    echo ""
    echo "حسگر هدف: Validity VFS5011 (USB 138a:0011)"
    local fp_list result
    fp_list=$(fprintd-list "$USER" 2>&1 || true)

    if printf '%s\n' "$fp_list" | grep -qiE 'no fingerprints enrolled|no fingers enrolled'; then
        echo ""
        echo "حالا انگشت موردنظرت را چند بار روی حسگر بکش تا ثبت شود."
        fprintd-enroll "$USER"
        result=$?
        if [ "$result" -ne 0 ]; then
            echo "⚠ ثبت اثر انگشت کامل نشد؛ پیام خطای بالا را بررسی کن."
            return "$result"
        fi
        echo "✅ ثبت اثر انگشت با موفقیت پایان یافت."
    elif printf '%s\n' "$fp_list" | grep -qE '#[0-9]+:'; then
        echo "اثر انگشت از قبل برای کاربر $USER ثبت شده است؛ ثبت مجدد انجام نمی‌شود."
    else
        echo "⚠ نتوانستم وضعیت اثر انگشت ثبت‌شده را تشخیص بدهم."
        printf '%s\n' "$fp_list"
        return 1
    fi

    echo ""
    echo "در حال راه‌اندازی مجدد سرویس اثر انگشت برای پاک‌کردن وضعیت قبلی حسگر..."
    if ! sudo -A systemctl restart fprintd; then
        echo "⚠ راه‌اندازی مجدد fprintd ناموفق بود."
        return 1
    fi
    echo "✅ سرویس راه‌اندازی مجدد شد."
    echo ""
    echo "حالا انگشت ثبت‌شده را برای آزمایش تشخیص روی حسگر بکش..."
    fprintd-verify "$USER"
    result=$?
    if [ "$result" -eq 0 ]; then
        echo "✅ حسگر اثر انگشت درست کار می‌کند."
    else
        echo "⚠ تأیید اثر انگشت موفق نشد؛ پیام بالا را بررسی کن."
    fi
    echo "نکته: fprintd معمولاً به‌صورت خودکار با درخواست برنامه‌ها اجرا می‌شود؛ inactive (dead) در حالت بیکاری طبیعی است و نیازی به enable کردن سرویس نیست."
    echo "تنظیم ورود با اثر انگشت در صفحه قفل ممکن است به تنظیمات محیط دسکتاپ هم نیاز داشته باشد."
    return "$result"
}

# ──────────────────────────────────────────────────────────
# توابع عمومی منو
# ──────────────────────────────────────────────────────────

show_main_menu() {
    clear
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                         جعبه‌ابزار شخصی ایرج (v3.7 GUI)                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "┌──────────────────────────── نرم‌افزارهای سیستمی ────────────────────────────┐"
    printf "│  1) بروزرسانی کامل سیستم              2) افزودن خودکار مخازن ایران          │\n"
    printf "│  3) نصب/تنظیم کیبورد فارسی            4) نصب فونت‌های فارسی                 │\n"
    printf "│  5) نصب و ثبت اثر انگشت (Validity)                                          │\n"
    echo "└──────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "┌──────────────────────────── نرم‌افزارهای اینترنتی ─────────────────────────┐"
    printf "│  6) نمایشگر سرعت اینترنت              7) Google Chrome                      │\n"
    printf "│  8) Windscribe VPN                                                         │\n"
    echo "└──────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "┌────────────────────────── نرم‌افزارهای برنامه‌نویسی ───────────────────────┐"
    printf "│  9) Visual Studio Code                10) Remmina                            │\n"
    printf "│ 11) Git                               12) Node.js و npm                     │\n"
    printf "│ 13) Python 3 + pip + venv                                                   │\n"
    echo "└──────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  با انتخاب هر شماره، عملیات همان ابزار مستقیماً اجرا می‌شود."
    echo "  0) خروج"
    echo ""
    read -r -p "  شماره گزینه را وارد کنید: " choice
}

run_toolbox_action() {
    local choice="$1" app
    case "$choice" in
        1) system_update_update ;;
        2) iran_mirrors_menu ;;
        3) persian_keyboard_install ;;
        4) persian_fonts_install ;;
        5) fingerprint_install ;;
        6)
            if app_is_installed netmon; then netmon_update; else netmon_install; fi
            ;;
        7) useful_apps_install_one chrome ;;
        8) useful_apps_install_one windscribe ;;
        9) useful_apps_install_one vscode ;;
        10) useful_apps_install_one remmina ;;
        11|12|13)
            case "$choice" in
                11) app=git ;;
                12) app=npm ;;
                13) app=python ;;
            esac
            if app_is_installed "$app"; then
                echo "✓ $app از قبل نصب است. برای اطمینان، نصب/تعمیر آن دوباره اجرا می‌شود."
            fi
            useful_apps_install_one "$app"
            ;;
        0) return 10 ;;
        *) echo "گزینه نامعتبر است."; sleep 1; return 0 ;;
    esac
    local result=$?
    echo ""
    if [ "$result" -eq 0 ]; then
        echo "✅ عملیات پایان یافت."
    else
        echo "⚠ عملیات با خطا یا ناتمام ماندن پایان یافت؛ پیام‌های بالا را بررسی کن."
    fi
    echo ""
    if [ "$choice" = "2" ]; then
        echo "منوی اصلی تا چند ثانیه دیگر به‌صورت خودکار نمایش داده می‌شود..."
        sleep 4
    else
        read -r -p "برای بازگشت به منوی اصلی Enter بزن..."
    fi
    return 0
}


# ── رابط گرافیکی و ثبت تغییرات ─────────────────────────────
TOOLBOX_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/iraj-toolbox"
TOOLBOX_LOG_DIR="$TOOLBOX_STATE_DIR/logs"
TOOLBOX_SNAPSHOT_DIR="$TOOLBOX_STATE_DIR/snapshots"
mkdir -p "$TOOLBOX_LOG_DIR" "$TOOLBOX_SNAPSHOT_DIR"

create_transaction_snapshot() {
    local label="$1" stamp dest
    stamp="$(date +%Y%m%d-%H%M%S)"
    dest="$TOOLBOX_SNAPSHOT_DIR/${stamp}-${label}"
    mkdir -p "$dest/config/apt/sources.list.d" "$dest/user"
    {
        echo "timestamp=$stamp"
        echo "label=$label"
        echo "hostname=$(hostname)"
        echo "user=$USER"
        echo "script_version=3.7-gui"
    } > "$dest/metadata.txt"
    dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' > "$dest/packages-before.tsv" 2>/dev/null || true
    if [ -f /etc/apt/sources.list ]; then sudo -A cp -a /etc/apt/sources.list "$dest/config/apt/" 2>/dev/null || true; fi
    if [ -d /etc/apt/sources.list.d ]; then sudo -A cp -a /etc/apt/sources.list.d/. "$dest/config/apt/sources.list.d/" 2>/dev/null || true; fi
    gsettings get org.gnome.desktop.input-sources sources > "$dest/user/input-sources.txt" 2>/dev/null || true
    gsettings get org.gnome.desktop.input-sources xkb-options > "$dest/user/xkb-options.txt" 2>/dev/null || true
    gsettings get org.gnome.desktop.wm.keybindings switch-input-source > "$dest/user/switch-input-source.txt" 2>/dev/null || true
    gsettings get org.gnome.desktop.wm.keybindings switch-input-source-backward > "$dest/user/switch-input-source-backward.txt" 2>/dev/null || true
    find "$HOME/.local/share/fonts" -maxdepth 2 -type f -printf '%P\t%p\n' 2>/dev/null > "$dest/user/fonts-before.tsv" || true
    printf '%s\n' "$dest"
}

# Ownership ledger: remove only explicit packages this toolbox installed itself.
owned_packages_for() {
    case "$1" in
        chrome) printf '%s\n' google-chrome-stable ;;
        vscode) printf '%s\n' code ;;
        windscribe) printf '%s\n' windscribe ;;
        remmina) printf '%s\n' remmina remmina-plugin-rdp remmina-plugin-vnc remmina-plugin-secret ;;
        git) printf '%s\n' git ;;
        npm) printf '%s\n' nodejs npm ;;
        python) printf '%s\n' python3 python3-pip python3-venv python3-dev ;;
        netmon) printf '%s\n' netmon-speed ;;
    esac
}
package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}
record_keyboard_original_once() {
    local d="$TOOLBOX_STATE_DIR/ownership"; mkdir -p "$d"
    [ -e "$d/keyboard-original.saved" ] && return 0
    {
        printf 'sources\t'; gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || echo "UNAVAILABLE"
        printf 'xkb_options\t'; gsettings get org.gnome.desktop.input-sources xkb-options 2>/dev/null || echo "UNAVAILABLE"
        printf 'switch_forward\t'; gsettings get org.gnome.desktop.wm.keybindings switch-input-source 2>/dev/null || echo "UNAVAILABLE"
        printf 'switch_backward\t'; gsettings get org.gnome.desktop.wm.keybindings switch-input-source-backward 2>/dev/null || echo "UNAVAILABLE"
    } > "$d/keyboard-original.tsv"
    touch "$d/keyboard-original.saved"
}
record_fonts_before() {
    local d="$TOOLBOX_STATE_DIR/ownership"; mkdir -p "$d"
    find "$HOME/.local/share/fonts" -type f -print 2>/dev/null | sort > "$d/fonts-before.tmp"
}
record_fonts_after() {
    local d="$TOOLBOX_STATE_DIR/ownership"
    [ -f "$d/fonts-before.tmp" ] || return 0
    find "$HOME/.local/share/fonts" -type f -print 2>/dev/null | sort > "$d/fonts-after.tmp"
    comm -13 "$d/fonts-before.tmp" "$d/fonts-after.tmp" > "$d/fonts-owned.txt"
    rm -f "$d/fonts-before.tmp" "$d/fonts-after.tmp"
    touch "$d/fonts-owned.saved"
}
can_remove_action() {
    local action="$1" d="$TOOLBOX_STATE_DIR/ownership"
    case "$action" in
        netmon) netmon_status | grep -q '^installed$' ;;
        # Fingerprint enrollment is sensitive biometric data; no automatic uninstall action is offered.
        fingerprint) return 1 ;;
        persian_keyboard) [ -f "$d/keyboard-original.saved" ] && persian_keyboard_status | grep -q '^installed$' ;;
        persian_fonts) [ -f "$d/fonts-owned.saved" ] && [ -s "$d/fonts-owned.txt" ] ;;
        chrome|vscode|windscribe|remmina|git|npm|python) [ -s "$d/$action.packages" ] ;;
        *) return 1 ;;
    esac
}
remove_owned_app() {
    local action="$1" d="$TOOLBOX_STATE_DIR/ownership" packages=() pkg failed=0
    local -a remaining=()
    [ -s "$d/$action.packages" ] || { echo "حذف امن ممکن نیست: مالکیت این نصب ثبت نشده است؛ ممکن است برنامه از قبل نصب بوده باشد."; return 1; }
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        if package_installed "$pkg"; then packages+=("$pkg"); fi
    done < "$d/$action.packages"
    [ "${#packages[@]}" -gt 0 ] || { echo "هیچ بستهٔ نصب‌شده‌ای از فهرست مالکیت پیدا نشد؛ پروندهٔ مالکیت برای بررسی حفظ می‌شود."; return 1; }
    echo "مرحله ۱/۳: پاک‌سازی بسته‌های ثبت‌شده متعلق به جعبه‌ابزار: ${packages[*]}"
    echo "از purge استفاده می‌شود تا پیکربندی سیستمی ثبت‌شده در dpkg نیز پاک شود؛ autoremove اجرا نمی‌شود."
    sudo -A apt-get purge -y --no-auto-remove "${packages[@]}" || return 1
    for pkg in "${packages[@]}"; do
        if package_installed "$pkg"; then
            echo "خطا: بسته هنوز نصب است: $pkg"
            remaining+=("$pkg"); failed=1
        fi
    done
    if [ "$failed" -ne 0 ]; then
        printf '%s\n' "${remaining[@]}" > "$d/$action.packages"
        echo "حذف ناقص بود؛ فهرست بسته‌های باقی‌مانده حفظ شد تا امکان تلاش مجدد باشد."
        return 1
    fi
    echo "مرحله ۲/۳: بررسی تنظیمات و مخازن اختصاصی ایجادشده توسط جعبه‌ابزار..."
    # Only remove the VS Code source/key if this toolbox recorded creating them.
    # Never remove user data, extensions, profiles, or unrelated repository files.
    if [ "$action" = vscode ] && [ -s "$d/vscode-created-files.txt" ]; then
        while IFS= read -r f; do
            case "$f" in
                /etc/apt/sources.list.d/vscode.sources|/etc/apt/keyrings/microsoft.gpg)
                    if [ -e "$f" ]; then
                        echo "حذف فایل مخزن/کلید ایجادشده توسط این ابزار: $f"
                        sudo -A rm -f -- "$f" || return 1
                    fi
                    ;;
                *) echo "مسیر غیرمجاز برای پاک‌سازی نادیده گرفته شد: $f" ;;
            esac
        done < "$d/vscode-created-files.txt"
        rm -f "$d/vscode-created-files.txt"
        sudo -A apt-get update || echo "هشدار: به‌روزرسانی فهرست مخازن پس از حذف مخزن VS Code ناموفق بود."
    fi
    rm -f "$d/$action.packages"
    echo "مرحله ۳/۳: تأیید شد بسته‌های ثبت‌شده حذف شده‌اند."
    echo "تنظیمات شخصی، پروفایل‌ها، افزونه‌ها و داده‌های کاربر عمداً حفظ شدند."
    case "$action" in
        chrome) echo "پروفایل Chrome (نشانک‌ها، نشست‌ها و تنظیمات) در پوشه خانه پاک نشده است." ;;
        vscode) echo "پوشه تنظیمات و افزونه‌های VS Code در پوشه خانه پاک نشده است." ;;
        windscribe) echo "تنظیمات شخصی/حساب Windscribe پاک نشده است؛ برای حذف داده‌های حساب، جداگانه بررسی کن." ;;
        remmina) echo "اتصال‌های ذخیره‌شده و تنظیمات Remmina حفظ شدند." ;;
        git) echo "تنظیمات Git کاربر مانند ~/.gitconfig حفظ شدند." ;;
        npm) echo "پروژه‌ها و بسته‌های npm نصب‌شده در پوشه خانه پاک نشده‌اند." ;;
        python) echo "محیط‌های مجازی و پروژه‌های Python پاک نشده‌اند؛ Python سیستمی و وابستگی‌های مشترک دست‌کاری نشدند." ;;
    esac
}
uninstall_gui_action() {
    local action="$1" d="$TOOLBOX_STATE_DIR/ownership" key value
    case "$action" in
        netmon) netmon_uninstall ;;
        chrome|vscode|windscribe|remmina|git|npm|python) remove_owned_app "$action" ;;
        persian_keyboard)
            [ -f "$d/keyboard-original.tsv" ] || { echo "تنظیمات اولیهٔ کیبورد ثبت نشده؛ حذف امن متوقف شد."; return 1; }
            # Restore only if current sources still match what this tool sets; avoid overwriting later user edits.
            current=$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || true)
            [[ "$current" == "[('xkb', 'us'), ('xkb', 'ir')]" ]] || { echo "تنظیم کیبورد پس از نصب تغییر کرده است؛ برای جلوگیری از بازنویسی تغییرات جدید، بازگردانی خودکار متوقف شد."; return 1; }
            while IFS=$'\t' read -r key value; do
                [ "$value" = "UNAVAILABLE" ] && continue
                case "$key" in
                    sources) gsettings set org.gnome.desktop.input-sources sources "$value" || return 1 ;;
                    xkb_options) gsettings set org.gnome.desktop.input-sources xkb-options "$value" || return 1 ;;
                    switch_forward) gsettings set org.gnome.desktop.wm.keybindings switch-input-source "$value" || return 1 ;;
                    switch_backward) gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "$value" || return 1 ;;
                esac
            done < "$d/keyboard-original.tsv"
            rm -f "$d/keyboard-original.tsv" "$d/keyboard-original.saved"
            echo "تنظیمات قبلی کیبورد بازیابی شد."
            ;;
        persian_fonts)
            [ -f "$d/fonts-owned.txt" ] || { echo "فهرست فونت‌های اضافه‌شده توسط ابزار ثبت نشده؛ حذف امن متوقف شد."; return 1; }
            while IFS= read -r f; do
                [ -n "$f" ] || continue
                case "$f" in "$HOME/.local/share/fonts/"*) rm -f -- "$f" ;; *) echo "مسیر خارج از پوشهٔ فونت کاربر رد شد: $f" ;; esac
            done < "$d/fonts-owned.txt"
            find "$HOME/.local/share/fonts" -mindepth 1 -type d -empty -delete 2>/dev/null || true
            fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
            rm -f "$d/fonts-owned.txt" "$d/fonts-owned.saved"
            echo "فقط فایل‌های فونتی که در زمان نصب جدیداً ایجاد و ثبت شده بودند حذف شدند."
            ;;
        *) echo "این گزینه عملیات حذف ندارد."; return 1 ;;
    esac
}

# Use the existing handlers. GUI actions are explicit and are logged.
run_gui_action() {
    local action="$1" result=0 snap log
    log="$TOOLBOX_LOG_DIR/$(date +%Y%m%d-%H%M%S)-${action//[^a-zA-Z0-9_-]/_}.log"
    snap="$(create_transaction_snapshot "$action")"
    local own_dir="$TOOLBOX_STATE_DIR/ownership" pkg before_file after_file
    mkdir -p "$own_dir"
    if [ "$action" = "persian_keyboard" ]; then record_keyboard_original_once; fi
    if [ "$action" = "persian_fonts" ]; then record_fonts_before; fi
    before_file="$own_dir/$action-packages-before.tmp"
    : > "$before_file"
    while IFS= read -r pkg; do
        [ -n "$pkg" ] && package_installed "$pkg" && echo "$pkg" >> "$before_file"
    done < <(owned_packages_for "$action")
    if [ "$action" = "vscode" ]; then
        for f in /etc/apt/sources.list.d/vscode.sources /etc/apt/keyrings/microsoft.gpg; do
            [ -e "$f" ] || echo "$f" >> "$own_dir/vscode-created-files.pending"
        done
    fi
    {
        echo "SANA/Linux Toolbox transaction"
        echo "Action: $action"
        echo "Snapshot: $snap"
        echo "Started: $(date --iso-8601=seconds)"
        echo "----------------------------------------"
        case "$action" in
            system_update) system_update_update ;;
            iran_mirrors) iran_mirrors_menu ;;
            persian_keyboard) persian_keyboard_install ;;
            persian_fonts) persian_fonts_install ;;
            fingerprint) fingerprint_install ;;
            netmon) if app_is_installed netmon; then netmon_update; else netmon_install; fi ;;
            chrome|windscribe|vscode|remmina|git|npm|python) useful_apps_install_one "$action" ;;
            netmon_remove) netmon_uninstall ;;
            *_remove) uninstall_gui_action "${action%_remove}" ;;
            *) echo "Unknown action: $action"; result=1 ;;
        esac
        result=$?
        if [ "$result" -eq 0 ]; then
            if [ "$action" = "persian_fonts" ]; then record_fonts_after; fi
            if [[ "$action" =~ ^(chrome|vscode|windscribe|remmina|git|npm|python|netmon)$ ]]; then
                local owned_file="$own_dir/$action.packages"
                : > "$owned_file"
                while IFS= read -r pkg; do
                    [ -n "$pkg" ] || continue
                    if package_installed "$pkg" && ! grep -Fxq "$pkg" "$before_file"; then echo "$pkg" >> "$owned_file"; fi
                done < <(owned_packages_for "$action")
                [ -s "$owned_file" ] || rm -f "$owned_file"
            fi
            if [ "$action" = "vscode" ] && [ -f "$own_dir/vscode-created-files.pending" ]; then
                while IFS= read -r f; do
                    case "$f" in
                        /etc/apt/sources.list.d/vscode.sources|/etc/apt/keyrings/microsoft.gpg) [ -e "$f" ] && echo "$f" >> "$own_dir/vscode-created-files.txt" ;;
                    esac
                done < "$own_dir/vscode-created-files.pending"
                rm -f "$own_dir/vscode-created-files.pending"
            fi
        fi
        rm -f "$before_file"
        echo "----------------------------------------"
        echo "Finished: $(date --iso-8601=seconds)"
        echo "Exit status: $result"
        echo "Snapshot: $snap"
    } 2>&1 | tee "$log"
    return "$result"
}

if [[ "${1:-}" == "--action" ]]; then
    shift
    run_gui_action "${1:-}"
    exit $?
fi

if [[ "${1:-}" == "--can-remove" ]]; then
    can_remove_action "${2:-}" && echo yes || echo no
    exit 0
fi

if [[ "${1:-}" == "--status" ]]; then
    case "${2:-}" in
        netmon) netmon_status ;;
        persian_keyboard) persian_keyboard_status ;;
        persian_fonts) persian_fonts_status ;;
        fingerprint) command -v fprintd-enroll >/dev/null 2>&1 && dpkg-query -W -f='${Status}' fprintd 2>/dev/null | grep -q 'install ok installed' && echo installed || echo not_installed ;;
        chrome|windscribe|vscode|remmina|git|npm|python) app_is_installed "$2" && echo installed || echo not_installed ;;
        *) echo unknown ;;
    esac
    exit 0
fi

# ── Python/Tkinter GUI embedded in this single .sh file ─────
# Bootstrap GUI dependency automatically; do not modify system if already available.
if ! python3 -c 'import tkinter' >/dev/null 2>&1; then
    echo "رابط گرافیکی به بستهٔ python3-tk نیاز دارد."
    echo "در حال بررسی مخازن و نصب پیش‌نیاز؛ ممکن است رمز sudo -A خواسته شود..."
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "خطا: apt-get پیدا نشد؛ نصب خودکار روی این سیستم پشتیبانی نمی‌شود."
        exit 1
    fi
    if ! sudo -A -v; then
        echo "خطا: مجوز مدیر سیستم (sudo) دریافت نشد."
        exit 1
    fi
    if ! sudo -A apt-get update; then
        echo "خطا در به‌روزرسانی فهرست بسته‌ها؛ رابط اجرا نشد و تنظیم دیگری تغییر نکرد."
        exit 1
    fi
    if ! sudo -A apt-get install -y python3-tk; then
        echo "نصب python3-tk ناموفق بود؛ رابط اجرا نشد."
        exit 1
    fi
    if ! python3 -c 'import tkinter' >/dev/null 2>&1; then
        echo "بسته نصب شد، اما Tkinter برای python3 فعلی در دسترس نیست."
        echo "نسخه Python: $(python3 --version 2>&1)"
        exit 1
    fi
    echo "پیش‌نیاز نصب شد؛ در حال باز کردن جعبه‌ابزار..."
fi

# Install Arabic/Persian shaping dependencies when missing. This fixes Tkinter's
# lack of native Arabic joining/bidirectional text rendering.
if ! python3 -c 'import arabic_reshaper; from bidi.algorithm import get_display' >/dev/null 2>&1; then
    echo "در حال آماده‌سازی نمایش صحیح متن فارسی..."
    if ! sudo -A -v; then
        echo "خطا: برای آماده‌سازی نمایش فارسی، مجوز sudo -A لازم است."
        exit 1
    fi
    if ! sudo -A apt-get update || ! sudo -A apt-get install -y python3-bidi python3-arabic-reshaper; then
        echo "خطا: نصب پیش‌نیازهای نمایش فارسی ناموفق بود."
        exit 1
    fi
fi

exec python3 - "$0" <<'PYGUI'
import os, sys, subprocess, threading, tkinter as tk
from tkinter import ttk, messagebox
import arabic_reshaper
from bidi.algorithm import get_display
import tempfile, textwrap, atexit

# Graphical sudo askpass helper. Password is passed only to sudo over its
# askpass pipe and is never written to disk or included in the toolbox log.
_askpass_fd, _askpass_path = tempfile.mkstemp(prefix='linux-toolbox-askpass-', suffix='.py')
os.close(_askpass_fd)
_askpass_source = r'''#!/usr/bin/env python3
import sys
try:
    import tkinter as tk
    from tkinter import ttk
    import tkinter.font as tkfont
    import arabic_reshaper
    from bidi.algorithm import get_display
    def rtl(text):
        return get_display(arabic_reshaper.reshape(text))

    root = tk.Tk()
    root.title('احراز هویت مدیر سیستم')
    root.attributes('-topmost', True)
    root.resizable(False, False)
    answer = {'value': None}
    available = set(tkfont.families(root))
    family = next((f for f in ('Vazirmatn', 'Noto Sans Arabic', 'Noto Naskh Arabic', 'Noto Sans', 'DejaVu Sans') if f in available), 'TkDefaultFont')
    frame = ttk.Frame(root, padding=16)
    frame.grid(row=0, column=0, sticky='nsew')
    ttk.Label(frame, text=rtl('برای ادامه، رمز عبور حساب خود را وارد کنید:'),
              font=(family, 10), justify='right', anchor='e').grid(row=0, column=0, sticky='ew', pady=(0, 10))
    entry = ttk.Entry(frame, show='*', width=34, justify='left')
    entry.grid(row=1, column=0, sticky='ew', pady=(0, 12))
    buttons = ttk.Frame(frame)
    buttons.grid(row=2, column=0, sticky='e')
    def accept(event=None):
        answer['value'] = entry.get()
        root.quit()
    def cancel(event=None):
        answer['value'] = None
        root.quit()
    ttk.Button(buttons, text=rtl('تأیید'), command=accept).pack(side='right', padx=(6, 0))
    ttk.Button(buttons, text=rtl('لغو'), command=cancel).pack(side='right')
    entry.bind('<Return>', accept)
    root.bind('<Escape>', cancel)
    root.protocol('WM_DELETE_WINDOW', cancel)
    root.update_idletasks()
    x = max(0, (root.winfo_screenwidth() - root.winfo_reqwidth()) // 2)
    y = max(0, (root.winfo_screenheight() - root.winfo_reqheight()) // 2)
    root.geometry(f'+{x}+{y}')
    root.lift()
    root.focus_force()
    entry.focus_force()
    root.mainloop()
    value = answer['value']
    root.destroy()
    if value is None:
        sys.exit(1)
    sys.stdout.write(value + '\n')
except Exception as exc:
    sys.stderr.write('GUI askpass failed: ' + str(exc) + '\n')
    sys.exit(1)
'''
with open(_askpass_path, 'w', encoding='utf-8') as _f:
    _f.write(_askpass_source)
os.chmod(_askpass_path, 0o700)
os.environ['SUDO_ASKPASS'] = _askpass_path
atexit.register(lambda: os.path.exists(_askpass_path) and os.unlink(_askpass_path))

def rtl(value):
    if not isinstance(value, str):
        return value
    try:
        return get_display(arabic_reshaper.reshape(value))
    except Exception:
        return value

SCRIPT=os.path.abspath(sys.argv[1])
APP_TITLE='جعبه‌ابزار اوبونتو'

GROUPS=[
 ('سیستم و درایورها', [
  ('system_update','به‌روزرسانی کامل سیستم','اجرای apt update و apt upgrade؛ عملیات اجرایی است'),
  ('iran_mirrors','مخازن سریع‌تر Ubuntu','مدیریت تنظیم مخازن نرم‌افزار'),
  ('fingerprint','حسگر اثر انگشت','fprintd و ابزارهای libfprint'),
 ]),
 ('اینترنت و شبکه', [
  ('netmon','نمایشگر سرعت اینترنت','نمایش سرعت شبکه، قدرت سیگنال و لوگوی اپراتور'),
  ('chrome','Google Chrome','مرورگر وب'),
  ('windscribe','Windscribe VPN','کلاینت VPN'),
 ]),
 ('برنامه‌نویسی و ابزارها', [
  ('vscode','Visual Studio Code','ویرایشگر کد'),
  ('remmina','Remmina','اتصال دسکتاپ راه دور'),
  ('git','Git','مدیریت نسخه'),
  ('npm','Node.js و npm','محیط JavaScript'),
  ('python','Python 3، pip و venv','محیط توسعه Python'),
 ]),
 ('زبان و ظاهر', [
  ('persian_keyboard','کیبورد فارسی','چیدمان فارسی/انگلیسی و میانبر Alt+Shift'),
  ('persian_fonts','فونت‌های فارسی','فونت‌های فارسی کاربر'),
 ]),
]
ACTION_ONLY={'system_update','iran_mirrors'}

# Ask fontconfig for the system's preferred font with Persian glyph coverage.
# This lets installed fonts (e.g. Vazirmatn, Sahel, Noto Sans Arabic) be used
# instead of hard-coding DejaVu Sans throughout the interface.
def choose_ui_font():
    candidates = [
        ('sans:lang=fa', 'Noto Sans Arabic'),
        ('Vazirmatn:lang=fa', 'Vazirmatn'),
        ('Sahel:lang=fa', 'Sahel'),
        ('Noto Sans Arabic:lang=fa', 'Noto Sans Arabic'),
        ('DejaVu Sans:lang=fa', 'DejaVu Sans'),
    ]
    for pattern, fallback in candidates:
        try:
            result = subprocess.run(['fc-match', '-f', '%{family}', pattern],
                                    text=True, capture_output=True, timeout=3)
            family = result.stdout.strip().split(',')[0].strip()
            if result.returncode == 0 and family:
                return family
        except Exception:
            pass
    return 'DejaVu Sans'

UI_FONT = choose_ui_font()
LOG_FONT = UI_FONT  # use the same readable Persian-capable font in the log

root=tk.Tk()
root.title(APP_TITLE + ' — نسخهٔ گرافیکی')
screen_h = root.winfo_screenheight()
window_h = max(560, min(700, screen_h - 90))
root.geometry(f'1050x{window_h}')
root.minsize(850,560)
style=ttk.Style(root)
try: style.theme_use('clam')
except tk.TclError: pass
style.configure('Header.TLabel',font=(UI_FONT,15,'bold'))
style.configure('Sub.TLabel',font=(UI_FONT,9))
style.configure('TLabel',font=(UI_FONT,9))
style.configure('TButton',padding=(10,7),font=(UI_FONT,9))
style.configure('TNotebook.Tab',font=(UI_FONT,9),padding=(8,4))
style.configure('Treeview',rowheight=38,font=(UI_FONT,9))
style.configure('Treeview.Heading',font=(UI_FONT,9,'bold'))

header=ttk.Frame(root,padding=(12,8,12,5)); header.pack(fill='x')
ttk.Label(header,text=rtl('جعبه‌ابزار اوبونتو'),style='Header.TLabel').pack(anchor='e')
ttk.Label(header,text=rtl('نصب و حذف تک‌کلیکی • نمایش زندهٔ خروجی • ثبت گزارش عملیات'),style='Sub.TLabel').pack(anchor='e',pady=(2,0))

status_text=tk.StringVar(value=rtl('در حال آماده‌سازی…'))
busy=False
rows={}
statuses={}
current_tab=None

notebook=ttk.Notebook(root)
notebook.pack(fill='both',expand=True,padx=14,pady=(6,8))
for group,items in GROUPS:
    frame=ttk.Frame(notebook,padding=6)
    notebook.add(frame,text=rtl(group))
    ttk.Label(frame,text=rtl('وضعیت هر برنامه مشخص است؛ برای نصب یا حذف، دکمهٔ همان ردیف را بزن.'),anchor='e').pack(fill='x',pady=(0,5))
    canvas=tk.Canvas(frame,highlightthickness=0)
    scrollbar=ttk.Scrollbar(frame,orient='vertical',command=canvas.yview)
    inner=ttk.Frame(canvas)
    inner.bind('<Configure>',lambda e,c=canvas:c.configure(scrollregion=c.bbox('all')))
    win=canvas.create_window((0,0),window=inner,anchor='nw')
    canvas.configure(yscrollcommand=scrollbar.set)
    canvas.bind('<Configure>',lambda e,c=canvas,w=win:c.itemconfigure(w,width=e.width))
    canvas.pack(side='left',fill='both',expand=True)
    scrollbar.pack(side='right',fill='y')
    for ident,label,desc in items:
        card=ttk.Frame(inner,padding=(5,4))
        card.pack(fill='x',pady=2)
        card.columnconfigure(1,weight=1)
        button= tk.Button(card,text='…',width=5,relief='flat',font=(UI_FONT,8,'bold'),
                          padx=3,pady=1,borderwidth=0,cursor='hand2',state='disabled')
        button.grid(row=0,column=0,rowspan=2,padx=(2,5),sticky='e')
        title=ttk.Label(card,text=rtl(label),font=(UI_FONT,10,'bold'),anchor='e')
        title.grid(row=0,column=1,sticky='ew')
        desc_lbl=ttk.Label(card,text=rtl(desc),style='Sub.TLabel',anchor='e')
        desc_lbl.grid(row=1,column=1,sticky='ew',pady=(3,0))
        state_lbl=ttk.Label(card,text=rtl('در حال بررسی وضعیت…'),anchor='e',width=18)
        state_lbl.grid(row=0,column=2,rowspan=2,padx=(7,3),sticky='e')
        rows[ident]={'label':label,'desc':desc,'button':button,'state':state_lbl}
        button.configure(command=lambda i=ident:click_action(i))

# Large live log area remains visible below every tab.
bottom=ttk.Frame(root,padding=(10,0,10,5)); bottom.pack(fill='x')
ttk.Label(bottom,textvariable=status_text,anchor='e').pack(side='left',fill='x',expand=True)

logframe=ttk.LabelFrame(root,text=rtl('گزارش زندهٔ عملیات'),padding=5,height=180)
logframe.pack(fill='both',expand=False,padx=14,pady=(0,8))
logframe.pack_propagate(False)
output=tk.Text(logframe,height=7,wrap='word',font=(LOG_FONT,9),state='disabled',undo=False)
logscroll=ttk.Scrollbar(logframe,orient='vertical',command=output.yview)
output.configure(yscrollcommand=logscroll.set)
logscroll.pack(side='left',fill='y')
output.pack(side='right',fill='both',expand=True)

def append_log(text):
    def update():
        output.configure(state='normal')
        output.insert('end',rtl(text))
        output.see('end')
        output.configure(state='disabled')
    root.after(0,update)

def status_for(ident):
    try:
        p=subprocess.run([SCRIPT,'--status',ident],text=True,capture_output=True,timeout=15)
        val=p.stdout.strip().splitlines()[-1] if p.stdout.strip() else 'unknown'
        return val if val in ('installed','not_installed') else 'unknown'
    except Exception:
        return 'unknown'

def set_row_state(ident,val):
    row=rows[ident]
    statuses[ident]=val
    if ident in ACTION_ONLY:
        row['state'].configure(text=rtl('عملیات اجرایی'))
        row['button'].configure(text=rtl('اجرا'),bg='#2563eb',fg='white',
                                activebackground='#1d4ed8',state='normal')
    elif val=='installed':
        row['state'].configure(text=rtl('نصب‌شده'))
        row['button'].configure(text=rtl('حذف'),bg='#dc2626',fg='white',
                                activebackground='#b91c1c',state='normal')
    elif val=='not_installed':
        row['state'].configure(text=rtl('نصب‌نشده'))
        row['button'].configure(text=rtl('نصب'),bg='#16a34a',fg='white',
                                activebackground='#15803d',state='normal')
    else:
        row['state'].configure(text=rtl('وضعیت نامشخص'))
        row['button'].configure(text=rtl('بررسی'),bg='#64748b',fg='white',
                                activebackground='#475569',state='normal')

def refresh_status():
    status_text.set(rtl('در حال بررسی وضعیت برنامه‌ها…'))
    for row in rows.values():
        row['button'].configure(state='disabled')
    def worker():
        results={k:status_for(k) for k in rows}
        def update():
            for ident,val in results.items(): set_row_state(ident,val)
            status_text.set(rtl('وضعیت به‌روز شد. برای هر برنامه از دکمهٔ همان ردیف استفاده کن.'))
        root.after(0,update)
    threading.Thread(target=worker,daemon=True).start()

ttk.Button(bottom,text=rtl('به‌روزرسانی وضعیت'),command=refresh_status).pack(side='right',padx=(6,0))

def click_action(ident):
    global busy
    if busy: return
    val=statuses.get(ident,'unknown')
    if val=='unknown':
        refresh_status()
        return
    if ident in ACTION_ONLY:
        action=ident
        prompt='این عملیات اجرا شود؟'
    elif val=='installed':
        try:
            p=subprocess.run([SCRIPT,'--can-remove',ident],text=True,capture_output=True,timeout=8)
            can=p.stdout.strip().splitlines()[-1:] == ['yes']
        except Exception:
            can=False
        if not can:
            messagebox.showwarning(rtl(APP_TITLE),rtl('حذف امن برای این مورد تأیید نشد؛ برای جلوگیری از حذف فایل‌ها یا تنظیمات شخصی، عملیات حذف انجام نمی‌شود.'))
            return
        action=ident+'_remove'
        prompt='برنامه/قابلیت حذف یا به حالت قبل بازگردانده شود؟'
    else:
        action=ident
        prompt='برنامه/قابلیت نصب شود؟'
    if not messagebox.askyesno(rtl(APP_TITLE),rtl(rows[ident]['label']+'\n\n'+prompt)):
        return
    start_action(ident,action)

def start_action(ident,action):
    global busy
    busy=True
    status_text.set(rtl('در حال اجرا؛ خروجی در گزارش زنده نمایش داده می‌شود…'))
    for row in rows.values(): row['button'].configure(state='disabled')
    append_log('\n\n'+'='*72+'\n')
    append_log('شروع عملیات: '+rows[ident]['label']+' | action='+action+'\n')
    append_log('زمان: '+__import__('datetime').datetime.now().astimezone().isoformat(timespec='seconds')+'\n')
    append_log('='*72+'\n')
    def worker():
        try:
            append_log('در حال بررسی مجوز مدیر سیستم (sudo)…\n')
            auth=subprocess.run(['sudo','-A','-v'],text=True,timeout=180,env=os.environ.copy())
            if auth.returncode!=0:
                append_log('خطا: مجوز sudo -A دریافت نشد؛ عملیات اجرا نشد.\n')
                finish_action(ident,1)
                return
            proc=subprocess.Popen([SCRIPT,'--action',action],stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT,text=True,bufsize=1)
            for line in proc.stdout:
                append_log(line)
            rc=proc.wait()
            append_log('\nپایان عملیات با کد خروج: '+str(rc)+'\n')
            finish_action(ident,rc)
        except Exception as exc:
            append_log('خطا در اجرای عملیات: '+str(exc)+'\n')
            finish_action(ident,1)
    threading.Thread(target=worker,daemon=True).start()

def finish_action(ident,rc):
    global busy
    def done():
        global busy
        busy=False
        status_text.set(rtl('عملیات پایان یافت؛ در حال بررسی دوبارهٔ وضعیت…' if rc==0 else 'عملیات با خطا پایان یافت؛ گزارش را بررسی کن.'))
        refresh_status()
    root.after(0,done)

refresh_status()
root.mainloop()
PYGUI

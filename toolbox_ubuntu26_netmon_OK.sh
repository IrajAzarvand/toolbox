#!/bin/bash

# ══════════════════════════════════════════════════════════
# جعبه‌ابزار شخصی ایرج - نسخه 3.6
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
    ["netmon"]="1.4.7"
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
    
    sudo apt update && sudo apt upgrade -y
    
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
    if dpkg -l | grep -q "netmon-speed"; then
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
Version: 1.5.1
Architecture: amd64
Maintainer: Iraj <iraj@localhost>
Description: نمایشگر سرعت اینترنت با ترازبندی بهینه
Depends: python3, python3-pystray, python3-pil, fonts-dejavu-core
EOF
    
    cat << 'PYEOF' > "$deb_dir/usr/local/bin/netmon.py"
#!/usr/bin/env python3
"""NetMon speed indicator with live cellular technology and cached operator logo."""
import io
import json
import os
import re
import subprocess
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

import pystray
from PIL import Image, ImageDraw, ImageFont, ImageOps

CACHE_DIR = Path.home() / ".cache" / "netmon" / "operators"
LOGO_MAX_BYTES = 3 * 1024 * 1024
LOGO_SIZE = (20, 20)
ISP_CHECK_INTERVAL = 60  # Recheck ISP identity every minute; route changes force an immediate refresh.


def run_command(args, timeout=5):
    try:
        result = subprocess.run(args, capture_output=True, text=True,
                                timeout=timeout, check=False)
        if result.returncode != 0:
            return ""
        # mmcli may emit ANSI color codes even when captured by a subprocess.
        # Strip them before parsing fields such as "state: connected".
        return re.sub(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])", "", result.stdout)
    except (OSError, subprocess.SubprocessError):
        return ""


def get_default_route_interfaces():
    """Return only interfaces used by an active IPv4/IPv6 default route."""
    interfaces = set()
    for args in (["ip", "-o", "route", "show", "default"],
                 ["ip", "-6", "-o", "route", "show", "default"]):
        output = run_command(args)
        for line in output.splitlines():
            match = re.search(r"(?:^|\s)dev\s+(\S+)", line)
            if match:
                interfaces.add(match.group(1))
    return interfaces


def get_default_route_signature():
    """Detect Wi-Fi/Ethernet changes, including a new active NetworkManager connection."""
    parts = []
    for args in (["ip", "-o", "route", "show", "default"],
                 ["ip", "-6", "-o", "route", "show", "default"]):
        parts.append(run_command(args).strip())
    # Include active connection UUID/name: a new Wi-Fi can reuse the same gateway.
    parts.append(run_command([
        "nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE", "connection", "show", "--active"
    ]).strip())
    return "\n".join(parts)


def get_net_stats():
    interfaces = get_default_route_interfaces()
    if not interfaces:
        return 0, 0
    rx, tx = 0, 0
    try:
        with open('/proc/net/dev', 'r', encoding='utf-8') as f:
            for line in f.readlines()[2:]:
                if ':' not in line:
                    continue
                name, values = line.split(':', 1)
                if name.strip() not in interfaces:
                    continue
                stats = values.split()
                rx += int(stats[0])
                tx += int(stats[8])
    except (OSError, ValueError, IndexError):
        pass
    return rx, tx


def format_speed(kbps):
    kbps = max(0, kbps)
    if kbps >= 1024:
        return f"{kbps / 1024:.1f} MB"
    return f"{kbps:.0f} KB"


def get_font(size):
    # Render at the tray's native pixel height to avoid the panel scaling a
    # 36px raster icon down (which makes text look blurred).
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


def get_active_cellular_modem():
    """Return current operator/access technology only for an active GSM device."""
    devices = run_command([
        "nmcli", "-t", "-f", "TYPE,STATE,DEVICE", "device", "status"
    ])
    gsm_devices = []
    for line in devices.splitlines():
        fields = line.split(":")
        if len(fields) >= 3 and fields[0] == "gsm" and fields[1].startswith("connected"):
            gsm_devices.append(":".join(fields[2:]))
    if not gsm_devices:
        return None

    modem_list = run_command(["mmcli", "-L"])
    paths = re.findall(r"/org/freedesktop/ModemManager1/Modem/(\d+)", modem_list)
    for modem_id in paths:
        details = run_command(["mmcli", "-m", modem_id], timeout=7)
        if not details or not re.search(r"state:\s+connected", details):
            continue
        tech_match = re.search(r"access tech:\s*([\w+-]+)", details, re.IGNORECASE)
        operator_match = re.search(r"operator name:\s*(.*?)\s*$", details, re.MULTILINE)
        operator = operator_match.group(1).strip() if operator_match else ""
        tech = tech_match.group(1).lower() if tech_match else ""
        signal_match = re.search(r"signal quality:\s*(\d+)\s*%", details, re.IGNORECASE)
        signal_quality = max(0, min(100, int(signal_match.group(1)))) if signal_match else None
        tech_labels = {
            "gprs": "2G", "edge": "2G", "gsm": "2G",
            "umts": "3G", "hspa": "3G", "hsdpa": "3G", "hsupa": "3G",
            "hspa+": "3G", "lte": "4G/LTE", "4g": "4G/LTE",
            "5gnr": "5G", "nr": "5G",
        }
        label = tech_labels.get(tech, "")
        if not label:
            if "5g" in tech or "nr" in tech:
                label = "5G"
            elif "lte" in tech:
                label = "4G/LTE"
            elif any(token in tech for token in ("umts", "hspa", "hsdpa", "hsupa")):
                label = "3G"
            elif tech in ("gsm", "gprs", "edge"):
                label = "2G"
        return {"operator": operator, "technology": label, "signal_quality": signal_quality, "modem_id": modem_id}
    return None


def safe_operator_key(operator):
    key = re.sub(r"[^a-z0-9_-]+", "-", operator.lower()).strip("-")
    return key[:70] or "unknown-operator"


# Fixed, exact Wikimedia Commons file titles. No generic image search is used.
# Sources: current Irancell logo, MCI 2025 brand logo, and Rightel logo from rightel.ir.
OPERATOR_FILES = {
    "irancell": "File:MTNirancell-Logo.png",
    "ایرانسل": "File:MTNirancell-Logo.png",
    "همراه اول": "File:MCI logo (2025).svg",
    "mci": "File:MCI logo (2025).svg",
    "رایتل": "File:شعار شركة رايتل.png",
    "rightel": "File:شعار شركة رايتل.png",
}
LOGO_MODE_FILE = Path.home() / ".config" / "netmon" / "logo_mode"
LOGO_MODE = "official"


def normalize_operator(operator):
    value = (operator or "").casefold().strip()
    if "irancell" in value or "ایرانسل" in value or "iran cell service" in value or "as44244" in value:
        return "irancell"
    if ("همراه اول" in value or value == "mci" or "as197207" in value
            or "mobile communication company of iran" in value
            or "mobile communications company of iran" in value):
        return "mci"
    if "rightel" in value or "رایتل" in value:
        return "rightel"
    return ""


def read_logo_mode():
    try:
        value = LOGO_MODE_FILE.read_text(encoding="utf-8").strip().lower()
        return value if value in {"official", "symbol"} else "official"
    except OSError:
        return "official"


def set_logo_mode(mode):
    try:
        LOGO_MODE_FILE.parent.mkdir(parents=True, exist_ok=True)
        LOGO_MODE_FILE.write_text(mode + "\n", encoding="utf-8")
        return True
    except OSError:
        return False


def get_public_isp_brand():
    """Infer the access provider from public-IP ASN metadata (not from local Wi-Fi name)."""
    request = urllib.request.Request(
        "https://ipconfig.io/json",
        headers={"User-Agent": "NetMonSpeed/1.5.1 (public ASN provider lookup)"},
    )
    try:
        with urllib.request.urlopen(request, timeout=6) as response:
            payload = json.loads(response.read(256 * 1024).decode("utf-8", errors="replace"))
    except Exception:
        return ""
    org = str(payload.get("asn_org", "") or "").strip()
    asn = str(payload.get("asn", "") or "").strip().upper()
    searchable = f"{org} {asn}".casefold()
    # Convert common ASN legal/parent-company names to the customer-facing brand.
    known_brands = (
        (("iran cell service and communication company", "as44244", "irancell"), "Irancell"),
        (("mobile communication company of iran", "mobile communications company of iran", "as197207", "mci"), "همراه اول"),
        (("rightel", "righ tel"), "رایتل"),
        (("telecommunication company of iran", "tci"), "مخابرات ایران"),
        (("shatel",), "شاتل"),
        (("mobinnet",), "مبین‌نت"),
        (("asiatech", "asia tech"), "آسیاتک"),
        (("pars online", "parsonline"), "پارس‌آنلاین"),
    )
    for entry in known_brands:
        terms, brand = entry
        if any(term in searchable for term in terms):
            return brand
    # Avoid inventing a logo when ASN metadata is empty or generic.
    if not org or org.casefold() in {"unknown", "private network", "not available"}:
        return ""
    return org


def download_operator_logo(operator):
    """Fetch only a known exact logo file from Commons and cache both display styles."""
    key = normalize_operator(operator)
    if not key:
        return None
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
    except OSError:
        return None

    official = CACHE_DIR / f"{key}-official.png"
    symbol = CACHE_DIR / f"{key}-symbol.png"
    if official.is_file() and symbol.is_file():
        try:
            with Image.open(official) as im: im.verify()
            with Image.open(symbol) as im: im.verify()
            return official
        except (OSError, ValueError):
            for path in (official, symbol):
                try: path.unlink()
                except OSError: pass

    file_title = OPERATOR_FILES.get(key)
    if not file_title:
        return None
    headers = {"User-Agent": "NetMonSpeed/1.5.1 (fixed operator logo sources)"}
    api = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
        "action": "query", "titles": file_title, "prop": "imageinfo",
        "iiprop": "url|mime", "iiurlwidth": 512, "format": "json",
    })
    try:
        request = urllib.request.Request(api, headers=headers)
        with urllib.request.urlopen(request, timeout=8) as response:
            data = json.loads(response.read(1024 * 1024).decode("utf-8", errors="replace"))
        pages = data.get("query", {}).get("pages", {})
        page = next(iter(pages.values()))
        info = (page.get("imageinfo") or [{}])[0]
        image_url = info.get("thumburl") or info.get("url")
        if not image_url or not image_url.startswith("https://"):
            return None
        request = urllib.request.Request(image_url, headers=headers)
        with urllib.request.urlopen(request, timeout=10) as response:
            raw = response.read(LOGO_MAX_BYTES + 1)
        if not raw or len(raw) > LOGO_MAX_BYTES:
            return None
        with Image.open(io.BytesIO(raw)) as source:
            source.load()
            original = source.convert("RGBA")
        # Trim transparent/white margins before preparing the full logo.
        alpha = original.getchannel("A")
        bbox = alpha.getbbox()
        if bbox:
            original = original.crop(bbox)
        # Save full logo at useful resolution; display sizing happens in load_logo().
        original.thumbnail((512, 512), Image.Resampling.LANCZOS)
        original.save(official, format="PNG", optimize=True)
        # Symbol mode is a square crop around the visual center, not a second web search.
        # This gives a consistent compact comparison; user can switch back to the full mark.
        w, h = original.size
        side = min(w, h)
        # Horizontal wordmarks usually place their standalone emblem on the left;
        # use that side for the square preview. Nearly-square artwork stays centered.
        left = 0 if w > h * 1.15 else max(0, (w - side) // 2)
        top = max(0, (h - side) // 2)
        cropped = original.crop((left, top, left + side, top + side))
        cropped.thumbnail((256, 256), Image.Resampling.LANCZOS)
        cropped.save(symbol, format="PNG", optimize=True)
        return official
    except Exception:
        return None


def load_logo(path, mode=None):
    if not path:
        return None
    try:
        mode = mode or read_logo_mode()
        path = Path(path)
        if path.name.endswith("-official.png") and mode == "symbol":
            path = path.with_name(path.name.replace("-official.png", "-symbol.png"))
        with Image.open(path) as source:
            source.load()
            logo = ImageOps.contain(source.convert("RGBA"), LOGO_SIZE)
        # Neutral light badge for clear contrast on dark panels.
        canvas = Image.new("RGBA", LOGO_SIZE, (248, 249, 251, 255))
        canvas_draw = ImageDraw.Draw(canvas)
        canvas_draw.rounded_rectangle((0, 0, LOGO_SIZE[0] - 1, LOGO_SIZE[1] - 1),
                                      radius=4, fill=(248, 249, 251, 255),
                                      outline=(205, 211, 219, 255), width=1)
        canvas.alpha_composite(logo, ((LOGO_SIZE[0] - logo.width) // 2,
                                      (LOGO_SIZE[1] - logo.height) // 2))
        return canvas
    except (OSError, ValueError):
        return None


def choose_logo_mode(icon, mode):
    """Switch persisted logo mode and refresh the tray image immediately."""
    if set_logo_mode(mode):
        icon.notify("حالت لوگو: " + ("نمادمحور" if mode == "symbol" else "رسمی کامل"), "NetMon")
        icon.update_menu()


def menu_mode_label(item):
    return "✓ " + ("نمادمحور" if read_logo_mode() == "symbol" else "لوگوی رسمی کامل")


def update_loop(icon):
    last_rx, last_tx = get_net_stats()
    font = get_font(16)
    padding = 2
    last_cellular_signature = None
    logo = None
    operator = ""
    technology = ""
    signal_quality = None
    cellular = None
    last_cellular_check = 0.0
    last_isp_check = -ISP_CHECK_INTERVAL
    isp_brand = ""
    last_logo_source = None
    last_logo_attempt = 0.0
    last_route_signature = None
    last_logo_mode = read_logo_mode()

    while True:
        time.sleep(1)
        curr_rx, curr_tx = get_net_stats()
        speed_rx_kbps = max(0.0, (curr_rx - last_rx) / 1024)
        speed_tx_kbps = max(0.0, (curr_tx - last_tx) / 1024)
        last_rx, last_tx = curr_rx, curr_tx

        # Refresh network identity promptly after changing Wi-Fi/router/provider.
        now = time.monotonic()
        route_signature = get_default_route_signature()
        route_changed = (last_route_signature is not None and
                         route_signature != last_route_signature)
        if route_signature != last_route_signature:
            last_route_signature = route_signature
        if route_changed:
            # Never keep showing the previous provider while the new one is being detected.
            logo = None
            last_logo_source = None
            isp_brand = ""
            last_isp_check = -ISP_CHECK_INTERVAL

        # Keep the speed refresh at one second, but query ModemManager only every 5 seconds.
        if now - last_cellular_check >= 5 or route_changed:
            cellular = get_active_cellular_modem()
            last_cellular_check = now
            signature = None
            if cellular:
                # When the OS has an active cellular connection, prefer the modem's
                # actual operator and avoid the extra public-IP lookup.
                operator = cellular.get("operator", "")
                technology = cellular.get("technology", "")
                signal_quality = cellular.get("signal_quality")
                signature = ("cellular", cellular.get("modem_id", ""), operator.casefold())
                # Retry a failed logo load periodically even if the operator name
                # stays the same. This avoids getting stuck with an empty logo after
                # a transient download/cache/read failure. Never retry more often
                # than once every 15 seconds.
                if (signature != last_cellular_signature or
                        (operator and not logo and now - last_logo_attempt >= 15)):
                    last_cellular_signature = signature
                    last_logo_source = signature
                    if operator:
                        last_logo_attempt = now
                        logo_path = download_operator_logo(operator)
                        logo = load_logo(logo_path, read_logo_mode())
                    else:
                        logo = None
            else:
                last_cellular_signature = None
                operator = ""
                technology = ""
                signal_quality = None
                # On Wi-Fi/Ethernet, infer the provider from public-IP ASN metadata.
                # Recheck periodically and immediately after a route/connection change.
                if now - last_isp_check >= ISP_CHECK_INTERVAL or route_changed:
                    isp_brand = get_public_isp_brand()
                    last_isp_check = now
                signature = ("isp", isp_brand.casefold()) if isp_brand else None
                if (signature != last_logo_source or
                        (isp_brand and not logo and now - last_logo_attempt >= 15)):
                    last_logo_source = signature
                    # Clear the previous provider's logo even if the new ISP is unknown
                    # or does not have one of the explicitly supported logos.
                    if isp_brand:
                        last_logo_attempt = now
                        logo_path = download_operator_logo(isp_brand)
                        logo = load_logo(logo_path, read_logo_mode())
                    else:
                        logo = None

        current_logo_mode = read_logo_mode()
        if current_logo_mode != last_logo_mode:
            last_logo_mode = current_logo_mode
            if cellular and operator:
                logo = load_logo(download_operator_logo(operator), current_logo_mode)
            elif isp_brand:
                logo = load_logo(download_operator_logo(isp_brand), current_logo_mode)

        rx_str = format_speed(speed_rx_kbps)
        tx_str = format_speed(speed_tx_kbps)
        # Build a more polished, dark-theme-friendly status icon: colored signal
        # bars, cached operator artwork, white technology label, and distinct
        # green/blue traffic arrows. Keep the image compact for the top panel.
        font = get_font(10)
        small_font = get_font(10)
        pad = 4
        gap = 5
        bar_width = 2
        bar_gap = 2
        bar_heights = (4, 7, 10, 13)
        # Signal bars represent ModemManager's reported signal quality.
        # Without a connected cellular modem, keep the signal graphic hidden.
        active_bars = (max(1, min(4, (signal_quality + 24) // 25))
                       if cellular and signal_quality is not None and signal_quality > 0 else 0)
        signal_w = (len(bar_heights) * bar_width + (len(bar_heights) - 1) * bar_gap) if cellular else 0
        # Render the cellular generation inside the signal-strength graphic
        # instead of as a separate, visually noisy label.
        tech = technology if cellular else ""
        tech_label = {
            "4G/LTE": "4G", "LTE": "4G", "4G": "4G",
            "3G": "3G", "2G": "2G", "5G": "5G",
        }.get(tech, tech.upper()[:3] if tech else "")
        tx_box = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), tx_str, font=small_font)
        rx_box = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), rx_str, font=small_font)
        tx_w = tx_box[2] - tx_box[0]
        rx_w = rx_box[2] - rx_box[0]
        arrow_w = 8
        traffic_w = arrow_w + 2 + tx_w + gap + arrow_w + 2 + rx_w
        logo_w = LOGO_SIZE[0] if logo else 0
        sep_w = 1 if cellular else 0
        img_w = pad * 2 + signal_w + (gap if cellular else 0)
        if logo:
            img_w += logo_w + gap
        # No separate technology text box: the compact label is drawn with
        # the signal bars below, keeping the tray icon narrower.
        if cellular:
            img_w += sep_w + gap
        img_w += traffic_w
        img_h = 24
        img = Image.new('RGB', (img_w, img_h), color=(24, 27, 32))
        draw = ImageDraw.Draw(img)
        x = pad
        # Windows-7-inspired glossy signal bars; active count follows real modem quality.
        if cellular:
            base_y = img_h - 3
            for index, h in enumerate(bar_heights):
                active = index < active_bars
                fill = (32, 205, 111) if active else (66, 74, 83)
                highlight = (151, 255, 190) if active else (112, 119, 128)
                bx = x
                draw.rounded_rectangle((bx, base_y - h, bx + bar_width - 1, base_y),
                                       radius=1, fill=fill)
                if h >= 7:
                    draw.line((bx, base_y - h + 1, bx, base_y - 2), fill=highlight, width=1)
                x += bar_width + bar_gap
            x += gap - bar_gap
            # Small, high-contrast generation label integrated with the bars.
            # Place it immediately above the bars so it reads as one signal icon.
            if tech_label:
                label_font = get_font(8)
                label_box = draw.textbbox((0, 0), tech_label, font=label_font)
                label_w = label_box[2] - label_box[0]
                label_h = label_box[3] - label_box[1]
                label_x = pad + max(0, (signal_w - label_w) // 2)
                label_y = 0
                draw.rounded_rectangle(
                    (label_x - 1, label_y, label_x + label_w + 1, label_y + label_h + 1),
                    radius=1, fill=(24, 27, 32)
                )
                draw.text((label_x, label_y), tech_label,
                          fill=(245, 247, 250), font=label_font)
        if logo:
            img.paste(logo, (x, (img_h - LOGO_SIZE[1]) // 2), logo)
            x += logo_w + gap
        # Upload/download: clean, compact beveled arrows inspired by Windows 7.
        # Use filled polygons (not overlapping thick lines) so the shapes stay crisp
        # at the 24px panel-icon size.
        mid_y = img_h // 2
        up_x = x
        # soft shadow, then a bright green upward arrow
        draw.polygon([(up_x + 3, mid_y - 5), (up_x + 7, mid_y - 1),
                      (up_x + 5, mid_y - 1), (up_x + 5, mid_y + 5),
                      (up_x + 1, mid_y + 5), (up_x + 1, mid_y - 1),
                      (up_x - 1, mid_y - 1)], fill=(8, 45, 28))
        draw.polygon([(up_x + 3, mid_y - 5), (up_x + 6, mid_y - 2),
                      (up_x + 4, mid_y - 2), (up_x + 4, mid_y + 4),
                      (up_x + 2, mid_y + 4), (up_x + 2, mid_y - 2),
                      (up_x, mid_y - 2)], fill=(54, 220, 112))
        draw.line((up_x + 2, mid_y + 3, up_x + 2, mid_y - 1), fill=(177, 255, 192), width=1)
        x += arrow_w + 2
        draw.text((x, (img_h - 10) // 2 - 1), tx_str, fill=(240, 243, 247), font=small_font)
        x += tx_w + gap
        down_x = x
        # matching glossy blue downward arrow
        draw.polygon([(down_x + 3, mid_y + 5), (down_x + 7, mid_y + 1),
                      (down_x + 5, mid_y + 1), (down_x + 5, mid_y - 5),
                      (down_x + 1, mid_y - 5), (down_x + 1, mid_y + 1),
                      (down_x - 1, mid_y + 1)], fill=(12, 35, 70))
        draw.polygon([(down_x + 3, mid_y + 5), (down_x + 6, mid_y + 2),
                      (down_x + 4, mid_y + 2), (down_x + 4, mid_y - 4),
                      (down_x + 2, mid_y - 4), (down_x + 2, mid_y + 2),
                      (down_x, mid_y + 2)], fill=(62, 157, 255))
        draw.line((down_x + 2, mid_y - 3, down_x + 2, mid_y + 1), fill=(183, 222, 255), width=1)
        x += arrow_w + 2
        draw.text((x, (img_h - 10) // 2 - 1), rx_str, fill=(240, 243, 247), font=small_font)
        icon.icon = img
        icon.title = f"NetMon | {technology}" if cellular and technology else "NetMon Speed"


def main():
    init_img = Image.new('RGB', (40, 24), color=(25, 25, 25))
    menu = pystray.Menu(
        pystray.MenuItem("حالت لوگو", lambda icon, item: None, enabled=False),
        pystray.MenuItem("لوگوی رسمی کامل", lambda icon, item: choose_logo_mode(icon, "official"),
                         checked=lambda item: read_logo_mode() == "official"),
        pystray.MenuItem("نمادمحور (برش مربعی)", lambda icon, item: choose_logo_mode(icon, "symbol"),
                         checked=lambda item: read_logo_mode() == "symbol"),
    )
    icon = pystray.Icon("netmon", init_img, "NetMon Speed", menu=menu)
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
    
    dpkg-deb --build "$deb_dir" "$tmp_dir/netmon-speed_1.4.9_amd64.deb" 2>/dev/null
    sudo dpkg -i "$tmp_dir/netmon-speed_1.4.9_amd64.deb" 2>/dev/null
    sudo apt-get install -f -y 2>/dev/null
    
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
    echo "در حال حذف نمایشگر سرعت اینترنت..."
    
    if pgrep -f "netmon.py" > /dev/null; then
        echo "  متوقف کردن برنامه..."
        pkill -f netmon.py
        sleep 1
    fi
    
    sudo dpkg --purge netmon-speed 2>/dev/null
    
    echo ""
    echo "✅ برنامه با موفقیت حذف شد."
    echo ""
}

netmon_update() {
    echo ""
    echo "بررسی بروزرسانی..."
    echo "  نسخه فعلی: 1.4.9"
    echo "  آخرین نسخه: 1.4.9"
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
                sudo snap remove remmina || return 1
            fi
            sudo apt update && sudo apt install -y remmina remmina-plugin-rdp remmina-plugin-vnc remmina-plugin-secret gnome-keyring || return 1
            echo "اجرای Remmina..."
            (remmina >/dev/null 2>&1 &)
            ;;
        vscode)
            echo "در حال نصب Visual Studio Code از مخزن رسمی Microsoft..."
            if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
                sudo apt update && sudo apt install -y curl gpg ca-certificates
            fi
            sudo install -d -m 0755 /etc/apt/keyrings || return 1
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg || return 1
            sudo chmod a+r /etc/apt/keyrings/microsoft.gpg
            printf '%s\n' 'Types: deb' 'URIs: https://packages.microsoft.com/repos/code' 'Suites: stable' 'Components: main' 'Architectures: amd64 arm64 armhf' 'Signed-By: /etc/apt/keyrings/microsoft.gpg' | sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null || return 1
            sudo apt update && sudo apt install -y code || return 1
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
            sudo apt install -y "$tmp_deb"
            local result=$?
            rm -f "$tmp_deb"
            [ "$result" -eq 0 ] || return "$result"
            ;;
        git)
            echo "در حال نصب Git..."
            sudo apt-get update && sudo apt-get install -y git || return 1
            git --version
            ;;
        npm)
            echo "در حال نصب Node.js و npm از مخازن Ubuntu..."
            sudo apt-get update && sudo apt-get install -y nodejs npm || return 1
            node --version 2>/dev/null || true
            npm --version 2>/dev/null || true
            ;;
        python)
            echo "در حال نصب Python 3، pip و محیط مجازی..."
            sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv python3-dev || return 1
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
            sudo apt install -y "$tmp_deb"
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
        sudo apt-get update && sudo apt-get install -y curl || return 1
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
    sudo mkdir -p "$backup_dir" || return 1
    local source_files=()
    [ -f /etc/apt/sources.list ] && source_files+=(/etc/apt/sources.list)
    while IFS= read -r -d '' file; do source_files+=("$file"); done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print0 2>/dev/null)

    for file in "${source_files[@]}"; do
        if sudo grep -Eq '(^|[[:space:]])(https?://)?(archive\.ubuntu\.com/ubuntu|security\.ubuntu\.com/ubuntu|ports\.ubuntu\.com/ubuntu|[a-z]{2}\.archive\.ubuntu\.com/ubuntu)' "$file"; then
            local relative="${file#/etc/apt/}"
            sudo mkdir -p "$backup_dir/$(dirname "$relative")"
            sudo cp -a "$file" "$backup_dir/$relative" || { failed=1; break; }
            sudo sed -i -E \
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
    if sudo apt-get update; then
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
            if sudo test -f "$backup_dir/$relative"; then sudo cp -a "$backup_dir/$relative" "$file"; fi
        done
        sudo apt-get update
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
        echo "  sudo apt install curl"
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
    sudo apt-get update && sudo apt-get install -y fprintd libfprint-2-2 || return 1

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
    if ! sudo systemctl restart fprintd; then
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
    echo "║                         جعبه‌ابزار شخصی ایرج (v3.6)                          ║"
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

# ──────────────────────────────────────────────────────────
# حلقه اصلی
# ──────────────────────────────────────────────────────────
while true; do
    show_main_menu
    if [ "$choice" = "0" ]; then
        echo ""
        echo "خدانگهدار! 👋"
        exit 0
    fi
    run_toolbox_action "$choice"
    result=$?
    [ "$result" -eq 10 ] && exit 0
done

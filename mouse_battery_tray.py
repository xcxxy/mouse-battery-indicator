# -*- coding: utf-8 -*-
"""
多品牌无线鼠标电量托盘
======================
无驱动、无官方软件，直接走 HID 厂商自定义接口读电量。

支持（自动识别）：
  - 迈从 MCHOSE A7 系列（VID 0x5253 / 0x3837）——已验证
  - 罗技 Logitech（VID 0x046D，HID++ 2.0 协议）——实验性
  - 通用 HID Battery Strength（Usage Page 0x06, Usage 0x20）——自动扫描

颜色规则：
  - 电量 < 20%   红色
  - 电量 > 80%   绿色
  - 其他         白色
  - 充电中       左上角黄色 ⚡

托盘显示：多个设备同时连接时，取最低电量值显示，tooltip 列出全部设备。
"""

import hid
import time
import threading
import queue
from PIL import Image, ImageDraw, ImageFont
import pystray
from pystray import MenuItem, Menu

POLL_INTERVAL = 5          # 秒
READ_TIMEOUT_MS = 2000

state_q = queue.Queue()


# ============================================================
# 驱动基类
# ============================================================
class BatteryDriver:
    name = "Unknown"
    vendor_id = 0
    product_id = 0

    def __init__(self, dev_info):
        self.info = dev_info
        self.name = dev_info.get("product_string") or f"{self.__class__.__name__}"
        self.vendor_id = dev_info["vendor_id"]
        self.product_id = dev_info["product_id"]
        self.path = dev_info["path"]

    def read(self):
        """返回 {'battery': int, 'charging': bool} 或 None"""
        raise NotImplementedError

    def close(self):
        pass


# ============================================================
# 迈从 MCHOSE（已验证）
# ============================================================
class MchoseDriver(BatteryDriver):
    VIDS = (0x5253, 0x3837)
    USAGE_PAGE = 0xFF01
    REPORT_CMD = 0x11
    REPORT_INPUT = 0x13

    def __init__(self, dev_info):
        super().__init__(dev_info)
        self.dev = hid.device()
        self.dev.open_path(self.path)

    def read(self):
        # 构造 feature report: [0x11, 0xF4, 0x55, 0xFF*62]
        pkt = bytearray(65)
        pkt[0] = self.REPORT_CMD
        pkt[1] = 0x0B ^ 0xFF
        pkt[2] = 0xAA ^ 0xFF
        for i in range(3, 65):
            pkt[i] = 0xFF
        try:
            self.dev.send_feature_report(list(pkt))
        except Exception:
            return None
        # 设备先回 ACK(0xE5) 再回状态(0xE2)，连续读直到 E2
        for _ in range(5):
            try:
                raw = self.dev.read(64, timeout_ms=READ_TIMEOUT_MS)
            except Exception:
                raw = None
            if not raw or raw[0] != self.REPORT_INPUT:
                continue
            payload = bytearray(raw[1:])
            for i in range(len(payload)):
                payload[i] ^= 0xFF
            if payload[0] != 0xE2 or len(payload) < 17:
                continue
            return {
                "battery": payload[4],
                "charging": payload[3] != 0,
            }
        return None

    def close(self):
        try:
            self.dev.close()
        except Exception:
            pass


# ============================================================
# ATK（烈空/蜻蜓/鸭嘴兽等，VXE/ATK Gear 同厂）
# 协议来源：ATK HUB v3.0 网页版 WebHID 逆向
# VID=0x373B, usagePage=0xFF05, reportId=8, 帧长63字节
# ============================================================
class AtkDriver(BatteryDriver):
    VIDS = (0x373B,)
    USAGE_PAGE = 0xFF05
    REPORT_ID = 8
    CMD_BATTERY = 7
    CMD_CHARGING = 15
    BASE_OFFSET = 7
    FRAME_LEN = 63

    def __init__(self, dev_info):
        super().__init__(dev_info)
        self.dev = hid.device()
        self.dev.open_path(self.path)
        self._req_code = 0

    def _build_frame(self, command_id):
        """构造63字节请求帧：[req_hi, req_lo, cmd, 0,0,0,0, ...]"""
        self._req_code = (self._req_code + 1) % 65535
        if self._req_code == 0:
            self._req_code = 1
        frame = bytearray(self.FRAME_LEN)
        frame[0] = (self._req_code >> 8) & 0xFF   # requestCode 大端
        frame[1] = self._req_code & 0xFF
        frame[2] = command_id & 0xFF
        return frame

    def _send_and_recv(self, command_id, timeout_ms=1500):
        frame = self._build_frame(command_id)
        try:
            self.dev.send_report(self.REPORT_ID, list(frame))
        except Exception:
            return None
        target_req = self._req_code
        for _ in range(5):
            try:
                raw = self.dev.read(64, timeout_ms=timeout_ms)
            except Exception:
                raw = None
            if not raw:
                continue
            # raw[0] = reportId, 后面是63字节payload
            if raw[0] != self.REPORT_ID:
                continue
            payload = raw[1:]
            if len(payload) < self.BASE_OFFSET + 1:
                continue
            req_hi = payload[0]
            req_lo = payload[1]
            resp_req = (req_hi << 8) | req_lo
            if resp_req != target_req:
                continue  # 不是我们这次请求的响应
            return payload
        return None

    def read(self):
        # 先读电量
        batt_payload = self._send_and_recv(self.CMD_BATTERY)
        if not batt_payload:
            return None
        battery = batt_payload[self.BASE_OFFSET]
        # 再读充电状态（失败不影响电量显示）
        charge_payload = self._send_and_recv(self.CMD_CHARGING)
        charging = False
        if charge_payload:
            charging = charge_payload[self.BASE_OFFSET] != 0
        return {"battery": battery, "charging": charging}

    def close(self):
        try:
            self.dev.close()
        except Exception:
            pass


# ============================================================
# 罗技 Logitech HID++ 2.0（实验性）
# ============================================================
class LogitechDriver(BatteryDriver):
    VIDS = (0x046D,)

    def __init__(self, dev_info):
        super().__init__(dev_info)
        self.dev = hid.device()
        self.dev.open_path(self.path)
        self._batt_idx = None
        self._dev_idx = None

    def _hidpp(self, feature_idx, func=0, params=None, dev_idx=0):
        """发 HID++ 2.0 短消息，返回响应 payload 或 None"""
        if params is None:
            params = []
        msg = bytearray(20)
        msg[0] = 0x11  # long report (HID++ 用 0x11 比较稳)
        msg[1] = (dev_idx << 4) & 0xFF
        msg[2] = (feature_idx >> 4) & 0xFF
        msg[3] = ((feature_idx & 0x0F) << 4) & 0xFF
        for i, p in enumerate(params[:13]):
            msg[4 + i] = p & 0xFF
        try:
            self.dev.send_feature_report(list(msg))
        except Exception:
            return None
        for _ in range(4):
            try:
                raw = self.dev.read(64, timeout_ms=1000)
            except Exception:
                raw = None
            if not raw:
                continue
            if raw[0] not in (0x10, 0x11):
                continue
            return list(raw[1:])
        return None

    def _discover_battery(self):
        """通过 root feature 0x0000 查找 battery feature 0x1000 的 index"""
        for d_idx in [0, 1, 2, 3, 4, 5]:
            try:
                resp = self._hidpp(0x0000, 0, [0x10, 0x00], dev_idx=d_idx)
            except Exception:
                continue
            if resp and len(resp) >= 4:
                idx = resp[3]
                if 0 < idx < 0x10:
                    self._batt_idx = idx
                    self._dev_idx = d_idx
                    return True
        return False

    def read(self):
        if self._batt_idx is None:
            if not self._discover_battery():
                return None
        try:
            resp = self._hidpp(self._batt_idx, 0, dev_idx=self._dev_idx)
        except Exception:
            return None
        if not resp or len(resp) < 6:
            return None
        # HID++ 2.0 BatteryStatus: byte 4=level(0-100), byte 5=status
        level = resp[4]
        status = resp[5]
        if level == 0xFF:
            return None
        charging = status in (1, 2, 4)
        return {"battery": level, "charging": charging}

    def close(self):
        try:
            self.dev.close()
        except Exception:
            pass


# ============================================================
# 通用 HID Battery Strength（标准 USB HID 规范）
# ============================================================
class GenericBatteryDriver(BatteryDriver):
    """扫描 usage_page=0x06 (Generic Desktop) 且 usage=0x20 (Battery Strength) 的设备"""

    @classmethod
    def matches(cls, dev_info):
        return dev_info.get("usage_page") == 0x06 and dev_info.get("usage") == 0x20

    def __init__(self, dev_info):
        super().__init__(dev_info)
        self.dev = hid.device()
        self.dev.open_path(self.path)

    def read(self):
        # 标准 HID Battery Strength feature report
        # 尝试读 report ID 0
        try:
            raw = self.dev.get_feature_report(0, 64)
        except Exception:
            try:
                raw = self.dev.read(64, timeout_ms=1000)
            except Exception:
                return None
        if not raw:
            return None
        # Battery Strength 通常是 0-100 或 0-255
        for b in raw[1:]:
            if 0 <= b <= 100:
                return {"battery": b, "charging": False}
        return None

    def close(self):
        try:
            self.dev.close()
        except Exception:
            pass


# ============================================================
# 设备扫描 & 驱动注册
# ============================================================
DRIVER_CLASSES = [MchoseDriver, AtkDriver, LogitechDriver]


def detect_drivers():
    """枚举所有 HID 设备，返回能识别的驱动实例列表"""
    drivers = []
    seen = set()
    for d in hid.enumerate():
        path = d["path"]
        if path in seen:
            continue
        # 专用驱动
        for cls in DRIVER_CLASSES:
            expected_up = getattr(cls, "USAGE_PAGE", None)
            if d["vendor_id"] in cls.VIDS and (expected_up is None or d.get("usage_page") == expected_up):
                try:
                    drv = cls(d)
                    drivers.append(drv)
                    seen.add(path)
                    break
                except Exception:
                    continue
        # 通用电池驱动
        if GenericBatteryDriver.matches(d):
            try:
                drv = GenericBatteryDriver(d)
                drivers.append(drv)
                seen.add(path)
            except Exception:
                continue
    return drivers


# ============================================================
# 后台采集线程
# ============================================================
def worker():
    while True:
        drivers = detect_drivers()
        if not drivers:
            state_q.put({"devices": [], "error": "未识别到支持的无线鼠标"})
            time.sleep(POLL_INTERVAL)
            continue

        results = []
        for drv in drivers:
            try:
                r = drv.read()
                if r:
                    results.append({
                        "name": drv.name,
                        "vid": drv.vendor_id,
                        "pid": drv.product_id,
                        "battery": r["battery"],
                        "charging": r["charging"],
                    })
            except Exception:
                pass
            finally:
                drv.close()

        state_q.put({"devices": results, "error": None if results else "设备无响应"})
        time.sleep(POLL_INTERVAL)


# ============================================================
# 托盘图标
# ============================================================
def color_for(battery):
    if battery < 0:
        return (180, 180, 180, 255)
    if battery < 20:
        return (231, 76, 60, 255)
    if battery > 80:
        return (46, 204, 113, 255)
    return (236, 240, 241, 255)


def make_icon(min_battery, any_charging):
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = color_for(min_battery)

    # 电池外框
    x0, y0, x1, y1 = 6, 18, 48, 46
    draw.rounded_rectangle([x0, y0, x1, y1], radius=4, outline=color, width=3)
    draw.rectangle([x1 + 2, y0 + 8, x1 + 8, y1 - 8], fill=color)

    # 电量填充
    if min_battery >= 0:
        fill_w = int((x1 - x0 - 6) * (min_battery / 100.0))
        if fill_w > 0:
            draw.rectangle([x0 + 3, y0 + 3, x0 + 3 + fill_w, y1 - 3], fill=color)

    # 数字
    try:
        font = ImageFont.truetype("C:\\Windows\\Fonts\\arialbd.ttf", 22)
    except Exception:
        font = ImageFont.load_default()
    label = "--" if min_battery < 0 else f"{min_battery}"
    bbox = draw.textbbox((0, 0), label, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((size - tw) / 2 - bbox[0], (size - th) / 2 - bbox[1]),
              label, fill=color, font=font)

    if any_charging:
        try:
            cfont = ImageFont.truetype("C:\\Windows\\Fonts\\arialbd.ttf", 16)
            draw.text((2, 0), "⚡", fill=(241, 196, 15, 255), font=cfont)
        except Exception:
            pass
    return img


def main():
    latest = {"devices": [], "error": "初始化…"}

    def update_icon(icon):
        try:
            while True:
                s = state_q.get_nowait()
                latest.update(s)
        except queue.Empty:
            pass

        devs = latest["devices"]
        if devs:
            min_batt = min(d["battery"] for d in devs)
            any_charging = any(d["charging"] for d in devs)
            icon.icon = make_icon(min_batt, any_charging)
            # tooltip：列出所有设备
            lines = []
            for d in devs:
                b = "--" if d["battery"] < 0 else f"{d['battery']}%"
                c = " · 充电中" if d["charging"] else ""
                lines.append(f"{d['name']}: {b}{c}")
            icon.title = "\n".join(lines)
        else:
            icon.icon = make_icon(-1, False)
            icon.title = latest.get("error") or "未识别到设备"

    def on_refresh(icon, item):
        update_icon(icon)

    def on_quit(icon, item):
        icon.stop()

    menu = Menu(
        MenuItem("刷新", on_refresh, default=True),
        MenuItem("退出", on_quit),
    )

    icon = pystray.Icon("wireless_battery", make_icon(-1, False),
                        "无线鼠标电量", menu)

    threading.Thread(target=worker, daemon=True).start()

    def poll_ui():
        while True:
            update_icon(icon)
            time.sleep(2)
    threading.Thread(target=poll_ui, daemon=True).start()

    icon.run()


if __name__ == "__main__":
    main()

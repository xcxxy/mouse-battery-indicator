# mouse-battery-indicator
鼠标托盘电量指示器，Windows 右下角托盘显示无线鼠标电量，**无需官方驱动**

## ✨ 支持设备
- ✅ 迈从 MCHOSE A7 Pro（实测稳定可用）
- ⚠️ ATK / VXE 系列（协议逆向自官方Hub，需要实机验证）
- ⚠️ 罗技 Logitech HID++ 2.0（Unifying / Bolt 接收器，部分型号可能不兼容）

> 其他品牌（雷蛇、雷柏等）暂未适配，每个厂商为私有HID协议，需要单独抓包逆向。

## 🎨 电量颜色规则
- 电量 ＜ 20%：图标红色（低电量提醒）
- 电量 ＞ 80%：图标绿色
- 20% ≤ 电量 ≤ 80%：图标白色

## 📦 源码使用方式
### 环境依赖
Python 3.8+
```bash
pip install -r requirements.txt
### 依赖清单
```plaintext
pystray
hidapi
pillow
```

### 启动（Windows后台静默运行，无黑窗口）
```bash
pythonw mouse_battery_tray.py
```

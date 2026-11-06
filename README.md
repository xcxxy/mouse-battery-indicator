# Mouse Battery Tray

一个运行在 Windows 系统托盘中的鼠标电量查看小工具。读取电量使用鼠标或接收器的 HID 接口，不需要打开鼠标厂商驱动软件。

## 当前适配名单

以下是代码中按 USB VID/PID 和 HID 接口特征识别的设备。**这不代表同一品牌的所有型号都兼容，也不代表名单中的每个型号都已在实机上验证。**

| 品牌 / 型号 | 识别条件 | 状态说明 |
|---|---|---|
| MCHOSE A7 Pro | VID `5253`、PID `1021`、Usage Page `FF01` | 已在 MCHOSE A7 Pro 2.4G 接收器上实测读取到电量 |
| Razer Lancehead Wireless | VID `1532`、PID `0070` | 代码已适配，未实机验证 |
| Razer Mamba Wireless | VID `1532`、PID `0072` 或 `0073` | 代码已适配，未实机验证 |
| Razer Pro Click | VID `1532`、PID `0077` 或 `0080` | 代码已适配，未实机验证 |
| Razer Viper Ultimate | VID `1532`、PID `007A` 或 `007B` | 代码已适配，未实机验证 |
| Razer DeathAdder V2 Pro | VID `1532`、PID `007C` 或 `007D` | 代码已适配，未实机验证 |
| Razer Basilisk X HyperSpeed | VID `1532`、PID `0083` | 代码已适配，未实机验证 |
| Razer Basilisk Ultimate | VID `1532`、PID `0086` 或 `0088` | 代码已适配，未实机验证 |
| Razer Naga Pro | VID `1532`、PID `008F` 或 `0090` | 代码已适配，未实机验证 |
| Razer Orochi V2 | VID `1532`、PID `0094` | 代码已适配，未实机验证 |
| ATK / BITMOUSE 有线设备 | VID `373B`、PID `1264`、Usage Page `FF05` | 代码已适配，未实机验证 |
| ATK / BITMOUSE 接收器 | VID `373B`、PID `11DC`、Usage Page `FF05` | 代码已适配，未实机验证 |

支持范围取决于设备实际暴露的 USB ID、HID 接口和固件协议。相同商品名的不同版本、连接模式或接收器可能使用不同 ID；VXE、VGN 或其他 ATK 型号不会因为品牌相同就自动兼容。

目前尚未验证多只受支持鼠标同时连接时的选择行为；程序会使用 Windows 枚举到的第一个受支持接口。

## 功能

- 在系统托盘显示电池图标，悬停可查看电量。
- 电量 `≥80%` 显示绿色，`≤20%` 显示红色，其他电量显示白色；暂时无法读取时显示灰色。
- 电量低时显示提醒。
- 每 5 分钟自动刷新，也可以从托盘菜单手动刷新。
- 托盘菜单可切换“登录时启动”。

## 运行

需要 Windows 和内置的 Windows PowerShell。下载或克隆项目后，在脚本所在目录运行：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\Mouse-Battery-Tray.ps1"
```

普通启动时，程序会默认设置为当前 Windows 用户登录时启动；可在托盘图标的右键菜单中关闭该选项。右键菜单也提供手动刷新和退出。

## 诊断

只枚举鼠标和厂商 HID 接口，不发送设备报文：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\Mouse-Battery-Tray.ps1" -ListHidDevices
```

手动读取首个识别到的受支持设备时，程序会先要求输入 `READ` 确认，然后发送该适配器的电量读取请求：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\Mouse-Battery-Tray.ps1" -ReadBattery
```

`-TestMode` 可用于短暂启动托盘界面；测试窗口会在 8 秒后自动关闭，且不会设置登录启动：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\Mouse-Battery-Tray.ps1" -TestMode
```

## 安全与限制

- 对未知 HID 设备，`-ListHidDevices` 仅列出接口信息，不会尝试发送电量命令。
- 电量查询与 DPI/配置写入是不同的协议操作；本项目中的适配器只实现电量读取，不实现 DPI 修改。
- 各品牌协议适配的验证程度不同。除 MCHOSE A7 Pro 外，其他名单设备目前尚未在实机上验证；请在自己的设备上谨慎测试。
- 代码已在 Windows 11 的 Windows PowerShell 5.1 环境通过 PowerShell 语法与内嵌 C# 编译检查；这不等于所有设备型号均已验证。

## 文件

- `Mouse-Battery-Tray.ps1`：托盘程序及 HID 电量适配器。

# Battery tray for selected wireless mice with an optional read-only probe.
param(
    [switch]$ReadBattery,
    [switch]$TestMode,
    [switch]$ListHidDevices
)

$ErrorActionPreference = 'Stop'

$nativeCode = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public sealed class MouseHidDevice
{
    public string Path;
    public string Name;
    public ushort VendorId;
    public ushort ProductId;
    public byte TransactionId;
    public ushort Usage;
    public ushort UsagePage;
    public ushort InputReportByteLength;
    public ushort OutputReportByteLength;
    public ushort FeatureReportByteLength;
}

public static class MouseBatteryAdapters
{
    private const uint DIGCF_PRESENT = 0x00000002;
    private const uint DIGCF_DEVICEINTERFACE = 0x00000010;
    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_OVERLAPPED = 0x40000000;
    private const uint ERROR_IO_PENDING = 997;
    private const uint WAIT_OBJECT_0 = 0;
    private const uint WAIT_TIMEOUT = 258;
    private const ushort TargetVid = 0x5253;
    private const ushort TargetPid = 0x1021;
    private const ushort TargetUsagePage = 0xFF01;
    private const ushort RazerVid = 0x1532;
    private const ushort AtkVid = 0x373B;
    private const ushort AtkWiredPid = 0x1264;
    private const ushort AtkDonglePid = 0x11DC;
    private const ushort AtkUsagePage = 0xFF05;

    [StructLayout(LayoutKind.Sequential)]
    private struct DeviceInterfaceData
    {
        public int Size;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    private struct HidCaps
    {
        public ushort Usage;
        public ushort UsagePage;
        public ushort InputReportByteLength;
        public ushort OutputReportByteLength;
        public ushort FeatureReportByteLength;
        public ushort Reserved0;
        public ushort Reserved1;
        public ushort Reserved2;
        public ushort Reserved3;
        public ushort Reserved4;
        public ushort Reserved5;
        public ushort Reserved6;
        public ushort Reserved7;
        public ushort Reserved8;
        public ushort Reserved9;
        public ushort Reserved10;
        public ushort Reserved11;
        public ushort Reserved12;
        public ushort Reserved13;
        public ushort Reserved14;
        public ushort Reserved15;
        public ushort Reserved16;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps;
        public ushort NumberInputValueCaps;
        public ushort NumberInputDataIndices;
        public ushort NumberOutputButtonCaps;
        public ushort NumberOutputValueCaps;
        public ushort NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps;
        public ushort NumberFeatureValueCaps;
        public ushort NumberFeatureDataIndices;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HidAttributes
    {
        public int Size;
        public ushort VendorId;
        public ushort ProductId;
        public ushort VersionNumber;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeOverlapped
    {
        public IntPtr Internal;
        public IntPtr InternalHigh;
        public int Offset;
        public int OffsetHigh;
        public IntPtr EventHandle;
    }

    [DllImport("hid.dll")]
    private static extern void HidD_GetHidGuid(out Guid hidGuid);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr SetupDiGetClassDevs(
        ref Guid classGuid, string enumerator, IntPtr hwndParent, uint flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiEnumDeviceInterfaces(
        IntPtr deviceInfoSet, IntPtr deviceInfoData, ref Guid interfaceClassGuid,
        uint memberIndex, ref DeviceInterfaceData deviceInterfaceData);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(
        IntPtr deviceInfoSet, ref DeviceInterfaceData deviceInterfaceData,
        IntPtr deviceInterfaceDetailData, int deviceInterfaceDetailDataSize,
        out int requiredSize, IntPtr deviceInfoData);

    [DllImport("setupapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
        uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("hid.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_GetAttributes(
        SafeFileHandle device, ref HidAttributes attributes);

    [DllImport("hid.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_GetPreparsedData(
        SafeFileHandle device, out IntPtr preparsedData);

    [DllImport("hid.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_FreePreparsedData(IntPtr preparsedData);

    [DllImport("hid.dll")]
    private static extern int HidP_GetCaps(IntPtr preparsedData, out HidCaps capabilities);

    [DllImport("hid.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_SetFeature(SafeFileHandle device, byte[] report, int length);

    [DllImport("hid.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_GetFeature(SafeFileHandle device, byte[] report, int length);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WriteFile(
        SafeFileHandle file, byte[] buffer, uint bytesToWrite,
        out uint bytesWritten, ref NativeOverlapped overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReadFile(
        SafeFileHandle file, byte[] buffer, uint bytesToRead,
        out uint bytesRead, ref NativeOverlapped overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateEvent(
        IntPtr eventAttributes, bool manualReset, bool initialState, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetOverlappedResult(
        SafeFileHandle file, ref NativeOverlapped overlapped, out uint transferred,
        bool wait);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CancelIoEx(
        SafeFileHandle file, ref NativeOverlapped overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr icon);

    private static byte RazerTransactionId(ushort productId)
    {
        switch (productId)
        {
            case 0x0070: return 0x1F;
            case 0x0072:
            case 0x0073:
            case 0x007C:
            case 0x007D: return 0x3F;
            case 0x007A:
            case 0x007B: return 0xFF;
            case 0x0077:
            case 0x0080:
            case 0x0083: return productId == 0x0083 ? (byte)0xFF : (byte)0x1F;
            case 0x0086:
            case 0x0088:
            case 0x008F:
            case 0x0090:
            case 0x0094: return 0x1F;
            default: return 0;
        }
    }

    private static string RazerModel(ushort productId)
    {
        switch (productId)
        {
            case 0x0070: return "Razer Lancehead Wireless";
            case 0x0072:
            case 0x0073: return "Razer Mamba Wireless";
            case 0x0077:
            case 0x0080: return "Razer Pro Click";
            case 0x007A:
            case 0x007B: return "Razer Viper Ultimate";
            case 0x007C:
            case 0x007D: return "Razer DeathAdder V2 Pro";
            case 0x0083: return "Razer Basilisk X HyperSpeed";
            case 0x0086:
            case 0x0088: return "Razer Basilisk Ultimate";
            case 0x008F:
            case 0x0090: return "Razer Naga Pro";
            case 0x0094: return "Razer Orochi V2";
            default: return null;
        }
    }

    private static bool IsSupportedAtk(ushort vendorId, ushort productId, HidCaps caps)
    {
        return vendorId == AtkVid &&
            (productId == AtkWiredPid || productId == AtkDonglePid) &&
            caps.UsagePage == AtkUsagePage &&
            caps.InputReportByteLength >= 64 &&
            caps.OutputReportByteLength >= 64;
    }

        private static bool Transfer(
            SafeFileHandle handle, byte[] buffer, bool write, out uint transferred)
        {
            transferred = 0;
            IntPtr eventHandle = CreateEvent(IntPtr.Zero, true, false, null);
            if (eventHandle == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());

            var overlapped = new NativeOverlapped();
            overlapped.EventHandle = eventHandle;
            try
            {
                bool completed = write
                    ? WriteFile(handle, buffer, (uint)buffer.Length, out transferred, ref overlapped)
                    : ReadFile(handle, buffer, (uint)buffer.Length, out transferred, ref overlapped);
                if (!completed)
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error != ERROR_IO_PENDING)
                        throw new System.ComponentModel.Win32Exception(error);

                    uint wait = WaitForSingleObject(eventHandle, 1500);
                    if (wait == WAIT_TIMEOUT)
                    {
                        CancelIoEx(handle, ref overlapped);
                        uint ignored;
                        GetOverlappedResult(handle, ref overlapped, out ignored, true);
                        throw new TimeoutException(write
                            ? "Timed out sending the ATK battery query."
                            : "Timed out waiting for the ATK battery response.");
                    }
                    if (wait != WAIT_OBJECT_0)
                        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                    if (!GetOverlappedResult(handle, ref overlapped, out transferred, false))
                        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                }
                return true;
            }
            finally
            {
                CloseHandle(eventHandle);
            }
        }

    public static List<MouseHidDevice> FindDevices(bool includeOtherMice)
    {
        Guid hidGuid;
        HidD_GetHidGuid(out hidGuid);
        IntPtr set = SetupDiGetClassDevs(
            ref hidGuid, null, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (set == new IntPtr(-1))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());

        var devices = new List<MouseHidDevice>();
        try
        {
            for (uint index = 0; ; index++)
            {
                var interfaceData = new DeviceInterfaceData();
                interfaceData.Size = Marshal.SizeOf(typeof(DeviceInterfaceData));
                if (!SetupDiEnumDeviceInterfaces(
                    set, IntPtr.Zero, ref hidGuid, index, ref interfaceData))
                    break;

                int required;
                SetupDiGetDeviceInterfaceDetail(
                    set, ref interfaceData, IntPtr.Zero, 0, out required, IntPtr.Zero);
                if (required <= 0)
                    continue;

                IntPtr detail = Marshal.AllocHGlobal(required);
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetail(
                        set, ref interfaceData, detail, required, out required, IntPtr.Zero))
                        continue;

                    string path = Marshal.PtrToStringUni(IntPtr.Add(detail, 4));
                    SafeFileHandle openedHandle = CreateFile(
                        path, GENERIC_READ | GENERIC_WRITE,
                        FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero,
                        OPEN_EXISTING, 0, IntPtr.Zero);
                    if (openedHandle.IsInvalid)
                    {
                        openedHandle.Dispose();
                        openedHandle = CreateFile(path, 0,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero,
                            OPEN_EXISTING, 0, IntPtr.Zero);
                    }

                    using (SafeFileHandle handle = openedHandle)
                    {
                        if (handle.IsInvalid)
                            continue;

                        var attributes = new HidAttributes();
                        attributes.Size = Marshal.SizeOf(typeof(HidAttributes));
                        if (!HidD_GetAttributes(handle, ref attributes))
                            continue;

                        IntPtr preparsed;
                        if (!HidD_GetPreparsedData(handle, out preparsed))
                            continue;
                        try
                        {
                            HidCaps caps;
                            int status = HidP_GetCaps(preparsed, out caps);
                            if (status != 0x00110000)
                                continue;

                            bool isA7Pro = attributes.VendorId == TargetVid &&
                                attributes.ProductId == TargetPid &&
                                caps.UsagePage == TargetUsagePage &&
                                caps.FeatureReportByteLength >= 21;
                            byte razerTransactionId = RazerTransactionId(attributes.ProductId);
                            bool isSupportedRazer = attributes.VendorId == RazerVid &&
                                razerTransactionId != 0 &&
                                caps.UsagePage == 0x0001 && caps.Usage == 0x0002 &&
                                caps.FeatureReportByteLength >= 91;
                            bool isSupportedAtk = IsSupportedAtk(
                                attributes.VendorId, attributes.ProductId, caps);
                            bool isMouseCollection = caps.UsagePage == 0x0001 &&
                                caps.Usage == 0x0002;
                            bool isVendorCollection = caps.UsagePage >= 0xFF00 &&
                                (caps.FeatureReportByteLength > 0 ||
                                 caps.InputReportByteLength > 0);
                            if (includeOtherMice
                                ? (!isMouseCollection && !isVendorCollection)
                                : (!isA7Pro && !isSupportedRazer && !isSupportedAtk))
                                continue;

                            devices.Add(new MouseHidDevice {
                                Path = path,
                                Name = isA7Pro ? "MCHOSE A7 Pro" :
                                    (isSupportedRazer ? RazerModel(attributes.ProductId) :
                                    (isSupportedAtk ? "ATK / BITMOUSE mouse" : "Unknown")),
                                VendorId = attributes.VendorId,
                                ProductId = attributes.ProductId,
                                TransactionId = isSupportedRazer ? razerTransactionId : (byte)0,
                                Usage = caps.Usage,
                                UsagePage = caps.UsagePage,
                                InputReportByteLength = caps.InputReportByteLength,
                                OutputReportByteLength = caps.OutputReportByteLength,
                                FeatureReportByteLength = caps.FeatureReportByteLength
                            });
                        }
                        finally
                        {
                            HidD_FreePreparsedData(preparsed);
                        }
                    }
                }
                finally
                {
                    Marshal.FreeHGlobal(detail);
                }
            }
        }
        finally
        {
            SetupDiDestroyDeviceInfoList(set);
        }
        return devices;
    }

    public static int ReadBattery(MouseHidDevice target)
    {
        if (target.VendorId == RazerVid && target.TransactionId != 0)
            return ReadRazerBattery(target);

        if (target.VendorId == AtkVid &&
            (target.ProductId == AtkWiredPid || target.ProductId == AtkDonglePid))
            return ReadAtkBattery(target);

        if (target.VendorId != TargetVid || target.ProductId != TargetPid)
            throw new InvalidOperationException("No read-only battery adapter is registered for this device.");

        using (SafeFileHandle handle = CreateFile(
            target.Path, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero,
            OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (handle.IsInvalid)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());

            for (int attempt = 0; attempt < 4; attempt++)
            {
                var request = new byte[21];
                for (int i = 0; i < request.Length; i++)
                    request[i] = 0xFF;
                request[0] = 0x11;
                request[1] = 0xF9;

                if (!HidD_SetFeature(handle, request, request.Length))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),
                        "The read-only battery query could not be sent.");

                System.Threading.Thread.Sleep(60);

                var reply = new byte[21];
                reply[0] = 0x11;
                if (!HidD_GetFeature(handle, reply, reply.Length))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),
                        "The battery response could not be read.");

                if ((byte)(reply[1] ^ 0xFF) != 0x06)
                    throw new InvalidOperationException(
                        "No matching battery response. The mouse may be asleep or the protocol may differ.");

                ushort vid = (ushort)((reply[2] ^ 0xFF) | ((reply[3] ^ 0xFF) << 8));
                ushort pid = (ushort)((reply[4] ^ 0xFF) | ((reply[5] ^ 0xFF) << 8));
                if (vid == 0)
                {
                    System.Threading.Thread.Sleep(120);
                    continue;
                }

                if (vid != TargetVid)
                    throw new InvalidOperationException(
                        String.Format("The response vendor is {0:X4}, not MCHOSE 5253.", vid));

                int battery = reply[11] ^ 0xFF;
                if (battery > 100)
                    throw new InvalidOperationException(
                        "The device returned an invalid battery percentage.");
                return battery;
            }

            throw new InvalidOperationException(
                "The mouse returned an empty identity four times. Wake it and retry.");
        }
    }

    private static int ReadRazerBattery(MouseHidDevice target)
    {
        using (SafeFileHandle handle = CreateFile(
            target.Path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero,
            OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (handle.IsInvalid)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());

            var request = new byte[target.FeatureReportByteLength];
            request[0] = 0x00;
            request[1] = target.TransactionId;
            request[5] = 0x02;
            request[6] = 0x07;
            request[7] = 0x80;
            byte checksum = 0;
            for (int i = 2; i <= 87; i++)
                checksum ^= request[i];
            request[88] = checksum;

            if (!HidD_SetFeature(handle, request, request.Length))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),
                    "The Razer battery query could not be sent.");

            System.Threading.Thread.Sleep(60);

            var reply = new byte[target.FeatureReportByteLength];
            reply[0] = 0x00;
            if (!HidD_GetFeature(handle, reply, reply.Length))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),
                    "The Razer battery response could not be read.");

            if (reply[0] != 0x02 || reply[1] != target.TransactionId ||
                reply[6] != 0x07 || reply[7] != 0x80)
                throw new InvalidOperationException(
                    "The Razer interface did not return a matching battery response.");

            int rawBattery = reply[9];
            return (int)Math.Round(rawBattery * 100.0 / 255.0);
        }
    }

    private static int ReadAtkBattery(MouseHidDevice target)
    {
        using (SafeFileHandle handle = CreateFile(
            target.Path, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero,
            OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero))
        {
            if (handle.IsInvalid)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());

            byte[] request = new byte[64];
            request[0] = 0x08;
            request[2] = 0x72;
            request[3] = 0x02;
            request[5] = target.ProductId == AtkWiredPid ? (byte)0x00 : (byte)0x01;
            request[6] = 0x07;
            request[7] = 0x01;
            request[8] = 0x00;
            int checksum = 0;
            for (int i = 2; i < request.Length; i++)
                checksum = (checksum + request[i]) & 0xFF;
            request[1] = (byte)checksum;

            uint written;
            Transfer(handle, request, true, out written);
            if (written != request.Length)
                throw new InvalidOperationException("The ATK battery request was not fully sent.");

            byte[] reply = new byte[Math.Max(64, (int)target.InputReportByteLength)];
            uint received;
            Transfer(handle, reply, false, out received);
            if (received < 9 || reply[0] != 0x08 || reply[1] != 0x72 ||
                reply[2] != 0x00 || reply[4] != request[5] ||
                reply[5] != 0x07 || reply[6] < 1)
                throw new InvalidOperationException(
                    "The ATK interface did not return a matching battery response.");

            int battery = reply[7];
            if (battery < 1 || battery > 100)
                throw new InvalidOperationException(
                    "The ATK mouse is offline/asleep or returned an invalid battery percentage.");
            return battery;
        }
    }
}
'@

Add-Type -TypeDefinition $nativeCode

if ($ListHidDevices) {
    $devices = [MouseBatteryAdapters]::FindDevices($true)
    if ($devices.Count -eq 0) {
        Write-Host 'No mouse or vendor-specific HID interfaces were found.'
        exit 0
    }

    Write-Host 'HID discovery only; no reports were sent.'
    foreach ($device in $devices) {
        Write-Host ('VID:PID {0:X4}:{1:X4}  UsagePage:Usage {2:X4}:{3:X4}  Input:{4} Output:{5} Feature:{6}' -f `
            $device.VendorId, $device.ProductId, $device.UsagePage, $device.Usage,
            $device.InputReportByteLength, $device.OutputReportByteLength,
            $device.FeatureReportByteLength)
    }
    Write-Host 'Unknown devices are listed only; their battery protocols are not queried.'
    exit 0
}

$devices = [MouseBatteryAdapters]::FindDevices($false)
if ($devices.Count -eq 0) {
    Write-Host 'No mouse with a registered battery adapter was found.'
    exit 2
}

Write-Host ("Found {0} supported battery interface(s)." -f $devices.Count)
if ($ReadBattery) {
    $confirmation = Read-Host 'This sends a read-only battery query to the supported mouse. Type READ to continue'
    if ($confirmation -cne 'READ') {
        Write-Host 'Cancelled; no command was sent.'
        exit 0
    }

    $battery = [MouseBatteryAdapters]::ReadBattery($devices[0])
    Write-Host ("Battery: {0}%" -f $battery)
    Write-Host 'The response protocol ID may differ from the receiver USB product ID.'
    Write-Host 'Query completed. No DPI/configuration write command is present in this probe.'
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$mutexName = 'Local\MchoseA7BatteryTray'
if ($TestMode) {
    $mutexName += 'Test'
}
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) {
    $mutex.Dispose()
    exit 0
}

$startupKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupName = 'MchoseA7BatteryTray'
$script:previousBattery = $null
$script:wasLowBattery = $false
$script:hasReadState = $false
$script:activeModel = 'Wireless mouse'
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
$script:notifyIcon.Text = '鼠标电量：正在读取'
$script:notifyIcon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$refreshItem = $menu.Items.Add('立即刷新')
$startupItem = New-Object System.Windows.Forms.ToolStripMenuItem('登录时启动')
$startupItem.CheckOnClick = $true
$startupValue = Get-ItemProperty -LiteralPath $startupKey -Name $startupName `
    -ErrorAction SilentlyContinue
$startupItem.Checked = $null -ne $startupValue
$exitItem = $menu.Items.Add('退出')
$menu.Items.Insert(1, $startupItem)
$script:notifyIcon.ContextMenuStrip = $menu

function Show-A7Notice([string]$title, [string]$message) {
    $script:notifyIcon.BalloonTipTitle = $title
    $script:notifyIcon.BalloonTipText = $message
    $script:notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $script:notifyIcon.ShowBalloonTip(5000)
}

function New-A7BatteryIcon([Nullable[int]]$battery) {
    $bitmap = New-Object System.Drawing.Bitmap(
        32, 32, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $outlineColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $interiorColor = [System.Drawing.Color]::FromArgb(55, 55, 55)
    if ($null -eq $battery) {
        $fillColor = [System.Drawing.Color]::FromArgb(145, 145, 145)
    } elseif ($battery -ge 80) {
        $fillColor = [System.Drawing.Color]::FromArgb(45, 205, 85)
    } elseif ($battery -le 20) {
        $fillColor = [System.Drawing.Color]::FromArgb(240, 65, 65)
    } else {
        $fillColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    }

    $outlinePen = New-Object System.Drawing.Pen($outlineColor, 2)
    $interiorBrush = New-Object System.Drawing.SolidBrush($interiorColor)
    $fillBrush = New-Object System.Drawing.SolidBrush($fillColor)
    $terminalBrush = New-Object System.Drawing.SolidBrush($outlineColor)
    try {
        $graphics.FillRectangle($interiorBrush, 5, 8, 21, 17)
        $graphics.DrawRectangle($outlinePen, 4, 7, 22, 18)
        $graphics.FillRectangle($terminalBrush, 27, 12, 3, 8)

        if ($null -ne $battery -and $battery -gt 0) {
            $fillWidth = [Math]::Max(1, [Math]::Round(17 * $battery / 100))
            $graphics.FillRectangle($fillBrush, 7, 10, $fillWidth, 13)
        }

        $iconHandle = $bitmap.GetHicon()
        try {
            return [System.Drawing.Icon]::FromHandle($iconHandle).Clone()
        } finally {
            [void][MouseBatteryAdapters]::DestroyIcon($iconHandle)
        }
    } finally {
        $terminalBrush.Dispose()
        $fillBrush.Dispose()
        $interiorBrush.Dispose()
        $outlinePen.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Set-A7BatteryIcon([Nullable[int]]$battery) {
    $newIcon = New-A7BatteryIcon $battery
    $oldIcon = $script:notifyIcon.Icon
    $script:notifyIcon.Icon = $newIcon
    if ($null -ne $oldIcon) {
        $oldIcon.Dispose()
    }
}

function Update-A7Battery {
    try {
        $found = [MouseBatteryAdapters]::FindDevices($false)
        if ($found.Count -eq 0) {
            throw '找不到已适配的鼠标电量接口。'
        }

        if (-not [string]::IsNullOrWhiteSpace($found[0].Name) -and
            $found[0].Name -ne 'Unknown') {
            $script:activeModel = $found[0].Name
        }

        $value = [MouseBatteryAdapters]::ReadBattery($found[0])
        Set-A7BatteryIcon $value
        $script:notifyIcon.Text = "$($script:activeModel) 电量：$value%"

        if (-not $script:hasReadState) {
            $script:hasReadState = $true
        } elseif ($null -eq $script:previousBattery) {
            Show-A7Notice '鼠标电量已恢复' "$($script:activeModel) 当前电量：$value%"
        }

        if ($value -le 20 -and -not $script:wasLowBattery) {
            Show-A7Notice '鼠标电量低' "$($script:activeModel) 仅剩 $value%，请及时充电。"
            $script:wasLowBattery = $true
        } elseif ($value -ge 25) {
            $script:wasLowBattery = $false
        }

        $script:previousBattery = $value
    } catch {
        $message = $_.Exception.Message
        Set-A7BatteryIcon $null
        $script:notifyIcon.Text = "$($script:activeModel) 电量：暂不可读"
        if (-not $script:hasReadState -or $null -ne $script:previousBattery) {
            Show-A7Notice '无法读取鼠标电量' $message
        }
        $script:previousBattery = $null
        $script:hasReadState = $true
    }
}

function Set-A7Startup([bool]$enabled) {
    if ($enabled) {
        $powershellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $command = '"{0}" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}"' -f `
            $powershellPath, $PSCommandPath
        New-ItemProperty -LiteralPath $startupKey -Name $startupName -Value $command `
            -PropertyType String -Force -ErrorAction Stop | Out-Null
    } else {
        Remove-ItemProperty -LiteralPath $startupKey -Name $startupName `
            -ErrorAction SilentlyContinue
    }
}

$refreshItem.add_Click({ Update-A7Battery })
$startupItem.add_Click({
    try {
        Set-A7Startup $startupItem.Checked
    } catch {
        $startupItem.Checked = -not $startupItem.Checked
        Show-A7Notice '无法更改开机启动设置' $_.Exception.Message
    }
})
$exitItem.add_Click({
    $script:notifyIcon.Visible = $false
    $timer.Stop()
    [System.Windows.Forms.Application]::Exit()
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300000
$timer.add_Tick({ Update-A7Battery })
$testTimer = $null

try {
    if (-not $TestMode) {
        Set-A7Startup $true
    }
    Update-A7Battery
    $timer.Start()
    if ($TestMode) {
        Write-Host 'Tray test started; closing automatically in 8 seconds.'
        $testTimer = New-Object System.Windows.Forms.Timer
        $testTimer.Interval = 8000
        $testTimer.add_Tick({
            $testTimer.Stop()
            [System.Windows.Forms.Application]::Exit()
        })
        $testTimer.Start()
    }
    [System.Windows.Forms.Application]::Run()
} finally {
    $timer.Dispose()
    if ($null -ne $testTimer) {
        $testTimer.Dispose()
    }
    $menu.Dispose()
    $script:notifyIcon.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

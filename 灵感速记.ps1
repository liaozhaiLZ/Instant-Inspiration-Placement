#requires -Version 5.1
# 灵感速记 - Inspiration Quick Note
# Windows 11 WPF 毛玻璃风格灵感记录工具

$ErrorActionPreference = 'Stop'
$script:AppRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $script:AppRoot) { $script:AppRoot = (Get-Location).Path }
$script:AppLog = Join-Path $script:AppRoot 'app.log'
$script:LibraryName = '灵感库'
$script:AppVersion = '1.2.1'

function Write-Log {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $script:AppLog -Value ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message) -Encoding UTF8
    } catch { }
}

try { Set-Content -LiteralPath $script:AppLog -Value '' -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }

$script:IconPath = Join-Path $script:AppRoot 'icon-white.png'
if (-not (Test-Path -LiteralPath $script:IconPath)) { $script:IconPath = Join-Path $script:AppRoot 'icon.png' }

function Get-AppIconImage {
    if (-not (Test-Path -LiteralPath $script:IconPath)) { return $null }
    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.UriSource = New-Object System.Uri($script:IconPath)
        $bmp.EndInit()
        $bmp.Freeze()
        return $bmp
    } catch {
        Write-Log ('icon image failed: ' + $_.Exception.Message)
        return $null
    }
}

# ---------------------------------------------------------------- native interop
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:NativeCode = @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Lingan
{
    public static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct ACCENTPOLICY { public int AccentState; public int AccentFlags; public int GradientColor; public int AnimationId; }

        [StructLayout(LayoutKind.Sequential)]
        private struct WINCOMPATTRDATA { public int Attribute; public IntPtr Data; public int SizeOfData; }

        [DllImport("user32.dll")]
        private static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WINCOMPATTRDATA data);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);

        public static bool PingHost(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) { return false; }
            IntPtr result;
            IntPtr ok = SendMessageTimeout(hWnd, 0x8002, IntPtr.Zero, IntPtr.Zero, 0x0002, 1200, out result);
            return ok != IntPtr.Zero && result != IntPtr.Zero;
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        public static void SetAppId(string appId)
        {
            try { SetCurrentProcessExplicitAppUserModelID(appId); } catch { }
        }

        [DllImport("user32.dll")]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll")]
        public static extern IntPtr PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        public static IntPtr FindSignalHost()
        {
            return FindWindow(null, "LinganSignalHost");
        }


        public static void ForceShow(IntPtr hwnd)
        {
            ShowWindow(hwnd, 5);
            SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
            SetWindowPos(hwnd, new IntPtr(-2), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
            SetForegroundWindow(hwnd);
        }

        public static void RoundCorners(IntPtr hwnd)
        {
            try {
                int pref = 2;
                DwmSetWindowAttribute(hwnd, 33, ref pref, 4);
                int dark = 0;
                DwmSetWindowAttribute(hwnd, 20, ref dark, 4);
            } catch { }
        }

        public static void EnableAcrylic(IntPtr hwnd, int tintARGB)
        {
            ACCENTPOLICY policy = new ACCENTPOLICY();
            policy.AccentState = 4;
            policy.AccentFlags = 2;
            policy.GradientColor = tintARGB;
            policy.AnimationId = 0;
            WINCOMPATTRDATA data = new WINCOMPATTRDATA();
            data.Attribute = 19;
            IntPtr ptr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(ACCENTPOLICY)));
            try
            {
                Marshal.StructureToPtr(policy, ptr, false);
                data.Data = ptr;
                data.SizeOfData = Marshal.SizeOf(typeof(ACCENTPOLICY));
                SetWindowCompositionAttribute(hwnd, ref data);
            }
            finally { Marshal.FreeHGlobal(ptr); }
        }

        public static void DisableAcrylic(IntPtr hwnd)
        {
            ACCENTPOLICY policy = new ACCENTPOLICY();
            policy.AccentState = 0;
            policy.AccentFlags = 0;
            policy.GradientColor = 0;
            policy.AnimationId = 0;
            WINCOMPATTRDATA data = new WINCOMPATTRDATA();
            data.Attribute = 19;
            IntPtr ptr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(ACCENTPOLICY)));
            try
            {
                Marshal.StructureToPtr(policy, ptr, false);
                data.Data = ptr;
                data.SizeOfData = Marshal.SizeOf(typeof(ACCENTPOLICY));
                SetWindowCompositionAttribute(hwnd, ref data);
            }
            finally { Marshal.FreeHGlobal(ptr); }
        }
    }

    public class SignalHost : NativeWindow
    {
        public const int WM_SIGNAL = 0x8001;
        public const int WM_PING = 0x8002;
        public event EventHandler Signaled;

        public SignalHost()
        {
            CreateParams cp = new CreateParams();
            cp.Caption = "LinganSignalHost";
            cp.X = 0; cp.Y = 0; cp.Width = 0; cp.Height = 0;
            CreateHandle(cp);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_SIGNAL)
            {
                EventHandler h = Signaled;
                if (h != null) { h(this, EventArgs.Empty); }
            }
            else if (m.Msg == WM_PING)
            {
                m.Result = (IntPtr)1;
                return;
            }
            base.WndProc(ref m);
        }

        public void Destroy()
        {
            DestroyHandle();
        }
    }

    public class HotkeyHost : NativeWindow
    {
        private const int WM_HOTKEY = 0x0312;
        public event EventHandler Pressed;

        public HotkeyHost()
        {
            CreateParams cp = new CreateParams();
            cp.Caption = "LinganHotkeyHost";
            cp.X = 0; cp.Y = 0; cp.Width = 0; cp.Height = 0;
            CreateHandle(cp);
        }

        public bool Register(int id, uint mods, uint vk)
        {
            return Native.RegisterHotKey(this.Handle, id, mods, vk);
        }

        public void Unregister(int id)
        {
            Native.UnregisterHotKey(this.Handle, id);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {

                EventHandler h = Pressed;
                if (h != null) { h(this, EventArgs.Empty); }
            }
            base.WndProc(ref m);
        }

        public void Destroy()
        {
            DestroyHandle();
        }
    }
}
"@

Add-Type -TypeDefinition $script:NativeCode -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' -ErrorAction Stop

# ---------------------------------------------------------------- single instance
$script:SignalHost = $null

# a hidden window named LinganSignalHost marks the running instance
$existingHost = [Lingan.Native]::FindSignalHost()
if ($existingHost -ne [IntPtr]::Zero) {
    if ([Lingan.Native]::PingHost($existingHost)) {
        [void][Lingan.Native]::PostMessage($existingHost, 0x8001, [IntPtr]::Zero, [IntPtr]::Zero)
        exit
    }
    # the other instance does not answer (for example it was started as administrator)
    Write-Log 'existing instance unreachable, starting a new one'
}

try {
    $script:SignalHost = New-Object Lingan.SignalHost
    $script:SignalHost.add_Signaled({
            try { Show-MainWindow } catch { Write-Log ('signal failed: ' + $_.Exception.Message) }
        })
} catch {
    $script:SignalHost = $null
    Write-Log ('signal host failed: ' + $_.Exception.Message)
}

# ---------------------------------------------------------------- config
$script:ConfigPath = Join-Path $script:AppRoot 'config.json'
$script:Config = [ordered]@{
    hotkey       = 'Ctrl+Alt+Space'
    theme        = 'system'
    accent       = '#7C6CF6'
    autostart    = $false
    startupAsked = $false
    lastView     = 'home'
    widgetVisible = $true
    widgetImage   = ''
    widgetRight   = 10
    widgetBottom  = 10
    punish        = $false
}

function Load-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return }
    try {
        $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        $data = $raw | ConvertFrom-Json
        foreach ($k in @($script:Config.Keys)) {
            $v = $data.$k
            if ($null -ne $v) { $script:Config[$k] = $v }
        }
    } catch {
        Write-Log ('配置读取失败: ' + $_.Exception.Message)
    }
}

function Save-Config {
    try {
        $json = $script:Config | ConvertTo-Json -Depth 5
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($script:ConfigPath, $json, $utf8)
    } catch {
        Write-Log ('配置保存失败: ' + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- paths / data
function Get-LibraryPath { Join-Path $script:AppRoot $script:LibraryName }

function Ensure-Library {
    $lib = Get-LibraryPath
    if (-not (Test-Path -LiteralPath $lib)) {
        $null = New-Item -ItemType Directory -Path $lib -Force
        Write-Log ('已创建灵感库: ' + $lib)
    }
    return $lib
}

function Format-TimeText {
    param([datetime]$Time)
    $now = Get-Date
    $span = $now - $Time
    if ($span.TotalSeconds -lt 60) { return '刚刚' }
    if ($span.TotalMinutes -lt 60) { return ('{0} 分钟前' -f [int][math]::Floor($span.TotalMinutes)) }
    if ($Time.Date -eq $now.Date) { return ('今天 {0:HH:mm}' -f $Time) }
    if ($Time.Date -eq $now.Date.AddDays(-1)) { return ('昨天 {0:HH:mm}' -f $Time) }
    if ($Time.Year -eq $now.Year) { return ('{0:MM月dd日 HH:mm}' -f $Time) }
    return ('{0:yyyy-MM-dd HH:mm}' -f $Time)
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -lt 1024) { return ('{0} B' -f $Bytes) }
    if ($Bytes -lt 1048576) { return ('{0:0.0} KB' -f ($Bytes / 1024)) }
    return ('{0:0.0} MB' -f ($Bytes / 1048576))
}

function Get-DisplayTitle {
    param([string]$FileName)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $t = $stem -replace '^\d{8}-\d{4}\s+', ''
    $t = $t -replace '\s+\(\d+\)$', ''
    if ([string]::IsNullOrWhiteSpace($t)) { return '未命名灵感' }
    return $t.Trim()
}

function Get-Items {
    param([string]$Filter = '')
    $lib = Ensure-Library
    $list = New-Object System.Collections.ArrayList
    $files = @(Get-ChildItem -LiteralPath $lib -Filter '*.txt' -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        $title = Get-DisplayTitle $f.Name
        if ($Filter -and -not $title.ToLower().Contains($Filter.ToLower())) { continue }
        $text = ''
        try { $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 } catch { $text = '' }
        if ($null -eq $text) { $text = '' }
        $preview = ($text -replace '\s+', ' ').Trim()
        if ($preview.Length -gt 70) { $preview = $preview.Substring(0, 70) + '…' }
        if ([string]::IsNullOrWhiteSpace($preview)) { $preview = '（空白）' }
        $null = $list.Add([pscustomobject]@{
            Title    = $title
            Path     = $f.FullName
            TimeText = Format-TimeText $f.LastWriteTime
            Preview  = $preview
            SizeText = Format-Size $f.Length
            SortKey  = $f.LastWriteTime
        })
    }
    return @($list | Sort-Object SortKey -Descending)
}

function New-ItemFilePath {
    param([string]$Title)
    $lib = Ensure-Library
    $slug = $Title -replace '[\\/:*?"<>|\r\n\t]', ' '
    $slug = ($slug -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = '未命名灵感' }
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40) }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $base = "$stamp $slug"
    $path = Join-Path $lib ($base + '.txt')
    $i = 2
    while (Test-Path -LiteralPath $path) {
        $path = Join-Path $lib ("$base ($i).txt")
        $i++
    }
    return $path
}

# ---------------------------------------------------------------- theme
$script:Palettes = @{
    dark  = @{
        ShellBg         = '#E815161B'
        PopupBg         = '#F815161B'
        CardBg          = '#1FFFFFFF'
        CardBgHover     = '#30FFFFFF'
        CardBgPress     = '#18FFFFFF'
        CardBorder      = '#26FFFFFF'
        CardBorderHover = '#45FFFFFF'
        ShellBorder     = '#2EFFFFFF'
        InputBg         = '#14FFFFFF'
        TextPrimary     = '#F2F4F7FA'
        TextSecondary   = '#A3EDF1F5'
        TextPlaceholder = '#5CEDF1F5'
        Divider         = '#1FFFFFFF'
        ScrollThumb     = '#3DFFFFFF'
    }
    light = @{
        ShellBg         = '#F2F2F3F6'
        PopupBg         = '#FFFAFAFC'
        CardBg          = '#B3FFFFFF'
        CardBgHover     = '#E8FFFFFF'
        CardBgPress     = '#D0FFFFFF'
        CardBorder      = '#1A000000'
        CardBorderHover = '#38000000'
        ShellBorder     = '#29000000'
        InputBg         = '#7AFFFFFF'
        TextPrimary     = '#1A1B20'
        TextSecondary   = '#7D1A1B20'
        TextPlaceholder = '#521A1B20'
        Divider         = '#14000000'
        ScrollThumb     = '#33000000'
    }
}

$script:AccentPresets = @('#7C6CF6', '#5B8DEF', '#22C1A4', '#F2748F', '#F2A93B', '#8C8FA3')
$script:Brushes = @{}
$script:ApplyingTheme = $false

function ConvertTo-WColor {
    param([string]$Hex)
    return [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
}

function Set-Brush {
    param([string]$Key, [string]$Hex)
    $c = ConvertTo-WColor $Hex
    $existing = $null
    if ($script:Brushes.ContainsKey($Key)) { $existing = $script:Brushes[$Key] }
    if ($null -ne $existing -and -not $existing.IsFrozen -and $existing.Color -eq $c) { return }
    $b = New-Object System.Windows.Media.SolidColorBrush($c)
    $raw = [System.Runtime.CompilerServices.RuntimeHelpers]::GetObjectValue($b)
    $script:Brushes[$Key] = $raw
    $script:App.Resources[$Key] = $raw
}

function Get-AlphaHex {
    param([string]$Hex, [string]$Alpha)
    $h = $Hex.TrimStart('#')
    if ($h.Length -eq 8) { $h = $h.Substring(2) }
    return ('#' + $Alpha + $h)
}

function Get-SystemLight {
    try {
        $v = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop
        return ([int]$v -eq 1)
    } catch {
        return $false
    }
}

function Get-EffectiveLight {
    if ($script:Config.theme -eq 'light') { return $true }
    if ($script:Config.theme -eq 'dark') { return $false }
    return (Get-SystemLight)
}

function Apply-Theme {
    $script:ApplyingTheme = $true
    try {
        $isLight = Get-EffectiveLight
        $pal = $script:Palettes['dark']
        if ($isLight) { $pal = $script:Palettes['light'] }
        foreach ($k in $pal.Keys) { Set-Brush $k $pal[$k] }

        $accent = [string]$script:Config.accent
        if ([string]::IsNullOrWhiteSpace($accent)) { $accent = '#7C6CF6' }
        Set-Brush 'Accent' $accent
        if ($isLight) {
            Set-Brush 'AccentSoft' (Get-AlphaHex $accent '2E')
        } else {
            Set-Brush 'AccentSoft' (Get-AlphaHex $accent '3B')
        }
        Set-Brush 'AccentHover' (Get-AlphaHex $accent 'FF')
        $script:IsLight = $isLight

        if ($script:UI) {
            if ($script:UI.RadSys) {
                $script:ApplyingTheme = $true
                $script:UI.RadSys.IsChecked = ($script:Config.theme -eq 'system')
                $script:UI.RadLight.IsChecked = ($script:Config.theme -eq 'light')
                $script:UI.RadDark.IsChecked = ($script:Config.theme -eq 'dark')
                $script:UI.PopR1.IsChecked = ($script:Config.theme -eq 'system')
                $script:UI.PopR2.IsChecked = ($script:Config.theme -eq 'light')
                $script:UI.PopR3.IsChecked = ($script:Config.theme -eq 'dark')
            }
            Update-Swatches
            Update-ShellTint
        }
    } finally {
        $script:ApplyingTheme = $false
    }
}

function Update-ShellTint {
    if (-not $script:UI) { return }
    if (-not $script:UI.Window.IsVisible) { return }
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($script:UI.Window)
        if ($helper.Handle -eq [IntPtr]::Zero) { return }
        if ($script:AcrylicEnabled) {
            $col = $script:Brushes['ShellBg'].Color
            $tint = ([int]$col.A -shl 24) -bor ([int]$col.B -shl 16) -bor ([int]$col.G -shl 8) -bor [int]$col.R
            [Lingan.Native]::EnableAcrylic($helper.Handle, $tint)
        }
    } catch {
        Write-Log ('亚克力失败: ' + $_.Exception.Message)
    }
}

function Update-Swatches {
    foreach ($name in @('SwatchPanel', 'PopSwatches')) {
        $panel = $null
        if ($script:UI.ContainsKey($name)) { $panel = $script:UI[$name] }
        if (-not $panel) { continue }
        $panel.Children.Clear()
        foreach ($c in $script:AccentPresets) {
            $isSel = ($c.ToLower() -eq ([string]$script:Config.accent).ToLower())
            $ring = New-Object System.Windows.Controls.Border
            $ring.Width = 30
            $ring.Height = 30
            $ring.CornerRadius = (New-Object System.Windows.CornerRadius 15)
            $ring.Margin = (New-Object System.Windows.Thickness 0, 0, 8, 8)
            $ring.Padding = (New-Object System.Windows.Thickness 4)
            $ring.Tag = $c
            $ring.Cursor = 'Hand'
            if ($isSel) {
                $ring.BorderThickness = (New-Object System.Windows.Thickness 2)
                $ring.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::White))
            } else {
                $ring.BorderThickness = (New-Object System.Windows.Thickness 0)
                $ring.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::Transparent))
            }
            $dot = New-Object System.Windows.Controls.Border
            $dot.CornerRadius = (New-Object System.Windows.CornerRadius 11)
            $dot.Background = (New-Object System.Windows.Media.SolidColorBrush((ConvertTo-WColor $c)))
            $ring.Child = $dot
            $ring.Add_MouseLeftButtonUp({
                    param($s, $e)
                    $script:Config.accent = [string]$s.Tag
                    Save-Config
                    Apply-Theme
                    Refresh-All
                })
            $null = $panel.Children.Add($ring)
        }
    }
}

# ---------------------------------------------------------------- ui helpers
function Get-El { param([string]$Name) return $script:UI[$Name] }

# ---------------------------------------------------------------- greeting egg / author (v1.2.1)
$script:GreetLines = @(
    '时间在上一条……', '这里没东西了……', '真的没了……', '干嘛不信啊', '好了不要再点了！！！',
    '这里只是个标语！', '这里没有更多彩蛋了', '好吧你赢了', '给你个奖励'
)
$script:GreetPhase = 0
$script:GreetIndex = -1
$script:GreetLastTap = [datetime]::MinValue
$script:GreetIdleTimer = $null

$script:AuthorLines = @(
    '哈喽，这里是*聊斋LaZarus*',
    '非常感谢使用烧了我好几十块钱的小程序',
    '这玩意本质上就是个笔记本',
    '只是因为我嫌我自己手机的记事本不好使然后突发灵感做的',
    '然后又塞了很多乱七八糟的小彩蛋',
    '最后就是这里没有任何彩蛋（不骗你）',
    '谢谢使用'
)
$script:AuthorTimer1 = $null
$script:AuthorTimer2 = $null
$script:AuthorJitter = $null

function Get-GreetText {
    $h = (Get-Date).Hour
    if ($h -lt 6) { return '深夜的灵感最珍贵' }
    if ($h -lt 11) { return '早上好，记下此刻的想法' }
    if ($h -lt 14) { return '午间灵感，随手记下' }
    if ($h -lt 19) { return '下午好，有什么新点子？' }
    return '晚上好，今天有什么新想法？'
}

function Set-GreetText([string]$Text) {
    if (-not $script:UI.HomeTitle) { return }
    $script:UI.HomeTitle.Text = $Text
    $anim = [System.Windows.Media.Animation.DoubleAnimation]::new(0.0, 1.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(220)))
    $script:UI.HomeTitle.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $anim)
}

function Reset-GreetEgg {
    $script:GreetPhase = 0
    $script:GreetIndex = -1
    $script:GreetLastTap = [datetime]::MinValue
    if ($script:GreetIdleTimer) { $script:GreetIdleTimer.Stop(); $script:GreetIdleTimer = $null }
    Set-GreetText (Get-GreetText)
}

function Arm-GreetIdle {
    if (-not $script:GreetIdleTimer) {
        $script:GreetIdleTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:GreetIdleTimer.Interval = [TimeSpan]::FromSeconds(12)
        $script:GreetIdleTimer.Add_Tick({
                $script:GreetIdleTimer.Stop()
                $script:GreetIdleTimer = $null
                Reset-GreetEgg
            })
    }
    $script:GreetIdleTimer.Stop()
    $script:GreetIdleTimer.Start()
}

function Invoke-GreetTap {
    $script:GreetPunished = $false
    $now = Get-Date
    $quick = $false
    if ($script:GreetLastTap -ne [datetime]::MinValue) {
        $quick = (($now - $script:GreetLastTap).TotalSeconds -lt 6)
    }
    $script:GreetLastTap = $now
    Arm-GreetIdle
    $stamp = $now.ToString('yyyy年M月d日 dddd HH:mm')
    if ($script:GreetPhase -eq 0) {
        $script:GreetPhase = 1
        Set-GreetText $stamp
        return
    }
    if ($script:GreetPhase -eq 1) {
        if (-not $quick) { Set-GreetText $stamp; return }
        $script:GreetPhase = 2
        $script:GreetIndex = 0
        Set-GreetText $script:GreetLines[0]
        return
    }
    if (($script:GreetIndex + 1) -lt $script:GreetLines.Count) {
        $script:GreetIndex++
        Set-GreetText $script:GreetLines[$script:GreetIndex]
        return
    }
    try { $script:Config.punish = $true; Save-Config } catch { }
    Write-Log 'greeting egg exhausted, exiting'
    try { [System.Windows.Application]::Current.Shutdown() } catch { }
}

function New-RainbowBrush {
    $b = New-Object System.Windows.Media.LinearGradientBrush
    $b.StartPoint = [System.Windows.Point]::new(0, 0)
    $b.EndPoint = [System.Windows.Point]::new(1, 0)
    $b.MappingMode = 'RelativeToBoundingBox'
    $cols = @('#FF7C6CF6', '#FF5B8DEF', '#FF22C1A4', '#FFF2A93B', '#FFF2748F', '#FF7C6CF6')
    for ($i = 0; $i -lt $cols.Count; $i++) {
        $gs = New-Object System.Windows.Media.GradientStop
        $gs.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($cols[$i])
        $gs.Offset = [double]$i / [double]($cols.Count - 1)
        $b.GradientStops.Add($gs)
    }
    $tt = New-Object System.Windows.Media.TranslateTransform
    $b.Transform = $tt
    $anim = [System.Windows.Media.Animation.DoubleAnimation]::new(0.0, 1.0, [System.Windows.Duration]::new([TimeSpan]::FromSeconds(4)))
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $anim)
    return $b
}

function Get-RainbowHex([double]$t) {
    $h = ((($t % 1.0) + 1.0) % 1.0) * 360.0
    $s = 0.70
    $l = 0.62
    $c = (1.0 - [Math]::Abs(2.0 * $l - 1.0)) * $s
    $x = $c * (1.0 - [Math]::Abs((($h / 60.0) % 2.0) - 1.0))
    $m = $l - ($c / 2.0)
    $rf = 0.0; $gf = 0.0; $bf = 0.0
    if ($h -lt 60) { $rf = $c; $gf = $x }
    elseif ($h -lt 120) { $rf = $x; $gf = $c }
    elseif ($h -lt 180) { $gf = $c; $bf = $x }
    elseif ($h -lt 240) { $gf = $x; $bf = $c }
    elseif ($h -lt 300) { $rf = $x; $bf = $c }
    else { $rf = $c; $bf = $x }
    $r = [int][Math]::Round(($rf + $m) * 255)
    $g = [int][Math]::Round(($gf + $m) * 255)
    $b = [int][Math]::Round(($bf + $m) * 255)
    return ('#FF{0:X2}{1:X2}{2:X2}' -f $r, $g, $b)
}

function Initialize-AuthorEntry {
    $panel = $script:UI.AuthorEntryPanel
    if (-not $panel) { return }
    $panel.Children.Clear()
    $text = '作者的话'
    $chars = @()
    $cols = @('#FF7C6CF6', '#FF5B8DEF', '#FF22C1A4', '#FFF2A93B', '#FFF2748F', '#FF7C6CF6')
    for ($i = 0; $i -lt $text.Length; $i++) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = [string]$text[$i]
        $tb.FontSize = 13.5
        $tb.FontWeight = 'SemiBold'
        $tb.VerticalAlignment = 'Center'
        # each character samples its own slice of the rainbow so the whole word reads as a gradient
        $frac = [double]$i / [double]$text.Length
        $brush = New-Object System.Windows.Media.LinearGradientBrush
        $brush.MappingMode = 'RelativeToBoundingBox'
        $brush.StartPoint = [System.Windows.Point]::new(0, 0)
        $brush.EndPoint = [System.Windows.Point]::new(1, 0)
        $gsA = New-Object System.Windows.Media.GradientStop
        $gsA.Color = [System.Windows.Media.ColorConverter]::ConvertFromString((Get-RainbowHex $frac))
        $gsA.Offset = 0
        $gsB = New-Object System.Windows.Media.GradientStop
        $gsB.Color = [System.Windows.Media.ColorConverter]::ConvertFromString((Get-RainbowHex ([Math]::Min(0.999, $frac + 0.09))))
        $gsB.Offset = 1
        $brush.GradientStops.Add($gsA)
        $brush.GradientStops.Add($gsB)
        $raw = [System.Runtime.CompilerServices.RuntimeHelpers]::GetObjectValue($brush)
        $tb.Foreground = $raw
        $tt = New-Object System.Windows.Media.TranslateTransform
        $tb.RenderTransform = $tt
        $panel.Children.Add($tb) | Out-Null
        $chars += , @($tb, $tt)
    }
    $script:AuthorJitter = $chars
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(900)
    $timer.Add_Tick({
            if (-not $script:AuthorJitter -or $script:AuthorJitter.Count -eq 0) { return }
            $idx = Get-Random -Minimum 0 -Maximum $script:AuthorJitter.Count
            $tt = $script:AuthorJitter[$idx][1]
            $a = [System.Windows.Media.Animation.DoubleAnimation]::new(-3.5, 0.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(320)))
            $a.EasingFunction = [System.Windows.Media.Animation.CubicEase]::new()
            $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $a)
            if ((Get-Random -Maximum 100) -lt 40) {
                $idx2 = Get-Random -Minimum 0 -Maximum $script:AuthorJitter.Count
                $tt2 = $script:AuthorJitter[$idx2][1]
                $a2 = [System.Windows.Media.Animation.DoubleAnimation]::new(2.5, 0.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(360)))
                $tt2.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $a2)
            }
        })
    $timer.Start()
}

function Render-Author {
    $body = $script:UI.AuthorBody
    if (-not $body) { return }
    $body.Children.Clear()
    foreach ($line in $script:AuthorLines) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.FontSize = 15
        $tb.LineHeight = 28
        $tb.TextWrapping = 'Wrap'
        $tb.TextAlignment = 'Center'
        $tb.HorizontalAlignment = 'Center'
        $tb.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
        $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'TextPrimary')
        $parts = $line -split '\*'
        for ($k = 0; $k -lt $parts.Count; $k++) {
            if ($parts[$k].Length -eq 0) { continue }
            $run = New-Object System.Windows.Documents.Run($parts[$k])
            if (($k % 2) -eq 1) {
                $run.FontStyle = 'Italic'
                $run.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'Accent')
            }
            $tb.Inlines.Add($run)
        }
        $body.Children.Add($tb) | Out-Null
    }

    # reserved empty space + two lines that fade in later
    $tailPanel = New-Object System.Windows.Controls.StackPanel
    $tailPanel.MinHeight = 170
    $tailPanel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 40)
    $state = @()
    for ($i = 1; $i -le 2; $i++) {
        $tb = New-Object System.Windows.Controls.TextBlock
        if ($i -eq 1) { $tb.Text = '你怎么还没看完......' } else { $tb.Text = '怎么有人能这么闲......' }
        $tb.FontSize = 13
        $tb.HorizontalAlignment = 'Center'
        $tb.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
        $tb.Opacity = 0
        $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'TextSecondary')
        $tailPanel.Children.Add($tb) | Out-Null
        $state += $tb
    }
    $body.Children.Add($tailPanel) | Out-Null
    $script:AuthorTailLines = $state
}

function Start-AuthorTimer {
    Stop-AuthorTimer
    $script:AuthorTimer1 = New-Object System.Windows.Threading.DispatcherTimer
    $script:AuthorTimer1.Interval = [TimeSpan]::FromSeconds(5)
    $script:AuthorTimer1.Add_Tick({
            $script:AuthorTimer1.Stop()
            $script:AuthorTimer1 = $null
            $lines = $script:AuthorTailLines
            if (-not $lines -or $lines.Count -lt 1) { return }
            $a = [System.Windows.Media.Animation.DoubleAnimation]::new(0.0, 0.9, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1400)))
            $lines[0].BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
            $script:AuthorTimer2 = New-Object System.Windows.Threading.DispatcherTimer
            $script:AuthorTimer2.Interval = [TimeSpan]::FromSeconds(1.5)
            $script:AuthorTimer2.Add_Tick({
                    $script:AuthorTimer2.Stop()
                    $script:AuthorTimer2 = $null
                    $l2 = $script:AuthorTailLines
                    if (-not $l2 -or $l2.Count -lt 2) { return }
                    $b2 = [System.Windows.Media.Animation.DoubleAnimation]::new(0.0, 0.9, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1400)))
                    $l2[1].BeginAnimation([System.Windows.UIElement]::OpacityProperty, $b2)
                })
            $script:AuthorTimer2.Start()
        })
    $script:AuthorTimer1.Start()
}

function Stop-AuthorTimer {
    if ($script:AuthorTimer1) { $script:AuthorTimer1.Stop(); $script:AuthorTimer1 = $null }
    if ($script:AuthorTimer2) { $script:AuthorTimer2.Stop(); $script:AuthorTimer2 = $null }
    if ($script:AuthorTailLines) {
        foreach ($l in $script:AuthorTailLines) {
            if ($l) { $l.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null); $l.Opacity = 0 }
        }
    }
}
function Show-View {
    param([string]$Name)
    $script:CurrentView = $Name
    foreach ($v in @('Home', 'New', 'List', 'Manage', 'Settings', 'Poems', 'Author')) {
        $el = $script:UI['View' + $v]
        if ($el) { $el.Visibility = 'Collapsed' }
    }
    $target = $script:UI['View' + $Name]
    if ($target) { $target.Visibility = 'Visible' }
    $script:Config.lastView = $Name.ToLower()
    if ($Name -eq 'List' -or $Name -eq 'Manage') { Refresh-Items }
    if ($Name -eq 'Home') { Update-Home }
    if ($Name -eq 'New') { Update-TagChips -Reshuffle }
    if ($Name -eq 'Poems') { Refresh-Poems }
    if ($Name -eq 'Author') { Render-Author; Start-AuthorTimer } else { Stop-AuthorTimer }
    if ($Name -eq 'Settings') { Update-PoemState }
}

function Update-Home {
    if ($script:Config.punish) {
        $script:Config.punish = $false
        try { Save-Config } catch { }
        $script:GreetPhase = 0
        $script:GreetIndex = -1
        $script:GreetPunished = $true
        Set-GreetText '学乖了吧，下次别玩了'
    } elseif (-not $script:GreetPunished) {
        Reset-GreetEgg
    }
    $items = @(Get-Items)
    $script:UI.HomeSub.Text = ('共 {0} 条灵感 · 保存在「灵感库」文件夹中' -f $items.Count)
    Update-WhaleBubble
}

function Update-Placeholders {
    if ($script:UI.TxtTitle.Text.Length -eq 0) {
        $script:UI.TitlePlaceholder.Visibility = 'Visible'
    } else {
        $script:UI.TitlePlaceholder.Visibility = 'Collapsed'
    }
    if ($script:UI.TxtBody.Text.Length -eq 0) {
        $script:UI.BodyPlaceholder.Visibility = 'Visible'
    } else {
        $script:UI.BodyPlaceholder.Visibility = 'Collapsed'
    }
    $n = ($script:UI.TxtBody.Text -replace '\s', '').Length
    $script:UI.WordCount.Text = ('{0} 字' -f $n)
}

function Set-SaveStatus {
    param([string]$Text)
    $script:UI.SaveStatus.Text = $Text
}

function Mark-Dirty {
    $script:Dirty = $true
    Set-SaveStatus '未保存 · Ctrl+S 保存'
}

function Refresh-Items {
    $filter = ''
    if ($script:UI.TxtSearch) { $filter = $script:UI.TxtSearch.Text.Trim() }
    $items = @(Get-Items -Filter $filter)
    $script:Items = $items
    if ($script:UI.ListBrowse) { $script:UI.ListBrowse.ItemsSource = $items }
    if ($script:UI.ListManage) { $script:UI.ListManage.ItemsSource = $items }
    if ($script:UI.ListCount) {
        if ($filter) {
            $script:UI.ListCount.Text = ('{0} 条匹配' -f $items.Count)
        } else {
            $script:UI.ListCount.Text = ('{0} 条' -f $items.Count)
        }
    }
    if ($script:UI.EmptyBrowse) {
        if ($items.Count -eq 0) {
            $script:UI.EmptyBrowse.Visibility = 'Visible'
            if ($filter) { $script:UI.EmptyBrowse.Text = '没有匹配的灵感' } else { $script:UI.EmptyBrowse.Text = '还没有灵感，去「新建灵感」记一条吧' }
        } else {
            $script:UI.EmptyBrowse.Visibility = 'Collapsed'
        }
    }
    if ($script:UI.EmptyManage) {
        if ($items.Count -eq 0) { $script:UI.EmptyManage.Visibility = 'Visible' } else { $script:UI.EmptyManage.Visibility = 'Collapsed' }
    }
    $script:UI.SearchPh.Visibility = if ($script:UI.TxtSearch.Text.Length -eq 0) { 'Visible' } else { 'Collapsed' }
    if ($script:UI.ListBrowse) {
        if ($items.Count -gt 0) {
            if ($null -eq $script:UI.ListBrowse.SelectedItem) { $script:UI.ListBrowse.SelectedIndex = 0 }
        } else {
            $script:UI.ListBrowse.SelectedIndex = -1
            $script:UI.ReadTitle.Text = ''
            $script:UI.ReadMeta.Text = ''
            $script:UI.ReadBody.Text = ''
        }
    }
}

function Refresh-All {
    Refresh-Items
    Update-Home
}

# ---------------------------------------------------------------- editor ops
function Get-CurrentTitle {
    $t = $script:UI.TxtTitle.Text.Trim()
    if ($t.Length -gt 0) { return $t }
    $body = $script:UI.TxtBody.Text.Trim()
    if ($body.Length -gt 0) {
        $first = @($body -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 })[0]
        if ($first) {
            $first = $first.Trim()
            if ($first.Length -gt 24) { $first = $first.Substring(0, 24) }
            return $first
        }
    }
    return '未命名灵感'
}

function Save-Current {
    $lib = Ensure-Library
    $title = Get-CurrentTitle
    $body = $script:UI.TxtBody.Text

    if ($script:CurrentPath -and (Test-Path -LiteralPath $script:CurrentPath)) {
        $target = $script:CurrentPath
        $dir = [System.IO.Path]::GetDirectoryName($target)
        $oldStem = [System.IO.Path]::GetFileNameWithoutExtension($target)
        $prefixMatch = [regex]::Match($oldStem, '^\d{8}-\d{4}\s+')
        $slug = $title -replace '[\\/:*?"<>|\r\n\t]', ' '
        $slug = ($slug -replace '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($slug)) { $slug = '未命名灵感' }
        if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40) }
        if ($prefixMatch.Success) {
            $newName = $prefixMatch.Value + $slug + '.txt'
            $newPath = Join-Path $dir $newName
            if ($newPath -ne $target -and -not (Test-Path -LiteralPath $newPath)) {
                try {
                    [System.IO.File]::Move($target, $newPath)
                    $target = $newPath
                    $script:CurrentPath = $newPath
                } catch { }
            }
        }
    } else {
        $target = New-ItemFilePath $title
        $script:CurrentPath = $target
    }

    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($target, $body, $utf8)
    $script:Dirty = $false
    $rel = [System.IO.Path]::GetFileName($target)
    Set-SaveStatus ('已保存 · {0:HH:mm} · {1}\{2}' -f (Get-Date), $script:LibraryName, $rel)
    $script:UI.SaveStatus.ToolTip = $target
    Refresh-All
}

function Load-IntoEditor {
    param([string]$Path)
    $text = ''
    try { $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 } catch { $text = '' }
    if ($null -eq $text) { $text = '' }
    $script:UI.TxtTitle.Text = Get-DisplayTitle ([System.IO.Path]::GetFileName($Path))
    $script:UI.TxtBody.Text = $text
    $script:NoteTags = @(Get-NoteTagsFromText $text)
    Update-TagChips
    $script:CurrentPath = $Path
    $script:Dirty = $false
    Set-SaveStatus ('已打开 · ' + [System.IO.Path]::GetFileName($Path))
    $script:UI.SaveStatus.ToolTip = $Path
    Update-Placeholders
}

function New-Editor {
    $script:UI.TxtTitle.Text = ''
    $script:UI.TxtBody.Text = ''
    $script:NoteTags = @()
    Update-TagChips
    $script:CurrentPath = $null
    $script:Dirty = $false
    Set-SaveStatus '新灵感 · 保存后会写入「灵感库」'
    $script:UI.SaveStatus.ToolTip = ''
    Update-Placeholders
}

# ---------------------------------------------------------------- dialogs
$script:DialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="#00000000"
        ResizeMode="NoResize" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        SizeToContent="Height" Width="420" FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="13"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Grid Margin="16">
    <Border CornerRadius="16" Background="{DynamicResource PopupBg}" BorderBrush="{DynamicResource ShellBorder}" BorderThickness="1" Padding="22,20,22,18">
      <Border.Effect>
        <DropShadowEffect BlurRadius="24" ShadowDepth="6" Direction="270" Opacity="0.45" Color="#000000"/>
      </Border.Effect>
      <StackPanel>
        <TextBlock x:Name="DlgTitle" FontSize="15" FontWeight="SemiBold"/>
        <TextBlock x:Name="DlgMsg" TextWrapping="Wrap" FontSize="12.5" Foreground="{DynamicResource TextSecondary}" Margin="0,10,0,0" LineHeight="20"/>
        <Border x:Name="InputWrap" Visibility="Collapsed" CornerRadius="10" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" Padding="10,2" Margin="0,14,0,0">
          <TextBox x:Name="DlgInput" Background="Transparent" BorderThickness="0" FontSize="13" Padding="0,7" CaretBrush="{DynamicResource Accent}"/>
        </Border>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
          <Button x:Name="DlgCancel" Content="取消" Style="{DynamicResource FlatButton}" Margin="0,0,8,0" MinWidth="72"/>
          <Button x:Name="DlgOk" Content="确定" Style="{DynamicResource PrimaryButton}" MinWidth="78"/>
        </StackPanel>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

function Show-Dialog {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet('info', 'input', 'confirm', 'yesno')]
        [string]$Mode = 'info',
        [string]$DefaultText = '',
        [string]$OkText = '确定',
        [string]$CancelText = '取消'
    )
    $w = [System.Windows.Markup.XamlReader]::Parse($script:DialogXaml)
    $w.Owner = $script:UI.Window
    $t = $w.FindName('DlgTitle')
    $m = $w.FindName('DlgMsg')
    $iw = $w.FindName('InputWrap')
    $inp = $w.FindName('DlgInput')
    $ok = $w.FindName('DlgOk')
    $cancel = $w.FindName('DlgCancel')

    $t.Text = $Title
    $m.Text = $Message
    $ok.Content = $OkText
    $cancel.Content = $CancelText
    if ($Mode -eq 'info') { $cancel.Visibility = 'Collapsed' }
    if ($Mode -eq 'yesno') { $cancel.Content = $CancelText }
    if ($Mode -eq 'input') {
        $iw.Visibility = 'Visible'
        $inp.Text = $DefaultText
    }

    $script:DlgResult = $null
    $ok.Add_Click({ param($s, $e) $script:DlgResult = 'ok'; $script:DlgWindow.Close() })
    $cancel.Add_Click({ param($s, $e) $script:DlgResult = 'cancel'; $script:DlgWindow.Close() })
    $script:DlgWindow = $w
    $w.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq 'Escape') { $script:DlgResult = 'cancel'; $script:DlgWindow.Close() }
            if ($e.Key -eq 'Enter') { $script:DlgResult = 'ok'; $script:DlgWindow.Close() }
        })
    $w.Add_Loaded({
            param($s, $e)
            if ($iw.Visibility -eq 'Visible') {
                $inp.Focus() | Out-Null
                $inp.SelectAll()
            } else {
                $ok.Focus() | Out-Null
            }
        })
    $null = $w.ShowDialog()
    if ($script:DlgResult -eq 'ok') {
        if ($Mode -eq 'input') { return $inp.Text }
        return $true
    }
    return $false
}

function Show-Toast {
    param([string]$Message)
    $script:UI.ToastText.Text = $Message
    $script:UI.Toast.Visibility = 'Visible'
    $script:UI.Toast.IsHitTestVisible = $false
}

# ---------------------------------------------------------------- window control
function Show-MainWindow {
    $w = $script:UI.Window
    if (-not $w.IsVisible) { $w.Show() }
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($w)).Handle
        if ($h -ne [IntPtr]::Zero) {
            [Lingan.Native]::ForceShow($h)
            [Lingan.Native]::RoundCorners($h)
        }
    } catch { }
    if ($w.WindowState -eq 'Minimized') { $w.WindowState = 'Normal' }
    $w.Activate()
    $w.Topmost = $true
    $w.Topmost = $false
    $w.Focus() | Out-Null
    Apply-Theme
}

function Hide-MainWindow {
    $script:UI.Window.Hide()
}

function Exit-App {
    $script:Exiting = $true
    try { if ($script:Hotkey) { $script:Hotkey.Unregister(1); $script:Hotkey.Destroy() } } catch { }
    try {
        if ($script:Tray) {
            $script:Tray.Visible = $false
            $script:Tray.Dispose()
        }
    } catch { }
    try { $script:App.Shutdown() } catch { }
}

# ---------------------------------------------------------------- hotkey
function Get-VirtualKey {
    param([string]$Name)
    try {
        $v = [System.Enum]::Parse([System.Windows.Forms.Keys], $Name, $true)
        return [int]$v
    } catch {
        return 0
    }
}

function ConvertTo-HotkeySpec {
    param([string]$Text)
    $mods = 0
    $vk = 0
    if ([string]::IsNullOrWhiteSpace($Text)) { return @{ Mods = 0; VK = 0 } }
    foreach ($part in ($Text -split '\+')) {
        $p = $part.Trim()
        if ($p.Length -eq 0) { continue }
        $low = $p.ToLower()
        if ($low -eq 'ctrl' -or $low -eq 'control') { $mods = $mods -bor 2; continue }
        if ($low -eq 'alt') { $mods = $mods -bor 1; continue }
        if ($low -eq 'shift') { $mods = $mods -bor 4; continue }
        if ($low -eq 'win' -or $low -eq 'windows' -or $low -eq 'super') { $mods = $mods -bor 8; continue }
        $vk = Get-VirtualKey $p
    }
    return @{ Mods = $mods; VK = $vk }
}

function Format-HotkeyName {
    param([string]$Text)
    return ($Text -replace 'OemMinus', '-' -replace 'OemPlus', '=' -replace 'OemComma', ',' -replace 'OemPeriod', '.' -replace 'OemQuestion', '/')
}

function Register-Hotkey {
    param([string]$Text)
    $spec = ConvertTo-HotkeySpec $Text
    if ($spec.Mods -eq 0 -or $spec.VK -eq 0) { return $false }
    if ($script:HotkeyRegistered) {
        try { $script:Hotkey.Unregister(1) } catch { }
        $script:HotkeyRegistered = $false
    }
    $ok = $false
    try { $ok = $script:Hotkey.Register(1, [uint32]$spec.Mods, [uint32]$spec.VK) } catch { $ok = $false }
    $script:HotkeyRegistered = $ok
    
    return $ok
}

function Apply-HotkeyFromConfig {
    $ok = Register-Hotkey $script:Config.hotkey
    $fallback = $false
    if (-not $ok) {
        # the configured combo may already be owned by another program: try a few sane alternatives
        foreach ($alt in @('Ctrl+Alt+N', 'Ctrl+Shift+Space', 'Ctrl+Alt+L')) {
            if ($alt -eq $script:Config.hotkey) { continue }
            if (Register-Hotkey $alt) {
                $script:Config.hotkey = $alt
                Save-Config
                $ok = $true
                $fallback = $true
                break
            }
        }
    }
    if ($script:UI.HotkeyDisplay) {
        $script:UI.HotkeyDisplay.Text = (Format-HotkeyName $script:Config.hotkey)
    }
    if (-not $ok) {
        if ($script:UI.HotkeyState) {
            $script:UI.HotkeyState.Text = '注册失败：该组合可能已被其他程序占用'
            $script:UI.HotkeyState.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Danger')
        }
    } elseif ($fallback) {
        if ($script:UI.HotkeyState) {
            $script:UI.HotkeyState.Text = '原快捷键被占用，已自动改用 ' + (Format-HotkeyName $script:Config.hotkey)
            $script:UI.HotkeyState.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Warn')
        }
    } else {
        if ($script:UI.HotkeyState) {
            $script:UI.HotkeyState.Text = '已生效 · 在任何界面按下即可呼出'
            $script:UI.HotkeyState.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'TextSecondary')
        }
    }
    return $ok
}

function Start-HotkeyRecording {
    $script:Recording = $true
    $script:UI.BtnRecord.Content = '请按下组合键…（Esc 取消）'
    $script:UI.ViewSettings.Focus() | Out-Null
}

function Stop-HotkeyRecording {
    $script:Recording = $false
    $script:UI.BtnRecord.Content = '录制新快捷键'
}

# ---------------------------------------------------------------- autostart
function Get-AutostartValue {
    try {
        $v = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name '灵感速记' -ErrorAction Stop
        return $v
    } catch {
        return $null
    }
}

function Set-Autostart {
    param([bool]$Enable)
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        if ($Enable) {
            $launcher = Join-Path $script:AppRoot '启动灵感速记.vbs'
            $val = 'wscript.exe "' + $launcher + '"'
            Set-ItemProperty -Path $key -Name '灵感速记' -Value $val
        } else {
            Remove-ItemProperty -Path $key -Name '灵感速记' -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        Write-Log ('自启动设置失败: ' + $_.Exception.Message)
        return $false
    }
}

# ---------------------------------------------------------------- tray
function New-AppIcon {
    if (Test-Path -LiteralPath $script:IconPath) {
        try {
            $src = [System.Drawing.Image]::FromFile($script:IconPath)
            $size = 32
            $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.DrawImage($src, 0, 0, $size, $size)
            $g.Dispose()
            $src.Dispose()
            $h = $bmp.GetHicon()
            $icon = [System.Drawing.Icon]::FromHandle($h)
            $bmp.Dispose()
            return $icon
        } catch {
            Write-Log ('tray icon failed: ' + $_.Exception.Message)
        }
    }
    $size = 32
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $accent = ConvertTo-WColor $script:Config.accent
    $col = [System.Drawing.Color]::FromArgb(255, $accent.R, $accent.G, $accent.B)
    $rect = New-Object System.Drawing.RectangleF(3, 3, ($size - 6), ($size - 6))
    $rad = 9.0
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($rect.X, $rect.Y, $rad, $rad, 180, 90)
    $path.AddArc(($rect.Right - $rad), $rect.Y, $rad, $rad, 270, 90)
    $path.AddArc(($rect.Right - $rad), ($rect.Bottom - $rad), $rad, $rad, 0, 90)
    $path.AddArc($rect.X, ($rect.Bottom - $rad), $rad, $rad, 90, 90)
    $path.CloseFigure()
    $brush = New-Object System.Drawing.SolidBrush($col)
    $g.FillPath($brush, $path)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.2)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen, 10, 12, 22, 12)
    $g.DrawLine($pen, 10, 17, 22, 17)
    $g.DrawLine($pen, 10, 22, 17, 22)
    $h = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($h)
    $g.Dispose()
    $pen.Dispose()
    $brush.Dispose()
    return $icon
}

function Initialize-Tray {
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = New-AppIcon
    $tray.Text = '灵感速记'
    $tray.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $mOpen = $menu.Items.Add('打开灵感速记')
    $mNew = $menu.Items.Add('新建灵感')
    $mBrowse = $menu.Items.Add('查看灵感')
    $null = $menu.Items.Add('-')
    $mExit = $menu.Items.Add('退出')

    $mOpen.add_Click({
            $script:UI.Window.Dispatcher.Invoke([Action] {
                    Show-MainWindow
                    Show-View 'Home'
                })
        })
    $mNew.add_Click({
            $script:UI.Window.Dispatcher.Invoke([Action] {
                    Show-MainWindow
                    Show-View 'New'
                    New-Editor
                })
        })
    $mBrowse.add_Click({
            $script:UI.Window.Dispatcher.Invoke([Action] {
                    Show-MainWindow
                    Show-View 'List'
                })
        })
    $mExit.add_Click({
            $script:UI.Window.Dispatcher.Invoke([Action] { Exit-App })
        })

    $tray.ContextMenuStrip = $menu
    $tray.add_MouseDoubleClick({
            $script:UI.Window.Dispatcher.Invoke([Action] {
                    Show-MainWindow
                    Show-View 'Home'
                })
        })
    $tray.add_BalloonTipClicked({
            $script:UI.Window.Dispatcher.Invoke([Action] {
                    Show-MainWindow
                    Show-View 'Home'
                })
        })
    $script:Tray = $tray
    $script:TrayMenu = $menu
}

# ---------------------------------------------------------------- tags / lists
$script:TagVocab = @(
    '灵感', '想法', '待办', '计划', '复盘', '学习', '工作', '生活', '阅读', '写作',
    '设计', '产品', '代码', '效率', '习惯', '情绪', '人际', '健康', '理财', '时间管理',
    '创意', '观察', '问题', '假设', '结论', '摘录', '疑问', '目标', '项目', '方法论',
    '心理', '认知', '表达', '沟通', '决策', '取舍', '随想', '隐喻', '故事', '场景',
    '用户', '需求', '反馈', '数据', '实验', '自动化', '工具', '音乐', '电影', '旅行',
    '美食', '清晨', '深夜', '通勤', '会议', '读书笔记', '灵光一现', '要不要做', '为什么'
)
$script:TagChips = @()
$script:NoteTags = @()

function Get-RandomTagSet {
    param([int]$Count = 7)
    $shuffled = @($script:TagVocab | Sort-Object { Get-Random })
    if ($shuffled.Count -le $Count) { return , $shuffled }
    return , @($shuffled[0..($Count - 1)])
}

function New-TagChip {
    param([string]$Tag)
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = ('#' + $Tag)
    $btn.Tag = $Tag
    $btn.Style = [System.Runtime.CompilerServices.RuntimeHelpers]::GetObjectValue($script:App.Resources['TagChip'])
    $btn.Add_Click({
            param($s, $e)
            Toggle-NoteTag ([string]$s.Tag)
        })
    return $btn
}

function Update-TagChipStates {
    param($Chips)
    foreach ($chip in $Chips) {
        $tag = [string]$chip.Tag
        if ($script:NoteTags -contains $tag) {
            $chip.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'AccentSoft')
            $chip.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, 'Accent')
            $chip.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'Accent')
        } else {
            $chip.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'CardBg')
            $chip.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, 'CardBorder')
            $chip.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'TextSecondary')
        }
    }
}

function Update-TagChips {
    param([switch]$Reshuffle)
    $panel = $script:UI.TagPanel
    if (-not $panel) { return }
    if ($Reshuffle -or $null -eq $script:TagChips -or $script:TagChips.Count -eq 0) {
        $set = New-Object System.Collections.ArrayList
        foreach ($t in (Get-RandomTagSet 7)) { $null = $set.Add($t) }
        foreach ($t in $script:NoteTags) { if (-not $set.Contains($t)) { $null = $set.Add($t) } }
        $script:TagChips = @($set.ToArray())
    } else {
        $set = New-Object System.Collections.ArrayList
        foreach ($t in $script:TagChips) { $null = $set.Add($t) }
        foreach ($t in $script:NoteTags) { if (-not $set.Contains($t)) { $null = $set.Add($t) } }
        $script:TagChips = @($set.ToArray())
    }
    $panel.Children.Clear()
    $chips = New-Object System.Collections.ArrayList
    foreach ($t in $script:TagChips) {
        $chip = New-TagChip $t
        $null = $panel.Children.Add($chip)
        $null = $chips.Add($chip)
    }
    Update-TagChipStates $chips.ToArray()
}

function Get-NoteTagsFromText {
    param([string]$Text)
    $result = @()
    if ([string]::IsNullOrEmpty($Text)) { return , $result }
    foreach ($m in [regex]::Matches($Text, '#([\p{L}\p{N}_]{1,12})')) {
        $t = $m.Groups[1].Value
        if (($script:TagVocab -contains $t) -and ($result -notcontains $t)) { $result += $t }
    }
    return , $result
}

function Toggle-NoteTag {
    param([string]$Tag)
    if ([string]::IsNullOrWhiteSpace($Tag)) { return }
    $list = New-Object System.Collections.ArrayList
    foreach ($t in $script:NoteTags) { $null = $list.Add($t) }
    $token = '#' + $Tag
    $body = $script:UI.TxtBody.Text
    if ($list.Contains($Tag)) {
        $null = $list.Remove($Tag)
        $body = [regex]::Replace($body, ('\s*' + [regex]::Escape($token) + '(?![\p{L}\p{N}_])'), '')
        $script:UI.TxtBody.Text = $body.TrimEnd()
    } else {
        $null = $list.Add($Tag)
        $trimmed = $body.TrimEnd()
        if ($trimmed.Length -gt 0) { $trimmed = $trimmed + "`r`n" }
        $script:UI.TxtBody.Text = $trimmed + $token
    }
    $script:NoteTags = @($list.ToArray())
    Update-TagChips
    Mark-Dirty
}

function Invoke-ListCommand {
    param([ValidateSet('bullet', 'number', 'indent', 'outdent')][string]$Mode)
    $tb = $script:UI.TxtBody
    $text = $tb.Text
    if ([string]::IsNullOrEmpty($text)) { return }
    $lines = New-Object System.Collections.ArrayList
    foreach ($l in [regex]::Split($text, "`r`n")) { $null = $lines.Add($l) }
    $selStart = $tb.SelectionStart
    $selEnd = $selStart + $tb.SelectionLength
    $maxIdx = [Math]::Max(0, $text.Length - 1)
    $first = $tb.GetLineIndexFromCharacterIndex([Math]::Min($selStart, $maxIdx))
    $last = $tb.GetLineIndexFromCharacterIndex([Math]::Min($selEnd, $maxIdx))
    if ($first -lt 0) { $first = 0 }
    if ($last -lt $first) { $last = $first }
    if ($last -ge $lines.Count) { $last = $lines.Count - 1 }
    $n = 0
    for ($i = $first; $i -le $last; $i++) {
        $line = $lines[$i]
        $m = [regex]::Match($line, '^(\s*)(?:[•\-\*]|\d+[.)])\s+')
        $pad = $m.Groups[1].Value
        $rest = $line.Substring($m.Length)
        switch ($Mode) {
            'bullet' { $n++; $lines[$i] = $pad + '• ' + $rest }
            'number' { $n++; $lines[$i] = $pad + $n + '. ' + $rest }
            'indent' { $lines[$i] = '  ' + $line }
            'outdent' {
                if ($line.StartsWith('  ')) { $lines[$i] = $line.Substring(2) }
                elseif ($line.StartsWith(' ')) { $lines[$i] = $line.Substring(1) }
            }
        }
    }
    $newText = ($lines -join "`r`n")
    $tb.Text = $newText
    $offset = 0
    for ($i = 0; $i -lt $first; $i++) { $offset += $lines[$i].Length + 2 }
    $blockLen = 0
    for ($i = $first; $i -le $last; $i++) { $blockLen += $lines[$i].Length + 2 }
    $tb.SelectionStart = [Math]::Min($offset, $newText.Length)
    $tb.SelectionLength = [Math]::Max(0, [Math]::Min($blockLen - 2, $newText.Length - $tb.SelectionStart))
    $tb.Focus() | Out-Null
    Mark-Dirty
}

function Get-WidgetImagePath {
    $name = [string]$script:Config.widgetImage
    if ($name) {
        if ([System.IO.Path]::IsPathRooted($name)) {
            if (Test-Path -LiteralPath $name) { return $name }
        } else {
            $cand = Join-Path $script:AppRoot $name
            if (Test-Path -LiteralPath $cand) { return $cand }
        }
    }
    $def = Join-Path $script:AppRoot 'widget.png'
    if (Test-Path -LiteralPath $def) { return $def }
    return $null
}

function Get-WidgetImageSource {
    $path = Get-WidgetImagePath
    if (-not $path) { return $null }
    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource = New-Object System.Uri($path)
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.EndInit()
        $bmp.Freeze()
        return $bmp
    } catch {
        Write-Log ('widget image failed: ' + $_.Exception.Message)
        return $null
    }
}

function Update-WidgetState {
    try {
        Invoke-WidgetRelease -Instant
        Hide-WidgetBubble
        if ($script:Config.widgetVisible) { $script:UI.WidgetLayer.Visibility = 'Visible' } else { $script:UI.WidgetLayer.Visibility = 'Collapsed' }
        $bmp = Get-WidgetImageSource
        if ($bmp) {
            $raw = [System.Runtime.CompilerServices.RuntimeHelpers]::GetObjectValue($bmp)
            $script:UI.WidgetImage.Source = $raw
            $geo = New-Object System.Windows.Media.RectangleGeometry
            $geo.Rect = New-Object System.Windows.Rect(0, 0, 132, 132)
            $geo.RadiusX = 24
            $geo.RadiusY = 24
            $script:UI.WidgetImage.Clip = $geo
            $script:UI.WidgetMascot.Visibility = 'Visible'
        } else {
            $script:UI.WidgetMascot.Visibility = 'Collapsed'
        }
        if ($script:UI.WidgetState) {
            $path = Get-WidgetImagePath
            $label = '未设置'
            if ($path) { $label = [System.IO.Path]::GetFileName($path) }
            $script:UI.WidgetState.Text = ('图片：{0} · 点一下冒气泡 3 秒，连点换台词；按住拖动，右键换图' -f $label)
        }
    } catch {
        Write-Log ('widget state failed: ' + $_.Exception.Message)
    }
}

function Get-WidgetSize([double]$w, [double]$h) {
    $rw = 320.0
    $rh = 206.0
    if ($script:UI.WidgetRoot.Width -gt 0) { $rw = [double]$script:UI.WidgetRoot.Width }
    if ($script:UI.WidgetRoot.Height -gt 0) { $rh = [double]$script:UI.WidgetRoot.Height }
    if ($rw -gt $w) { $rw = $w }
    if ($rh -gt $h) { $rh = $h }
    return @($rw, $rh)
}

function Set-WidgetPosition([double]$left, [double]$top) {
    $layer = $script:UI.WidgetLayer
    $w = 780.0
    $h = 560.0
    if ($layer.ActualWidth -gt 0) { $w = [double]$layer.ActualWidth }
    if ($layer.ActualHeight -gt 0) { $h = [double]$layer.ActualHeight }
    $size = Get-WidgetSize $w $h
    $rw = $size[0]
    $rh = $size[1]
    $maxL = [Math]::Max(0.0, $w - $rw)
    $maxT = [Math]::Max(0.0, $h - $rh)
    $left = [Math]::Max(0.0, [Math]::Min($left, $maxL))
    $top = [Math]::Max(0.0, [Math]::Min($top, $maxT))
    [System.Windows.Controls.Canvas]::SetLeft($script:UI.WidgetRoot, $left)
    [System.Windows.Controls.Canvas]::SetTop($script:UI.WidgetRoot, $top)
}

function Apply-WidgetPosition {
    $layer = $script:UI.WidgetLayer
    $w = 780.0
    $h = 560.0
    if ($layer.ActualWidth -gt 0) { $w = [double]$layer.ActualWidth }
    if ($layer.ActualHeight -gt 0) { $h = [double]$layer.ActualHeight }
    $r = [double]$script:Config.widgetRight
    $b = [double]$script:Config.widgetBottom
    if ($r -lt 0) { $r = 10 }
    if ($b -lt 0) { $b = 10 }
    $size = Get-WidgetSize $w $h
    Set-WidgetPosition ($w - $size[0] - $r) ($h - $size[1] - $b)
}

function Save-WidgetPosition {
    $layer = $script:UI.WidgetLayer
    $w = 780.0
    $h = 560.0
    if ($layer.ActualWidth -gt 0) { $w = [double]$layer.ActualWidth }
    if ($layer.ActualHeight -gt 0) { $h = [double]$layer.ActualHeight }
    $l = [double][System.Windows.Controls.Canvas]::GetLeft($script:UI.WidgetRoot)
    $tp = [double][System.Windows.Controls.Canvas]::GetTop($script:UI.WidgetRoot)
    $size = Get-WidgetSize $w $h
    $script:Config.widgetRight = [int][Math]::Round($w - ($l + $size[0]))
    $script:Config.widgetBottom = [int][Math]::Round($h - ($tp + $size[1]))
    Save-Config
}

function Set-WidgetSquash([double]$sx, [double]$sy, [int]$ms) {
    try {
        $dur = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($ms))
        $ease = New-Object System.Windows.Media.Animation.CubicEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $ax = New-Object System.Windows.Media.Animation.DoubleAnimation($sx, $dur)
        $ax.EasingFunction = $ease
        $ax.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::HoldEnd
        $ay = New-Object System.Windows.Media.Animation.DoubleAnimation($sy, $dur)
        $ay.EasingFunction = $ease
        $ay.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::HoldEnd
        $script:UI.WidgetSquash.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $ax)
        $script:UI.WidgetSquash.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $ay)
    } catch {
        Write-Log ('widget squash failed: ' + $_.Exception.Message)
    }
}

function Invoke-WidgetPress {
    try {
        Set-WidgetSquash 1.10 0.84 70
        if ($null -eq $script:WidgetPressTimer) {
            $script:WidgetPressTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:WidgetPressTimer.Interval = [TimeSpan]::FromMilliseconds(260)
            $script:WidgetPressTimer.Add_Tick({
                    try {
                        $script:WidgetPressTimer.Stop()
                        if ($script:WidgetHeld) { Set-WidgetSquash 1.14 0.78 130 }
                    } catch {
                        Write-Log ('widget press tick failed: ' + $_.Exception.Message)
                    }
                })
        }
        $script:WidgetHeld = $true
        $script:WidgetPressTimer.Stop()
        $script:WidgetPressTimer.Start()
    } catch {
        Write-Log ('widget press failed: ' + $_.Exception.Message)
    }
}

function New-WidgetKeyTrack([object[]]$frames) {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $anim.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::HoldEnd
    foreach ($f in $frames) {
        $kf = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame
        $kf.KeyTime = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds([double]$f[0]))
        $kf.Value = [double]$f[1]
        $ease = New-Object System.Windows.Media.Animation.CubicEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
        $kf.EasingFunction = $ease
        [void]$anim.KeyFrames.Add($kf)
    }
    return $anim
}

function Invoke-WidgetRelease([switch]$Instant) {
    $script:WidgetHeld = $false
    try {
        if ($script:WidgetPressTimer) { $script:WidgetPressTimer.Stop() }
    } catch { }
    try {
        if ($Instant) {
            $script:UI.WidgetSquash.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null)
            $script:UI.WidgetSquash.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $null)
            return
        }
        # 橡皮鸭回弹：先弹过头一点，再小幅回摆两下
        $ax = New-WidgetKeyTrack @(
            @(120, 0.92),
            @(260, 1.05),
            @(400, 0.98),
            @(540, 1.0)
        )
        $ay = New-WidgetKeyTrack @(
            @(120, 1.12),
            @(260, 0.95),
            @(400, 1.02),
            @(540, 1.0)
        )
        $script:UI.WidgetSquash.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $ax)
        $script:UI.WidgetSquash.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $ay)
    } catch {
        Write-Log ('widget release failed: ' + $_.Exception.Message)
    }
}
function Select-WidgetImage {
    try {
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Title = '选择插件图片'
        $dlg.Filter = '图片文件 (*.png;*.jpg;*.jpeg;*.gif;*.bmp)|*.png;*.jpg;*.jpeg;*.gif;*.bmp|所有文件 (*.*)|*.*'
        $dlg.InitialDirectory = $script:AppRoot
        if ($dlg.ShowDialog() -ne $true) { return }
        $src = $dlg.FileName
        $ext = [System.IO.Path]::GetExtension($src).ToLower()
        $dest = Join-Path $script:AppRoot ('widget' + $ext)
        if ($src -ne $dest) { [System.IO.File]::Copy($src, $dest, $true) }
        $script:Config.widgetImage = [System.IO.Path]::GetFileName($dest)
        $script:Config.widgetVisible = $true
        Save-Config
        Update-WidgetState
        if ($script:UI.ChkWidget) { $script:UI.ChkWidget.IsChecked = $true }
    } catch {
        $null = Show-Dialog -Title '更换插件图片失败' -Message $_.Exception.Message -Mode 'info'
    }
}
function Update-WhaleBubble {
    $count = 0
    try {
        $lib = Get-LibraryPath
        if (Test-Path -LiteralPath $lib) {
            $today = (Get-Date).Date
            foreach ($f in [System.IO.Directory]::GetFiles($lib, '*.txt')) {
                if ([System.IO.File]::GetLastWriteTime($f).Date -eq $today) { $count++ }
            }
        }
    } catch { $count = 0 }
    $script:WidgetCountText = ('今天你写了 {0} 条灵感' -f $count)
    try {
        if ($script:UI.WidgetBubbleText -and $script:BubbleVisible -ne $true) {
            $script:UI.WidgetBubbleText.Text = $script:WidgetCountText
        }
    } catch { }
}

function Get-PoemPath {
    return (Join-Path $script:AppRoot '对话框.txt')
}

function Get-PoemLines {
    $list = New-Object System.Collections.ArrayList
    try {
        $path = Get-PoemPath
        if (Test-Path -LiteralPath $path) {
            foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
                $s = $line.Trim()
                if ($s.Length -gt 0) { [void]$list.Add($s) }
            }
        }
    } catch {
        Write-Log ('poem read failed: ' + $_.Exception.Message)
    }
    return @($list.ToArray())
}

function Save-PoemLines([string[]]$lines) {
    try {
        $clean = @()
        foreach ($line in $lines) {
            $s = [string]$line
            if ($null -eq $s) { continue }
            $s = $s.Trim()
            if ($s.Length -gt 0) { $clean += $s }
        }
        $text = ($clean -join "`r`n`r`n") + "`r`n"
        [System.IO.File]::WriteAllText((Get-PoemPath), $text, (New-Object System.Text.UTF8Encoding $true))
        $script:WidgetLines = $null
        Write-Log ('poems saved: ' + $clean.Count)
        return $clean.Count
    } catch {
        Write-Log ('poem write failed: ' + $_.Exception.Message)
        return -1
    }
}

function Update-PoemState {
    try {
        if (-not $script:UI.PoemState) { return }
        $count = @(Get-PoemLines).Count
        $script:UI.PoemState.Text = ('共 {0} 句台词（对话框.txt）· 连点挂件随机播一句' -f $count)
    } catch {
        Write-Log ('poem state failed: ' + $_.Exception.Message)
    }
}

function Refresh-Poems {
    try {
        $lines = @(Get-PoemLines)
        if ($script:UI.PoemList) {
            $script:UI.PoemList.ItemsSource = $null
            $script:UI.PoemList.ItemsSource = $lines
        }
        if ($script:UI.PoemCount) {
            $script:UI.PoemCount.Text = ('{0} 句' -f $lines.Count)
        }
        if ($script:UI.PoemEdit) {
            $script:UI.PoemEdit.Text = ''
        }
        if ($script:UI.PoemHint) {
            $script:UI.PoemHint.Text = '提示：改完会立刻写回 对话框.txt，挂件下一次点击就用新台词。'
        }
        Update-PoemState
    } catch {
        Write-Log ('poems refresh failed: ' + $_.Exception.Message)
    }
}

function Get-WidgetLines {
    if ($null -ne $script:WidgetLines) { return $script:WidgetLines }
    $script:WidgetLines = @(Get-PoemLines)
    return $script:WidgetLines
}

function Hide-WidgetBubble {
    try {
        if ($script:BubbleTimer) { $script:BubbleTimer.Stop() }
        if ($script:UI.WidgetBubble) {
            $script:UI.WidgetBubble.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
            $script:UI.WidgetBubble.Visibility = 'Collapsed'
        }
        $script:BubbleVisible = $false
    } catch {
        Write-Log ('widget bubble hide failed: ' + $_.Exception.Message)
    }
}

function Show-WidgetBubble([string]$Text, [int]$Ms) {
    try {
        if (-not $script:UI.WidgetBubble) { return }
        if ($Text) { $script:UI.WidgetBubbleText.Text = $Text }
        $script:BubbleVisible = $true
        $script:UI.WidgetBubble.Visibility = 'Visible'
        $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(140)))
        $script:UI.WidgetBubble.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
        if ($null -eq $script:BubbleTimer) {
            $script:BubbleTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:BubbleTimer.Add_Tick({
                    try {
                        if ($script:BubblePhase -eq 'hold') {
                            $script:BubblePhase = 'fade'
                            $fadeOut = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150)))
                            $script:UI.WidgetBubble.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
                            $script:BubbleTimer.Interval = [TimeSpan]::FromMilliseconds(200)
                        } else {
                            $script:BubbleTimer.Stop()
                            $script:UI.WidgetBubble.Visibility = 'Collapsed'
                            $script:BubbleVisible = $false
                        }
                    } catch {
                        Write-Log ('widget bubble tick failed: ' + $_.Exception.Message)
                    }
                })
        }
        $script:BubblePhase = 'hold'
        $script:BubbleTimer.Stop()
        $script:BubbleTimer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(300, $Ms))
        $script:BubbleTimer.Start()
    } catch {
        Write-Log ('widget bubble show failed: ' + $_.Exception.Message)
    }
}

function Invoke-WidgetTap {
    try {
        $now = [DateTime]::Now
        $rapid = $false
        if ($script:WidgetLastTap -is [DateTime]) {
            if (($now - $script:WidgetLastTap).TotalSeconds -lt 4.0) { $rapid = $true }
        }
        $script:WidgetLastTap = $now
        if ($rapid) {
            $lines = @(Get-WidgetLines)
            if ($lines.Count -gt 0) {
                Show-WidgetBubble ([string]($lines | Get-Random)) 3000
            } else {
                Show-WidgetBubble $script:WidgetCountText 3000
            }
        } else {
            Show-WidgetBubble $script:WidgetCountText 3000
        }
    } catch {
        Write-Log ('widget tap failed: ' + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- xaml
$script:StylesXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Style TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
  </Style>
  <Style TargetType="TextBox">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    <Setter Property="CaretBrush" Value="{DynamicResource Accent}"/>
    <Setter Property="SelectionBrush" Value="{DynamicResource Accent}"/>
    <Setter Property="SelectionOpacity" Value="0.35"/>
  </Style>
  <Style x:Key="WinButton" TargetType="Button">
    <Setter Property="Width" Value="34"/>
    <Setter Property="Height" Value="26"/>
    <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
    <Setter Property="FontSize" Value="10"/>
    <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="7" Background="Transparent">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgHover}"/>
              <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgPress}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="FlatButton" TargetType="Button">
    <Setter Property="Padding" Value="12,7"/>
    <Setter Property="FontSize" Value="12.5"/>
    <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="9" Background="Transparent" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgHover}"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgPress}"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.4"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="PrimaryButton" TargetType="Button">
    <Setter Property="Padding" Value="18,8"/>
    <Setter Property="FontSize" Value="12.5"/>
    <Setter Property="Foreground" Value="#FFFFFF"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="10" Background="{DynamicResource Accent}" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Opacity" Value="0.9"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Opacity" Value="0.78"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="ScrollBar">
    <Setter Property="Width" Value="9"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="IsTabStop" Value="False"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Grid Background="Transparent">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.DecreaseRepeatButton>
                <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
              </Track.DecreaseRepeatButton>
              <Track.IncreaseRepeatButton>
                <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
              </Track.IncreaseRepeatButton>
              <Track.Thumb>
                <Thumb Cursor="Hand">
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border CornerRadius="4" Background="{DynamicResource ScrollThumb}" Margin="2,0"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </Grid>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>  <Style x:Key="CardButton" TargetType="Button">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Background" Value="{DynamicResource CardBg}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="16" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgHover}"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource CardBorderHover}"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgPress}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="TagChip" TargetType="Button">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FontSize" Value="11.5"/>
    <Setter Property="Width" Value="94"/>
    <Setter Property="Height" Value="28"/>
    <Setter Property="Margin" Value="0,0,8,8"/>
    <Setter Property="Background" Value="{DynamicResource CardBg}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/>
    <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="14" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource CardBorderHover}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="MiniButton" TargetType="Button">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FontSize" Value="11.5"/>
    <Setter Property="Padding" Value="10,5"/>
    <Setter Property="Background" Value="{DynamicResource CardBg}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/>
    <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="9" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgHover}"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource CardBorderHover}"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgPress}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="SegRadio" TargetType="RadioButton">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FontSize" Value="12.5"/>
    <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Border x:Name="b" CornerRadius="9" Padding="14,7" Background="Transparent" BorderThickness="1" BorderBrush="Transparent">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgHover}"/>
            </Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource AccentSoft}"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Accent}"/>
              <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="ListItemStyle" TargetType="ListBoxItem">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Border x:Name="b" CornerRadius="10" Margin="0,2" Padding="12,9" Background="Transparent" BorderThickness="1" BorderBrush="Transparent">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgHover}"/>
            </Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource AccentSoft}"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Accent}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="RowListItemStyle" TargetType="ListBoxItem">
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Border x:Name="b" CornerRadius="12" Margin="0,0,0,8" Background="Transparent" BorderThickness="0">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="#10FFFFFF"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="RowIconButton" TargetType="Button">
    <Setter Property="Width" Value="30"/>
    <Setter Property="Height" Value="28"/>
    <Setter Property="Margin" Value="4,0,0,0"/>
    <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="8" Background="Transparent">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgHover}"/>
              <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource CardBgPress}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="SectionCard" TargetType="Border">
    <Setter Property="CornerRadius" Value="14"/>
    <Setter Property="Background" Value="{DynamicResource CardBg}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="16,11"/>
  </Style>
  <Style TargetType="CheckBox">
    <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FontSize" Value="12.5"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" Background="Transparent">
            <Border x:Name="box" Width="18" Height="18" CornerRadius="6" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" VerticalAlignment="Center">
              <TextBlock x:Name="tick" Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="9" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
            </Border>
            <ContentPresenter Margin="9,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="box" Property="Background" Value="{DynamicResource Accent}"/>
              <Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Accent}"/>
              <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="ScrollBarThin" TargetType="ScrollBar">
    <Setter Property="Width" Value="8"/>
  </Style>
</ResourceDictionary>
'@

$script:WindowXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="灵感速记" Width="860" Height="860"
        WindowStyle="None" AllowsTransparency="True" Background="#00000000"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        ShowInTaskbar="True" UseLayoutRounding="True" SnapsToDevicePixels="True"
        FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="13"
        TextOptions.TextFormattingMode="Display">
  <Grid x:Name="RootGrid">
    <Border x:Name="Shell" CornerRadius="20" Background="{DynamicResource ShellBg}" BorderThickness="1" BorderBrush="{DynamicResource ShellBorder}">
      <Border.Effect>
        <DropShadowEffect BlurRadius="32" ShadowDepth="8" Direction="270" Opacity="0.42" Color="#000000"/>
      </Border.Effect>
      <Grid>
        <Border CornerRadius="20" IsHitTestVisible="False">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#12FFFFFF" Offset="0"/>
              <GradientStop Color="#00FFFFFF" Offset="0.55"/>
              <GradientStop Color="#08FFFFFF" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
        </Border>
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="46"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <Grid x:Name="TitleBar" Grid.Row="0" Background="Transparent">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
              <Border x:Name="AppBadge" Width="20" Height="20" CornerRadius="6" Background="{DynamicResource Accent}">
                <TextBlock x:Name="AppBadgeGlyph" Text="&#xE70F;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock Text="灵感速记" FontSize="12.5" FontWeight="SemiBold" Margin="9,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0">
              <Button x:Name="BtnMin" Style="{DynamicResource WinButton}" Content="&#xE921;" Margin="0,0,2,0"/>
              <Button x:Name="BtnClose" Style="{DynamicResource WinButton}" Content="&#xE711;"/>
            </StackPanel>
          </Grid>

          <Grid x:Name="ViewHost" Grid.Row="1">

            <Grid x:Name="ViewHome" Margin="26,2,26,22">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <StackPanel Margin="6,4,0,16">
                <TextBlock x:Name="HomeTitle" Text="今天想记点什么？" FontSize="24" FontWeight="SemiBold"/>
                <TextBlock x:Name="HomeSub" Text="所有灵感都会保存在「灵感库」文件夹里" FontSize="12.5" Foreground="{DynamicResource TextSecondary}" Margin="0,7,0,0"/>
              </StackPanel>
              <Grid Grid.Row="1">
                <Grid.RowDefinitions>
                  <RowDefinition Height="*"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Button x:Name="BtnGoNew" Grid.Row="0" Grid.Column="0" Style="{DynamicResource CardButton}" Margin="0,0,7,7">
                  <StackPanel Margin="18,14,18,14" VerticalAlignment="Center">
                    <Border Width="38" Height="38" CornerRadius="12" Background="{DynamicResource AccentSoft}" HorizontalAlignment="Left">
                      <TextBlock Text="&#xE70F;" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="新建灵感" FontSize="16" FontWeight="SemiBold" Margin="0,10,0,2"/>
                    <TextBlock Text="记录一条新的想法" FontSize="12" Foreground="{DynamicResource TextSecondary}"/>
                  </StackPanel>
                </Button>

                <Button x:Name="BtnGoList" Grid.Row="0" Grid.Column="1" Style="{DynamicResource CardButton}" Margin="7,0,0,7">
                  <StackPanel Margin="18,14,18,14" VerticalAlignment="Center">
                    <Border Width="38" Height="38" CornerRadius="12" Background="{DynamicResource AccentSoft}" HorizontalAlignment="Left">
                      <TextBlock Text="&#xE8A5;" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="查看灵感" FontSize="16" FontWeight="SemiBold" Margin="0,10,0,2"/>
                    <TextBlock Text="按时间翻看所有记录" FontSize="12" Foreground="{DynamicResource TextSecondary}"/>
                  </StackPanel>
                </Button>

                <Button x:Name="BtnGoManage" Grid.Row="1" Grid.Column="0" Style="{DynamicResource CardButton}" Margin="0,7,7,0">
                  <StackPanel Margin="18,14,18,14" VerticalAlignment="Center">
                    <Border Width="38" Height="38" CornerRadius="12" Background="{DynamicResource AccentSoft}" HorizontalAlignment="Left">
                      <TextBlock Text="&#xE8FD;" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="管理灵感" FontSize="16" FontWeight="SemiBold" Margin="0,10,0,2"/>
                    <TextBlock Text="重命名 · 删除 · 定位文件" FontSize="12" Foreground="{DynamicResource TextSecondary}"/>
                  </StackPanel>
                </Button>

                <Button x:Name="BtnGoSettings" Grid.Row="1" Grid.Column="1" Style="{DynamicResource CardButton}" Margin="7,7,0,0">
                  <StackPanel Margin="18,14,18,14" VerticalAlignment="Center">
                    <Border Width="38" Height="38" CornerRadius="12" Background="{DynamicResource AccentSoft}" HorizontalAlignment="Left">
                      <TextBlock Text="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="设置" FontSize="16" FontWeight="SemiBold" Margin="0,10,0,2"/>
                    <TextBlock Text="快捷键 · 底色 · 开机启动" FontSize="12" Foreground="{DynamicResource TextSecondary}"/>
                  </StackPanel>
                </Button>
              </Grid>
              <Button x:Name="BtnGoAuthor" Grid.Row="2" Style="{DynamicResource CardButton}" Margin="0,7,0,0" Height="54" ToolTip="七行字，慢慢看">
                <Grid Margin="18,0,18,0">
                  <StackPanel x:Name="AuthorEntryPanel" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  <TextBlock Text="&#xE76C;" FontFamily="Segoe MDL2 Assets" FontSize="11" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource TextPlaceholder}"/>
                </Grid>
              </Button>              <TextBlock x:Name="HomeHint" Grid.Row="3" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="6,12,80,0" TextWrapping="Wrap"/>

              <Canvas x:Name="WidgetLayer" Grid.Row="0" Grid.RowSpan="4" Panel.ZIndex="20" Background="{x:Null}">
                  <Grid x:Name="WidgetRoot" Width="320" Height="206">
                    <Border x:Name="WidgetBubble" Visibility="Collapsed" Opacity="0" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,0,10,0" MaxWidth="306" Padding="11,7,12,7" CornerRadius="12" Background="{DynamicResource PopupBg}" BorderBrush="{DynamicResource ShellBorder}" BorderThickness="1" IsHitTestVisible="False">
                      <Border.Effect>
                        <DropShadowEffect BlurRadius="16" ShadowDepth="3" Direction="270" Opacity="0.35" Color="#000000"/>
                      </Border.Effect>
                      <TextBlock x:Name="WidgetBubbleText" Text="今天你写了 0 条灵感" FontSize="11.5" MaxWidth="272" TextWrapping="Wrap" Foreground="{DynamicResource TextPrimary}"/>
                    </Border>
                    <Grid x:Name="WidgetMascot" Width="132" Height="132" HorizontalAlignment="Right" VerticalAlignment="Bottom" Cursor="Hand" Background="#00000000" ToolTip="点一下：压扁回弹并弹出气泡（3 秒）；短时间内连点会随机换一句话；按住可拖动位置；右键换图片">
                      <Grid.RenderTransform>
                        <TransformGroup>
                          <ScaleTransform x:Name="WidgetSquash" ScaleX="1" ScaleY="1" CenterX="66" CenterY="132"/>
                          <TranslateTransform x:Name="WidgetJump" X="0" Y="0"/>
                        </TransformGroup>
                      </Grid.RenderTransform>
                      <Image x:Name="WidgetImage" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality">
                        <Image.Effect>
                          <DropShadowEffect BlurRadius="18" ShadowDepth="4" Direction="270" Opacity="0.28" Color="#000000"/>
                        </Image.Effect>
                      </Image>
                    </Grid>
                  </Grid>
                </Canvas>            </Grid>

            <Grid x:Name="ViewNew" Visibility="Collapsed" Margin="26,0,26,20">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <Grid Grid.Row="0" Margin="0,0,0,12">
                <Button x:Name="BtnBackNew" Style="{DynamicResource FlatButton}" Padding="8,6" HorizontalAlignment="Left">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="&#xE72B;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                    <TextBlock Text="返回"/>
                  </StackPanel>
                </Button>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <Button x:Name="BtnOpenFile" Style="{DynamicResource FlatButton}" Margin="0,0,2,0">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE8E5;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock Text="打开文件"/>
                    </StackPanel>
                  </Button>
                  <Button x:Name="BtnNewFile" Style="{DynamicResource FlatButton}" Margin="0,0,2,0">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE7C3;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock Text="新建文件"/>
                    </StackPanel>
                  </Button>
                  <Button x:Name="BtnColorMenu" Style="{DynamicResource FlatButton}">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE790;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock Text="更改底色"/>
                    </StackPanel>
                  </Button>
                </StackPanel>
              </Grid>

              <Grid Grid.Row="1" Margin="2,0,2,10">
                <TextBox x:Name="TxtTitle" FontSize="21" FontWeight="SemiBold" Padding="0,2" MaxLength="120"/>
                <TextBlock x:Name="TitlePlaceholder" Text="标题（留空则自动取首行）" FontSize="21" FontWeight="SemiBold" Foreground="{DynamicResource TextPlaceholder}" IsHitTestVisible="False" VerticalAlignment="Center" Margin="2,0,0,0"/>
              </Grid>

              <Grid Grid.Row="2" Margin="2,0,2,8">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <WrapPanel x:Name="TagPanel" VerticalAlignment="Center"/>
                <Button x:Name="BtnReshuffleTags" Grid.Column="1" Style="{DynamicResource MiniButton}" Content="换一批" VerticalAlignment="Top" Margin="0,0,0,8" ToolTip="重新随机一批词条"/>
              </Grid>

              <Border Grid.Row="3" CornerRadius="14" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" Padding="16,12">
                <Grid>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                  </Grid.RowDefinitions>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                    <Button x:Name="BtnListBullet" Style="{DynamicResource MiniButton}" Content="&#x2022; 无序" Margin="0,0,6,0" ToolTip="把选中的行变成圆点列表"/>
                    <Button x:Name="BtnListNumber" Style="{DynamicResource MiniButton}" Content="1. 有序" Margin="0,0,6,0" ToolTip="把选中的行变成编号列表"/>
                    <Button x:Name="BtnIndent" Style="{DynamicResource MiniButton}" Content="&#x2192; 缩进" Margin="0,0,6,0" ToolTip="把选中的行右移一级（Tab）"/>
                    <Button x:Name="BtnOutdent" Style="{DynamicResource MiniButton}" Content="&#x2190; 取消缩进" ToolTip="把选中的行左移一级（Shift+Tab）"/>
                  </StackPanel>
                  <Grid Grid.Row="1">
                    <TextBox x:Name="TxtBody" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontSize="14" Padding="0" SpellCheck.IsEnabled="False"/>
                    <TextBlock x:Name="BodyPlaceholder" Text="在这里写下此刻的灵感……" FontSize="14" Foreground="{DynamicResource TextPlaceholder}" IsHitTestVisible="False" Margin="2,2,0,0"/>
                  </Grid>
                </Grid>
              </Border>

              <Grid Grid.Row="4" Margin="2,12,2,0">
                <TextBlock x:Name="SaveStatus" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                  <TextBlock x:Name="WordCount" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="0,0,14,0" VerticalAlignment="Center"/>
                  <Button x:Name="BtnSave" Style="{DynamicResource PrimaryButton}" Content="保存"/>
                </StackPanel>
              </Grid>
            </Grid>

            <Grid x:Name="ViewList" Visibility="Collapsed" Margin="26,0,26,20">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>

              <Grid Grid.Row="0" Margin="0,0,0,12">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="BtnBackList" Style="{DynamicResource FlatButton}" Padding="8,6">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE72B;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock Text="返回"/>
                    </StackPanel>
                  </Button>
                  <TextBlock Text="查看灵感" FontSize="15" FontWeight="SemiBold" Margin="10,0,0,0" VerticalAlignment="Center"/>
                  <TextBlock x:Name="ListCount" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="10,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
                <Border HorizontalAlignment="Right" Width="210" CornerRadius="9" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" Padding="10,0">
                  <Grid>
                    <TextBlock x:Name="SearchPh" Text="搜索标题…" FontSize="12.5" Foreground="{DynamicResource TextPlaceholder}" VerticalAlignment="Center" IsHitTestVisible="False"/>
                    <TextBox x:Name="TxtSearch" VerticalContentAlignment="Center" FontSize="12.5" Padding="0,7"/>
                  </Grid>
                </Border>
              </Grid>

              <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="290"/>
                  <ColumnDefinition Width="14"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Grid Grid.Column="0">
                  <ListBox x:Name="ListBrowse" Background="Transparent" BorderThickness="0" ItemContainerStyle="{DynamicResource ListItemStyle}" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                    <ListBox.ItemTemplate>
                      <DataTemplate>
                        <StackPanel>
                          <TextBlock Text="{Binding Title}" FontSize="13" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
                          <TextBlock Text="{Binding TimeText}" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,3,0,0"/>
                        </StackPanel>
                      </DataTemplate>
                    </ListBox.ItemTemplate>
                  </ListBox>
                  <TextBlock x:Name="EmptyBrowse" Text="还没有灵感记录" FontSize="12.5" Foreground="{DynamicResource TextSecondary}" HorizontalAlignment="Center" VerticalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center" Margin="20" Visibility="Collapsed"/>
                </Grid>

                <Border Grid.Column="2" CornerRadius="14" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" Padding="18,14">
                  <Grid>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock x:Name="ReadTitle" FontSize="16" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
                    <TextBlock x:Name="ReadMeta" Grid.Row="1" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,5,0,12"/>
                    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                      <TextBox x:Name="ReadBody" IsReadOnly="True" TextWrapping="Wrap" FontSize="13.5" IsTabStop="False" Background="Transparent"/>
                    </ScrollViewer>
                  </Grid>
                </Border>
              </Grid>
            </Grid>

            <Grid x:Name="ViewManage" Visibility="Collapsed" Margin="26,0,26,20">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <Grid Grid.Row="0" Margin="0,0,0,12">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="BtnBackManage" Style="{DynamicResource FlatButton}" Padding="8,6">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE72B;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock Text="返回"/>
                    </StackPanel>
                  </Button>
                  <TextBlock Text="管理灵感" FontSize="15" FontWeight="SemiBold" Margin="10,0,0,0" VerticalAlignment="Center"/>
                  <TextBlock x:Name="ManageCount" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="10,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
                <Button x:Name="BtnOpenLibrary" Style="{DynamicResource FlatButton}" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="&#xE838;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                    <TextBlock Text="打开灵感库文件夹"/>
                  </StackPanel>
                </Button>
              </Grid>

              <Grid Grid.Row="1">
                <ListBox x:Name="ListManage" Background="Transparent" BorderThickness="0" ItemContainerStyle="{DynamicResource RowListItemStyle}" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                  <ListBox.ItemTemplate>
                    <DataTemplate>
                      <Border CornerRadius="12" Background="{DynamicResource CardBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" Padding="16,11">
                        <Grid>
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                          </Grid.ColumnDefinitions>
                          <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="{Binding Title}" FontSize="13.5" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
                            <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                              <TextBlock Text="{Binding TimeText}" FontSize="11" Foreground="{DynamicResource TextSecondary}"/>
                              <TextBlock Text="  ·  " FontSize="11" Foreground="{DynamicResource TextSecondary}"/>
                              <TextBlock Text="{Binding SizeText}" FontSize="11" Foreground="{DynamicResource TextSecondary}"/>
                            </StackPanel>
                          </StackPanel>
                          <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                            <Button x:Name="RowEdit" Content="&#xE70F;" Style="{DynamicResource RowIconButton}" Tag="{Binding Path}" ToolTip="编辑这条灵感"/>
                            <Button x:Name="RowOpen" Content="&#xE838;" Style="{DynamicResource RowIconButton}" Tag="{Binding Path}" ToolTip="在文件夹中显示"/>
                            <Button x:Name="RowRename" Content="&#xE8AC;" Style="{DynamicResource RowIconButton}" Tag="{Binding Path}" ToolTip="重命名"/>
                            <Button x:Name="RowDelete" Content="&#xE74D;" Style="{DynamicResource RowIconButton}" Tag="{Binding Path}" ToolTip="删除"/>
                          </StackPanel>
                        </Grid>
                      </Border>
                    </DataTemplate>
                  </ListBox.ItemTemplate>
                </ListBox>
                <TextBlock x:Name="EmptyManage" Text="还没有灵感记录" FontSize="12.5" Foreground="{DynamicResource TextSecondary}" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
              </Grid>

              <TextBlock x:Name="ManageHint" Grid.Row="2" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="2,10,0,0"/>
            </Grid>

            <Grid x:Name="ViewSettings" Visibility="Collapsed" Margin="26,0,26,16" Focusable="True">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>

              <Grid Margin="0,0,0,10">
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="BtnBackSettings" Style="{DynamicResource FlatButton}" Padding="8,6">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE72B;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock Text="返回"/>
                    </StackPanel>
                  </Button>
                  <TextBlock Text="设置" FontSize="15" FontWeight="SemiBold" Margin="10,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
                <TextBlock x:Name="AboutVersion" Text="v1.1 · 正式版" FontSize="11.5" Foreground="{DynamicResource TextPlaceholder}" HorizontalAlignment="Right" Margin="0,0,6,0" VerticalAlignment="Center"/>
              </Grid>

              <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel Margin="0,0,6,0">
                  <Border Style="{DynamicResource SectionCard}" Margin="0,0,0,6">
                    <StackPanel>
                      <TextBlock Text="底色" FontSize="13.5" FontWeight="SemiBold"/>
                      <TextBlock Text="「跟随系统」会随 Windows 的浅色 / 深色模式自动切换" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="0,4,0,10"/>
                      <StackPanel Orientation="Horizontal">
                        <RadioButton x:Name="RadSys" GroupName="theme" Style="{DynamicResource SegRadio}" Content="跟随系统" Tag="system" Margin="0,0,8,0"/>
                        <RadioButton x:Name="RadLight" GroupName="theme" Style="{DynamicResource SegRadio}" Content="浅色" Tag="light" Margin="0,0,8,0"/>
                        <RadioButton x:Name="RadDark" GroupName="theme" Style="{DynamicResource SegRadio}" Content="深色" Tag="dark"/>
                      </StackPanel>
                      <TextBlock Text="强调色" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="0,12,0,6"/>
                      <WrapPanel x:Name="SwatchPanel"/>
                    </StackPanel>
                  </Border>

                  <Border Style="{DynamicResource SectionCard}" Margin="0,0,0,6">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel>
                        <TextBlock Text="呼出快捷键" FontSize="13.5" FontWeight="SemiBold"/>
                        <TextBlock x:Name="HotkeyDisplay" Text="Ctrl+Alt+Space" FontSize="17" FontWeight="SemiBold" Margin="0,6,0,3"/>
                        <TextBlock x:Name="HotkeyState" FontSize="11.5" Foreground="{DynamicResource TextSecondary}"/>
                      </StackPanel>
                      <Button x:Name="BtnRecord" Grid.Column="1" Style="{DynamicResource FlatButton}" Content="录制新快捷键" VerticalAlignment="Center"/>
                    </Grid>
                  </Border>

                  <Border Style="{DynamicResource SectionCard}" Margin="0,0,0,6">
                    <StackPanel>
                      <TextBlock Text="启动" FontSize="13.5" FontWeight="SemiBold" Margin="0,0,0,8"/>
                      <CheckBox x:Name="ChkAutostart" Content="开机时自动启动灵感速记（后台运行）"/>
                      <TextBlock x:Name="AutostartState" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="27,8,0,0"/>
                    </StackPanel>
                  </Border>

                  <Border Style="{DynamicResource SectionCard}" Margin="0,0,0,6">
                    <StackPanel>
                      <TextBlock Text="插件" FontSize="13.5" FontWeight="SemiBold" Margin="0,0,0,8"/>
                      <CheckBox x:Name="ChkWidget" Content="在首页显示插件挂件"/>
                      <Grid Margin="27,6,0,0">
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock x:Name="WidgetState" Grid.Column="0" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" VerticalAlignment="Center" TextWrapping="Wrap"/>
                        <StackPanel Grid.Column="1" Orientation="Horizontal" Margin="10,0,0,0" VerticalAlignment="Center">
                          <Button x:Name="BtnWidgetImage" Style="{DynamicResource FlatButton}" Content="更换图片" Margin="0,0,6,0"/>
                          <Button x:Name="BtnWidgetReset" Style="{DynamicResource FlatButton}" Content="恢复默认图片"/>
                        </StackPanel>
                      </Grid>
                      <Border Height="1" Background="{DynamicResource Divider}" Margin="0,10,0,0"/>
                      <Grid Margin="0,10,0,0">
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                          <TextBlock Text="苦命文学" FontSize="12.5" FontWeight="SemiBold"/>
                          <TextBlock x:Name="PoemState" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="0,3,0,0" TextWrapping="Wrap" MaxWidth="520" HorizontalAlignment="Left"/>
                        </StackPanel>
                        <Button x:Name="BtnOpenPoems" Grid.Column="1" Style="{DynamicResource FlatButton}" Content="编辑台词" VerticalAlignment="Center" Margin="10,0,0,0"/>
                      </Grid>
                    </StackPanel>
                  </Border>

                  <Border Style="{DynamicResource SectionCard}" Margin="0,0,0,6">
                    <StackPanel>
                      <TextBlock Text="数据" FontSize="13.5" FontWeight="SemiBold"/>
                      <TextBlock x:Name="LibraryPathText" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="0,6,0,10" TextWrapping="Wrap"/>
                      <StackPanel Orientation="Horizontal">
                        <Button x:Name="BtnOpenLib" Style="{DynamicResource FlatButton}" Content="打开文件夹" Margin="0,0,6,0"/>
                        <Button x:Name="BtnRefresh" Style="{DynamicResource FlatButton}" Content="刷新列表"/>
                      </StackPanel>
                    </StackPanel>
                  </Border>


                  <Border Style="{DynamicResource SectionCard}">
                    <Grid>
                      <StackPanel>
                        <TextBlock Text="后台与退出" FontSize="13.5" FontWeight="SemiBold"/>
                        <TextBlock Text="关闭按钮只会把窗口收进任务栏；要彻底退出请点右侧按钮。" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="0,6,0,0" TextWrapping="Wrap" MaxWidth="560" HorizontalAlignment="Left" VerticalAlignment="Center"/>
                      </StackPanel>
                      <Button x:Name="BtnExit" Style="{DynamicResource FlatButton}" Content="退出应用" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>
                  </Border>
                </StackPanel>
              </ScrollViewer>
            </Grid>

                        <Grid x:Name="ViewAuthor" Visibility="Collapsed" Margin="26,0,26,20">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <Grid Grid.Row="0" Margin="0,0,0,12">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="BtnBackAuthor" Style="{DynamicResource FlatButton}" Content="←  返回" Margin="0,0,10,0"/>
                  <TextBlock Text="作者的话" FontSize="14" FontWeight="SemiBold" VerticalAlignment="Center"/>
                </StackPanel>
              </Grid>
              <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel x:Name="AuthorBody" MaxWidth="600" HorizontalAlignment="Center" Margin="0,24,0,0"/>
              </ScrollViewer>
            </Grid>
<Grid x:Name="ViewPoems" Visibility="Collapsed" Margin="26,0,26,20">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <Grid Grid.Row="0" Margin="0,0,0,12">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="BtnBackPoems" Style="{DynamicResource FlatButton}" Padding="8,6">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE72B;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock Text="返回"/>
                    </StackPanel>
                  </Button>
                  <TextBlock Text="苦命文学" FontSize="15" FontWeight="SemiBold" Margin="10,0,0,0" VerticalAlignment="Center"/>
                  <TextBlock x:Name="PoemCount" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="10,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
                <Button x:Name="BtnPoemOpenFile" Style="{DynamicResource FlatButton}" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="&#xE8E5;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="0,0,6,0" VerticalAlignment="Center"/>
                    <TextBlock Text="在文件夹中打开"/>
                  </StackPanel>
                </Button>
              </Grid>

              <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="300"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <ListBox x:Name="PoemList" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                  <ListBox.ItemContainerStyle>
                    <Style TargetType="ListBoxItem">
                      <Setter Property="Template">
                        <Setter.Value>
                          <ControlTemplate TargetType="ListBoxItem">
                            <Border x:Name="pb" CornerRadius="12" Margin="0,0,0,6" Padding="14,10" Background="{DynamicResource CardBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1">
                              <ContentPresenter/>
                            </Border>
                            <ControlTemplate.Triggers>
                              <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="pb" Property="Background" Value="{DynamicResource CardBgHover}"/>
                              </Trigger>
                              <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="pb" Property="Background" Value="{DynamicResource AccentSoft}"/>
                                <Setter TargetName="pb" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                              </Trigger>
                            </ControlTemplate.Triggers>
                          </ControlTemplate>
                        </Setter.Value>
                      </Setter>
                    </Style>
                  </ListBox.ItemContainerStyle>
                  <ListBox.ItemTemplate>
                    <DataTemplate>
                      <TextBlock Text="{Binding}" FontSize="12.5" TextWrapping="Wrap"/>
                    </DataTemplate>
                  </ListBox.ItemTemplate>
                </ListBox>

                <Border Grid.Column="1" Margin="14,0,0,0" CornerRadius="14" Background="{DynamicResource CardBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" Padding="14">
                  <Grid>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="*"/>
                      <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="选中左边一句可以在下面改写；也可以直接写新的再点「新增一句」" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,8" TextWrapping="Wrap"/>
                    <Grid Grid.Row="1">
                      <TextBox x:Name="PoemEdit" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontSize="14" SpellCheck.IsEnabled="False"/>
                      <TextBlock x:Name="PoemEditPlaceholder" Text="在这里写一句新台词，或选中左边一句后改写……" FontSize="14" Foreground="{DynamicResource TextPlaceholder}" IsHitTestVisible="False" Margin="4,4,0,0" TextWrapping="Wrap"/>
                    </Grid>
                    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
                      <Button x:Name="BtnPoemSave" Style="{DynamicResource PrimaryButton}" Content="保存这句" Margin="0,0,8,0"/>
                      <Button x:Name="BtnPoemAdd" Style="{DynamicResource FlatButton}" Content="新增一句" Margin="0,0,8,0"/>
                      <Button x:Name="BtnPoemDelete" Style="{DynamicResource FlatButton}" Content="删除这句"/>
                    </StackPanel>
                  </Grid>
                </Border>
              </Grid>

              <TextBlock x:Name="PoemHint" Grid.Row="2" FontSize="11.5" Foreground="{DynamicResource TextSecondary}" Margin="2,10,0,0" TextWrapping="Wrap"/>
            </Grid>
          </Grid>
        </Grid>
      </Grid>
    </Border>

    <Popup x:Name="ColorPopup" AllowsTransparency="True" StaysOpen="False" Placement="Bottom" PopupAnimation="Fade" Opacity="1">
      <Border Background="{DynamicResource PopupBg}" CornerRadius="14" BorderBrush="{DynamicResource ShellBorder}" BorderThickness="1" Padding="14" Margin="0,6,0,0">
        <Border.Effect>
          <DropShadowEffect BlurRadius="20" ShadowDepth="4" Direction="270" Opacity="0.45" Color="#000000"/>
        </Border.Effect>
        <StackPanel Width="246">
          <TextBlock Text="底色" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="2,0,0,8"/>
          <StackPanel Orientation="Horizontal">
            <RadioButton x:Name="PopR1" GroupName="themePop" Style="{DynamicResource SegRadio}" Content="系统" Tag="system" Margin="0,0,6,0"/>
            <RadioButton x:Name="PopR2" GroupName="themePop" Style="{DynamicResource SegRadio}" Content="浅色" Tag="light" Margin="0,0,6,0"/>
            <RadioButton x:Name="PopR3" GroupName="themePop" Style="{DynamicResource SegRadio}" Content="深色" Tag="dark"/>
          </StackPanel>
          <TextBlock Text="强调色" FontSize="11" Foreground="{DynamicResource TextSecondary}" Margin="2,12,0,8"/>
          <WrapPanel x:Name="PopSwatches"/>
        </StackPanel>
      </Border>
    </Popup>
  </Grid>
</Window>
'@

# ---------------------------------------------------------------- boot
$script:App = New-Object System.Windows.Application
$script:App.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
[AppDomain]::CurrentDomain.add_UnhandledException({
        param($s, $e)
        try { Write-Log ('fatal: ' + $e.ExceptionObject.ToString()) } catch { }
    })
$script:App.add_DispatcherUnhandledException({
        param($s, $e)
        try { Write-Log ('ui exception: ' + $e.Exception.ToString()) } catch { }
        $e.Handled = $true
    })
$script:App.Resources = New-Object System.Windows.ResourceDictionary

Write-Log 'start'
try { [Lingan.Native]::SetAppId('Lingan.QuickNote') } catch { }

$styleDict = [System.Windows.Markup.XamlReader]::Parse($script:StylesXaml)
$script:App.Resources.MergedDictionaries.Add($styleDict)

$script:UI = @{}
$script:CurrentPath = $null
$script:Dirty = $false
$script:Recording = $false
$script:Exiting = $false
$script:AcrylicEnabled = $false

Load-Config
$null = Ensure-Library

$win = [System.Windows.Markup.XamlReader]::Parse($script:WindowXaml)
$script:UI.Window = $win

$names = @(
    'RootGrid', 'Shell', 'TitleBar', 'ViewHost',
    'ViewHome', 'HomeTitle', 'HomeSub', 'HomeHint',
    'BtnGoNew', 'BtnGoList', 'BtnGoManage', 'BtnGoSettings',
    'ViewNew', 'BtnBackNew', 'BtnOpenFile', 'BtnNewFile', 'BtnColorMenu',
    'TxtTitle', 'TitlePlaceholder', 'TxtBody', 'BodyPlaceholder', 'SaveStatus', 'WordCount', 'BtnSave',
    'ViewList', 'BtnBackList', 'ListCount', 'TxtSearch', 'SearchPh', 'ListBrowse', 'EmptyBrowse',
    'ReadTitle', 'ReadMeta', 'ReadBody',
    'ViewManage', 'BtnBackManage', 'ManageCount', 'BtnOpenLibrary', 'ListManage', 'EmptyManage', 'ManageHint',
    'ViewSettings', 'BtnBackSettings', 'RadSys', 'RadLight', 'RadDark', 'SwatchPanel',
    'HotkeyDisplay', 'HotkeyState', 'BtnRecord', 'ChkAutostart', 'AutostartState',
    'LibraryPathText', 'BtnOpenLib', 'BtnRefresh', 'BtnExit',
    'ColorPopup', 'PopR1', 'PopR2', 'PopR3', 'PopSwatches',
    'BtnMin', 'BtnClose', 'AppBadge', 'AppBadgeGlyph',
    'TagPanel', 'BtnReshuffleTags', 'BtnListBullet', 'BtnListNumber', 'BtnIndent', 'BtnOutdent',
    'WidgetLayer', 'WidgetRoot', 'WidgetBubble', 'WidgetBubbleText', 'WidgetMascot', 'WidgetSquash', 'WidgetJump', 'WidgetImage', 'AboutVersion', 'ChkWidget', 'WidgetState', 'BtnWidgetImage', 'BtnWidgetReset', 'PoemState', 'BtnOpenPoems', 'ViewPoems', 'BtnBackPoems', 'PoemCount', 'PoemList', 'PoemEdit', 'BtnPoemSave', 'BtnPoemAdd', 'BtnPoemDelete', 'PoemHint', 'BtnPoemOpenFile', 'PoemEditPlaceholder',
    'ViewAuthor', 'BtnBackAuthor', 'BtnGoAuthor', 'AuthorEntryPanel', 'AuthorBody'
)

foreach ($n in $names) {
    $el = $win.FindName($n)
    if ($el) { $script:UI[$n] = $el }
    else { Write-Log ('missing element: ' + $n) }
}

$appIcon = Get-AppIconImage
if ($appIcon) {
    $win.Icon = [System.Runtime.CompilerServices.RuntimeHelpers]::GetObjectValue($appIcon)
    $badgeBrush = New-Object System.Windows.Media.ImageBrush($appIcon)
    $badgeBrush.Stretch = [System.Windows.Media.Stretch]::UniformToFill
    $script:UI.AppBadge.Background = [System.Runtime.CompilerServices.RuntimeHelpers]::GetObjectValue($badgeBrush)
    if ($script:UI.AppBadgeGlyph) { $script:UI.AppBadgeGlyph.Visibility = 'Collapsed' }
}

# danger brush (used for warnings)
Set-Brush 'Danger' '#F2748F'
Set-Brush 'Warn' '#F2A93B'

Apply-Theme

$script:UI.HomeHint.Text = ('按 {0} 可从任何地方呼出 · 关闭窗口会收进任务栏' -f (Format-HotkeyName $script:Config.hotkey))
$script:UI.LibraryPathText.Text = ('灵感库位置：' + (Get-LibraryPath))
$script:UI.ManageHint.Text = '提示：文件名开头的数字是保存时间，重命名只会改动后面的标题部分。'
$script:UI.ChkAutostart.IsChecked = [bool]$script:Config.autostart
$script:UI.ChkWidget.IsChecked = [bool]$script:Config.widgetVisible
Update-WidgetState
if ($script:Config.autostart) { $script:UI.AutostartState.Text = '已开启 · 开机后会静默启动并驻留托盘' } else { $script:UI.AutostartState.Text = '未开启' }
$script:UI.HotkeyDisplay.Text = Format-HotkeyName $script:Config.hotkey
$script:UI.AboutVersion.Text = ('v{0} · 正式版' -f $script:AppVersion)

# --- wire: window chrome
$script:UI.BtnMin.Add_Click({ $script:UI.Window.WindowState = 'Minimized' })
$script:UI.BtnClose.Add_Click({ $script:UI.Window.WindowState = 'Minimized' })
$script:UI.TitleBar.Add_MouseLeftButtonDown({
        param($s, $e)
        if ($e.ButtonState -eq 'Pressed') {
            try { $script:UI.Window.DragMove() } catch { }
        }
    })
$win.Add_Closing({
        param($s, $e)
        if (-not $script:Exiting) {
            $e.Cancel = $true
            $script:UI.Window.Hide()
        }
    })

# ---------------- wire: navigation
$script:UI.BtnGoNew.Add_Click({ Show-View 'New'; New-Editor; $script:UI.TxtBody.Focus() | Out-Null })
$script:UI.BtnGoList.Add_Click({ Show-View 'List' })
$script:UI.BtnGoManage.Add_Click({ Show-View 'Manage' })
$script:UI.BtnGoSettings.Add_Click({ Show-View 'Settings' })
$script:UI.BtnBackNew.Add_Click({ Show-View 'Home' })
$script:UI.BtnBackList.Add_Click({ Show-View 'Home' })
$script:UI.BtnBackManage.Add_Click({ Show-View 'Home' })
$script:UI.BtnBackSettings.Add_Click({ Show-View 'Home' })

# ---------------- wire: editor
$script:UI.TxtBody.Add_TextChanged({ Update-Placeholders; if (-not $script:Loading) { Mark-Dirty } })
$script:UI.TxtTitle.Add_TextChanged({ Update-Placeholders; if (-not $script:Loading) { Mark-Dirty } })
$script:UI.BtnSave.Add_Click({ Save-Current })
$script:UI.BtnNewFile.Add_Click({
        New-Editor
        $script:UI.TxtTitle.Focus() | Out-Null
    })
$script:UI.BtnOpenFile.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Title = '打开灵感文件'
        $dlg.Filter = '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*'
        $dlg.InitialDirectory = Get-LibraryPath
        if ($dlg.ShowDialog($script:UI.Window)) {
            Load-IntoEditor $dlg.FileName
            Show-View 'New'
        }
    })
$script:UI.BtnListBullet.Add_Click({ Invoke-ListCommand 'bullet' })
$script:UI.BtnListNumber.Add_Click({ Invoke-ListCommand 'number' })
$script:UI.BtnIndent.Add_Click({ Invoke-ListCommand 'indent' })
$script:UI.BtnOutdent.Add_Click({ Invoke-ListCommand 'outdent' })
$script:UI.BtnReshuffleTags.Add_Click({ Update-TagChips -Reshuffle })
$script:UI.TxtBody.Add_PreviewKeyDown({
        param($s, $e)
        $tb = $script:UI.TxtBody
        $mods = [System.Windows.Input.Keyboard]::Modifiers
        if ($e.Key -eq 'Tab') {
            if (($mods -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0) { Invoke-ListCommand 'outdent' } else { Invoke-ListCommand 'indent' }
            $e.Handled = $true
            return
        }
        if ($e.Key -eq 'Enter' -and $mods -eq [System.Windows.Input.ModifierKeys]::None) {
            $text = $tb.Text
            $idx = $tb.SelectionStart
            $lineStart = $text.LastIndexOf("`n", [Math]::Max(0, $idx - 1)) + 1
            $lineText = $text.Substring($lineStart, [Math]::Max(0, $idx - $lineStart))
            $m = [regex]::Match($lineText, '^(\s*)(?:•\s+|(\d+)[.)]\s+)')
            if ($m.Success) {
                $pad = $m.Groups[1].Value
                $e.Handled = $true
                if ($lineText.Trim().Length -le $m.Length) {
                    $tb.Text = $text.Substring(0, $lineStart) + $text.Substring($idx)
                    $tb.SelectionStart = $lineStart
                } else {
                    if ($m.Groups[2].Success) { $marker = ([int]$m.Groups[2].Value + 1).ToString() + '. ' } else { $marker = '• ' }
                    $insert = "`r`n" + $pad + $marker
                    $tb.Text = $text.Substring(0, $idx) + $insert + $text.Substring($idx)
                    $tb.SelectionStart = $idx + $insert.Length
                }
                Mark-Dirty
            }
        }
    })

$script:UI.BtnColorMenu.Add_Click({
        $script:UI.ColorPopup.PlacementTarget = $script:UI.BtnColorMenu
        $script:UI.ColorPopup.IsOpen = $true
    })

# ---------------- wire: list
$script:UI.ListBrowse.Add_SelectionChanged({
        param($s, $e)
        $sel = $script:UI.ListBrowse.SelectedItem
        if (-not $sel) { return }
        $text = ''
        try { $text = Get-Content -LiteralPath $sel.Path -Raw -Encoding UTF8 } catch { $text = '' }
        if ($null -eq $text) { $text = '' }
        $script:UI.ReadTitle.Text = $sel.Title
        $script:UI.ReadMeta.Text = ('最近修改：' + $sel.TimeText + '　·　' + $sel.SizeText + '　·　' + [System.IO.Path]::GetFileName($sel.Path))
        $script:UI.ReadBody.Text = $text
    })
$script:UI.TxtSearch.Add_TextChanged({ Refresh-Items })
$script:UI.TxtSearch.Add_GotFocus({ $script:UI.SearchPh.Visibility = 'Collapsed' })
$script:UI.TxtSearch.Add_LostFocus({ if ($script:UI.TxtSearch.Text.Length -eq 0) { $script:UI.SearchPh.Visibility = 'Visible' } })

# ---------------- wire: manage
$script:UI.ListManage.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($s, $e)
        $btn = $e.OriginalSource
        while ($btn -and -not ($btn -is [System.Windows.Controls.Button])) { $btn = $btn.Parent }
        if (-not $btn) { return }
        $path = [string]$btn.Tag
        if ([string]::IsNullOrWhiteSpace($path)) { return }
        switch ($btn.Name) {
            'RowEdit' {
                Show-MainWindow
                Show-View 'New'
                Load-IntoEditor $path
            }
            'RowOpen' {
                Start-Process explorer.exe -ArgumentList ('/select,"' + $path + '"')
            }
            'RowRename' {
                $oldTitle = Get-DisplayTitle ([System.IO.Path]::GetFileName($path))
                $newTitle = Show-Dialog -Title '重命名灵感' -Message '输入新的标题，文件名开头的保存时间会保留。' -Mode 'input' -DefaultText $oldTitle
                if ($newTitle -and $newTitle.Trim().Length -gt 0) {
                    try {
                        $dir = [System.IO.Path]::GetDirectoryName($path)
                        $stem = [System.IO.Path]::GetFileNameWithoutExtension($path)
                        $pm = [regex]::Match($stem, '^\d{8}-\d{4}\s+')
                        $prefix = ''
                        if ($pm.Success) { $prefix = $pm.Value }
                        $slug = $newTitle.Trim() -replace '[\\/:*?"<>|\r\n\t]', ' '
                        $slug = ($slug -replace '\s+', ' ').Trim()
                        if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40) }
                        $newPath = Join-Path $dir ($prefix + $slug + '.txt')
                        if ($newPath -ne $path) {
                            if (Test-Path -LiteralPath $newPath) {
                                $null = Show-Dialog -Title '重命名失败' -Message '已存在同名文件。' -Mode 'info'
                            } else {
                                [System.IO.File]::Move($path, $newPath)
                            }
                        }
                    } catch {
                        $null = Show-Dialog -Title '重命名失败' -Message $_.Exception.Message -Mode 'info'
                    }
                    Refresh-All
                }
            }
            'RowDelete' {
                $ok = Show-Dialog -Title '删除灵感' -Message ('确定要删除「' + (Get-DisplayTitle ([System.IO.Path]::GetFileName($path))) + '」吗？此操作不可撤销。') -Mode 'confirm' -OkText '删除' -CancelText '取消'
                if ($ok) {
                    try { [System.IO.File]::Delete($path) } catch { }
                    Refresh-All
                }
            }
        }
    })

$script:WidgetDrag = $null
$script:WidgetLines = $null
$script:WidgetLastTap = $null
$script:BubbleVisible = $false
$script:WidgetCountText = '今天你写了 0 条灵感'
$script:WidgetMoved = $false

function Start-WidgetDrag([double]$x, [double]$y) {
    $script:WidgetDrag = @{
        X = $x
        Y = $y
        L = [double][System.Windows.Controls.Canvas]::GetLeft($script:UI.WidgetRoot)
        T = [double][System.Windows.Controls.Canvas]::GetTop($script:UI.WidgetRoot)
    }
    $script:WidgetMoved = $false
}

function Move-WidgetDrag([double]$x, [double]$y) {
    if ($null -eq $script:WidgetDrag) { return }
    $dx = $x - [double]$script:WidgetDrag.X
    $dy = $y - [double]$script:WidgetDrag.Y
    if ([Math]::Abs($dx) -gt 3 -or [Math]::Abs($dy) -gt 3) { $script:WidgetMoved = $true }
    if ($script:WidgetMoved) {
        Set-WidgetPosition (([double]$script:WidgetDrag.L) + $dx) (([double]$script:WidgetDrag.T) + $dy)
    }
}

function End-WidgetDrag {
    $wasDrag = [bool]$script:WidgetMoved
    $script:WidgetDrag = $null
    $script:WidgetMoved = $false
    if ($wasDrag) { Save-WidgetPosition; Invoke-WidgetRelease -Instant } else { Invoke-WidgetRelease; Invoke-WidgetTap }
}

$script:UI.WidgetMascot.Add_MouseLeftButtonDown({
        param($s, $e)
        try {
            $pt = $e.GetPosition($script:UI.WidgetLayer)
            Start-WidgetDrag ([double]$pt.X) ([double]$pt.Y)
            Invoke-WidgetPress
            if (-not $script:WidgetEggTimer) {
                $script:WidgetEggTimer = New-Object System.Windows.Threading.DispatcherTimer
                $script:WidgetEggTimer.Interval = [TimeSpan]::FromMilliseconds(480)
                $script:WidgetEggTimer.Add_Tick({
                        $script:WidgetEggTimer.Stop()
                        Show-WidgetBubble '如果生活把我揍扁，那我就扁扁地离开.......' 4200
                    })
            }
            $script:WidgetEggTimer.Stop()
            $script:WidgetEggTimer.Start()
            $script:UI.WidgetMascot.CaptureMouse() | Out-Null
            $e.Handled = $true
        } catch {
            Write-Log ('widget drag start failed: ' + $_.Exception.Message)
        }
    })

$script:UI.WidgetMascot.Add_MouseMove({
        param($s, $e)
        try {
            if ($null -eq $script:WidgetDrag) { return }
            if ($e.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
            $pt = $e.GetPosition($script:UI.WidgetLayer)
            Move-WidgetDrag ([double]$pt.X) ([double]$pt.Y)
        } catch {
            Write-Log ('widget drag move failed: ' + $_.Exception.Message)
        }
    })

$script:UI.WidgetMascot.Add_MouseLeftButtonUp({
        param($s, $e)
        if ($script:WidgetEggTimer -and -not $script:WidgetMoved) { $script:WidgetEggTimer.Stop() }
        try { $script:UI.WidgetMascot.ReleaseMouseCapture() } catch { }
        try { End-WidgetDrag } catch { Write-Log ('widget drag end failed: ' + $_.Exception.Message) }
    })
$script:UI.WidgetMascot.Add_MouseRightButtonUp({
        param($s, $e)
        $e.Handled = $true
        Select-WidgetImage
    })
$script:UI.BtnGoAuthor.Add_Click({ Show-View 'Author' })
$script:UI.BtnBackAuthor.Add_Click({ Show-View 'Home' })
$script:UI.HomeTitle.Cursor = 'Hand'
$script:UI.HomeTitle.Background = [System.Windows.Media.Brushes]::Transparent
$script:UI.HomeTitle.ToolTip = '点一下：今天是几号；再点一下：嗯，有彩蛋'
$script:UI.HomeTitle.Add_PreviewMouseLeftButtonDown({ param($s, $e) $e.Handled = $true; try { Invoke-GreetTap } catch { Write-Log ('greet tap failed: ' + $_.Exception.Message) } })
Initialize-AuthorEntry
$script:UI.BtnOpenLibrary.Add_Click({
        Start-Process explorer.exe -ArgumentList ('"' + (Get-LibraryPath) + '"')
    })

# ---------------- wire: settings
foreach ($r in @('RadSys', 'RadLight', 'RadDark', 'PopR1', 'PopR2', 'PopR3')) {
    $el = $script:UI[$r]
    if (-not $el) { continue }
    $el.AddHandler([System.Windows.Controls.RadioButton]::CheckedEvent, [System.Windows.RoutedEventHandler]{
            param($s, $e)
            if ($script:ApplyingTheme) { return }
            $tag = [string]$s.Tag
            if ([string]::IsNullOrWhiteSpace($tag)) { return }
            $script:Config.theme = $tag
            Save-Config
            Apply-Theme
            Update-ShellTint
        })
}

$script:AutostartBusy = $false
$applyAutostart = {
        if ($script:AutostartBusy) { return }
        $want = [bool]$script:UI.ChkAutostart.IsChecked
        $script:AutostartBusy = $true
        try {
            $ok = Set-Autostart $want
            if ($ok) {
                $script:Config.autostart = $want
                Save-Config
                if ($want) { $script:UI.AutostartState.Text = '已开启 · 开机后会静默启动并驻留托盘' }
                else { $script:UI.AutostartState.Text = '未开启' }
            } else {
                $script:UI.ChkAutostart.IsChecked = -not $want
                $script:UI.AutostartState.Text = '设置失败，请检查系统权限'
            }
        } finally {
            $script:AutostartBusy = $false
        }
    }
$script:UI.ChkAutostart.Add_Checked($applyAutostart)
$script:UI.ChkAutostart.Add_Unchecked($applyAutostart)

$script:UI.BtnRecord.Add_Click({
        if ($script:Recording) {
            Stop-HotkeyRecording
        } else {
            Start-HotkeyRecording
        }
    })

$script:UI.ViewSettings.Add_PreviewKeyDown({
        param($s, $e)
        if (-not $script:Recording) { return }
        $key = $e.Key
        if ($key -eq 'Escape') {
            Stop-HotkeyRecording
            $e.Handled = $true
            return
        }
        if ($key -eq 'LeftCtrl' -or $key -eq 'RightCtrl' -or $key -eq 'LeftAlt' -or $key -eq 'RightAlt' -or $key -eq 'LeftShift' -or $key -eq 'RightShift' -or $key -eq 'LWin' -or $key -eq 'RWin' -or $key -eq 'System') {
            return
        }
        $vk = [System.Windows.Input.KeyInterop]::VirtualKeyFromKey($key)
        if ($vk -le 0) { return }
        $mods = [System.Windows.Input.Keyboard]::Modifiers
        $parts = New-Object System.Collections.ArrayList
        if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0) { $null = $parts.Add('Ctrl') }
        if (($mods -band [System.Windows.Input.ModifierKeys]::Alt) -ne 0) { $null = $parts.Add('Alt') }
        if (($mods -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0) { $null = $parts.Add('Shift') }
        if (($mods -band [System.Windows.Input.ModifierKeys]::Windows) -ne 0) { $null = $parts.Add('Win') }
        if ($parts.Count -eq 0) {
            $script:UI.HotkeyState.Text = '快捷键必须包含 Ctrl / Alt / Shift / Win 之一'
            return
        }
        $keyName = ([System.Windows.Forms.Keys]$vk).ToString()
        $null = $parts.Add($keyName)
        $combo = ($parts -join '+')
        $e.Handled = $true
        Stop-HotkeyRecording
        $script:Config.hotkey = $combo
        Save-Config
        $ok = Apply-HotkeyFromConfig
        if (-not $ok) {
            $null = Show-Dialog -Title '快捷键注册失败' -Message ('「' + (Format-HotkeyName $combo) + '」可能已被其他程序占用，请换一个组合。') -Mode 'info'
        }
        $script:UI.HomeHint.Text = ('按 {0} 可从任何地方呼出 · 关闭窗口后仍在托盘运行' -f (Format-HotkeyName $script:Config.hotkey))
    })

$script:UI.BtnOpenLib.Add_Click({
        Start-Process explorer.exe -ArgumentList ('"' + (Get-LibraryPath) + '"')
    })
$script:UI.BtnRefresh.Add_Click({ Refresh-All })
$script:WidgetBusy = $false
$applyWidget = {
    if ($script:WidgetBusy) { return }
    $script:WidgetBusy = $true
    try {
        $script:Config.widgetVisible = [bool]$script:UI.ChkWidget.IsChecked
        Save-Config
        Update-WidgetState
    } finally {
        $script:WidgetBusy = $false
    }
}
$script:UI.ChkWidget.Add_Checked($applyWidget)
$script:UI.ChkWidget.Add_Unchecked($applyWidget)
$script:UI.BtnWidgetImage.Add_Click({ Select-WidgetImage })
$script:UI.BtnWidgetReset.Add_Click({
        $script:Config.widgetImage = ''
        Save-Config
        Update-WidgetState
    })
$script:UI.BtnOpenPoems.Add_Click({ Show-View 'Poems' })
$script:UI.BtnBackPoems.Add_Click({ Show-View 'Settings' })
$script:UI.BtnPoemOpenFile.Add_Click({
        try {
            $path = Get-PoemPath
            if (Test-Path -LiteralPath $path) { Start-Process explorer.exe ('/select,"' + $path + '"') }
            else { Start-Process explorer.exe $script:AppRoot }
        } catch {
            Write-Log ('poem open failed: ' + $_.Exception.Message)
        }
    })
$script:UI.PoemEdit.Add_TextChanged({
        try {
            if ($script:UI.PoemEditPlaceholder) {
                if ($script:UI.PoemEdit.Text.Length -eq 0) { $script:UI.PoemEditPlaceholder.Visibility = 'Visible' }
                else { $script:UI.PoemEditPlaceholder.Visibility = 'Collapsed' }
            }
        } catch { }
    })
$script:UI.PoemList.Add_SelectionChanged({
        try {
            $sel = $script:UI.PoemList.SelectedItem
            if ($null -ne $sel) { $script:UI.PoemEdit.Text = [string]$sel }
        } catch {
            Write-Log ('poem select failed: ' + $_.Exception.Message)
        }
    })
$script:UI.BtnPoemSave.Add_Click({
        try {
            $idx = $script:UI.PoemList.SelectedIndex
            $text = $script:UI.PoemEdit.Text
            if ($idx -lt 0) {
                $script:UI.PoemHint.Text = '先在左边选中一句，再改下面的文字。'
                return
            }
            if ([string]::IsNullOrWhiteSpace($text)) {
                $script:UI.PoemHint.Text = '内容不能为空；想删掉这句请点「删除这句」。'
                return
            }
            $lines = @(Get-PoemLines)
            $lines[$idx] = $text.Trim()
            $count = Save-PoemLines $lines
            Refresh-Poems
            if ($count -ge 0) { $script:UI.PoemHint.Text = ('已保存，共 {0} 句。挂件下一次点击就会用新台词。' -f $count) }
            else { $script:UI.PoemHint.Text = '写文件失败，看看 app.log。' }
        } catch {
            Write-Log ('poem save failed: ' + $_.Exception.Message)
        }
    })
$script:UI.BtnPoemAdd.Add_Click({
        try {
            $text = $script:UI.PoemEdit.Text
            if ([string]::IsNullOrWhiteSpace($text)) {
                $script:UI.PoemHint.Text = '先在右边输入一句新台词，再点「新增一句」。'
                return
            }
            $lines = @(Get-PoemLines)
            $lines += $text.Trim()
            $count = Save-PoemLines $lines
            Refresh-Poems
            if ($count -ge 0) { $script:UI.PoemHint.Text = ('已新增一句，现在共 {0} 句。' -f $count) }
            else { $script:UI.PoemHint.Text = '写文件失败，看看 app.log。' }
        } catch {
            Write-Log ('poem add failed: ' + $_.Exception.Message)
        }
    })
$script:UI.BtnPoemDelete.Add_Click({
        try {
            $idx = $script:UI.PoemList.SelectedIndex
            if ($idx -lt 0) {
                $script:UI.PoemHint.Text = '先在左边选中要删掉的那一句。'
                return
            }
            $lines = @(Get-PoemLines)
            $lines = @($lines | Where-Object { $_ -ne $lines[$idx] })
            $count = Save-PoemLines $lines
            Refresh-Poems
            if ($count -ge 0) { $script:UI.PoemHint.Text = ('已删除，现在共 {0} 句。' -f $count) }
            else { $script:UI.PoemHint.Text = '写文件失败，看看 app.log。' }
        } catch {
            Write-Log ('poem delete failed: ' + $_.Exception.Message)
        }
    })
$script:UI.BtnExit.Add_Click({
        $ok = Show-Dialog -Title '退出灵感速记' -Message '退出后将不再驻留后台，快捷键也会失效。确定退出吗？' -Mode 'confirm' -OkText '退出'
        if ($ok) { Exit-App }
    })

# ---------------- global keys
$win.Add_KeyDown({
        param($s, $e)
        $mods = [System.Windows.Input.Keyboard]::Modifiers
        if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0 -and $e.Key -eq 'S') {
            if ($script:UI.ViewNew.Visibility -eq 'Visible') {
                Save-Current
                $e.Handled = $true
            }
        }
        if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0 -and $e.Key -eq 'N') {
            Show-View 'New'
            New-Editor
            $e.Handled = $true
        }
        if ($e.Key -eq 'Escape' -and -not $script:Recording) {
            if ($script:UI.ViewHome.Visibility -ne 'Visible') {
                Show-View 'Home'
                $e.Handled = $true
            }
        }
    })

$win.Add_Loaded({
        param($s, $e)
        Show-View 'Home'
        Refresh-All
        Apply-WidgetPosition
        Update-PoemState
        try {
            if (-not $script:Hotkey) { $script:Hotkey = New-Object Lingan.HotkeyHost }
            $script:Hotkey.add_Pressed({
                    try {
                        $w = $script:UI.Window
                        if ($null -eq $w) { return }
                        if ($w.IsVisible -and $w.WindowState -ne 'Minimized') {
                            $w.WindowState = 'Minimized'
                        } else {
                            Show-MainWindow
                        }
                    } catch {
                        Write-Log ('hotkey toggle failed: ' + $_.Exception.Message)
                    }
                })
        } catch {
            Write-Log ('hotkey host failed: ' + $_.Exception.Message)
        }
        try {
            $null = Apply-HotkeyFromConfig
            Write-Log ('hotkey applied: ' + $script:Config.hotkey)
        } catch {
            Write-Log ('hotkey apply failed: ' + $_.Exception.Message)
        }
        try {
            if (-not $script:Tray) { Initialize-Tray }
            Write-Log 'tray ready'
        } catch {
            Write-Log ('tray failed: ' + $_.Exception.Message)
        }
    })


$script:FirstRunTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:FirstRunTimer.Interval = [TimeSpan]::FromMilliseconds(700)
$script:FirstRunTimer.Add_Tick({
        try {
            $script:FirstRunTimer.Stop()
            if (-not $script:Config.startupAsked) {
                $ok = Show-Dialog -Title '开机自动启动？' -Message '是否让「灵感速记」随 Windows 一起启动，并在后台待命？之后可以随时在设置里修改。' -Mode 'yesno' -OkText '好的，开机启动' -CancelText '暂不需要'
                $script:Config.startupAsked = $true
                if ($ok) {
                    $script:UI.ChkAutostart.IsChecked = $true
                } else {
                    $script:Config.autostart = $false
                    $script:UI.ChkAutostart.IsChecked = $false
                    $script:UI.AutostartState.Text = '未开启'
                }
                Save-Config
            }
        } catch {
            Write-Log ('first run dialog failed: ' + $_.Exception.Message)
        }
    })
$script:FirstRunTimer.Start()
Write-Log 'running'

try {
    $null = $script:App.Run($win)
} catch {
    try { Write-Log ('run failed: ' + $_.Exception.ToString()) } catch { }
}
Write-Log 'exit'
try { if ($script:Hotkey) { $script:Hotkey.Destroy() } } catch { }
try { if ($script:Tray) { $script:Tray.Dispose() } } catch { }
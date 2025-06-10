# Script metadata for Intune
<#
.SYNOPSIS
    System Information Widget for enterprise deployment
.DESCRIPTION
    Displays system information in a floating widget on Windows desktop
.NOTES
    Name: SystemInfoWidget.ps1
    Author: You
    Version: 2.1
#>

# Base directory configuration
$baseDir = "C:\pathToScrtipt"
$widgetDir = "$baseDir\SystemInfoWidget"

# Create necessary directories
if (!(Test-Path $baseDir)) {
    New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
}
if (!(Test-Path $widgetDir)) {
    New-Item -ItemType Directory -Path $widgetDir -Force | Out-Null
}

# Logging function
function Write-Log {
    param($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    $logMessage | Out-File -FilePath "$widgetDir\widget.log" -Append
    Write-Host $Message
}

# Create the VBS launcher script to hide PowerShell window
$vbsScript = @"
Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File ""$widgetDir\SystemInfoWidget.ps1""", 0, False
"@

# Create the main widget PowerShell script
$widgetScript = @'
Add-Type -AssemblyName PresentationCore, PresentationFramework, System.Xaml

try {
    # Create or get application instance
    if ([System.Windows.Application]::Current -eq $null) {
        $app = New-Object System.Windows.Application
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    } else {
        $app = [System.Windows.Application]::Current
    }

    # Close any existing widgets
    if ([System.Windows.Application]::Current -ne $null) {
        [System.Windows.Application]::Current.Windows | Where-Object { $_.Title -eq "System Info Widget" } | ForEach-Object { $_.Close() }
    }

    # Screen dimensions and widget placement
    $screenWidth = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $screenHeight = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $widgetWidth = 400
    $widgetHeight = 220
    
    # Right edge positioning with confirmed offset
    $left = $screenWidth - $widgetWidth + 120
    $top = $screenHeight - $widgetHeight

    # Add Win32 API support for window styling
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    
    public class Win32 {
        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(
            IntPtr hWnd,
            IntPtr hWndInsertAfter,
            int X,
            int Y,
            int cx,
            int cy,
            uint uFlags
        );
        
        [DllImport("user32.dll")]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll")]
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
        
        public static readonly IntPtr HWND_BOTTOM = new IntPtr(1);
        public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
        public static readonly uint SWP_NOSIZE = 0x0001;
        public static readonly uint SWP_NOMOVE = 0x0002;
        public static readonly uint SWP_NOACTIVATE = 0x0010;
        public static readonly int GWL_EXSTYLE = -20;
        public static readonly int WS_EX_TOOLWINDOW = 0x00000080;
        public static readonly int WS_EX_APPWINDOW = 0x00040000;
    }
"@

    # XAML definition with desktop-level integration
    $XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="System Info Widget"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        Width="$widgetWidth" Height="$widgetHeight"
        Left="$left" Top="$top"
        ResizeMode="NoResize"
        WindowStartupLocation="Manual"
        ShowInTaskbar="False">
    <Grid Margin="0">
        <Border Background="#00000000" BorderThickness="0">
            <StackPanel Margin="0">
                <TextBlock Name="ComputerNameText" Foreground="White" FontSize="14" Margin="0"/>
                <TextBlock Name="ModelText" Foreground="White" FontSize="14" Margin="0"/>
                <TextBlock Name="HostnameText" Foreground="White" FontSize="14" Margin="0"/>
                <TextBlock Name="IpAddressText" Foreground="White" FontSize="14" Margin="0"/>
                <TextBlock Name="DnsServersText" Foreground="White" FontSize="14" Margin="0"/>
                <TextBlock Name="FqdnText" Foreground="White" FontSize="14" Margin="0"/>
                <TextBlock Name="OsVersionText" Foreground="White" FontSize="14" Margin="0"/>
                <TextBlock Name="SerialNumberText" Foreground="White" FontSize="14" Margin="0"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@

    # Parse XAML and create window
    [xml]$XAMLObject = $XAML
    $reader = (New-Object System.Xml.XmlNodeReader $XAMLObject)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Force position on load
    $window.Add_Loaded({
        $window.Left = $left
        $window.Top = $top
        $window.WindowState = 'Normal'
        $window.ShowInTaskbar = $false
    })

    # Set window style and position on initialization
    $window.Add_SourceInitialized({
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        $progman = [Win32]::FindWindow("Progman", "Program Manager")

        # Set tool window style
        $style = [Win32]::GetWindowLong($hwnd, [Win32]::GWL_EXSTYLE)
        $style = $style -bor [Win32]::WS_EX_TOOLWINDOW
        $style = $style -band -bnot [Win32]::WS_EX_APPWINDOW
        [Win32]::SetWindowLong($hwnd, [Win32]::GWL_EXSTYLE, $style)

        # Set window position and Z-order
        [Win32]::SetWindowPos(
            $hwnd,
            [Win32]::HWND_NOTOPMOST,
            $left, $top, $widgetWidth, $widgetHeight,
            [Win32]::SWP_NOACTIVATE
        )
    })

    # Strict position maintenance
    $window.Add_LocationChanged({
        if ($window.Left -ne $left -or $window.Top -ne $top) {
            $window.Left = $left
            $window.Top = $top
        }
    })

    # Add window dragging functionality
    $window.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    # Enhanced IP and DNS retrieval function with caching
    function Get-IpAndDns {
        try {
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
            if ($adapter) {
                $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
                $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses
                
                return [pscustomobject]@{
                    IP = $ipConfig.IPAddress
                    DNS = if ($dnsServers) { $dnsServers -join ", " } else { "N/A" }
                }
            }
        } catch {
            "$widgetDir\widget.log" | Out-File -Append -InputObject "Network information error: $_"
            return [pscustomobject]@{
                IP = "N/A"
                DNS = "N/A"
            }
        }
    }

    # Enhanced system information retrieval
    function Get-SystemInfo {
        try {
            $computerSystem = Get-CimInstance Win32_ComputerSystem
            $OS = Get-CimInstance Win32_OperatingSystem
            $BIOS = Get-CimInstance Win32_BIOS
            $netInfo = Get-IpAndDns
            $FQDN = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName

            @{
                ComputerName = $env:COMPUTERNAME
                Model = "$($computerSystem.Manufacturer) $($computerSystem.Model)".Trim()
                Hostname = $env:COMPUTERNAME
                IPAddress = $netInfo.IP
                DNSServers = $netInfo.DNS
                FQDN = $FQDN
                OsVersion = $OS.Caption
                SerialNumber = $BIOS.SerialNumber
            }
        } catch {
            "$widgetDir\widget.log" | Out-File -Append -InputObject "System information error: $_"
            return $null
        }
    }

    # UI update function
    function Update-WindowContent {
        try {
            $info = Get-SystemInfo
            if ($info) {
                $window.Dispatcher.Invoke([action]{
                    $window.FindName("ComputerNameText").Text = "Computer Name: $($info.ComputerName)"
                    $window.FindName("ModelText").Text = "Model: $($info.Model)"
                    $window.FindName("HostnameText").Text = "Hostname: $($info.Hostname)"
                    $window.FindName("IpAddressText").Text = "IP Address: $($info.IPAddress)"
                    $window.FindName("DnsServersText").Text = "DNS Servers: $($info.DNSServers)"
                    $window.FindName("FqdnText").Text = "FQDN: $($info.FQDN)"
                    $window.FindName("OsVersionText").Text = "OS Version: $($info.OsVersion)"
                    $window.FindName("SerialNumberText").Text = "Serial Number: $($info.SerialNumber)"
                })
            }
        } catch {
            "$widgetDir\widget.log" | Out-File -Append -InputObject "UI update error: $_"
        }
    }

    # Configure and start update timer
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(5)
    $timer.Add_Tick({ 
        Update-WindowContent
        # Maintain position during updates
        $window.Left = $left
        $window.Top = $top
    })
    $timer.Start()

    # Initialize and show window
    Update-WindowContent
    $window.Show()

    $app.Run()

} catch {
    "$widgetDir\widget.log" | Out-File -Append -InputObject "Critical error in widget: $_"
    exit 1
}
'@

try {
    # Create the widget script file
    $widgetScript | Out-File -FilePath "$widgetDir\SystemInfoWidget.ps1" -Force -Encoding UTF8
    
    # Create the VBS launcher
    $vbsScript | Out-File -FilePath "$widgetDir\LaunchWidget.vbs" -Force -Encoding ASCII

    # Create scheduled task for all users
    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$widgetDir\LaunchWidget.vbs`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 0)

    # Register the scheduled task
    Register-ScheduledTask -TaskName "SystemInfoWidget" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

    # Start the widget immediately (hidden)
    Start-Process "wscript.exe" -ArgumentList "`"$widgetDir\LaunchWidget.vbs`"" -WindowStyle Hidden

    Write-Log "Widget deployment successful"
    exit 0
} catch {
    Write-Log "Deployment error: $_"
    exit 1
}

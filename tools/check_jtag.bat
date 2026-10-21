@echo off
chcp 936 >nul
setlocal
set "TD=C:\anlogic\TD_6.2.1_Engineer_6.2.168.116"
set "BIN=%TD%\bin"
set "USBOFF=1"

echo ==========================================================
echo   HX1P35A 板载 USB-JTAG 一键体检
echo   用法: 插上 Type-C(板子上电) 后双击本文件
echo   目的: 分清是"驱动没装"还是"线没通"
echo ==========================================================
echo.

echo [1/3] USB 层: 板子的 FT2232H 有没有枚举出来
pnputil /enum-devices /connected | findstr /C:"VID_0403" >nul 2>&1
if errorlevel 1 (
    echo       [X] 未发现 0403 设备
    echo           1^) 换一根"能传数据"的 Type-C 线 ^(很多线只供电^)
    echo           2^) 确认板上电源开关已打开
    echo           3^) 换 USB 口, 避开前置面板 / 扩展坞 / Hub
) else (
    echo       [OK] 在线的 0403 设备:
    pnputil /enum-devices /connected | findstr /C:"VID_0403"
    set "USBOFF=0"
)
echo.

echo [2/3] 驱动层: 绑定的是不是 WinUSB
if "%USBOFF%"=="0" (
    pnputil /enum-devices /connected /class USBDevice | findstr /C:"USB-JTAG" /C:"WinUSB" /C:"设备描述" /C:"制造商名称" /C:"驱动程序名称"
    echo       期望: USB-JTAG Cable / WinUSB^(Powered by UsbDriverTool^) / oem213.inf
) else (
    echo       -- 跳过 ^(设备未连接, 先解决 [1]^)
)
echo.

echo [3/3] 工具链层: hwserver 能否看到调试适配器
if exist "%BIN%\hwserver.exe" (
    cd /d "%BIN%"
    hwserver.exe -l
) else (
    echo       [X] 找不到 %BIN%\hwserver.exe
)
echo.
echo ----------------------------------------------------------
echo   判据: 出现 "count: 1"  = 全通, 可直接去 BitWriter 烧写
echo         "count: 0"  = 没通, 先看 [1] 和 [2] 哪一步先失败
echo ----------------------------------------------------------
echo.
pause

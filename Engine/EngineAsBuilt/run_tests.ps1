# run_tests.ps1
# This script executes swift test inside the initialized MSVC Arm64 CMD context.

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TestArgs
)

$PSScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$env:SDL3_INCLUDE = "C:/dev/SDL3/include"
$env:SDL3_LIB = "C:/dev/SDL3/lib"
$env:SDL3_IMAGE_INCLUDE = "C:/dev/SDL3/include"
$env:SDL3_IMAGE_LIB = "C:/dev/SDL3/lib"
$env:SDL3_TTF_INCLUDE = "C:/dev/SDL3/include"
$env:SDL3_TTF_LIB = "C:/dev/SDL3/lib"

$env:DXFRW_INCLUDE = "C:/dev/libdxfrw/src"
$env:DXFRW_LIB = "C:/dev/libdxfrw/build/Release"

$env:DWG_INCLUDE = "C:/dev/libredwg/include"
$env:DWG_LIB = "C:/dev/libredwg/build"

$env:ZLIB_NG_INCLUDE = "C:/dev/zlib-ng/include"
$env:ZLIB_NG_LIB = "C:/dev/zlib-ng/lib"

$env:ICONV_INCLUDE = "C:/dev/vcpkg/installed/arm64-windows/include"
$env:ICONV_LIB = "C:/dev/vcpkg/installed/arm64-windows/lib"

$vcvarsPath = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat"
$argsString = if ($TestArgs) { $TestArgs -join " " } else { "" }
$testCommand = "swift test $argsString"
cmd.exe /c "cd /d `"$PSScriptDir`" && `"$vcvarsPath`" arm64 >nul 2>&1 && $testCommand"


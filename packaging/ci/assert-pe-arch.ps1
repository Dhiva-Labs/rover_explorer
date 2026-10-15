<#
.SYNOPSIS
Fails unless a Flutter Windows build folder is built for the expected CPU.

.DESCRIPTION
Reads the COFF machine type of every .exe and .dll under -Dir and the ELF
e_machine of data\app.so (the AOT snapshot, which is an ELF file even on
Windows). No Visual Studio tools are needed.

-IgnoreUninstaller skips unins*.exe, for checking a folder an Inno Setup
installer wrote: the uninstaller Inno Setup 6 generates is a 32-bit x86
program, whatever the architecture of the application it belongs to.

  packaging\ci\assert-pe-arch.ps1 -Dir <folder> -Arch x64|arm64 [-IgnoreUninstaller]
#>
param(
    [Parameter(Mandatory)][string]$Dir,
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch,
    [switch]$IgnoreUninstaller
)
$ErrorActionPreference = 'Stop'

$expectedPe = if ($Arch -eq 'x64') { 0x8664 } else { 0xAA64 }
$expectedElf = if ($Arch -eq 'x64') { 0x3E } else { 0xB7 }

function Get-PeMachine([string]$Path) {
    $fs = [IO.File]::OpenRead($Path)
    try {
        $br = New-Object IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $fs.Position = $br.ReadInt32()
        if ($br.ReadUInt32() -ne 0x4550) { throw "$Path is not a PE file" }
        return [int]$br.ReadUInt16()
    } finally { $fs.Dispose() }
}

$files = Get-ChildItem -Path $Dir -Recurse -File -Include *.exe, *.dll
if ($IgnoreUninstaller) {
    foreach ($u in $files | Where-Object { $_.Name -like 'unins*.exe' }) {
        '{0,-50} 0x{1:X4} (Inno Setup uninstaller, not checked)' -f $u.Name, (Get-PeMachine $u.FullName)
    }
    $files = @($files | Where-Object { $_.Name -notlike 'unins*.exe' })
}
if (-not ($files.Name -contains 'rover_explorer.exe') -or -not ($files.Name -contains 'flutter_windows.dll')) {
    throw "rover_explorer.exe or flutter_windows.dll missing from $Dir"
}

$bad = 0
foreach ($f in $files) {
    $m = Get-PeMachine $f.FullName
    '{0,-50} 0x{1:X4}' -f $f.Name, $m
    if ($m -ne $expectedPe) {
        Write-Host "::error file=$($f.FullName)::machine 0x$('{0:X4}' -f $m), expected 0x$('{0:X4}' -f $expectedPe)"
        $bad++
    }
}

$bytes = [IO.File]::ReadAllBytes((Join-Path $Dir 'data\app.so'))
$elf = [int][BitConverter]::ToUInt16($bytes, 0x12)
'data\app.so ELF e_machine 0x{0:X2}' -f $elf
if ($elf -ne $expectedElf) {
    Write-Host "::error::data\app.so is ELF machine 0x$('{0:X2}' -f $elf), expected 0x$('{0:X2}' -f $expectedElf)"
    $bad++
}

"checked $($files.Count) PE files and app.so for $Arch"
if ($bad) { throw "$bad file(s) are not built for $Arch" }

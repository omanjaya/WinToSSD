param([string]$RequestPath, [string]$ResultPath, [switch]$LibraryOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Say([string]$Text) { Write-Host $Text }
function Snapshot($Disk) {
    [pscustomobject]@{
        number = [int]$Disk.Number; name = [string]$Disk.FriendlyName
        serial = ([string]$Disk.SerialNumber).Trim(); uniqueId = [string]$Disk.UniqueId
        path = [string]$Disk.Path; size = [long]$Disk.Size
        sizeGiB = [math]::Round($Disk.Size / 1GB, 1); partitionStyle = [string]$Disk.PartitionStyle
    }
}
function Assert-Identity($Disk, $Expected, [switch]$AfterErase) {
    $now = Snapshot $Disk
    foreach ($key in @('number', 'path', 'serial', 'size')) {
        if ([string]$now.$key -cne [string]$Expected.$key) { throw "Identitas SSD berubah ($key). Cari SSD dan periksa ulang." }
    }
    if (!$AfterErase -and $now.uniqueId -cne $Expected.uniqueId) { throw 'Unique ID SSD berubah. Periksa ulang.' }
}
function Assert-DiskBasic($Disk) {
    if ([string]$Disk.BusType -ne 'USB') { throw 'Hanya disk dengan koneksi USB yang diizinkan.' }
    if ($Disk.IsBoot -or $Disk.IsSystem) { throw 'Disk Windows/boot yang sedang digunakan tidak boleh dipilih.' }
    if ($Disk.IsOffline -or $Disk.IsReadOnly) { throw 'SSD offline atau read-only. Perbaiki statusnya dahulu di Disk Management.' }
    if ([string]$Disk.HealthStatus -ne 'Healthy') { throw 'Windows melaporkan disk tidak sehat.' }
    if ([long]$Disk.Size -lt 64GB) { throw 'Versi ini mensyaratkan SSD minimal 64 GiB.' }
    if ([string]::IsNullOrWhiteSpace([string]$Disk.Path) -or [string]::IsNullOrWhiteSpace([string]$Disk.UniqueId)) { throw 'Adaptor tidak menyediakan identitas disk yang cukup.' }
    if (@(Get-Disk | Where-Object { $_.UniqueId -eq $Disk.UniqueId }).Count -ne 1) { throw 'Identitas disk duplikat. Lepaskan disk USB lain dan periksa ulang.' }
    $parts = @(Get-Partition -Disk $Disk)
    if (@($parts | Where-Object { $_.IsBoot -or $_.IsSystem }).Count -gt 0) { throw 'Disk berisi partisi Windows/boot aktif komputer ini.' }
    # Do not suppress CIM/storage errors: inability to prove safety must block the operation.
    foreach ($page in @(Get-CimInstance Win32_PageFileUsage)) {
        $letter = ([string]$page.Name).Substring(0, 1)
        if (@(Get-Partition -DriveLetter $letter | Where-Object DiskNumber -EQ $Disk.Number).Count -gt 0) { throw 'SSD digunakan untuk pagefile Windows.' }
    }
}
function Assert-LocalPath([string]$Path) {
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path.Contains('"')) { throw "Gunakan jalur lokal biasa, bukan jaringan: $Path" }
    $item = Get-Item -LiteralPath $Path -Force
    $cursor = $item
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Junction/symlink tidak didukung: $Path" }
        if ($cursor -is [IO.DirectoryInfo]) { $cursor = $cursor.Parent } else { $cursor = $cursor.Directory }
    }
    return $item.FullName
}
function Assert-SourceSeparate([string]$Path, $Disk) {
    $resolved = Assert-LocalPath $Path
    $volumes = @(Get-Volume -FilePath $resolved)
    if ($volumes.Count -ne 1) { throw "Lokasi volume sumber tidak dapat dipastikan: $Path" }
    $partitions = @(Get-Partition -Volume $volumes[0])
    if ($partitions.Count -ne 1) { throw "Lokasi disk sumber tidak dapat dipastikan: $Path" }
    if ($partitions[0].DiskNumber -eq $Disk.Number) { throw "ISO, aplikasi, log, atau driver tersimpan di SSD tujuan: $Path" }
}
function With-Iso([string]$Path, [scriptblock]$Body) {
    $full = Assert-LocalPath $Path
    if ([IO.Path]::GetExtension($full) -ine '.iso') { throw 'Pilih file .iso Windows.' }
    $mountedHere = $false
    $isoLock = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $image = Get-DiskImage -ImagePath $full
        if (!$image.Attached) { $image = Mount-DiskImage -ImagePath $full -Access ReadOnly -PassThru; $mountedHere = $true }
        $vols = @($image | Get-Volume | Where-Object { $_.DriveLetter })
        if ($vols.Count -ne 1) { throw 'ISO tidak memiliki satu volume dengan drive letter yang dapat dibaca.' }
        $root = ([string]$vols[0].DriveLetter) + ':\'
        $files = @(@('sources\install.wim', 'sources\install.esd') | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path -LiteralPath $_ })
        if ($files.Count -ne 1) { throw 'ISO harus berisi satu sources\install.wim atau install.esd. ISO split SWM/custom tidak didukung.' }
        & $Body $root $files[0]
    } finally {
        if ($mountedHere) { try { Dismount-DiskImage -ImagePath $full | Out-Null } catch { Say "ISO belum dilepas: $($_.Exception.Message)" } }
        $isoLock.Dispose()
    }
}
function Assert-Image($Image, [string]$Mode, [int]$HostBuild) {
    $version = [version]$Image.Version
    if ([string]$Image.Architecture -notin @('9', 'x64', 'amd64')) { throw 'ISO harus berarsitektur x64 (Intel/AMD), bukan x86 atau ARM.' }
    if ($version.Major -ne 10 -or $version.Build -lt 10240 -or [string]$Image.InstallationType -ne 'Client') { throw 'Versi ini hanya mendukung image klien Windows 10/11 resmi.' }
    if ($Mode -notin @('UEFI', 'BIOS')) { throw 'Mode boot tidak valid.' }
    if ($version.Build -ge 22000 -and $Mode -ne 'UEFI') { throw 'Windows 11 memerlukan UEFI/GPT. Pilih UEFI atau gunakan ISO Windows 10 untuk Legacy BIOS.' }
    if ($HostBuild -lt $version.Build) { throw "Build Windows komputer pemasang ($HostBuild) lebih tua daripada ISO ($($version.Build)). Gunakan Windows dengan build yang sama/lebih baru. Versi ini belum mendukung ADK terpisah." }
}
function Native([string]$Exe, [string[]]$Arguments) {
    Say ((Split-Path $Exe -Leaf) + ' ' + ($Arguments -join ' '))
    # PowerShell 5.1 turns redirected stderr lines into terminating errors under 'Stop'; judge tools by exit code only.
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments 2>&1 | ForEach-Object { Say ([string]$_) }
    if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $Exe -Leaf) gagal, kode $LASTEXITCODE. Lihat log." }
}
function Assert-ToolSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ([string]$signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw "Alat boot ISO tidak memiliki tanda tangan Microsoft yang valid: $Path"
    }
}
function Preflight($Request, [string]$Root, [string]$ImagePath) {
    Say 'Memeriksa SSD, sumber ISO, dan kompatibilitas image...'
    $disk = Get-Disk -Number ([int]$Request.disk.number)
    Assert-Identity $disk $Request.disk
    Assert-DiskBasic $disk
    foreach ($path in @($Request.iso; $Request.appPath; $PSCommandPath; $RequestPath; (Split-Path -Parent $ResultPath))) {
        Assert-SourceSeparate ([string]$path) $disk
    }
    if ($Request.mode -eq 'BIOS' -and $disk.Size -gt 2TB) { throw 'Legacy MBR dibatasi 2 TiB. Pilih UEFI/GPT.' }
    if ($Request.mode -eq 'BIOS' -and $disk.LogicalSectorSize -ne 512) { throw 'Legacy BIOS pada disk 4Kn tidak didukung. Gunakan UEFI.' }
    $image = Get-WindowsImage -ImagePath $ImagePath -Index ([int]$Request.index)
    $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    Assert-Image $image $Request.mode $build
    if ($disk.Size -lt ([long]$image.ImageSize + 24GB)) { throw 'Ruang SSD tidak cukup untuk image, partisi boot/recovery, dan ruang kerja Windows.' }
    foreach ($tool in @('dism.exe', 'bcdboot.exe', 'bcdedit.exe', 'reagentc.exe', 'mountvol.exe')) {
        if (!(Test-Path -LiteralPath (Join-Path $env:WINDIR "System32\$tool"))) { throw "Alat Windows tidak tersedia: $tool" }
    }
    if ($Request.mode -eq 'BIOS' -and !(Test-Path -LiteralPath (Join-Path $Root 'boot\bootsect.exe'))) { throw 'ISO tidak menyertakan boot\bootsect.exe untuk Legacy BIOS.' }
    if ($Request.mode -eq 'BIOS') { Assert-ToolSignature (Join-Path $Root 'boot\bootsect.exe') }
    if (![string]::IsNullOrWhiteSpace([string]$Request.drivers)) {
        Assert-SourceSeparate $Request.drivers $disk
        $driverItems = @(Get-ChildItem -LiteralPath $Request.drivers -Recurse -Force)
        if (@($driverItems | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count) { throw 'Folder driver mengandung junction/symlink.' }
        if (@($driverItems | Where-Object Extension -EQ '.inf').Count -eq 0) { throw 'Folder driver tidak berisi .inf. Ekstrak paket driver produsen terlebih dahulu.' }
    }
    $localFree = (Get-Volume -FilePath $RequestPath).SizeRemaining
    if ($localFree -lt 2GB) { throw 'Disk tempat log aplikasi perlu ruang kosong minimal 2 GiB untuk scratch DISM.' }
    $freeLetters = @(68..90 | ForEach-Object { [char]$_ } | Where-Object { !(Test-Path "${_}:\") -and !(Get-PSDrive -Name ([string]$_) -ErrorAction SilentlyContinue) })
    if ($freeLetters.Count -lt 3) { throw 'Diperlukan tiga drive letter kosong untuk partisi sementara.' }
    Say 'Menghitung SHA-256 ISO. ISO besar dapat memerlukan beberapa menit...'
    $hash = (Get-FileHash -LiteralPath $Request.iso -Algorithm SHA256).Hash
    $snapshot = Snapshot $disk
    $parts = @(Get-Partition -Disk $disk | Sort-Object PartitionNumber | ForEach-Object { [pscustomobject]@{ number = $_.PartitionNumber; offset = $_.Offset; size = $_.Size; type = [string]$_.Type; letter = [string]$_.DriveLetter } })
    $layout = if ($Request.mode -eq 'UEFI') { 'GPT: EFI FAT32 512 MiB + MSR 16 MiB + Windows NTFS + Recovery NTFS 3 GiB' } else { 'MBR: System NTFS aktif 550 MiB + Windows NTFS + Recovery NTFS 3 GiB' }
    $old = ($parts | ForEach-Object { "  Partisi $($_.number) $($_.letter) - $([math]::Round($_.size / 1GB, 2)) GiB ($($_.type))" }) -join "`r`n"
    $summary = @"
SEMUA ISI DISK $($disk.Number) AKAN DIHAPUS
Model: $($snapshot.name)
Kapasitas: $($snapshot.sizeGiB) GiB
Nomor seri: $($snapshot.serial)
Unique ID: $($snapshot.uniqueId)

Partisi saat ini:
$old

ISO: $($Request.iso)
Edisi: $($image.ImageName) | versi $($image.Version) | x64
SHA-256: $hash
Mode tujuan: $($Request.mode)
Rencana: $layout
Driver tambahan: $($Request.drivers)

SSD akan dipasang DI DALAM komputer setelah proses selesai.
Mode firmware, CPU, TPM, Secure Boot, dan driver komputer tujuan tidak bisa diperiksa dari sini.
Pemeriksaan berkas boot bukan jaminan berhasil boot pada perangkat tujuan.
"@
    [pscustomobject]@{ disk = $snapshot; isoHash = $hash; index = [int]$Request.index; mode = [string]$Request.mode; drivers = [string]$Request.drivers; iso = [string]$Request.iso; partitions = $parts; summary = $summary }
}
function Assert-Plan($Current, $Approved) {
    foreach ($key in @('isoHash', 'index', 'mode', 'drivers', 'iso')) {
        if ([string]$Current.$key -cne [string]$Approved.$key) { throw "Rencana berubah ($key). Jalankan pemeriksaan dan konfirmasi lagi." }
    }
    foreach ($key in @('number', 'path', 'serial', 'size', 'uniqueId')) {
        if ([string]$Current.disk.$key -cne [string]$Approved.disk.$key) { throw 'SSD berbeda dari rencana yang disetujui.' }
    }
    if (($Current.partitions | ConvertTo-Json -Depth 5 -Compress) -cne ($Approved.partitions | ConvertTo-Json -Depth 5 -Compress)) { throw 'Susunan partisi SSD berubah. Periksa ulang.' }
}
function Target-Disk($Expected) {
    $disk = Get-Disk -Number $Expected.number
    Assert-Identity $disk $Expected -AfterErase
    if ($disk.IsBoot -or $disk.IsSystem -or [string]$disk.BusType -ne 'USB') { throw 'SSD tidak lagi memenuhi syarat target.' }
    return $disk
}
function Target-Partition($Expected, $Part) {
    $null = Target-Disk $Expected
    $current = Get-Partition -DiskNumber $Expected.number -PartitionNumber $Part.PartitionNumber
    if ($current.Offset -ne $Part.Offset -or $current.Size -ne $Part.Size -or $current.DriveLetter -ne $Part.DriveLetter) { throw 'Identitas partisi tujuan berubah. Proses dihentikan.' }
    if ([string]$current.DriveLetter -notmatch '^[A-Za-z]$') { throw 'Partisi tujuan tidak mendapat drive letter yang valid.' }
    if ($current.DriveLetter) {
        $owner = @(Get-Partition -DriveLetter $current.DriveLetter)
        if ($owner.Count -ne 1 -or $owner[0].DiskNumber -ne $Expected.number) { throw 'Drive letter tidak lagi menunjuk SSD tujuan.' }
    }
    return $current
}
function Install-Windows($Request, [string]$Root, [string]$ImagePath) {
    if ($Request.confirmation -cne "HAPUS DISK $($Request.plan.disk.number)") { throw 'Konfirmasi penghapusan tidak cocok.' }
    $current = Preflight $Request $Root $ImagePath
    Assert-Plan $current $Request.plan
    $expected = $current.disk
    # Final safety gate immediately before the one destructive entry point.
    $disk = Get-Disk -Number $expected.number
    Assert-Identity $disk $expected
    Assert-DiskBasic $disk
    Say "MULAI FORMAT DISK $($expected.number). Jangan cabut kabel atau matikan komputer."
    if ([string]$disk.PartitionStyle -ne 'RAW') { Clear-Disk -InputObject $disk -RemoveData -RemoveOEM -Confirm:$false }
    $disk = Target-Disk $expected
    $style = if ($Request.mode -eq 'UEFI') { 'GPT' } else { 'MBR' }
    Initialize-Disk -InputObject $disk -PartitionStyle $style | Out-Null
    $disk = Target-Disk $expected
    if ($Request.mode -eq 'UEFI') {
        # Initialize-Disk adds its own MSR at the start; drop it so the layout is EFI, MSR, Windows, Recovery.
        foreach ($msr in @(Get-Partition -Disk $disk -ErrorAction SilentlyContinue | Where-Object GptType -EQ '{e3c9e316-0b5c-4db8-817d-f92df00215ae}')) {
            Remove-Partition -InputObject $msr -Confirm:$false
        }
        $disk = Target-Disk $expected
        $system = New-Partition -DiskPath $disk.Path -Size 512MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter
        $null = Target-Disk $expected
        New-Partition -DiskPath $disk.Path -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | Out-Null
        $fs = 'FAT32'
    } else {
        $system = New-Partition -DiskPath $disk.Path -Size 550MB -MbrType IFS -IsActive -AssignDriveLetter
        $fs = 'NTFS'
    }
    $part = Target-Partition $expected $system
    Format-Volume -Partition $part -FileSystem $fs -NewFileSystemLabel 'SYSTEM' -Confirm:$false | Out-Null
    $disk = Target-Disk $expected
    $windowsBytes = [long]([math]::Floor(($disk.LargestFreeExtent - 3GB - 8MB) / 1MB) * 1MB)
    $dataOptions = @{}
    if ($Request.mode -eq 'BIOS') { $dataOptions.MbrType = 'IFS' }
    $windows = New-Partition -DiskPath $disk.Path -Size $windowsBytes -AssignDriveLetter @dataOptions
    $part = Target-Partition $expected $windows
    Format-Volume -Partition $part -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false | Out-Null
    $disk = Target-Disk $expected
    $recovery = New-Partition -DiskPath $disk.Path -UseMaximumSize -AssignDriveLetter @dataOptions
    $part = Target-Partition $expected $recovery
    Format-Volume -Partition $part -FileSystem NTFS -NewFileSystemLabel 'Recovery' -Confirm:$false | Out-Null
    $s = "$($system.DriveLetter):"; $w = "$($windows.DriveLetter):"; $r = "$($recovery.DriveLetter):"
    $sys32 = Join-Path $env:WINDIR 'System32'
    $scratch = Join-Path (Split-Path $RequestPath -Parent) 'scratch'
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Say 'Menyalin image Windows ke SSD...'
    $null = Target-Partition $expected $windows
    Native "$sys32\dism.exe" @('/English', '/Apply-Image', "/ImageFile:$ImagePath", "/Index:$($Request.index)", "/ApplyDir:$w\", '/CheckIntegrity', '/Verify', "/ScratchDir:$scratch", "/LogPath:$(Split-Path $RequestPath -Parent)\dism.log")
    if (![string]::IsNullOrWhiteSpace([string]$Request.drivers)) {
        $null = Target-Partition $expected $windows
        Say 'Menambahkan driver bertanda tangan dari folder pilihan...'
        Native "$sys32\dism.exe" @('/English', "/Image:$w\", '/Add-Driver', "/Driver:$($Request.drivers)", '/Recurse', "/LogPath:$(Split-Path $RequestPath -Parent)\drivers.log")
    }
    Say 'Membuat berkas boot pada SSD tujuan...'
    $null = Target-Partition $expected $windows
    $null = Target-Partition $expected $system
    Native "$sys32\bcdboot.exe" @("$w\Windows", '/s', $s, '/f', $Request.mode, '/v')
    if ($Request.mode -eq 'BIOS') {
        $null = Target-Partition $expected $system
        Native (Join-Path $Root 'boot\bootsect.exe') @('/nt60', $s, '/mbr')
    }
    Say 'Menyiapkan Windows Recovery Environment...'
    $null = Target-Partition $expected $windows
    $null = Target-Partition $expected $recovery
    $winre = "$w\Windows\System32\Recovery\Winre.wim"
    if (!(Test-Path -LiteralPath $winre)) { throw 'Image tidak menyertakan Winre.wim. Pemasangan belum dinyatakan selesai.' }
    if ((Get-Item -LiteralPath $winre -Force).Length + 300MB -gt (Get-Volume -Partition $recovery).SizeRemaining) { throw 'Partisi recovery tidak cukup untuk WinRE dan ruang pembaruan.' }
    New-Item -ItemType Directory -Path "$r\Recovery\WindowsRE" -Force | Out-Null
    Copy-Item -LiteralPath $winre -Destination "$r\Recovery\WindowsRE\Winre.wim" -Force
    Native "$sys32\reagentc.exe" @('/setreimage', '/path', "$r\Recovery\WindowsRE", '/target', "$w\Windows")
    # Verify file presence, BCD store readability, and the expected OS loader entry.
    $null = Target-Partition $expected $windows
    $null = Target-Partition $expected $system
    $required = @("$w\Windows\System32\ntoskrnl.exe", "$w\Windows\System32\config\SYSTEM", "$r\Recovery\WindowsRE\Winre.wim")
    if ($Request.mode -eq 'UEFI') {
        $bcd = "$s\EFI\Microsoft\Boot\BCD"
        $required += @("$s\EFI\Boot\bootx64.efi", "$s\EFI\Microsoft\Boot\bootmgfw.efi", "$w\Windows\System32\winload.efi")
    } else {
        $bcd = "$s\Boot\BCD"
        $required += @("$s\bootmgr", "$w\Windows\System32\winload.exe")
    }
    $required += $bcd
    foreach ($file in $required) { if (!(Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file -Force).Length -eq 0) { throw "Berkas penting hilang/kosong: $file" } }
    Native "$sys32\bcdedit.exe" @('/store', $bcd, '/enum', '{bootmgr}')
    Native "$sys32\bcdedit.exe" @('/store', $bcd, '/enum', '{default}')
    Native "$sys32\reagentc.exe" @('/info', '/target', "$w\Windows")
    $part = Target-Partition $expected $recovery
    # Recovery/EFI types are never auto-mounted, so no NoDefaultDriveLetter (Storage rejects it on non-data partitions).
    if ($Request.mode -eq 'UEFI') { Set-Partition -InputObject $part -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' }
    else { Set-Partition -InputObject $part -MbrType 0x27 }
    foreach ($part in @($system, $recovery)) {
        $null = Target-Partition $expected $part
        Native "$sys32\mountvol.exe" @("$($part.DriveLetter):\", '/D')
    }
    Say 'Verifikasi berkas selesai. Boot fisik belum diuji.'
    [pscustomobject]@{ summary = @"
BERKAS WINDOWS DAN BOOT SELESAI DISIAPKAN
Disk $($expected.number): $($expected.name) - $($expected.sizeGiB) GiB
Mode: $($Request.mode) / $style

1. Tutup aplikasi dan matikan komputer pemasang sepenuhnya sebelum mencabut SSD.
2. Pasang SSD di slot internal komputer tujuan saat komputer tersebut mati.
3. Cocokkan mode firmware dengan pilihan $($Request.mode).
4. Pilih Windows Boot Manager (UEFI) atau SSD (Legacy) pada urutan boot.
5. Selesaikan pengaturan awal Windows; internet/akun mungkin diperlukan.

Windows Recovery didaftarkan; pengaktifannya berlangsung pada konfigurasi awal Windows.
Berkas boot telah diperiksa, tetapi keberhasilan boot dan kecocokan hardware belum diuji.
Jika muncul INACCESSIBLE_BOOT_DEVICE, periksa driver storage dan mode controller komputer tujuan.
Jangan ubah AHCI/RAID/VMD sembarangan jika komputer juga memiliki instalasi Windows lain.
Log tersimpan di folder sesi aplikasi.
"@ }
}

if ($LibraryOnly) { return }
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$exitCode = 0
$mutex = $null
$ownsMutex = $false
try {
    $admin = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!$admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Jalankan aplikasi sebagai Administrator.' }
    if (![Environment]::Is64BitProcess) { throw 'PowerShell x64 diperlukan.' }
    Import-Module Storage -ErrorAction Stop
    Import-Module Dism -ErrorAction Stop
    $mutex = New-Object Threading.Mutex($false, 'Global\SSDInstaller-Deployment')
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (!$ownsMutex) { throw 'Proses SSD Installer lain sedang berjalan.' }
    $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $data = switch ([string]$request.action) {
        'List' {
            $safe = @()
            foreach ($disk in @(Get-Disk | Where-Object { [string]$_.BusType -eq 'USB' })) {
                try { Assert-DiskBasic $disk; $safe += Snapshot $disk }
                catch { Say "Disk $($disk.Number) tidak ditampilkan: $($_.Exception.Message)" }
            }
            [pscustomobject]@{ disks = $safe }
        }
        'Inspect' {
            With-Iso $request.iso {
                param($root, $imagePath)
                $images = @(Get-WindowsImage -ImagePath $imagePath | ForEach-Object {
                    $detail = Get-WindowsImage -ImagePath $imagePath -Index $_.ImageIndex
                    $arch = switch ([string]$detail.Architecture) { '9' { 'x64' }; '0' { 'x86' }; '12' { 'ARM64' }; default { [string]$detail.Architecture } }
                    [pscustomobject]@{ index = [int]$detail.ImageIndex; name = [string]$detail.ImageName; architecture = $arch; version = [string]$detail.Version }
                })
                [pscustomobject]@{ images = $images }
            }
        }
        'Preflight' { With-Iso $request.iso { param($root, $imagePath) Preflight $request $root $imagePath } }
        'Install' { With-Iso $request.iso { param($root, $imagePath) Install-Windows $request $root $imagePath } }
        default { throw 'Aksi tidak dikenal.' }
    }
    @{ ok = $true; data = $data } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
} catch {
    $exitCode = 1
    Say $_.ScriptStackTrace
    Say $_.Exception.Message
    @{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $exitCode

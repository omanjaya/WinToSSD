param([string]$EnginePath = (Join-Path $PSScriptRoot 'Engine.ps1'))
$ErrorActionPreference = 'Stop'
. $EnginePath -LibraryOnly
$script:passed = 0
function Pass([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Output "PASS $Name"
}
function Reject([string]$Name, [scriptblock]$Body, [string]$ExpectedMessage) {
    $caught = $false
    try { & $Body } catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") { throw "Wrong rejection for ${Name}: $($_.Exception.Message)" }
        $caught = $true
    }
    if (!$caught) { throw "Unsafe acceptance: $Name" }
    $script:passed++
    Write-Output "PASS reject $Name"
}
function Clone($Value) { $Value | ConvertTo-Json -Depth 12 | ConvertFrom-Json }
$image10 = [pscustomobject]@{ Version = '10.0.19045.0'; Architecture = 9; InstallationType = 'Client' }
$image11 = [pscustomobject]@{ Version = '10.0.26100.0'; Architecture = 9; InstallationType = 'Client' }
Pass 'Windows 10 UEFI' { Assert-Image $image10 UEFI 26100 }
Pass 'Windows 10 BIOS' { Assert-Image $image10 BIOS 19045 }
Pass 'Windows 11 UEFI' { Assert-Image $image11 UEFI 26100 }
Reject 'Windows 11 BIOS' { Assert-Image $image11 BIOS 26100 } 'UEFI/GPT'
Reject 'host older than image' { Assert-Image $image11 UEFI 19045 } 'lebih tua'
Reject 'invalid firmware mode' { Assert-Image $image10 TYPO 26100 } 'Mode boot'
Reject 'ARM64' { $i = Clone $image11; $i.Architecture = 12; Assert-Image $i UEFI 26100 } 'x64'
Reject '32-bit image' { $i = Clone $image10; $i.Architecture = 0; Assert-Image $i BIOS 26100 } 'x64'
Reject 'Windows Server' { $i = Clone $image11; $i.InstallationType = 'Server'; Assert-Image $i UEFI 26100 } 'klien'
Reject 'Windows 7' { $i = Clone $image10; $i.Version = '6.1.7601.0'; Assert-Image $i BIOS 26100 } 'Windows 10/11'
$script:disk = [pscustomobject]@{
    Number = 3; FriendlyName = 'Test SSD'; SerialNumber = 'SERIAL-123'; UniqueId = 'USB-123'; Path = 'disk-path-123'
    Size = 256GB; PartitionStyle = 'GPT'; BusType = 'USB'; IsBoot = $false; IsSystem = $false
    IsOffline = $false; IsReadOnly = $false; HealthStatus = 'Healthy'; LogicalSectorSize = 512
}
$script:parts = @()
$script:pagefiles = @()
$script:letterParts = @()
$script:duplicates = $false
function Get-Disk { param($Number) if ($script:duplicates) { @($script:disk, $script:disk) } else { $script:disk } }
function Get-Partition { param($Disk, $DiskNumber, $DriveLetter) if ($DriveLetter) { $script:letterParts } else { $script:parts } }
function Get-CimInstance { param($ClassName) $script:pagefiles }
$snapshot = Snapshot $script:disk
Pass 'matching disk identity' { Assert-Identity $script:disk $snapshot }
foreach ($field in @('Number', 'Path', 'SerialNumber', 'UniqueId', 'Size')) {
    Reject "changed disk $field" { $d = Clone $script:disk; if ($field -eq 'Size' -or $field -eq 'Number') { $d.$field++ } else { $d.$field = 'replacement' }; Assert-Identity $d $snapshot } 'berubah'
}
Pass 'disk layout identity may change after erase' { $d = Clone $script:disk; $d.UniqueId = 'new-layout'; Assert-Identity $d $snapshot -AfterErase }
Reject 'serial may not change after erase' { $d = Clone $script:disk; $d.SerialNumber = 'replacement'; Assert-Identity $d $snapshot -AfterErase } 'berubah'
Pass 'eligible empty USB SSD' { Assert-DiskBasic $script:disk }
foreach ($flag in @('IsBoot', 'IsSystem')) {
    Reject "protected $flag disk" { $d = Clone $script:disk; $d.$flag = $true; Assert-DiskBasic $d } 'sedang digunakan'
}
foreach ($flag in @('IsOffline', 'IsReadOnly')) {
    Reject "$flag disk" { $d = Clone $script:disk; $d.$flag = $true; Assert-DiskBasic $d } 'read-only'
}
Reject 'internal NVMe' { $d = Clone $script:disk; $d.BusType = 'NVMe'; Assert-DiskBasic $d } 'USB'
Reject 'undersized disk' { $d = Clone $script:disk; $d.Size = 32GB; Assert-DiskBasic $d } '64 GiB'
Reject 'unhealthy disk' { $d = Clone $script:disk; $d.HealthStatus = 'Warning'; Assert-DiskBasic $d } 'tidak sehat'
Reject 'missing ID' { $d = Clone $script:disk; $d.UniqueId = ''; Assert-DiskBasic $d } 'identitas'
$script:duplicates = $true
Reject 'duplicate hardware ID' { Assert-DiskBasic $script:disk } 'duplikat'
$script:duplicates = $false
$script:parts = @([pscustomobject]@{ IsBoot = $false; IsSystem = $true })
Reject 'protected partition on USB' { Assert-DiskBasic $script:disk } 'partisi'
$script:parts = @()
$script:pagefiles = @([pscustomobject]@{ Name = 'E:\pagefile.sys' })
$script:letterParts = @([pscustomobject]@{ DiskNumber = 3 })
Reject 'pagefile on target' { Assert-DiskBasic $script:disk } 'pagefile'
$script:pagefiles = @()
$plan = [pscustomobject]@{ disk = $snapshot; isoHash = 'ABC123'; index = 1; mode = 'UEFI'; drivers = ''; iso = 'C:\Windows.iso'; localAccount = ''; partitions = @([pscustomobject]@{ number = 1; offset = 1048576; size = 128GB; type = 'Basic'; letter = 'E' }) }
Pass 'unchanged approved plan' { Assert-Plan $plan (Clone $plan) }
foreach ($field in @('isoHash', 'index', 'mode', 'drivers', 'iso', 'localAccount')) {
    Reject "changed plan $field" { $other = Clone $plan; if ($field -eq 'index') { $other.index = 2 } else { $other.$field = 'changed' }; Assert-Plan $other $plan } 'berubah'
}
Reject 'partition modified after approval' { $other = Clone $plan; $other.partitions[0].size = 64GB; Assert-Plan $other $plan } 'partisi'
Reject 'disk swapped after approval' { $other = Clone $plan; $other.disk.number = 8; Assert-Plan $other $plan } 'SSD berbeda'
# Destructive entry point must reject missing/wrong consent before it can query or mutate a disk.
function Clear-Disk { throw 'TEST FAILURE: Clear-Disk reached' }
Reject 'incorrect erase phrase' { Install-Windows ([pscustomobject]@{ confirmation = 'YES'; plan = $plan }) 'X:\' 'X:\sources\install.wim' } 'Konfirmasi'
$script:signature = [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Windows, O=Microsoft Corporation, C=US' } }
function Get-AuthenticodeSignature { param($LiteralPath) $script:signature }
Pass 'valid Microsoft boot tool' { Assert-ToolSignature 'X:\boot\bootsect.exe' }
$script:signature.Status = 'NotSigned'
Reject 'unsigned boot tool' { Assert-ToolSignature 'X:\boot\bootsect.exe' } 'tanda tangan'
$script:signature.Status = 'Valid'
$script:signature.SignerCertificate.Subject = 'CN=Untrusted Vendor, O=Not Microsoft Corporation, C=US'
Reject 'non-Microsoft boot tool' { Assert-ToolSignature 'X:\boot\bootsect.exe' } 'tanda tangan'
# Native tools may write to stderr on success; only the exit code decides failure.
if ($env:OS -eq 'Windows_NT') {
    $cmd = Join-Path $env:WINDIR 'System32\cmd.exe'
    Pass 'native tool stderr with exit 0' { Native $cmd @('/c', 'echo warning 1>&2 & exit 0') }
    Reject 'native tool nonzero exit' { Native $cmd @('/c', 'echo failure 1>&2 & exit 5') } 'kode 5'
}
Pass 'valid local account name' { Assert-AccountName 'Teknisi_01' }
Reject 'local account with space' { Assert-AccountName 'Pak Budi' } 'akun lokal'
Reject 'built-in account name' { Assert-AccountName 'administrator' } 'akun lokal'
Reject 'XML characters in account' { Assert-AccountName 'a<b>' } 'akun lokal'
Pass 'unattend is valid XML' { $x = [xml](Unattend-Xml 'Teknisi'); if ($x.unattend.settings.component.UserAccounts.LocalAccounts.LocalAccount.Name -ne 'Teknisi') { throw 'account missing' } }
$script:Lang = 'en'
Reject 'English messages' { Assert-Image $image11 BIOS 26100 } 'requires UEFI'
Reject 'English erase phrase' { Install-Windows ([pscustomobject]@{ confirmation = 'HAPUS DISK 3'; plan = $plan }) 'X:\' 'X:\sources\install.wim' } 'does not match'
$script:Lang = 'id'

# Full install flow against an in-memory disk; Storage cmdlets, DISM and file writes are mocked.
$RequestPath = 'C:\fake\session\request.json'
function New-FakeDisk {
    $script:fake = @{ style = 'GPT'; parts = [Collections.ArrayList]@(); letters = [Collections.Queue]@('R', 'S', 'T'); native = [Collections.ArrayList]@(); files = @{}; cleared = $false }
    $null = $script:fake.parts.Add([pscustomobject]@{ DiskNumber = 3; PartitionNumber = 1; Offset = 1MB; Size = 100GB; DriveLetter = [char]'E'; GptType = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'; MbrType = $null; IsActive = $false })
}
function Fake-End { $end = 1MB; foreach ($p in $script:fake.parts) { if ($p.Offset + $p.Size -gt $end) { $end = $p.Offset + $p.Size } }; [long]$end }
function Get-Disk { param($Number) $d = Clone $script:disk; $d.PartitionStyle = $script:fake.style; $d | Add-Member -NotePropertyName LargestFreeExtent -NotePropertyValue ([long]($d.Size - (Fake-End) - 1MB)) -PassThru }
function Clear-Disk { $script:fake.parts.Clear(); $script:fake.style = 'RAW'; $script:fake.cleared = $true }
# Like Windows, initializing as GPT creates an MSR on its own.
function Initialize-Disk { param($InputObject, $PartitionStyle) $script:fake.style = $PartitionStyle; if ($PartitionStyle -eq 'GPT') { $null = $script:fake.parts.Add([pscustomobject]@{ DiskNumber = 3; PartitionNumber = 1; Offset = 1MB; Size = 16MB; DriveLetter = [char]0; GptType = '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'; MbrType = $null; IsActive = $false }) } }
function Get-Partition { param($Disk, $DiskNumber, $PartitionNumber, $DriveLetter)
    if ($DriveLetter) { return @($script:fake.parts | Where-Object { [string]$_.DriveLetter -eq [string]$DriveLetter }) }
    if ($PartitionNumber) { return @($script:fake.parts | Where-Object PartitionNumber -EQ $PartitionNumber)[0] }
    @($script:fake.parts)
}
function Remove-Partition { param($InputObject) $script:fake.parts.Remove($InputObject); $n = 1; foreach ($p in @($script:fake.parts | Sort-Object Offset)) { $p.PartitionNumber = $n++ } }
function New-Partition { param($DiskPath, $Size, $GptType, $MbrType, [switch]$IsActive, [switch]$AssignDriveLetter, [switch]$UseMaximumSize)
    $offset = Fake-End
    if ($UseMaximumSize) { $Size = $script:disk.Size - $offset - 1MB }
    if (!$GptType -and $script:fake.style -eq 'GPT') { $GptType = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }
    $letter = if ($AssignDriveLetter) { [char]$script:fake.letters.Dequeue() } else { [char]0 }
    $p = [pscustomobject]@{ DiskNumber = 3; PartitionNumber = $script:fake.parts.Count + 1; Offset = $offset; Size = [long]$Size; DriveLetter = $letter; GptType = $GptType; MbrType = $MbrType; IsActive = [bool]$IsActive }
    $null = $script:fake.parts.Add($p); $p
}
function Format-Volume { }
function Set-Partition { param($InputObject, $GptType, $MbrType) if ($GptType) { $InputObject.GptType = $GptType }; if ($MbrType) { $InputObject.MbrType = $MbrType } }
function Native([string]$Exe, [string[]]$Arguments) { $null = $script:fake.native.Add((Split-Path $Exe -Leaf) + ' ' + ($Arguments -join ' ')) }
function Set-Content { param($LiteralPath, $Value) $script:fake.files[$LiteralPath] = [string]$Value }
function Test-Path { $true }
function Get-Item { [pscustomobject]@{ Length = 1 } }
function Get-Volume { [pscustomobject]@{ SizeRemaining = 3GB } }
function New-Item { }
function Copy-Item { }
function Say { }
function Assert-DiskBasic { }
function Preflight { $script:fakePlan }
function Install-Fake([string]$Mode, [string]$Account) {
    New-FakeDisk
    $script:fakePlan = [pscustomobject]@{ disk = (Snapshot (Get-Disk -Number 3)); isoHash = 'H'; index = 1; mode = $Mode; drivers = ''; iso = 'C:\w.iso'; localAccount = $Account; partitions = @(); summary = '' }
    $null = Install-Windows ([pscustomobject]@{ confirmation = 'HAPUS DISK 3'; mode = $Mode; index = 1; drivers = ''; plan = (Clone $script:fakePlan) }) "$env:SystemDrive\" "$env:SystemDrive\sources\install.wim"
}
Pass 'install flow UEFI layout has one MSR' {
    Install-Fake UEFI 'Teknisi'
    $types = @($script:fake.parts | Sort-Object Offset | ForEach-Object { $_.GptType }) -join ' '
    if (!$script:fake.cleared) { throw 'disk was not cleared' }
    if ($types -ne '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b} {e3c9e316-0b5c-4db8-817d-f92df00215ae} {ebd0a0a2-b9e5-4433-87c0-68b6b72699c7} {de94bba4-06d1-4d40-a16a-bfd50179d6ac}') { throw "unexpected GPT layout: $types" }
}
Pass 'install flow UEFI boot files and letter removal' {
    $log = $script:fake.native -join "`n"
    foreach ($expected in @('dism.exe /English /Apply-Image', 'bcdboot.exe S:\Windows /s R: /f UEFI', 'mountvol.exe R:\ /D', 'mountvol.exe T:\ /D')) { if (!$log.Contains($expected)) { throw "missing: $expected" } }
}
Pass 'install flow writes local account unattend' {
    $x = [xml]$script:fake.files['S:\Windows\Panther\unattend.xml']
    if ($x.unattend.settings.component.UserAccounts.LocalAccounts.LocalAccount.Name -ne 'Teknisi') { throw 'unattend account missing' }
}
Pass 'install flow BIOS layout' {
    Install-Fake BIOS ''
    $parts = @($script:fake.parts | Sort-Object Offset)
    if ($parts.Count -ne 3 -or $parts[0].MbrType -ne 'IFS' -or !$parts[0].IsActive -or $parts[2].MbrType -ne 0x27) { throw 'unexpected MBR layout' }
    $log = $script:fake.native -join "`n"
    foreach ($expected in @('bcdboot.exe S:\Windows /s R: /f BIOS', 'bootsect.exe /nt60 R: /mbr', 'mountvol.exe T:\ /D')) { if (!$log.Contains($expected)) { throw "missing: $expected" } }
    if ($script:fake.files.Count -ne 0) { throw 'unattend written without a local account' }
}
Write-Output "TOTAL: $script:passed tests passed. Storage/DISM are mocked; no physical disk or boot test was performed."

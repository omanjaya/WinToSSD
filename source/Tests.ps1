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
$plan = [pscustomobject]@{ disk = $snapshot; isoHash = 'ABC123'; index = 1; mode = 'UEFI'; drivers = ''; iso = 'C:\Windows.iso'; partitions = @([pscustomobject]@{ number = 1; offset = 1048576; size = 128GB; type = 'Basic'; letter = 'E' }) }
Pass 'unchanged approved plan' { Assert-Plan $plan (Clone $plan) }
foreach ($field in @('isoHash', 'index', 'mode', 'drivers', 'iso')) {
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
Write-Output "TOTAL: $script:passed tests passed. Storage/DISM are mocked; no physical disk or boot test was performed."

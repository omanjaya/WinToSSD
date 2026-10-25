<img src="docs/icon.png" alt="" width="72" align="right">

# WinToSSD (SSD Installer)

**Install Windows 10/11 from an ISO directly onto an SSD through a USB adapter, then fit the SSD inside the target PC or laptop. No bootable flash drive needed.**

**Pasang Windows 10/11 dari ISO langsung ke SSD lewat adaptor USB, lalu pasang SSD di dalam PC/laptop tujuan. Tanpa flashdisk installer.**

[![Download](https://img.shields.io/github/v/release/omanjaya/WinToSSD?include_prereleases&label=download)](../../releases/latest)
[![Build](https://github.com/omanjaya/WinToSSD/actions/workflows/build.yml/badge.svg)](https://github.com/omanjaya/WinToSSD/actions/workflows/build.yml)
[![VirusTotal v0.1.0](https://img.shields.io/badge/VirusTotal-v0.1.0-blue)](https://www.virustotal.com/gui/file/a6039499d538bc3c8fcf988bfbb1346899873fce8c014c229d1338d46ee91200)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

![SSD Installer](docs/screenshot.png)

> [!WARNING]
> **Preview / Pratinjau 0.1.** The selected SSD is **completely erased**. Use an empty or spare SSD. Tested so far: Windows 11 Pro (UEFI) installed from a Windows 11 26H2 PC and **booted successfully on an all-in-one PC**. Legacy BIOS, Windows 10, extra drivers and the local account option are not tested on hardware yet.
>
> SSD yang dipilih akan **dihapus seluruhnya**. Gunakan SSD kosong/cadangan. Sudah diuji: Windows 11 Pro (UEFI) dipasang dari PC Windows 11 26H2 dan **berhasil boot di PC AIO**. Legacy BIOS, Windows 10, driver tambahan, dan opsi akun lokal belum diuji di hardware.

## For technicians · Untuk teknisi

Useful for repair shops and technicians who replace or upgrade SSDs:

- Prepare a fresh Windows SSD on your workbench PC while the customer's laptop stays closed — no USB installer, no booting the target machine from a flash drive.
- Pick the edition (Home, Pro, …) straight from the official ISO, and add storage drivers (Intel RST/VMD/RAID `.inf`) so the new SSD boots on machines that need them.
- Choose UEFI/GPT or Legacy BIOS/MBR for the target machine, not the workbench PC.
- Optional **local account**: hand over a PC that boots straight to the desktop — no Microsoft account or Wi-Fi needed during setup.
- Live DISM progress, Windows kept awake during the install, English and Indonesian interface.
- Free and open source (MIT). Not affiliated with WinToHDD or Hasleo.

Cocok untuk servis laptop/PC yang mengganti atau upgrade SSD:

- Siapkan SSD berisi Windows baru di PC kerja, tanpa flashdisk installer dan tanpa membongkar-pasang boot di laptop pelanggan.
- Pilih edisi (Home, Pro, …) langsung dari ISO resmi, dan tambahkan driver storage (Intel RST/VMD/RAID `.inf`) agar SSD bisa boot di laptop yang memerlukannya.
- Pilih mode UEFI/GPT atau Legacy BIOS/MBR sesuai komputer tujuan, bukan PC kerja.
- Opsi **akun lokal**: serahkan PC yang langsung masuk desktop, tanpa akun Microsoft atau Wi-Fi saat setup.
- Progres DISM real-time, PC dicegah sleep selama pemasangan, tampilan bahasa Indonesia dan Inggris.
- Gratis dan open source (MIT). Tidak berafiliasi dengan WinToHDD maupun Hasleo.

## Safety checks · Pengaman

- Only healthy, writable **USB** disks are listed; the running Windows disk, boot/system disks and pagefile disks are rejected. The target disk is never preselected.
- **Check without formatting** first: reads the ISO and SSD and shows the full plan (model, capacity, serial number, current partitions).
- Erasing requires a checkbox plus typing `HAPUS DISK N`. Disk identity, ISO hash and partition layout are re-checked right before formatting.
- After applying, boot files, BCD and WinRE are verified on the SSD.

## Requirements · Kebutuhan

- Workbench PC: Windows 10/11 x64, Administrator rights. Its Windows build must be **the same or newer** than the ISO build (e.g. a 26200 PC cannot install a 26300 ISO).
- Official Windows 10/11 x64 ISO with `sources\install.wim` or `install.esd`.
- SSD of at least 64 GiB plus a SATA/NVMe-to-USB adapter.
- Windows 11 still requires compatible hardware (TPM, Secure Boot, CPU). Licensing/activation is not changed.

## Quick start · Cara cepat

1. Download `SSDInstaller.exe` from [Releases](../../releases/latest) and check its SHA-256 against `SHA256SUMS.txt`.
2. Run it as Administrator → **Pilih ISO** → pick the edition.
3. **Cari SSD USB** → pick the SSD by model, capacity and serial number.
4. Choose **UEFI / GPT** (Windows 11, modern PCs) or **Legacy BIOS / MBR** (old PCs, Windows 10 only). Optionally enter a **local account** name.
5. **2. Check without formatting** → read the plan → **3. Install Windows…** → confirm. (Switch the interface language in the top-right corner.)
6. When done, eject safely (or shut down), install the SSD in the target PC and boot from **Windows Boot Manager**.

Full guide in Indonesian: **[PANDUAN-SSDInstaller.md](PANDUAN-SSDInstaller.md)**. Test results: [HASIL-PENGUJIAN.txt](HASIL-PENGUJIAN.txt). Changes: [CHANGELOG.md](CHANGELOG.md). Found a problem? [Report a bug](../../issues/new/choose).

## About antivirus warnings · Soal peringatan antivirus

The EXE is not code-signed yet, so Windows SmartScreen shows "unknown publisher". Because it requests Administrator rights and runs DISM/diskpart-style PowerShell commands, a few antivirus engines may flag it heuristically. Release EXEs from 0.2 onward are built by [GitHub Actions](../../actions/workflows/build.yml) straight from this source, with the SHA-256 shown in each run. The full source is in [`source/`](source) — you can review it and build the EXE yourself:

```powershell
cd source
dotnet publish SSDInstaller.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish
.\Tests.ps1
```

## License

Application code: [MIT](LICENSE). The bundled .NET runtime has its own licenses in [`source/runtime-licenses`](source/runtime-licenses). Windows ISOs and licenses are not included.

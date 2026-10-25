# Changelog

## 0.2.0 — unreleased

### Added
- English interface: switch between Bahasa Indonesia and English in the top-right corner; the choice is remembered.
- Real progress: the progress bar and status show the DISM percentage while Windows is being applied.
- Windows is kept awake while the app works, so sleep cannot interrupt an installation.
- Optional local account: creates a passwordless local administrator and skips the Microsoft account and Wi-Fi pages during Windows setup (official `unattend.xml`).
- App icon.
- GitHub Actions build: runs the safety tests and builds the EXE from the public source on every push; tagged versions are attached to the GitHub Release.
- Bug report form that asks for the log and hardware details.
- Mock-based tests for the full install flow (UEFI and Legacy BIOS layouts, boot files, drive-letter removal, local account) — 56 tests in total.

### Changed
- The EXE is compressed: about 49 MB instead of 111 MB.
- Session files and logs moved to `%ProgramData%\SSDInstaller\Sessions`, a folder only Administrators and SYSTEM can write. The engine runs elevated, so other programs can no longer modify its script or requests.

## 0.1.0 — 2026-10-26

First public preview.

- Install Windows 10/11 x64 from an ISO onto a USB-connected SSD (UEFI/GPT or Legacy BIOS/MBR), with storage driver injection and WinRE.
- Safety checks: USB-only targets, system/boot/pagefile disks rejected, no preselected target, check-without-formatting plan, typed erase confirmation, identity/hash/layout re-checks before formatting.
- Fixes found while testing on Windows 11 26H2: native tool stderr no longer aborts under PowerShell 5.1; only one MSR partition; EFI/recovery drive letters are released with `mountvol`; the disabled install button looks disabled; plan text keeps its line breaks.
- Tested: Windows 11 Pro UEFI installed to a 256 GB SATA SSD over USB and booted on an all-in-one PC.

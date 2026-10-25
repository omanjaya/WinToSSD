# SSD Installer 0.2 — pratinjau

Aplikasi gratis untuk memasang Windows dari ISO ke SSD melalui adaptor USB. Setelah selesai, SSD dipasang di slot internal PC/laptop tujuan. Tidak memerlukan flashdisk installer. Aplikasi ini dibuat sendiri dan tidak berafiliasi dengan WinToHDD.

**Status: sudah diuji sekali end-to-end di Windows 11 26H2 (build 26300): Windows 11 Pro mode UEFI berhasil dipasang ke SSD SATA 256 GB melalui adaptor USB, berkas boot/WinRE terverifikasi, dan SSD berhasil boot setelah dipasang di PC AIO. Mode Legacy BIOS, Windows 10, ISO ESD, dan driver tambahan belum diuji. Gunakan SSD kosong/cadangan untuk pengujian pertama. Jangan mengandalkan versi pratinjau ini sebagai satu-satunya jalan pemulihan komputer.**

## Yang diperlukan

- Komputer pemasang dengan Windows 10/11 x64, hak Administrator, dan Windows PowerShell 5.1/komponen DISM bawaan yang berfungsi.
- Build Windows komputer pemasang harus sama atau lebih baru daripada build ISO. Contoh: host Windows 10 build 19045 tidak dapat memakai versi aplikasi ini untuk memasang ISO Windows 11 build 26100. Pembatasan ini menjaga kesesuaian alat deployment bawaan; dukungan ADK terpisah belum tersedia.
- ISO Windows 10/11 x64 resmi, berisi `sources\install.wim` atau `sources\install.esd`. Windows 7/8, Windows Server, ARM64, x86, ISO SWM terpecah, dan ISO modifikasi tidak didukung.
- SSD USB minimal 64 GiB (sebagian SSD berlabel 64 GB akan terdeteksi kurang dari 64 GiB dan ditolak), adaptor yang cocok dengan SSD SATA/NVMe, kabel stabil, dan catu daya memadai.
- ISO, aplikasi, driver, serta folder log harus berada di disk lain, bukan SSD tujuan. Folder jaringan, junction, dan symlink ditolak.
- Windows 11 tetap membutuhkan hardware yang memenuhi persyaratannya. Aplikasi tidak menghapus persyaratan CPU/TPM/Secure Boot dan tidak mengaktifkan lisensi Windows.

EXE sudah menyertakan runtime .NET sehingga pengguna tidak perlu memasang .NET SDK. File belum memiliki sertifikat penandatanganan kode; Windows dapat menampilkan penerbit tidak dikenal. Jangan mematikan antivirus. Jika diblokir, periksa sumber dan kebijakan perangkat terlebih dahulu.

## Cara menggunakan

1. Cadangkan seluruh isi SSD. Proses pemasangan menghapus **semua partisi dan data SSD yang dipilih**.
2. Simpan `SSDInstaller.exe` dan ISO di disk internal komputer pemasang. Sambungkan SSD tujuan melalui adaptor USB. Lepaskan disk USB lain yang tidak diperlukan agar lebih mudah mengenali target.
3. Jalankan `SSDInstaller.exe`, lalu setujui permintaan Administrator Windows. Bahasa tampilan (Indonesia/English) bisa diganti di pojok kanan atas.
4. Klik **Pilih ISO**, kemudian pilih edisi Windows yang sesuai dengan lisensimu. Pilihan edisi dibaca dari isi ISO.
5. Klik **Cari SSD USB**, lalu pilih disk berdasarkan model, kapasitas, dan nomor seri. Aplikasi tidak memilih target secara otomatis. Jika SSD tidak terlihat, buka tab Log proses untuk alasan penolakannya.
6. Pilih **UEFI / GPT** atau **Legacy BIOS / MBR** sesuai firmware komputer tempat SSD akan dipasang. Pilihan ini tidak dideteksi dari komputer pemasang karena komputer tujuan bisa berbeda.
7. Jika komputer tujuan memakai Intel RST/VMD/RAID atau controller yang memerlukan driver, ekstrak paket driver x64 resmi produsennya, lalu pilih folder berisi `.inf`. Installer driver `.exe` tidak digunakan langsung. Driver ditambahkan ke Windows, bukan ke image WinRE.
   - Opsional, **Akun lokal**: isi nama akun (1–20 huruf/angka, tanpa spasi) untuk membuat akun administrator **tanpa password** dan melewati halaman akun Microsoft serta Wi-Fi saat pengaturan awal Windows. Kosongkan jika akun ingin dibuat seperti biasa. Pasang password setelah masuk Windows. Opsi ini belum diuji di hardware.
8. Klik **Periksa tanpa format**. Ini membaca ISO dan SSD, serta memasang ISO sementara secara read-only; tidak memformat SSD. Penghitungan hash ISO besar bisa memerlukan beberapa menit.
9. Baca rencana pemasangan. Klik **Pasang Windows**, centang persetujuan penghapusan, lalu ketik frasa `HAPUS DISK N` yang ditampilkan. Baru setelah ini format diizinkan. Pemeriksaan lengkap dijalankan ulang sebelum format.
10. Biarkan proses berjalan hingga selesai; progres penyalinan ditampilkan dalam persen. Aplikasi menahan Windows agar tidak sleep otomatis, tetapi jangan menutup lid laptop, mencabut kabel, mengubah partisi, atau menghentikan aplikasi. Proses instalasi tidak menyediakan pembatalan setelah dimulai.
11. Setelah sukses, tutup aplikasi lalu eject SSD lewat **Safely Remove Hardware** (atau matikan komputer pemasang) sebelum mencabutnya. Pasang SSD di slot internal komputer tujuan saat komputer tujuan juga mati.
12. Sesuaikan mode firmware. Untuk UEFI pilih Windows Boot Manager bila tersedia; untuk Legacy pilih SSD. Selesaikan pengaturan awal Windows. Internet dan akun dapat diperlukan sesuai edisi/build Windows, kecuali akun lokal diisi.

## Memilih mode boot

| Pilihan | Penggunaan |
| --- | --- |
| UEFI / GPT | Windows 10 atau 11 pada komputer yang mendukung UEFI. EFI 512 MiB, MSR 16 MiB, Windows NTFS, dan recovery sekitar 3 GiB. |
| Legacy BIOS / MBR | Windows 10 pada komputer dengan boot Legacy/CSM. SSD maksimal 2 TiB dan sektor logis 512 byte. Partisi System NTFS aktif 550 MiB, Windows NTFS, dan recovery sekitar 3 GiB. |

Pilihan yang salah dapat membuat SSD tidak terbaca sebagai perangkat boot. Tidak ada mode universal yang menjamin boot di semua komputer. Pada komputer tujuan yang masih bisa menjalankan Windows, `msinfo32` menampilkan BIOS Mode instalasi yang sedang berjalan; tetap periksa pengaturan firmware komputer tersebut.

## Pemeriksaan yang dilakukan

- Hanya disk USB yang sehat, online, dan dapat ditulis yang diterima.
- Disk Windows/boot aktif, disk dengan partisi sistem aktif, dan disk pagefile ditolak.
- Identitas hardware, ukuran, nomor disk, sumber ISO, serta perubahan partisi diperiksa lagi sebelum penghapusan. Jika identitas tidak jelas atau duplikat, proses ditolak.
- SHA-256 mendeteksi perubahan ISO antara pemeriksaan dan pemasangan. **Hash ini bukan bukti ISO asli Microsoft**; gunakan ISO resmi. File ISO dikunci untuk pembacaan selama operasi.
- Arsitektur, jenis image, mode firmware, ruang disk, dan usia build host diperiksa. Bootsect dari ISO Legacy harus memiliki tanda tangan Microsoft yang valid.
- DISM memakai pemeriksaan integritas/verify; kode kegagalan alat diperiksa.
- BCDBoot diarahkan secara eksplisit ke partisi boot SSD. BCD komputer pemasang tidak menjadi target. Untuk Legacy, Bootsect juga diarahkan ke partisi SSD pilihan.
- Keberadaan berkas Windows/boot, EFI fallback untuk UEFI, keterbacaan BCD, dan entri loader diperiksa. WinRE disalin ke recovery dan didaftarkan secara offline; pengaktifannya dilakukan saat konfigurasi awal Windows.

Pemeriksaan tersebut **tidak** membuktikan kecocokan CPU, firmware, driver storage, Secure Boot, kesehatan kabel saat dipakai, atau keberhasilan boot fisik. Sejauh ini baru satu kombinasi yang diuji sampai boot: Windows 11 Pro UEFI di PC AIO.

## Jika proses gagal

- Sebelum format: baca alasan pada log dan perbaiki sumber/target. Jangan memaksa memilih disk yang ditolak.
- Setelah format dimulai: data lama tidak dipulihkan otomatis. SSD bisa berisi instalasi parsial. Simpan log, perbaiki penyebabnya, lalu periksa ulang sebelum mengulangi pemasangan.
- `No bootable device`: cocokkan mode UEFI/Legacy, urutan boot, dan pemasangan fisik SSD. Pada sebagian firmware, entri Windows Boot Manager perlu ditambahkan melalui pengaturan firmware.
- `INACCESSIBLE_BOOT_DEVICE`: periksa kebutuhan driver storage komputer tujuan, terutama RST/VMD/RAID. Jangan mengubah AHCI/RAID/VMD sembarangan jika ada instalasi Windows lain.
- Pelanggaran Secure Boot: periksa versi ISO dan pembaruan firmware/kunci Secure Boot dengan dokumentasi produsennya. Aplikasi tidak memodifikasi firmware atau menonaktifkan Secure Boot.

Klik **Buka folder log** untuk memperoleh `session.log` dan log DISM. Folder sesi berada di `%ProgramData%\SSDInstaller\Sessions`; hanya Administrator dan SYSTEM yang bisa menulis di sana, sehingga program lain tidak bisa mengubah skrip yang dijalankan aplikasi sebagai Administrator. Log berisi lokasi file dan identitas disk; periksa dulu sebelum membagikannya. Tidak ada pengiriman log atau telemetri aplikasi.

## Source dan build

Kode aplikasi berlisensi MIT. Runtime .NET yang dibundel memiliki lisensi dan pemberitahuan pihak ketiga tersendiri di paket ZIP. ISO Windows dan lisensinya tidak disertakan.

Dengan .NET 10 SDK, jalankan dari folder `source`:

```powershell
dotnet publish SSDInstaller.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish
```

Pengujian logika dengan mock (tidak mengakses disk fisik), dari PowerShell:

```powershell
.\Tests.ps1
```

Sebelum dianggap siap dipakai rutin, uji di komputer Windows dengan SSD cadangan: ISO WIM/ESD, Windows 10 Legacy/UEFI, Windows 11 UEFI, boot pertama, aktivasi WinRE, driver storage, kegagalan kabel, dan tampilan aplikasi pada beberapa skala layar.

## Referensi teknis Microsoft

- [Capture and apply Windows partitions](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/capture-and-apply-windows-system-and-recovery-partitions?view=windows-11)
- [BCDBoot dan penyiapan disk untuk komputer lain](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/bcdboot-command-line-options-techref-di?view=windows-11)
- [Partisi UEFI/GPT](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions?view=windows-11)
- [Kompatibilitas DISM](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-supported-platforms?view=windows-11)
- [Persyaratan Windows 11](https://learn.microsoft.com/en-us/windows/whats-new/windows-11-requirements)
- [REAgentC dan pengaktifan Windows Recovery](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/reagentc-command-line-options?view=windows-11)

# Track Restorer

Aplikasi Android (Flutter) untuk memperbaiki lagu lama secara offline: mengurangi desis (hiss), menormalkan loudness, dan menghapus semua metadata, lalu mengekspor WAV 16-bit / 44.1 kHz / stereo ke folder Download.

Semua proses berjalan di perangkat lewat FFmpeg. Aplikasi tidak meminta izin internet.

## Perintah FFmpeg yang dipakai

```
ffmpeg -y -i input.mp3 -map 0:a:0 -map_metadata -1 -fflags +bitexact -flags:a +bitexact \
  -af "afftdn=nr=12:nf=-30:tn=1,loudnorm=I=-14:TP=-1.0" \
  -acodec pcm_s16le -ar 44100 -ac 2 output.wav
```

`-fflags +bitexact -flags:a +bitexact` mencegah FFmpeg menulis tag "Lavf" sendiri ke WAV. `-map 0:a:0` membuang cover art.

## Build APK lewat GitHub (tanpa install Flutter)

1. Unggah semua isi folder ini ke repositori, termasuk folder `.github`.
2. Buka tab **Actions**, pilih **Build APK**, tekan **Run workflow**.
3. Setelah selesai (sekitar 5-10 menit), buka run tersebut dan unduh artifact `track-restorer-apk`.

APK rilis ditandatangani dengan kunci debug, cukup untuk dipasang sendiri. Untuk Play Store, buat keystore sendiri.

## Build lokal

```
flutter pub get
flutter run
flutter build apk --release
```

Butuh Flutter stable dan JDK 17.

## Catatan

- Paket `ffmpeg_kit_flutter` asli sudah dihentikan dan binary-nya dicabut, jadi proyek ini memakai fork `ffmpeg_kit_flutter_new`.
- `minSdk` 24 (syarat FFmpeg Kit) diatur di `android/app/build.gradle.kts`.
- Android 13+ selalu melaporkan izin storage sebagai ditolak, tetapi file baru buatan aplikasi tetap bisa ditulis ke Download. Jika Download tidak bisa ditulis (mis. Android 10), file disimpan di folder aplikasi dan UI memberi tahu lokasinya.
- Folder `android/` ditulis tangan, bukan hasil `flutter create`. Jika build Gradle gagal, jalankan `flutter create --platforms=android .` di folder proyek untuk membuat ulang scaffold, lalu pastikan `minSdk = 24` dan isi `AndroidManifest.xml` dari repo ini tetap dipakai.
- `pubspec.lock` belum ada. Setelah `flutter pub get` pertama, commit file itu agar versi paket terkunci.

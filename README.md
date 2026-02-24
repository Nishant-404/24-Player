# 🎧 24-Player

**24-Player** is a high-fidelity, ad-free music streaming and downloading application built with Flutter. Designed specifically for audiophiles and IEM enthusiasts, it prioritizes uncompressed 24-bit FLAC audio to deliver the highest possible listening experience directly to your device.

## ✨ The Vision
Most streaming apps heavily compress audio, ruining the experience for users with high-end In-Ear Monitors (IEMs). 24-Player fixes this by forcing high-resolution audio sources, paired with a custom dark-mode UI designed around the "Deep-V" aesthetic.

## 🚀 Current Features
* **High-Resolution Audio:** Prioritizes 24-bit / 44.1kHz FLAC streaming and downloads.
* **Universal Search & Playback:** Paste standard Spotify, Deezer, or Tidal links directly into the app to instantly fetch tracks.
* **Offline Library:** Download full albums directly to your local device storage with embedded high-res cover art.
* **Smart Recents:** An intelligent SQLite history database that tracks your recent playlists and albums for instantaneous playback.

## 🚧 Upcoming Roadmap (In Development)
* **Spotify-Style Sleep Timer:** Fading audio cutoff for late-night listening.
* **Swipe-to-Queue:** Intuitive gesture controls for playlist management.
* **Audiophile EQ:** 10-band graphic equalizer with custom presets tailored for specific IEM sound signatures.
* **Live Bitrate Display:** Real-time stream quality monitoring on the player screen.

## 🛠️ Built With
* [Flutter](https://flutter.dev/) - Frontend UI toolkit
* [Go (Golang)](https://go.dev/) - Embedded backend bridge for high-speed metadata scraping
* SQLite - Fast, local database for offline library management

## 🚀 Build Instructions
1. Clone the repository: `git clone https://github.com/nishant-404/24-Player.git`
2. Fetch dependencies: `flutter pub get`
3. Run the app: `flutter run`

## 📜 Acknowledgments
This project is an evolved, audiophile-focused fork of the [SpotiFLAC](https://github.com/Zarz.../SpotiFLAC) repository. 24-Player takes the powerful Go/Flutter bridge developed in the original project and diverges it to focus heavily on an IEM-first experience, a custom UI, and high-res audio prioritization.

## ⚖️ License
Distributed under the MIT License.
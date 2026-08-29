<div align="center">
  <img src="docs/app-icon.png" alt="Unibrow app icon" width="128" style="border-radius: 22%;">
  <h1>Unibrow</h1>
  <p>A native iOS SMB file browser. Browse shares on your network, view images and videos, and manage saved connections — with security considered at each layer.</p>
</div>

## Features

Unibrow connects your iPhone directly to SMB shares on your network — no cloud, no middleman.

- 🔌 Save & manage multiple SMB connections
- 🗂️ Browse folders with grid or list view
- 🖼️ Image thumbnails (JPEG, PNG, GIF, WebP)
- 🔍 Full-screen gallery with zoom & swipe
- ▶️ Built-in video playback (MP4, MOV, M4V)
- 🔐 Passwords in Keychain, encrypted thumbnail cache

### Connections

- **Save multiple SMB servers** — name, host, share, username, and password
- **Test before you save** — verify a connection works before adding it
- **Edit or delete** saved connections from the Files tab
- **Optional SMB3 encryption** per connection for encrypted traffic on the wire

### Browse files

- **Folder navigation** — drill into directories with standard back navigation
- **Grid or list view** — toggle layout from the toolbar
- **Files-style folders** — folder icons show empty/full state and item counts
- **Hide hidden files** — optional filter for dotfiles and hidden items (Settings)

### Photos & videos

- **Image thumbnails** — JPEG, PNG, GIF, and WebP, shown at their natural aspect ratio
- **Full-screen gallery** — pinch to zoom, swipe between images, swipe down to dismiss
- **Video playback** — open MP4, MOV, and M4V files in a built-in player

### Performance & storage

- **Smart thumbnails** — downsampled and cached on disk so folders load faster on repeat visits
- **Encrypted thumbnail cache** — cached previews are encrypted at rest on device
- **Clear cache** — view cache size and wipe thumbnails from Settings

### Privacy

- **Local-first** — files move only between your phone and your server
- **No analytics or third-party file relay** — the app talks only to servers you configure
- **Passwords in Keychain** — credentials are not stored in plaintext preferences

See **[Privacy & Security](docs/SECURITY.md)** for the full threat model, data handling details, and how credentials and caches are protected.

---

## Tech stack

| | |
|---|---|
| **Platform** | Native iOS (iPhone), iOS 26.5+ |
| **UI** | SwiftUI |
| **Language** | Swift 5 |
| **SMB** | [AMSMB2](https://github.com/amosavian/AMSMB2) 4.0.3 → [libsmb2](https://github.com/sahlberg/libsmb2) (dynamic framework) |
| **Media** | AVFoundation, AVKit, ImageIO |
| **Security** | Keychain Services, CryptoKit (AES-256-GCM), iOS Data Protection |
| **Storage** | UserDefaults (connection metadata), Keychain (passwords & cache key), encrypted on-disk thumbnail cache |
| **Dependencies** | Swift Package Manager — no third-party analytics or cloud SDKs |
| **Architecture** | Local-first; direct client ↔ server, no backend |

---

## Roadmap

The long-term goal: **one app for all your remote files and shells** — a unified file browser and remote terminal for your NAS, VPS, and homelab.

- [ ] **SSH terminal** — interactive shell access to remote hosts
- [ ] **Mosh** — resilient mobile shell sessions over flaky networks
- [ ] **Jellyfin** — connect to your media server, browse libraries, and stream from your collection
- [ ] **SFTP** — browse and transfer files over SSH file transfer
- [ ] **Search** — find files across connected shares and libraries
- [ ] **Favorites & recents** — quick access to folders and servers you use often

---

## License

Unibrow's own source code is licensed under the [MIT License](LICENSE).

This app uses [AMSMB2](https://github.com/amosavian/AMSMB2) (which wraps [libsmb2](https://github.com/sahlberg/libsmb2)) under the **GNU LGPL v2.1**. AMSMB2 is linked as a **dynamic framework** in the app bundle. If you distribute a build, you must comply with LGPL-2.1 for those components (including source availability for AMSMB2/libsmb2). See [LICENSE](LICENSE) for details.

## UpackX v1.2.0 — Production Release R1 (macOS Intel x86_64)

**UpackX** is a lightweight, high-performance native archive extractor built specifically for Intel Macs running macOS 14.0 Sonoma or newer.

---

### Highlights

- **Native Swift + AppKit:** Zero background daemons, minimal RAM usage (~12.5 – 27.2 MB constant RSS streaming).
- **Dual Finder Quick Actions:** Integrated directly into Finder's right-click context menu:
  - **Giải nén nhanh với UpackX:** Direct extraction in place without creating unwanted wrapper folders.
  - **Giải nén… với UpackX:** Native AppKit window to choose custom destination and conflict strategies.
- **Zero Duplicate Workflows:** Fully migrated to native Cocoa `NSServices`, resolving previous 4-menu duplication.
- **Broad Format Support:** ZIP, 7Z, RAR, TAR.GZ, BZ2, XZ, and multi-part archives (`.part1.rar`, `.7z.001`, `.z01`).
- **Safety First:** Zip-Slip path traversal defense, collision protection (Ask, Rename, Skip, Overwrite), and safe directory merging.
- **Google Drive Compatible:** Handles Google Drive for Desktop mount points, atomic rename fallbacks, and `SF_DATALESS` placeholders.
- **Minimal Icon Design:** High-resolution macOS iconset (`AppIcon.icns`) with 10 native resolutions and SVG master.

---

### Distribution Packages & Checksums

| Package | Format | Size | Description |
|---|---|---|---|
| **`UpackX-v1.2.0-macOS-Intel.dmg`** | Apple Disk Image | 2.1 MB | **Recommended.** Drag-and-drop installer into Applications. |
| **`UpackX-v1.2.0-macOS-Intel.pkg`** | Apple Installer | 1.8 MB | Guided installer package for macOS. |
| **`UpackX-v1.2.0-macOS-Intel.zip`** | Portable ZIP | 1.8 MB | Standalone `.app` bundle preserving metadata via `ditto`. |
| **`SHA256SUMS.txt`** | Text | 288 B | SHA-256 verification hashes for all distribution artifacts. |

#### SHA-256 Checksums
```text
a05dbd91f9baca41121f006577b165baa7555e277dd833f6514c5f3e307f326a  UpackX-v1.2.0-macOS-Intel.dmg
ab5e39050afafe01aa191e53b451aa02588e2c599b8c147ad0a614a0a775e872  UpackX-v1.2.0-macOS-Intel.pkg
285d6517b129f839e7a22e7c30eaf76bb57e465e7c4cfa165b689ae0600bc24a  UpackX-v1.2.0-macOS-Intel.zip
```

---

### Installation & First Launch

1. Download **`UpackX-v1.2.0-macOS-Intel.dmg`** or **`UpackX-v1.2.0-macOS-Intel.pkg`**.
2. Install UpackX into your `/Applications` directory.
3. **First Launch (Gatekeeper):**
   - Because this build is ad-hoc / developer signed without Apple Developer ID notarization, right-click on `UpackX.app` in `/Applications` and select **Open**, then click **Open** in the prompt.
4. Opening the app once activates native Finder Services in your user session.

---

### What's Next?
See [ROADMAP.md](https://github.com/VuPhm/UpackX/blob/master/ROADMAP.md) for upcoming features in Round 2, focusing on the **Native Compression Engine** (ZIP & 7Z creation, Finder quick compression, and multi-volume archive splitting).

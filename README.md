# Photo Manager (macOS)

Natív macOS alkalmazás a Sony ZV-E10 fényképezőgéppel való munkához. A követelmények a `docs/requirements.md` fájlban.

## Funkciók (MVP váz)

- USB-n csatlakoztatott kamera fotóinak böngészése (`ImageCaptureCore`)
- Fotók letöltése a Mac-re
- Fotók törlése a kameráról
- Albumok kezelése (helyi)
- "Upload batch": kijelölt fotók ideiglenes mappába gyűjtése, elnevezése, és egy gombnyomásra feltöltés Google Drive-ra
- Korábban feltöltött mappák szinkronizálása (későbbi képek hozzáadása / törlése)

## Projekt felépítése

```
PhotoManager/
├── PhotoManagerApp.swift        # @main belépési pont
├── Models/                      # Photo, Album, UploadBatch
├── Services/                    # CameraService (ImageCaptureCore), AlbumStore, DownloadService, GoogleDriveService, UploadBatchStore
├── ViewModels/                  # @Observable / ObservableObject view-modellek
└── Views/                       # SwiftUI képernyők
```

## Hogyan futtatható (Xcode projekt létrehozása)

A repo szándékosan csak a Swift forrásokat tartalmazza, nem egy `.xcodeproj`-ot, hogy ne kelljen kézzel generált project fájlt fenntartani.

1. Xcode → **File ▸ New ▸ Project… ▸ macOS ▸ App**
2. Product Name: `PhotoManager`, Interface: **SwiftUI**, Language: **Swift**
3. Mentsd ide: `photo-manager/` (ugyanebbe a könyvtárba). Az Xcode létrehoz egy `PhotoManager/` almappát — **töröld a benne generált `PhotoManagerApp.swift` és `ContentView.swift` fájlokat**, majd húzd be a meglévő `PhotoManager/` mappát (ami itt a repóban van) a projektbe ("Copy items if needed" KI, "Create groups" BE).
4. Target ▸ **Signing & Capabilities**: App Sandbox → kapcsold be
   - **USB** hozzáférést engedélyezd (App Sandbox alatt: "USB")
   - **Network** → Outgoing Connections (Client) – Google Drive API-hoz
5. `Info.plist` → add hozzá: `NSCameraUsageDescription` (ha szükséges), és az `ImageCaptureCore` frameworköt linkeld be (Build Phases ▸ Link Binary With Libraries ▸ `ImageCaptureCore.framework`).
6. Build & Run.

## Google Drive integráció

A `GoogleDriveService.swift` jelenleg **stub** (a hívások logolnak, nem küldenek hálózati kérést). Éles használathoz:

1. Hozz létre egy OAuth 2.0 Client ID-t a [Google Cloud Console](https://console.cloud.google.com/)-ban (Application type: **macOS**, Bundle ID: a tiéd).
2. Tedd a `Client ID`-t és `redirect URI`-t a `GoogleDriveService.Config`-ba.
3. Implementáld a `signIn()` és `upload(...)` metódusokat a Google Drive v3 REST API-val (`https://www.googleapis.com/upload/drive/v3/files`), resumable upload javasolt.

## Kamera-integráció megjegyzések (Sony ZV-E10)

A ZV-E10 USB-n keresztül Mac-hez PTP/MTP eszközként csatlakozik (ahogy a Fotók app is látja). A `CameraService` az `ImageCaptureCore` (`ICDeviceBrowser`, `ICCameraDevice`) API-t használja:

- `ICCameraDevice.mediaFiles` adja a képeket (`ICCameraFile`)
- `requestDownloadFile(...)` a letöltés
- `requestDeleteFiles(...)` a törlés

Ez ugyanaz az API, amit az Apple "Image Capture" alkalmazás is használ.

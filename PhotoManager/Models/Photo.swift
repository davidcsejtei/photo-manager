import Foundation

/// Egy, a kamerán levő fotó reprezentációja.
/// Az `id` stabilan azonosítja a képet szinkronizációk között (fájlnév + méret + dátum hash).
struct Photo: Identifiable, Hashable {
    let id: String
    let fileName: String
    let fileSize: Int64
    let captureDate: Date?
    let thumbnailURL: URL?       // lokális cache a thumbnailhez, ha már lehúztuk
    let isDownloaded: Bool       // le van-e mentve a Mac-re
    let localURL: URL?           // ha isDownloaded, itt van
    /// Opak referencia a `CameraService` által használt `ICCameraFile`-ra.
    /// `Any?` típussal tartjuk, hogy a modell ne függjön közvetlenül az ImageCaptureCore-tól.
    let deviceFileRef: AnyHashable?
}

extension Photo {
    static func mock(_ index: Int) -> Photo {
        Photo(
            id: "MOCK_\(index)",
            fileName: String(format: "DSC%05d.JPG", index),
            fileSize: Int64(2_500_000 + index * 1024),
            captureDate: Calendar.current.date(byAdding: .minute, value: -index, to: Date()),
            thumbnailURL: nil,
            isDownloaded: false,
            localURL: nil,
            deviceFileRef: nil
        )
    }
}

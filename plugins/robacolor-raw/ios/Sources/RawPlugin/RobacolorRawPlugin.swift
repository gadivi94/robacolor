import Foundation
import UIKit
import CoreImage
import CoreLocation
import ImageIO
import AVFoundation
import Photos
import PhotosUI
import UniformTypeIdentifiers
import Capacitor

/// Capa nativa de StealColor.
///
/// - `pick`: abre Fotos o Archivos y entrega los originales (HEIC, JPEG, RAW o vídeo) copiados a una carpeta
///   temporal, más una vista previa JPEG en Display P3 para que la web la analice y la muestre.
/// - `renderPhoto`: aplica el look (una tabla 3D que calcula la web), los efectos, el enderezado y el recorte al
///   original a resolución completa con Core Image, lo guarda en HEIC conservando sus metadatos y lo añade a Fotos.
/// - `renderVideo`: lo mismo con un vídeo, con AVFoundation (a toda velocidad, con su sonido) y lo añade a Fotos.
/// - `lastScreenshot`: la última captura de pantalla de la fototeca, para usarla como referencia.
/// - `takeShared`: la imagen que se envió a la app con «Compartir» (extensión opcional, vía App Group).
@objc(RobacolorRawPlugin)
public class RobacolorRawPlugin: CAPPlugin, CAPBridgedPlugin, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    public let identifier = "RobacolorRawPlugin"
    public let jsName = "RobacolorRaw"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "pick", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "renderPhoto", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "renderVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "lastScreenshot", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "takeShared", returnType: CAPPluginReturnPromise)
    ]

    static let appGroup = "group.cat.gadivi.robacolor"
    private static let rawExtensions: Set<String> = ["dng", "rw2", "raw", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "pef", "srw", "erf", "mrw", "3fr", "fff", "iiq", "x3f", "gpr"]
    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "3gp", "avi"]

    private var pending: CAPPluginCall?
    private let work = DispatchQueue(label: "stealcolor.native", qos: .userInitiated)
    private lazy var ciContext = CIContext(options: [CIContextOption.cacheIntermediates: false])

    // MARK: - Elegir originales

    @objc func pick(_ call: CAPPluginCall) {
        if pending != nil {
            call.reject("busy")
            return
        }
        pending = call
        let source = call.getString("source") ?? "photos"
        let kind = call.getString("kind") ?? "any"
        let multiple = call.getBool("multiple") ?? false
        DispatchQueue.main.async {
            guard let presenter = self.bridge?.viewController else {
                self.fail("No se pudo abrir el selector")
                return
            }
            if source == "files" {
                var types: [UTType] = [UTType.image, UTType.rawImage]
                if kind != "image" {
                    types.append(UTType.movie)
                }
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
                picker.delegate = self
                picker.allowsMultipleSelection = multiple
                presenter.present(picker, animated: true, completion: nil)
            } else {
                var config = PHPickerConfiguration()
                config.filter = kind == "image" ? PHPickerFilter.images : PHPickerFilter.any(of: [PHPickerFilter.images, PHPickerFilter.videos])
                config.selectionLimit = multiple ? 0 : 1
                // «current» entrega el archivo tal cual (HEIC, RAW, vídeo HEVC) en lugar de convertirlo
                config.preferredAssetRepresentationMode = .current
                let picker = PHPickerViewController(configuration: config)
                picker.delegate = self
                presenter.present(picker, animated: true, completion: nil)
            }
        }
    }

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        if results.isEmpty {
            fail("cancelled")
            return
        }
        let group = DispatchGroup()
        var copies = [URL?](repeating: nil, count: results.count)
        var names = [String](repeating: "foto", count: results.count)
        let lock = NSLock()
        for (index, result) in results.enumerated() {
            let provider = result.itemProvider
            let ids = provider.registeredTypeIdentifiers
            func firstConforming(_ type: UTType) -> String? {
                return ids.first { id in
                    if let t = UTType(id) { return t.conforms(to: type) }
                    return false
                }
            }
            let typeId = firstConforming(UTType.movie) ?? firstConforming(UTType.rawImage) ?? firstConforming(UTType.image) ?? UTType.image.identifier
            let suggested = provider.suggestedName
            group.enter()
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
                defer { group.leave() }
                guard let url = url else { return }
                // El archivo que entrega iOS se borra al salir de este bloque: se copia antes
                let copy = self.folder().appendingPathComponent(self.stamp() + "-" + String(index) + "." + url.pathExtension.lowercased())
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    lock.lock()
                    copies[index] = copy
                    names[index] = suggested ?? url.deletingPathExtension().lastPathComponent
                    lock.unlock()
                } catch {
                    return
                }
            }
        }
        group.notify(queue: work) {
            var pairs: [(URL, String)] = []
            for i in 0..<copies.count {
                if let c = copies[i] { pairs.append((c, names[i])) }
            }
            self.finishPick(pairs)
        }
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if urls.isEmpty {
            fail("cancelled")
            return
        }
        work.async {
            var pairs: [(URL, String)] = []
            for (index, url) in urls.enumerated() {
                let copy = self.folder().appendingPathComponent(self.stamp() + "-" + String(index) + "." + url.pathExtension.lowercased())
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil {
                    pairs.append((copy, url.deletingPathExtension().lastPathComponent))
                }
            }
            self.finishPick(pairs)
        }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        fail("cancelled")
    }

    private func finishPick(_ pairs: [(URL, String)]) {
        guard let call = pending else { return }
        let side = CGFloat(call.getInt("preview") ?? 2048)
        var items: [[String: Any]] = []
        for (url, name) in pairs {
            let ext = url.pathExtension.lowercased()
            let isVideo = RobacolorRawPlugin.videoExtensions.contains(ext) || (UTType(filenameExtension: ext)?.conforms(to: UTType.movie) ?? false)
            if isVideo {
                let asset = AVURLAsset(url: url)
                var size = CGSize.zero
                if let track = asset.tracks(withMediaType: AVMediaType.video).first {
                    let s = track.naturalSize.applying(track.preferredTransform)
                    size = CGSize(width: abs(s.width), height: abs(s.height))
                }
                items.append(["kind": "video", "path": url.absoluteString, "name": name, "width": Int(size.width), "height": Int(size.height), "type": ext])
                continue
            }
            guard let loaded = loadImage(url) else { continue }
            let preview = folder().appendingPathComponent("vista-" + stamp() + "-" + String(items.count) + ".jpg")
            do {
                try writePreview(loaded.image, maxSide: side, to: preview)
            } catch {
                continue
            }
            items.append([
                "kind": "image",
                "path": url.absoluteString,
                "preview": preview.absoluteString,
                "name": name,
                "width": Int(loaded.image.extent.width),
                "height": Int(loaded.image.extent.height),
                "raw": loaded.raw,
                "type": ext
            ])
        }
        pending = nil
        if items.isEmpty {
            call.reject("No se pudo abrir ningún archivo")
        } else {
            call.resolve(["items": items])
        }
    }

    // MARK: - Cargar y escribir imágenes

    private struct Loaded {
        let image: CIImage
        let raw: Bool
    }

    private func loadImage(_ url: URL) -> Loaded? {
        let ext = url.pathExtension.lowercased()
        var looksRaw = RobacolorRawPlugin.rawExtensions.contains(ext)
        if let type = UTType(filenameExtension: ext), type.conforms(to: UTType.rawImage) {
            looksRaw = true
        }
        if looksRaw, let filter = CIRAWFilter(imageURL: url), let output = filter.outputImage {
            return Loaded(image: originAtZero(output), raw: true)
        }
        if let image = CIImage(contentsOf: url, options: [CIImageOption.applyOrientationProperty: true]) {
            if image.extent.isInfinite || image.extent.width < 2 || image.extent.height < 2 { return nil }
            return Loaded(image: originAtZero(image), raw: false)
        }
        return nil
    }

    private func originAtZero(_ image: CIImage) -> CIImage {
        let o = image.extent.origin
        return image.transformed(by: CGAffineTransform(translationX: -o.x, y: -o.y))
    }

    private func scaled(_ image: CIImage, maxSide: CGFloat) -> CIImage {
        let longSide = max(image.extent.width, image.extent.height)
        let scale = min(CGFloat(1), maxSide / longSide)
        if scale >= 1 { return image }
        let out = image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: NSNumber(value: Double(scale)),
            kCIInputAspectRatioKey: NSNumber(value: 1.0)
        ])
        return originAtZero(out)
    }

    private func writePreview(_ image: CIImage, maxSide: CGFloat, to url: URL) throws {
        let small = scaled(image, maxSide: maxSide)
        guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { throw NativeError.failed("color") }
        try ciContext.writeJPEGRepresentation(of: small, to: url, colorSpace: space, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.9])
    }

    // MARK: - El look: tabla 3D y efectos

    private enum NativeError: Error {
        case failed(String)
    }

    private func cube(_ call: CAPPluginCall, space: CGColorSpace) throws -> CIFilter {
        guard let b64 = call.getString("lut"), let data = Data(base64Encoded: b64) else { throw NativeError.failed("Falta la tabla del look") }
        let n = call.getInt("n") ?? 64
        if data.count != n * n * n * 16 { throw NativeError.failed("La tabla del look no tiene el tamaño esperado") }
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { throw NativeError.failed("Core Image sin tablas 3D") }
        filter.setValue(NSNumber(value: n), forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        filter.setValue(space, forKey: "inputColorSpace")
        return filter
    }

    /// Claridad (contraste local), viñeteado y grano: aproximan los de la web con filtros de Core Image
    private func effects(_ input: CIImage, extent: CGRect, clarity: Double, vignette: Double, grain: Double, seed: Double) -> CIImage {
        var img = input
        let longSide = Double(max(extent.width, extent.height))
        if abs(clarity) > 0.001 {
            img = img.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: NSNumber(value: longSide * 0.02),
                kCIInputIntensityKey: NSNumber(value: clarity * 0.9)
            ])
        }
        if abs(vignette) > 0.001 {
            img = img.applyingFilter("CIVignetteEffect", parameters: [
                kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                kCIInputRadiusKey: NSNumber(value: Double(hypot(extent.width, extent.height)) * 0.5),
                kCIInputIntensityKey: NSNumber(value: -vignette * 0.9),
                "inputFalloff": NSNumber(value: 0.6)
            ])
        }
        if grain > 0.001, let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let amp = CGFloat(grain * 0.08)
            let shift = CGAffineTransform(translationX: CGFloat(seed.truncatingRemainder(dividingBy: 997.0)) * 13, y: CGFloat(seed.truncatingRemainder(dividingBy: 389.0)) * 7)
            let noise = random.transformed(by: shift).applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 2 * amp, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 2 * amp, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 2 * amp, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.5 - amp, y: 0.5 - amp, z: 0.5 - amp, w: 1)
            ]).cropped(to: extent)
            img = noise.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: img])
        }
        return img.cropped(to: extent)
    }

    // MARK: - Foto

    @objc func renderPhoto(_ call: CAPPluginCall) {
        work.async {
            do {
                let result = try self.developPhoto(call)
                call.resolve(result)
            } catch NativeError.failed(let message) {
                call.reject(message)
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    private func developPhoto(_ call: CAPPluginCall) throws -> [String: Any] {
        guard let path = call.getString("path"), let url = URL(string: path), let loaded = loadImage(url) else { throw NativeError.failed("No se pudo abrir el original") }
        let wantP3 = (call.getString("space") ?? "p3") == "p3"
        guard let lutSpace = CGColorSpace(name: wantP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB),
              let outSpace = CGColorSpace(name: CGColorSpace.displayP3) else { throw NativeError.failed("color") }
        var img = loaded.image
        let W = img.extent.width, H = img.extent.height

        // Enderezar: girar sobre el centro y ampliar lo justo para no dejar esquinas vacías (como en la web)
        let angle = call.getDouble("angle") ?? 0
        if abs(angle) > 0.001 {
            let t = abs(angle) * Double.pi / 180
            let c = CGFloat(cos(t)), s = CGFloat(sin(t))
            let cover = max((W * c + H * s) / W, (W * s + H * c) / H)
            var tr = CGAffineTransform(translationX: W / 2, y: H / 2)
            tr = tr.scaledBy(x: cover, y: cover)
            tr = tr.rotated(by: CGFloat(-angle * Double.pi / 180)) // en Core Image el eje y sube: el giro va al revés que en el lienzo
            tr = tr.translatedBy(x: -W / 2, y: -H / 2)
            img = img.clampedToExtent().transformed(by: tr).cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
        }
        // Recortar (x, y, w, h de 0 a 1 medidos desde arriba a la izquierda)
        if let crop = call.getObject("crop") {
            let x = CGFloat((crop["x"] as? NSNumber)?.doubleValue ?? 0), y = CGFloat((crop["y"] as? NSNumber)?.doubleValue ?? 0)
            let w = CGFloat((crop["w"] as? NSNumber)?.doubleValue ?? 1), h = CGFloat((crop["h"] as? NSNumber)?.doubleValue ?? 1)
            if x > 0.0001 || y > 0.0001 || w < 0.9999 || h < 0.9999 {
                let rect = CGRect(x: (x * W).rounded(), y: ((1 - y - h) * H).rounded(), width: max(2, (w * W).rounded()), height: max(2, (h * H).rounded()))
                img = originAtZero(img.cropped(to: rect))
            }
        }
        let extent = img.extent
        let filter = try cube(call, space: lutSpace)
        filter.setValue(img, forKey: kCIInputImageKey)
        guard var out = filter.outputImage else { throw NativeError.failed("No se pudo aplicar el look") }
        out = effects(out, extent: extent, clarity: call.getDouble("clarity") ?? 0, vignette: call.getDouble("vignette") ?? 0, grain: call.getDouble("grain") ?? 0, seed: 1)

        guard let cg = ciContext.createCGImage(out, from: extent, format: CIFormat.RGBA8, colorSpace: outSpace) else { throw NativeError.failed("No se pudo revelar la foto") }

        // Metadatos del original (fecha, ubicación, cámara) con la orientación ya aplicada y las medidas nuevas
        var props: [String: Any] = [:]
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            props = p
        }
        props[kCGImagePropertyOrientation as String] = 1
        props[kCGImagePropertyPixelWidth as String] = cg.width
        props[kCGImagePropertyPixelHeight as String] = cg.height
        if var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            props[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if var exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = cg.width
            exif[kCGImagePropertyExifPixelYDimension as String] = cg.height
            props[kCGImagePropertyExifDictionary as String] = exif
        }
        props.removeValue(forKey: kCGImagePropertyDNGDictionary as String)
        props[kCGImageDestinationLossyCompressionQuality as String] = call.getDouble("quality") ?? 0.92

        let heic = (call.getString("format") ?? "heic") == "heic"
        let name = (call.getString("name") ?? "stealcolor") + (heic ? ".heic" : ".jpg")
        let outURL = folder().appendingPathComponent(stamp() + "-" + name)
        let type = (heic ? UTType.heic : UTType.jpeg).identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, type, 1, nil) else { throw NativeError.failed("No se pudo crear el archivo") }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        if !CGImageDestinationFinalize(dest) { throw NativeError.failed("No se pudo escribir la foto") }

        var saved = false
        if call.getBool("save") ?? true {
            try addToPhotos(outURL, video: false, props: props, name: name)
            saved = true
        }
        return ["saved": saved, "path": outURL.absoluteString, "width": cg.width, "height": cg.height]
    }

    // MARK: - Vídeo

    @objc func renderVideo(_ call: CAPPluginCall) {
        work.async {
            do {
                try self.developVideo(call)
            } catch NativeError.failed(let message) {
                call.reject(message)
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    private func developVideo(_ call: CAPPluginCall) throws {
        guard let path = call.getString("path"), let url = URL(string: path) else { throw NativeError.failed("No se pudo abrir el vídeo") }
        guard let lutSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw NativeError.failed("color") }
        let asset = AVURLAsset(url: url)
        let filter = try cube(call, space: lutSpace)
        let clarity = call.getDouble("clarity") ?? 0, vignette = call.getDouble("vignette") ?? 0, grain = call.getDouble("grain") ?? 0
        let lock = NSLock()
        let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { (request: AVAsynchronousCIImageFilteringRequest) in
            let source = request.sourceImage
            lock.lock()
            filter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
            let graded = filter.outputImage
            lock.unlock()
            guard let looked = graded else {
                request.finish(with: source, context: nil)
                return
            }
            let out = self.effects(looked, extent: source.extent, clarity: clarity * 0.5, vignette: vignette, grain: grain, seed: request.compositionTime.seconds * 30)
            request.finish(with: out, context: nil)
        })
        // Salida en SDR (Rec. 709): el look está pensado para imagen estándar
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let maxSide = call.getInt("maxSide") ?? 3840
        let preset = maxSide >= 3840 ? AVAssetExportPreset3840x2160 : maxSide >= 1920 ? AVAssetExportPreset1920x1080 : maxSide >= 1280 ? AVAssetExportPreset1280x720 : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw NativeError.failed("Este vídeo no se puede exportar") }
        let name = (call.getString("name") ?? "stealcolor") + ".mov"
        let outURL = folder().appendingPathComponent(stamp() + "-" + name)
        session.outputURL = outURL
        session.outputFileType = AVFileType.mov
        session.videoComposition = composition
        let start = call.getDouble("start") ?? 0
        let duration = CMTimeGetSeconds(asset.duration)
        let end = min(call.getDouble("end") ?? duration, duration)
        if end > start {
            session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        }

        // Progreso para la web cada cuarto de segundo
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: 0.25)
        timer.setEventHandler { [weak self] in
            self?.notifyListeners("progress", data: ["value": session.progress])
        }
        timer.resume()

        session.exportAsynchronously {
            timer.cancel()
            if session.status == .completed {
                do {
                    try self.addToPhotos(outURL, video: true, props: [:], name: name)
                    var size = CGSize.zero
                    if let track = AVURLAsset(url: outURL).tracks(withMediaType: AVMediaType.video).first {
                        let s = track.naturalSize.applying(track.preferredTransform)
                        size = CGSize(width: abs(s.width), height: abs(s.height))
                    }
                    call.resolve(["saved": true, "path": outURL.absoluteString, "width": Int(size.width), "height": Int(size.height)])
                } catch NativeError.failed(let message) {
                    call.reject(message)
                } catch {
                    call.reject(error.localizedDescription)
                }
            } else {
                call.reject(session.error?.localizedDescription ?? "No se pudo exportar el vídeo")
            }
        }
    }

    // MARK: - Fotos

    private func addToPhotos(_ url: URL, video: Bool, props: [String: Any], name: String) throws {
        let sem = DispatchSemaphore(value: 0)
        var status = PHAuthorizationStatus.notDetermined
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
            status = s
            sem.signal()
        }
        sem.wait()
        if status != .authorized && status != .limited {
            throw NativeError.failed("Permite a StealColor añadir a Fotos en Ajustes")
        }
        var date: Date?
        var location: CLLocation?
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any], let text = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = f.date(from: text)
        }
        if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let lat = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
           let lon = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String ?? "E"
            location = CLLocation(latitude: latRef == "S" ? -lat : lat, longitude: lonRef == "W" ? -lon : lon)
        }
        var failure: Error?
        let done = DispatchSemaphore(value: 0)
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = name
            request.addResource(with: video ? .video : .photo, fileURL: url, options: options)
            if let d = date { request.creationDate = d }
            if let l = location { request.location = l }
        }, completionHandler: { ok, error in
            if !ok { failure = error ?? NativeError.failed("Fotos no aceptó el archivo") }
            done.signal()
        })
        done.wait()
        if let e = failure { throw e }
    }

    // MARK: - Última captura de pantalla

    @objc func lastScreenshot(_ call: CAPPluginCall) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            if status != .authorized && status != .limited {
                call.reject("denied")
                return
            }
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 1
            let assets: PHFetchResult<PHAsset>
            if let album = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil).firstObject {
                assets = PHAsset.fetchAssets(in: album, options: options)
            } else {
                options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", Int32(PHAssetMediaSubtype.photoScreenshot.rawValue))
                assets = PHAsset.fetchAssets(with: .image, options: options)
            }
            guard let asset = assets.firstObject else {
                call.reject("none")
                return
            }
            let request = PHImageRequestOptions()
            request.isNetworkAccessAllowed = true
            request.deliveryMode = .highQualityFormat
            request.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: request) { data, uti, _, _ in
                guard let data = data else {
                    call.reject("none")
                    return
                }
                var ext = "png"
                if let uti = uti, let type = UTType(uti), let e = type.preferredFilenameExtension { ext = e }
                let url = self.folder().appendingPathComponent("captura-" + self.stamp() + "." + ext)
                do {
                    try data.write(to: url, options: .atomic)
                    call.resolve(["path": url.absoluteString])
                } catch {
                    call.reject("none")
                }
            }
        }
    }

    // MARK: - Imagen compartida desde otra app (extensión «Compartir»)

    @objc func takeShared(_ call: CAPPluginCall) {
        guard let box = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RobacolorRawPlugin.appGroup) else {
            call.resolve([:])
            return
        }
        let inbox = box.appendingPathComponent("compartida", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [URLResourceKey.contentModificationDateKey], options: []), !files.isEmpty else {
            call.resolve([:])
            return
        }
        let newest = files.max { a, b in
            let da = (try? a.resourceValues(forKeys: [URLResourceKey.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let db = (try? b.resourceValues(forKeys: [URLResourceKey.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return da < db
        }
        guard let file = newest else {
            call.resolve([:])
            return
        }
        let copy = folder().appendingPathComponent("compartida-" + stamp() + "." + file.pathExtension.lowercased())
        do {
            try FileManager.default.copyItem(at: file, to: copy)
        } catch {
            call.resolve([:])
            return
        }
        for f in files { try? FileManager.default.removeItem(at: f) }
        call.resolve(["path": copy.absoluteString])
    }

    // MARK: - Utilidades

    private func folder() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stealcolor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    private func stamp() -> String {
        return String(Int(Date().timeIntervalSince1970 * 1000))
    }

    private func fail(_ message: String) {
        let call = pending
        pending = nil
        call?.reject(message)
    }
}

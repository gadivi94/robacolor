import Foundation
import UIKit
import CoreImage
import PhotosUI
import UniformTypeIdentifiers
import Capacitor

/// Abre una foto con el selector nativo y la entrega revelada a la web en 16 bits lineales.
///
/// - Los RAW (RW2, DNG, ProRAW, CR3, NEF, ARW…) se revelan con el motor RAW de Apple (`CIRAWFilter`).
/// - Cualquier otra imagen se abre tal cual, también a 16 bits, para que el resto del flujo sea el mismo.
///
/// Se escriben dos archivos temporales en crudo (RGBA, 16 bits por canal, sin cabecera): una vista
/// previa pequeña y la imagen a tamaño de exportación. La web los lee con `fetch`.
@objc(RobacolorRawPlugin)
public class RobacolorRawPlugin: CAPPlugin, CAPBridgedPlugin, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    public let identifier = "RobacolorRawPlugin"
    public let jsName = "RobacolorRaw"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "pick", returnType: CAPPluginReturnPromise)
    ]

    private static let rawExtensions: Set<String> = ["dng", "rw2", "raw", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "pef", "srw", "erf", "mrw", "3fr", "fff", "iiq", "x3f", "gpr"]
    private var pending: CAPPluginCall?
    private let work = DispatchQueue(label: "robacolor.raw", qos: .userInitiated)
    private lazy var ciContext = CIContext(options: [CIContextOption.cacheIntermediates: false])

    // MARK: - Llamada desde la web

    @objc func pick(_ call: CAPPluginCall) {
        if pending != nil {
            call.reject("busy")
            return
        }
        pending = call
        let source = call.getString("source") ?? "photos"
        DispatchQueue.main.async {
            guard let presenter = self.bridge?.viewController else {
                self.fail("No se pudo abrir el selector")
                return
            }
            if source == "files" {
                let types: [UTType] = [UTType.rawImage, UTType.image]
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
                picker.delegate = self
                picker.allowsMultipleSelection = false
                presenter.present(picker, animated: true, completion: nil)
            } else {
                var config = PHPickerConfiguration()
                config.filter = PHPickerFilter.images
                config.selectionLimit = 1
                // «current» evita que iOS convierta el RAW a JPEG antes de dárnoslo
                config.preferredAssetRepresentationMode = .current
                let picker = PHPickerViewController(configuration: config)
                picker.delegate = self
                presenter.present(picker, animated: true, completion: nil)
            }
        }
    }

    // MARK: - Selector de Fotos

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        guard let provider = results.first?.itemProvider else {
            fail("cancelled")
            return
        }
        let ids = provider.registeredTypeIdentifiers
        let rawId = ids.first { id in
            if let type = UTType(id) { return type.conforms(to: UTType.rawImage) }
            return false
        }
        let imageId = ids.first { id in
            if let type = UTType(id) { return type.conforms(to: UTType.image) }
            return false
        }
        let typeId = rawId ?? imageId ?? UTType.image.identifier
        let suggested = provider.suggestedName
        _ = provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, error in
            guard let url = url else {
                self.fail(error?.localizedDescription ?? "No se pudo leer la foto")
                return
            }
            // El archivo que entrega iOS se borra al salir de este bloque: hay que copiarlo antes
            let copy = self.folder().appendingPathComponent("origen." + url.pathExtension)
            do {
                try? FileManager.default.removeItem(at: copy)
                try FileManager.default.copyItem(at: url, to: copy)
            } catch {
                self.fail("No se pudo copiar la foto")
                return
            }
            let name = suggested ?? url.deletingPathExtension().lastPathComponent
            self.work.async { self.develop(copy, name: name) }
        }
    }

    // MARK: - Selector de Archivos

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            fail("cancelled")
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        work.async { self.develop(url, name: name) }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        fail("cancelled")
    }

    // MARK: - Revelado

    private func folder() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("robacolor-raw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    private func develop(_ url: URL, name: String) {
        guard let call = pending else { return }
        let wantP3 = (call.getString("space") ?? "srgb") == "p3"
        let previewSide = CGFloat(call.getInt("preview") ?? 1280)
        let fullSide = CGFloat(call.getInt("full") ?? 4096)

        var image: CIImage?
        var isRaw = false
        let ext = url.pathExtension.lowercased()
        var looksRaw = RobacolorRawPlugin.rawExtensions.contains(ext)
        if let type = UTType(filenameExtension: ext), type.conforms(to: UTType.rawImage) {
            looksRaw = true
        }
        if looksRaw {
            let filter: CIRAWFilter? = CIRAWFilter(imageURL: url)
            if let filter = filter, let output = filter.outputImage {
                image = output
                isRaw = true
            }
        }
        if image == nil {
            image = CIImage(contentsOf: url, options: [CIImageOption.applyOrientationProperty: true])
        }
        guard let source = image, !source.extent.isInfinite, source.extent.width >= 2, source.extent.height >= 2 else {
            fail("Este archivo no se puede abrir como foto")
            return
        }

        let colorSpaceName = wantP3 ? CGColorSpace.linearDisplayP3 : CGColorSpace.linearSRGB
        guard let colorSpace = CGColorSpace(name: colorSpaceName) else {
            fail("Espacio de color no disponible")
            return
        }

        let dir = folder()
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
        // Se borran los revelados anteriores (cada uno ocupa decenas de MB)
        if let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) {
            for item in old where item.pathExtension == "rgba16" {
                try? FileManager.default.removeItem(at: item)
            }
        }

        do {
            let preview = try render(source, maxSide: previewSide, colorSpace: colorSpace, to: dir.appendingPathComponent("vista-" + stamp + ".rgba16"))
            let full = try render(source, maxSide: fullSide, colorSpace: colorSpace, to: dir.appendingPathComponent("completa-" + stamp + ".rgba16"))
            let result: [String: Any] = [
                "preview": preview.url.absoluteString,
                "pw": preview.width,
                "ph": preview.height,
                "full": full.url.absoluteString,
                "fw": full.width,
                "fh": full.height,
                "width": Int(source.extent.width),
                "height": Int(source.extent.height),
                "name": name,
                "raw": isRaw,
                "space": wantP3 ? "p3" : "srgb"
            ]
            pending = nil
            call.resolve(result)
        } catch {
            fail("No se pudo revelar la foto")
        }
    }

    private struct Rendered {
        let url: URL
        let width: Int
        let height: Int
    }

    private enum RenderError: Error {
        case empty
    }

    /// Reduce la imagen para que su lado largo no pase de `maxSide` y la escribe como RGBA de 16 bits lineal.
    private func render(_ image: CIImage, maxSide: CGFloat, colorSpace: CGColorSpace, to url: URL) throws -> Rendered {
        let longSide = max(image.extent.width, image.extent.height)
        let scale = min(CGFloat(1), maxSide / longSide)
        var output = image
        if scale < 1 {
            output = image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: NSNumber(value: Double(scale)),
                kCIInputAspectRatioKey: NSNumber(value: 1.0)
            ])
        }
        let origin = output.extent.origin
        output = output.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        let width = Int(output.extent.width.rounded(.down))
        let height = Int(output.extent.height.rounded(.down))
        if width < 1 || height < 1 {
            throw RenderError.empty
        }
        let rowBytes = width * 8
        var data = Data(count: rowBytes * height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            if let base = buffer.baseAddress {
                self.ciContext.render(output, toBitmap: base, rowBytes: rowBytes, bounds: bounds, format: CIFormat.RGBA16, colorSpace: colorSpace)
            }
        }
        try data.write(to: url, options: Data.WritingOptions.atomic)
        return Rendered(url: url, width: width, height: height)
    }

    private func fail(_ message: String) {
        let call = pending
        pending = nil
        call?.reject(message)
    }
}

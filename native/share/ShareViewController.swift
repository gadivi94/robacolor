import UIKit
import UniformTypeIdentifiers

/// Extensión «Compartir → StealColor»: deja la imagen en la carpeta compartida (App Group) y avisa.
/// Al abrir StealColor, la app la recoge y la usa como referencia.
class ShareViewController: UIViewController {
    private let appGroup = "group.cat.gadivi.robacolor"
    private var started = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if started { return }
        started = true
        receive()
    }

    private func receive() {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            finish(false)
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            var ok = false
            if let url = url { ok = self.store(url) }
            if ok {
                DispatchQueue.main.async { self.finish(true) }
                return
            }
            // Algunas apps solo entregan los datos de la imagen
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                var saved = false
                if let data = data, let dir = self.inbox() {
                    let dest = dir.appendingPathComponent("ref-" + String(Int(Date().timeIntervalSince1970)) + ".jpg")
                    saved = (try? data.write(to: dest, options: .atomic)) != nil
                }
                DispatchQueue.main.async { self.finish(saved) }
            }
        }
    }

    private func inbox() -> URL? {
        guard let box = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let dir = box.appendingPathComponent("compartida", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    private func store(_ url: URL) -> Bool {
        guard let dir = inbox() else { return false }
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
        let dest = dir.appendingPathComponent("ref-" + String(Int(Date().timeIntervalSince1970)) + "." + ext)
        return (try? FileManager.default.copyItem(at: url, to: dest)) != nil
    }

    private func finish(_ ok: Bool) {
        let alert = UIAlertController(
            title: ok ? "Lista en StealColor" : "No se pudo compartir",
            message: ok ? "Abre StealColor: la imagen aparecerá como referencia." : "Prueba a compartir una foto.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        present(alert, animated: true, completion: nil)
    }
}

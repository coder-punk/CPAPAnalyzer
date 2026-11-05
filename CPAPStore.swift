import Foundation
import UniformTypeIdentifiers

@MainActor final class CPAPStore: ObservableObject {
    @Published var recordings: [EDFRecording] = []
    @Published var status = "Importeer EDF-bestanden vanaf je SD-kaart."
    @Published var selected: UUID?
    var active: EDFRecording? { recordings.first(where: { $0.id == selected }) ?? recordings.first }

    func importFiles(_ urls: [URL]) {
        var imported = 0
        var failures: [String] = []
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                failures.append("\(url.lastPathComponent): geen bestandstoegang")
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                guard url.pathExtension.lowercased() == "edf" else { failures.append("\(url.lastPathComponent): geen EDF"); continue }
                let data = try Data(contentsOf: url)
                let recording = try EDFReader.parse(data, filename: url.lastPathComponent)
                recordings.append(recording)
                imported += 1
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        recordings.sort { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
        if selected == nil { selected = recordings.first?.id }
        status = "\(imported) bestand(en) geïmporteerd." + (failures.isEmpty ? "" : " Problemen: " + failures.prefix(3).joined(separator: "; "))
    }
}

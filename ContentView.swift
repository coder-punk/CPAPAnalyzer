import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: CPAPStore
    @StateObject private var bluetooth = BluetoothManager()
    @State private var importer = false
    @State private var signalIndex = 0
    private let navy = Color(red: 0.05, green: 0.09, blue: 0.16)
    var body: some View {
        TabView {
            NavigationStack { dashboard }.tabItem { Label("Analyse", systemImage: "waveform.path.ecg") }
            NavigationStack { importPage }.tabItem { Label("Import", systemImage: "sdcard") }
            NavigationStack { bluetoothPage }.tabItem { Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationStack { helpPage }.tabItem { Label("Info", systemImage: "info.circle") }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
    }
    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let recording = store.active {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(recording.filename).font(.headline)
                            Text(recording.start?.formatted(date: .abbreviated, time: .shortened) ?? "Datum onbekend").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f uur", recording.duration / 3600)).font(.title3.bold())
                    }.padding().background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                    if !recording.signals.isEmpty {
                        let idx = min(signalIndex, recording.signals.count - 1)
                        let signal = recording.signals[idx]
                        Text("Signalen").font(.title2.bold())
                        Picker("Signaal", selection: $signalIndex) {
                            ForEach(recording.signals.indices, id: \.self) { i in Text(recording.signals[i].label.isEmpty ? "Signaal \(i+1)" : recording.signals[i].label).tag(i) }
                        }.pickerStyle(.menu)
                        signalChart(signal, duration: recording.duration)
                        HStack {
                            metric("Minimum", signal.samples.min().map { String(format: "%.2f", $0) } ?? "-")
                            metric("Gemiddeld", signal.samples.isEmpty ? "-" : String(format: "%.2f", signal.samples.reduce(0,+) / Double(signal.samples.count)))
                            metric("Maximum", signal.samples.max().map { String(format: "%.2f", $0) } ?? "-")
                        }
                        Text("Eenheid: \(signal.unit.isEmpty ? "onbekend" : signal.unit). Waarden uit het EDF-signaal, niet automatisch een klinische score.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if store.recordings.count > 1 {
                        Text("Opnames").font(.headline)
                        ForEach(store.recordings) { item in
                            Button { store.selected = item.id; signalIndex = 0 } label: {
                                HStack { Text(item.filename).lineLimit(1); Spacer(); if store.active?.id == item.id { Image(systemName: "checkmark.circle.fill") } }
                            }.padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                } else {
                    ContentUnavailableView("Nog geen slaapgegevens", systemImage: "moon.zzz", description: Text("Importeer EDF-bestanden uit de DATALOG-map van je ResMed SD-kaart."))
                    Button("Importeer bestanden") { importer = true }.buttonStyle(.borderedProminent)
                }
            }.padding()
        }.background(navy).navigationTitle("CPAPAnalyzer")
        .fileImporter(isPresented: $importer, allowedContentTypes: [.data, .item], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): store.importFiles(urls); case .failure(let error): store.status = error.localizedDescription }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SLAAPANALYSE").font(.caption.bold()).tracking(2).foregroundStyle(.cyan)
            Text("Jouw therapie, in detail.").font(.title2.bold())
            Text("Lokale analyse, zonder account of cloud.").font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline.monospacedDigit()) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private func signalChart(_ signal: EDFSignal, duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(signal.label).font(.headline)
            Chart {
                ForEach(signal.samples.indices, id: \.self) { index in
                    LineMark(x: .value("Tijd (min)", Double(index) / Double(max(1, signal.samples.count - 1)) * duration / 60), y: .value(signal.unit, signal.samples[index]))
                        .foregroundStyle(.cyan).lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXAxisLabel("Minuten vanaf begin")
            .frame(height: 260)
            Text("Tot 30.000 meetpunten per signaal. Weergave kan details missen bij hoge frequenties.").font(.caption).foregroundStyle(.secondary)
        }.padding().background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
    private var importPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("SD-kaart importeren", systemImage: "sdcard.fill").font(.title2.bold())
                Text("Kopieer de SD-kaart via een iPhone-compatibele kaartlezer naar de Bestanden-app, open de DATALOG-map en selecteer de .edf-bestanden. Je kunt meerdere bestanden tegelijk kiezen.")
                Button { importer = true } label: { Label("Selecteer EDF-bestanden", systemImage: "folder") }.buttonStyle(.borderedProminent)
                Text(store.status).font(.subheadline).foregroundStyle(.secondary)
                Text("Ondersteund: standaard EDF (16-bit) met numerieke signalen. Niet ondersteund in deze eerste versie: EDF+ annotaties, ResMed-specifieke eventdecodering, automatische AHI-berekening, STR.edf samenvattingsvelden en ZIP-import.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding()
        }.background(navy).navigationTitle("Import")
        .fileImporter(isPresented: $importer, allowedContentTypes: [.data, .item], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): store.importFiles(urls); case .failure(let error): store.status = error.localizedDescription }
        }
    }
    private var bluetoothPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Bluetooth ontdekken", systemImage: "antenna.radiowaves.left.and.right").font(.title2.bold())
                Text(bluetooth.stateText).foregroundStyle(.secondary)
                HStack {
                    Button("Zoeken") { bluetooth.scan() }.buttonStyle(.borderedProminent)
                    Button("Stop") { bluetooth.stop() }.buttonStyle(.bordered)
                }
                ForEach(bluetooth.devices, id: \.self) { name in Text(name).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)) }
                Text("Let op: dit is uitsluitend een BLE-apparatenscanner. ResMed publiceert geen algemene, gedocumenteerde Bluetooth-interface voor gedetailleerde AirSense 11-therapiegegevens. Een gevonden apparaat betekent niet dat de app therapiedata kan lezen.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding()
        }.background(navy).navigationTitle("Bluetooth")
    }
    private var helpPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("CPAPAnalyzer").font(.largeTitle.bold())
                Text("Versie 0.1 • Lokale EDF-viewer")
                Text("Dit is een eerste werkende basis voor een OSCAR-achtige app, geen volledige OSCAR-kloon. De app bewaart de geïmporteerde metingen alleen in het geheugen zolang hij open is. Gebruik originele SD-bestanden als back-up.")
                Text("De grafieken zijn informatief en geen vervanging voor medische beoordeling. Wijzig je therapie-instellingen niet op basis van deze app zonder overleg met je behandelaar.")
                Text("Voor volgende versies: ResMed STR.edf-samenvattingen, sessiecombinatie, flow-zoom, eventmarkeringen, AHI, lekkages en duurzame opslag.")
            }.padding()
        }.background(navy).navigationTitle("Info")
    }
}

import SwiftUI

@main
struct CPAPAnalyzerApp: App {
    @StateObject private var store = CPAPStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store) }
    }
}

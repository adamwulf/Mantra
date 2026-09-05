import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(iOS)
        SettingsView()
        #else
        TabView {
            NavigationStack {
                PhraseListView()
            }
            .tabItem {
                Label("Phrases", systemImage: "quote.bubble")
            }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        #endif
    }
}

#Preview {
    ContentView()
}

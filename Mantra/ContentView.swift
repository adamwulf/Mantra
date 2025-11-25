import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            PhraseListView()
                .tabItem {
                    Label("Phrases", systemImage: "quote.bubble")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    ContentView()
}

import SwiftUI

struct ContentView: View {
    var body: some View {
        SettingsView()
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 500)
        #endif
    }
}

#Preview {
    ContentView()
}

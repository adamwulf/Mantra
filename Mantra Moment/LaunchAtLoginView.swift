#if os(macOS)
import SwiftUI
import ServiceManagement

struct LaunchAtLoginView: View {
    @State private var launchAtLogin: Bool = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onAppear {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
            .onChange(of: launchAtLogin) { _, newValue in
                if newValue {
                    do {
                        try SMAppService.mainApp.register()
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        errorMessage = "Could not enable launch at login: \(error.localizedDescription)"
                        showError = true
                    }
                } else {
                    SMAppService.mainApp.unregister { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                                errorMessage = "Could not disable launch at login: \(error.localizedDescription)"
                                showError = true
                            }
                        }
                    }
                }
            }
            .alert("Login Item Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }

        Button("Open Login Items Settings") {
            SMAppService.openSystemSettingsLoginItems()
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundColor(.accentColor)
    }
}

#Preview {
    Form {
        LaunchAtLoginView()
    }
    .padding()
}
#endif

import SwiftUI
import SwiftData
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var ftpSettings: [FTPSettings]
    
    @State private var settings: FTPSettings = FTPSettings()
    @State private var showPassword: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("SFTP Server Configuration") {
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledContent("SFTP Server URL") {
                            TextField("", text: $settings.ftpServerURL)
                                .textContentType(.URL)
                        }
                        
                        LabeledContent("Port") {
                            TextField("", value: $settings.ftpPort, format: .number)
                                .frame(width: 60)
                        }
                        
                        LabeledContent("Username") {
                            TextField("", text: $settings.ftpUsername)
                                .textContentType(.username)
                        }
                        
                        LabeledContent("Password") {
                            HStack(spacing: 5) {
                                if showPassword {
                                    TextField("", text: $settings.ftpPassword)
                                        .textContentType(.password)
                                } else {
                                    SecureField("", text: $settings.ftpPassword)
                                        .textContentType(.password)
                                }
                                
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        LabeledContent("Upload Path") {
                            TextField("", text: $settings.ftpPath)
                                .help("Directory on the server where files will be uploaded (e.g., /public_html/uploads)")
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Web Server Configuration") {
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledContent("Web Server URL") {
                            TextField("", text: $settings.webServerURL)
                                .textContentType(.URL)
                                .help("The base URL where uploaded files will be accessible")
                                .frame(minWidth: 250)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("System Configuration") {
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledContent("Curl Path") {
                            HStack {
                                TextField("", text: $settings.curlPath)
                                    .help("Path to the curl executable (e.g., /usr/bin/curl)")
                                
                                Button {
                                    browseCurlPath()
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            
            // Save button outside of the Form
            HStack {
                Spacer()
                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 550, height: 550) // Height reduced as we don't need the extra space for the warning
        .fixedSize()
        .onAppear {
            if let existingSettings = ftpSettings.first {
                settings = existingSettings
            } else {
                let newSettings = FTPSettings()
                modelContext.insert(newSettings)
                settings = newSettings
            }
        }
    }
    
    private func browseCurlPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select the curl executable"
        panel.prompt = "Select"
        
        // Set initial directory based on common curl locations
        if FileManager.default.fileExists(atPath: "/usr/bin/curl") {
            panel.directoryURL = URL(fileURLWithPath: "/usr/bin")
        } else if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/curl") {
            panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        }
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    self.settings.curlPath = url.path
                }
            }
        }
    }
    
    private func saveSettings() {
        // Settings are already bound to the model object,
        // but we'll update the database explicitly
        try? modelContext.save()
    }
} 
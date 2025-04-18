import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var ftpSettings: [FTPSettings]
    
    @State private var settings: FTPSettings = FTPSettings()
    @State private var showPassword: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("FTP Server Configuration") {
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledContent("FTP Server URL") {
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
                        
                        LabeledContent("Use SFTP") {
                            Toggle("", isOn: $settings.useSFTP)
                                .labelsHidden()
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
        .frame(width: 550, height: 450)
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
    
    private func saveSettings() {
        // Settings are already bound to the model object,
        // but we'll update the database explicitly
        try? modelContext.save()
    }
} 
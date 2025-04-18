import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var recentUploads: [UploadedFile]
    @Query private var ftpSettings: [FTPSettings]
    
    // Function to open settings provided by the app
    var openSettings: () -> Void
    
    private var ftpService: FTPService {
        FTPService(settings: ftpSettings.first ?? FTPSettings())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and buttons
            HStack {
                Text("FFTPU")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.2))
            
            // Recent uploads list
            if recentUploads.isEmpty {
                Text("No recent uploads")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                List {
                    ForEach(recentUploads.sorted(by: { $0.uploadDate > $1.uploadDate }).prefix(5)) { upload in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(upload.filename)
                                    .lineLimit(1)
                                Text(upload.uploadDate, format: .dateTime)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if upload.isUploading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.7)
                            } else if upload.errorMessage != nil {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                            } else {
                                Button {
                                    copyURLToClipboard(url: upload.remoteURL)
                                } label: {
                                    Image(systemName: "doc.on.clipboard")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !upload.isUploading && upload.errorMessage == nil {
                                copyURLToClipboard(url: upload.remoteURL)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 300)
        .onAppear {
            // Create default settings if none exist
            if ftpSettings.isEmpty {
                let defaultSettings = FTPSettings()
                modelContext.insert(defaultSettings)
            }
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                uploadFile(url: url)
            }
        }
    }
    
    private func uploadFile(url: URL) {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        
        let uploadedFile = UploadedFile(
            filename: url.lastPathComponent,
            originalPath: url.path,
            uploadSize: fileSize
        )
        
        modelContext.insert(uploadedFile)
        appState.currentUpload = uploadedFile
        
        // Start upload process using MainActor since FTPService is a MainActor class
        Task { @MainActor in
            do {
                let remoteURL = try await ftpService.uploadFile(localURL: url, uploadedFile: uploadedFile)
                
                uploadedFile.remoteURL = remoteURL
                uploadedFile.isUploading = false
                uploadedFile.uploadProgress = 1.0
                appState.currentUpload = nil
                
                // Copy URL to clipboard automatically
                copyURLToClipboard(url: remoteURL)
            } catch {
                uploadedFile.isUploading = false
                uploadedFile.errorMessage = error.localizedDescription
                appState.currentUpload = nil
            }
        }
    }
    
    private func copyURLToClipboard(url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
} 
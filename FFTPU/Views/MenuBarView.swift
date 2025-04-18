import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.FFTPU", category: "MenuBarView")

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
                    .padding(.bottom, 8)
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
                                    .help(upload.errorMessage ?? "Unknown error")
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
                            } else if let errorMessage = upload.errorMessage {
                                logger.error("Failed upload: \(upload.filename) with error: \(errorMessage)")
                                
                                // Show the error message in a dialog
                                let alert = NSAlert()
                                alert.messageText = "Upload Error"
                                alert.informativeText = errorMessage
                                alert.alertStyle = .warning
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
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
                logger.debug("No FTP settings found, creating default")
                let defaultSettings = FTPSettings()
                modelContext.insert(defaultSettings)
            } else {
                logger.debug("Found existing FTP settings")
            }
        }
    }
    
    private func openFilePicker() {
        logger.debug("Opening file picker")
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                logger.debug("File selected: \(url.path)")
                uploadFile(url: url)
            } else {
                logger.debug("File selection cancelled")
            }
        }
    }
    
    private func uploadFile(url: URL) {
        logger.info("Starting upload process for file: \(url.lastPathComponent)")

        // Check if settings exist and are valid
        if ftpSettings.isEmpty {
            logger.error("No FTP settings available")
            let alert = NSAlert()
            alert.messageText = "No SFTP Settings"
            alert.informativeText = "Please configure your SFTP settings before uploading a file."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            openSettings()
            return
        }
        
        let settings = ftpSettings.first!
        // Basic settings validation
        if settings.ftpServerURL.isEmpty || settings.ftpUsername.isEmpty || settings.ftpPassword.isEmpty {
            logger.error("Incomplete SFTP settings: server=\(settings.ftpServerURL.isEmpty ? "missing" : "set"), username=\(settings.ftpUsername.isEmpty ? "missing" : "set"), password=\(settings.ftpPassword.isEmpty ? "missing" : "set")")
            let alert = NSAlert()
            alert.messageText = "Incomplete SFTP Settings"
            alert.informativeText = "Please complete your SFTP settings configuration before uploading."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            openSettings()
            return
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        logger.debug("File size: \(fileSize) bytes")
        
        let uploadedFile = UploadedFile(
            filename: url.lastPathComponent,
            originalPath: url.path,
            uploadSize: fileSize
        )
        
        logger.debug("Created UploadedFile record, inserting into model context")
        modelContext.insert(uploadedFile)
        appState.setCurrentUpload(uploadedFile)
        
        // Start upload process using MainActor since FTPService is a MainActor class
        Task { @MainActor in
            do {
                logger.debug("Starting FTP upload task")
                let remoteURL = try await ftpService.uploadFile(localURL: url, uploadedFile: uploadedFile)
                
                logger.info("Upload completed successfully, remote URL: \(remoteURL)")
                uploadedFile.remoteURL = remoteURL
                uploadedFile.isUploading = false
                uploadedFile.uploadProgress = 1.0
                appState.setCurrentUpload(nil)
                
                // Copy URL to clipboard automatically
                copyURLToClipboard(url: remoteURL)
                
                // Save model context
                try? modelContext.save()
            } catch let error as FTPError {
                logger.error("Upload failed with FTP error: \(error)")
                uploadedFile.isUploading = false
                
                // Customize error message based on error type
                switch error {
                case .uploadFailed(let message):
                    uploadedFile.errorMessage = "Upload failed: \(message)"
                case .fileNotFound:
                    uploadedFile.errorMessage = "File not found"
                case .missingSettings:
                    uploadedFile.errorMessage = "Incomplete SFTP settings"
                case .invalidCurlPath:
                    uploadedFile.errorMessage = "Invalid curl path"
                case .invalidConfiguration:
                    uploadedFile.errorMessage = "Invalid configuration"
                }
                
                appState.logUploadError(uploadedFile, error: error)
                appState.setCurrentUpload(nil)
                
                // Save model context with error state
                try? modelContext.save()
            } catch {
                logger.error("Upload failed with error: \(error.localizedDescription)")
                uploadedFile.isUploading = false
                uploadedFile.errorMessage = error.localizedDescription
                appState.logUploadError(uploadedFile, error: error)
                appState.setCurrentUpload(nil)
                
                // Save model context with error state
                try? modelContext.save()
            }
        }
    }
    
    private func copyURLToClipboard(url: String) {
        logger.debug("Copying URL to clipboard: \(url)")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
} 

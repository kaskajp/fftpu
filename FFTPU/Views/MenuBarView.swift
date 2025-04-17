import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var recentUploads: [UploadedFile]
    @Query private var ftpSettings: [FTPSettings]
    
    @State private var dragOver = false
    
    // Function to open settings provided by the app
    var openSettings: () -> Void
    
    private var ftpService: FTPService {
        FTPService(settings: ftpSettings.first ?? FTPSettings())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title
            HStack {
                Text("FFTPU")
                    .font(.headline)
                
                Spacer()
                
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
            
            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(dragOver ? .accentColor : .gray)
                    .background(dragOver ? Color.accentColor.opacity(0.1) : Color.clear)
                    .frame(height: 100)
                    .padding()
                
                VStack {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 24))
                    Text("Drop files here")
                        .font(.subheadline)
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $dragOver) { providers, _ in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, error in
                        guard let url = url, error == nil else { return }
                        DispatchQueue.main.async {
                            uploadFile(url: url)
                        }
                    }
                }
                return true
            }
            
            Divider()
            
            // Recent uploads list
            if recentUploads.isEmpty {
                Text("No recent uploads")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(recentUploads.sorted(by: { $0.uploadDate > $1.uploadDate }).prefix(5)) { upload in
                        HStack {
                            VStack(alignment: .leading) {
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
                .frame(maxHeight: 300)
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
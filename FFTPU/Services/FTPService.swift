import Foundation

enum FTPError: Error {
    case invalidConfiguration
    case uploadFailed(String)
    case fileNotFound
    case missingSettings
}

@MainActor
class FTPService {
    private let settings: FTPSettings
    
    init(settings: FTPSettings) {
        self.settings = settings
    }
    
    func uploadFile(localURL: URL, uploadedFile: UploadedFile) async throws -> String {
        // Validate settings
        guard !settings.ftpServerURL.isEmpty,
              !settings.ftpUsername.isEmpty,
              !settings.ftpPassword.isEmpty,
              !settings.webServerURL.isEmpty else {
            throw FTPError.missingSettings
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw FTPError.fileNotFound
        }
        
        // Create a temporary file for stderr output
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        
        // Build the curl command
        let protocolType = settings.useSFTP ? "sftp" : "ftp"
        let curlURL = "\(protocolType)://\(settings.ftpServerURL):\(settings.ftpPort)/\(localURL.lastPathComponent)"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        
        // Basic curl arguments for upload
        var arguments = [
            "--upload-file", localURL.path,
            "--user", "\(settings.ftpUsername):\(settings.ftpPassword)",
            "--stderr", stderrURL.path,
            "-#", // Show progress
            curlURL
        ]
        
        // Add SFTP specific options if needed
        if settings.useSFTP {
            arguments.append(contentsOf: [
                "--insecure", // Skip SSL verification
            ])
        }
        
        process.arguments = arguments
        
        // Set up a pipe for reading progress from stderr
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        // Create task that can capture the uploadedFile since we're in a @MainActor class now
        return try await Task {
            // Create a background task to update progress while upload is happening
            let progressTask = Task.detached { [uploadedFile] in
                var progressText = ""
                let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                    guard let stderrData = try? Data(contentsOf: stderrURL),
                          let output = String(data: stderrData, encoding: .utf8) else { return }
                    
                    if output != progressText {
                        progressText = output
                        // Parse progress from curl output (e.g. "##  1.2%")
                        if let percentString = output.components(separatedBy: "%").first?.components(separatedBy: "##").last,
                           let percent = Double(percentString.trimmingCharacters(in: .whitespaces)) {
                            Task { @MainActor in
                                uploadedFile.uploadProgress = percent / 100.0
                            }
                        }
                    }
                }
                
                // Keep the timer running until the process completes
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                        if !process.isRunning {
                            timer.invalidate()
                            continuation.resume()
                        }
                    }
                }
                
                timer.invalidate()
            }
            
            // Start the process
            do {
                try process.run()
                process.waitUntilExit()
                _ = await progressTask.value // Wait for the progress task to complete
                
                // Check if the process exited with an error
                if process.terminationStatus != 0 {
                    let stderrData = try Data(contentsOf: stderrURL)
                    let errorOutput = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                    throw FTPError.uploadFailed(errorOutput)
                }
                
                // Clean up
                try? FileManager.default.removeItem(at: stderrURL)
                
                // Create and return the web URL
                var webServerURL = settings.webServerURL
                if !webServerURL.hasSuffix("/") {
                    webServerURL += "/"
                }
                return webServerURL + localURL.lastPathComponent
            } catch {
                // Clean up
                try? FileManager.default.removeItem(at: stderrURL)
                throw error
            }
        }.value
    }
} 
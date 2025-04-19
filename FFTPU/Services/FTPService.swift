import Foundation
import OSLog

private let logger = Logger(subsystem: "com.FFTPU", category: "FTPService")

enum FTPError: Error {
    case invalidConfiguration
    case uploadFailed(String)
    case fileNotFound
    case missingSettings
    case invalidCurlPath
}

@MainActor
class FTPService {
    private let settings: FTPSettings
    
    init(settings: FTPSettings) {
        self.settings = settings
        logger.debug("FTPService initialized with settings: server=\(settings.ftpServerURL), port=\(settings.ftpPort), username=\(settings.ftpUsername.isEmpty ? "empty" : "set"), path=\(settings.ftpPath)")
    }
    
    func uploadFile(
        localURL: URL, 
        uploadedFile: UploadedFile,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        logger.info("Starting upload for file: \(localURL.lastPathComponent)")
        
        // Create a copy of settings to use in background tasks
        let settingsCopy = SettingsCopy(
            ftpServerURL: settings.ftpServerURL,
            ftpPort: settings.ftpPort,
            ftpUsername: settings.ftpUsername,
            ftpPassword: settings.ftpPassword,
            ftpPath: settings.ftpPath,
            webServerURL: settings.webServerURL,
            curlPath: settings.curlPath
        )
        
        // Move all heavy I/O operations to a background Task context
        return try await Task.detached {
            // Validate settings
            guard !settingsCopy.ftpServerURL.isEmpty,
                  !settingsCopy.ftpUsername.isEmpty,
                  !settingsCopy.ftpPassword.isEmpty,
                  !settingsCopy.webServerURL.isEmpty,
                  !settingsCopy.curlPath.isEmpty else {
                logger.error("Missing FTP settings: server=\(settingsCopy.ftpServerURL.isEmpty ? "empty" : "set"), username=\(settingsCopy.ftpUsername.isEmpty ? "empty" : "set"), password=\(settingsCopy.ftpPassword.isEmpty ? "empty" : "set"), webServerURL=\(settingsCopy.webServerURL.isEmpty ? "empty" : "set"), curlPath=\(settingsCopy.curlPath.isEmpty ? "empty" : "set")")
                throw FTPError.missingSettings
            }
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                logger.error("File not found at path: \(localURL.path)")
                throw FTPError.fileNotFound
            }
            
            // Verify curl path exists and is executable
            let curlPath = settingsCopy.curlPath
            logger.debug("Using curl path: \(curlPath)")
            
            // Check if the curl executable exists
            guard FileManager.default.fileExists(atPath: curlPath) else {
                logger.error("Curl executable not found at path: \(curlPath)")
                throw FTPError.invalidCurlPath
            }
            
            // Create a temporary file for stderr output
            let stderrURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("log")
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            logger.debug("Created temporary log file at: \(stderrURL.path)")
            
            // Build the curl command with the specified path
            let protocolType = "sftp"
            
            // Normalize path to ensure it starts with / and doesn't end with /
            var normalizedPath = settingsCopy.ftpPath
            if !normalizedPath.hasPrefix("/") {
                normalizedPath = "/" + normalizedPath
            }
            if normalizedPath.hasSuffix("/") {
                normalizedPath.removeLast()
            }
            // Handle root directory specially
            if normalizedPath == "" {
                normalizedPath = "/"
            }
            
            let curlURL = "\(protocolType)://\(settingsCopy.ftpServerURL):\(settingsCopy.ftpPort)\(normalizedPath)/\(localURL.lastPathComponent)"
            logger.debug("SFTP URL: \(curlURL)")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: curlPath)
            logger.debug("Using curl executable at: \(curlPath)")
            
            // Basic curl arguments for upload
            let arguments = [
                "--upload-file", localURL.path,
                "--user", "\(settingsCopy.ftpUsername):\(settingsCopy.ftpPassword)",
                "--stderr", stderrURL.path,
                "-#", // Show progress
                "--insecure", // Skip SSL verification
                curlURL
            ]
            
            process.arguments = arguments
            logger.debug("Curl command: \(curlPath) \(arguments.joined(separator: " ").replacingOccurrences(of: settingsCopy.ftpPassword, with: "****"))")
            
            // Set up a pipe for reading progress from stderr
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            // Start the process on background thread to prevent blocking
            logger.debug("Starting curl process")
            do {
                try process.run()
                logger.debug("Curl process started successfully")
            } catch {
                logger.error("Failed to start curl process: \(error.localizedDescription)")
                throw error
            }
            
            // Create task to monitor progress
            let progressMonitor = Task.detached {
                logger.debug("Progress monitoring task started")
                var progressText = ""
                
                // Use a separate thread for file I/O operations
                let fileMonitorQueue = DispatchQueue(label: "com.FFTPU.fileMonitor", qos: .utility)
                
                while !Task.isCancelled && process.isRunning {
                    // Read file in background
                    let output = await withCheckedContinuation { continuation in
                        fileMonitorQueue.async {
                            guard let stderrData = try? Data(contentsOf: stderrURL),
                                  let output = String(data: stderrData, encoding: .utf8) else {
                                continuation.resume(returning: "")
                                return
                            }
                            continuation.resume(returning: output)
                        }
                    }
                    
                    if !output.isEmpty, output != progressText {
                        progressText = output
                        // Parse progress from curl output (e.g. "##  1.2%")
                        if let percentString = output.components(separatedBy: "%").first?.components(separatedBy: "##").last,
                           let percent = Double(percentString.trimmingCharacters(in: .whitespaces)) {
                            let progress = percent / 100.0
                            
                            // Update on main thread
                            Task { @MainActor in
                                uploadedFile.uploadProgress = progress
                                progressHandler?(progress)
                                
                                if percent > 0 && Int(percent) % 10 == 0 {
                                    logger.debug("Upload progress: \(Int(percent))%")
                                }
                            }
                        }
                    }
                    
                    // Sleep to prevent CPU overuse
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
                
                logger.debug("Progress monitoring completed")
            }
            
            // Wait for the process to complete
            process.waitUntilExit()
            logger.debug("Curl process exited with status: \(process.terminationStatus)")
            
            // Cancel progress monitor
            progressMonitor.cancel()
            
            do {
                // Check if the process exited with an error
                if process.terminationStatus != 0 {
                    let stderrData = try Data(contentsOf: stderrURL)
                    let errorOutput = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                    logger.error("Upload failed with curl error: \(errorOutput)")
                    throw FTPError.uploadFailed(errorOutput)
                }
                
                // Clean up
                try? FileManager.default.removeItem(at: stderrURL)
                logger.debug("Temporary log file removed")
                
                // Create and return the web URL
                var webServerURL = settingsCopy.webServerURL
                if !webServerURL.hasSuffix("/") {
                    webServerURL += "/"
                }
                let resultURL = webServerURL + localURL.lastPathComponent
                logger.info("Upload successful. Web URL: \(resultURL)")
                return resultURL
            } catch {
                // Clean up
                try? FileManager.default.removeItem(at: stderrURL)
                logger.error("Error during upload process: \(error.localizedDescription)")
                throw error
            }
        }.value
    }
}

// Structure to copy settings for use in background tasks
private struct SettingsCopy {
    let ftpServerURL: String
    let ftpPort: Int
    let ftpUsername: String
    let ftpPassword: String
    let ftpPath: String
    let webServerURL: String
    let curlPath: String
} 
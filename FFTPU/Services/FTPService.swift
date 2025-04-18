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
    
    func uploadFile(localURL: URL, uploadedFile: UploadedFile) async throws -> String {
        logger.info("Starting upload for file: \(localURL.lastPathComponent)")
        
        // Validate settings
        guard !settings.ftpServerURL.isEmpty,
              !settings.ftpUsername.isEmpty,
              !settings.ftpPassword.isEmpty,
              !settings.webServerURL.isEmpty,
              !settings.curlPath.isEmpty else {
            logger.error("Missing FTP settings: server=\(self.settings.ftpServerURL.isEmpty ? "empty" : "set"), username=\(self.settings.ftpUsername.isEmpty ? "empty" : "set"), password=\(self.settings.ftpPassword.isEmpty ? "empty" : "set"), webServerURL=\(self.settings.webServerURL.isEmpty ? "empty" : "set"), curlPath=\(self.settings.curlPath.isEmpty ? "empty" : "set")")
            throw FTPError.missingSettings
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            logger.error("File not found at path: \(localURL.path)")
            throw FTPError.fileNotFound
        }
        
        // Verify curl path exists and is executable
        let curlPath = settings.curlPath
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
        var normalizedPath = settings.ftpPath
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
        
        let curlURL = "\(protocolType)://\(settings.ftpServerURL):\(settings.ftpPort)\(normalizedPath)/\(localURL.lastPathComponent)"
        logger.debug("SFTP URL: \(curlURL)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: curlPath)
        logger.debug("Using curl executable at: \(curlPath)")
        
        // Basic curl arguments for upload
        let arguments = [
            "--upload-file", localURL.path,
            "--user", "\(settings.ftpUsername):\(settings.ftpPassword)",
            "--stderr", stderrURL.path,
            "-#", // Show progress
            "--insecure", // Skip SSL verification
            curlURL
        ]
        
        process.arguments = arguments
        logger.debug("Curl command: \(curlPath) \(arguments.joined(separator: " ").replacingOccurrences(of: self.settings.ftpPassword, with: "****"))")
        
        // Set up a pipe for reading progress from stderr
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        // Create task that can capture the uploadedFile since we're in a @MainActor class now
        return try await Task {
            logger.debug("Starting curl process")
            // Start the process
            do {
                try process.run()
                logger.debug("Curl process started successfully")
            } catch {
                logger.error("Failed to start curl process: \(error.localizedDescription)")
                throw error
            }
            
            // Create a background task to update progress while upload is happening
            let progressTask = Task.detached { [uploadedFile] in
                logger.debug("Progress monitoring task started")
                var progressText = ""
                let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                    guard let stderrData = try? Data(contentsOf: stderrURL),
                          let output = String(data: stderrData, encoding: .utf8) else { return }
                    
                    if output != progressText {
                        progressText = output
                        // Parse progress from curl output (e.g. "##  1.2%")
                        if let percentString = output.components(separatedBy: "%").first?.components(separatedBy: "##").last,
                           let percent = Double(percentString.trimmingCharacters(in: .whitespaces)) {
                            Task { @MainActor in
                                uploadedFile.uploadProgress = percent / 100.0
                                if percent > 0 && Int(percent) % 10 == 0 {
                                    logger.debug("Upload progress: \(Int(percent))%")
                                }
                            }
                        }
                    }
                }
                
                defer {
                    progressTimer.invalidate()
                    logger.debug("Progress timer invalidated")
                }
                
                // Create a task-local RunLoop to process the timer events
                let runLoop = RunLoop.current
                
                // Wait for process completion
                while process.isRunning {
                    // Run the loop for a short time and then check again
                    runLoop.run(until: Date(timeIntervalSinceNow: 0.5))
                }
                logger.debug("Process completed, ending progress monitoring")
            }
            
            // Wait for the process to complete
            process.waitUntilExit()
            logger.debug("Curl process exited with status: \(process.terminationStatus)")
            
            // Wait for the progress task to complete (or cancel it if needed)
            if !progressTask.isCancelled {
                progressTask.cancel()
                logger.debug("Progress task cancelled")
            }
            
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
                var webServerURL = settings.webServerURL
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
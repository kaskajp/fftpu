import Foundation
import Combine
import OSLog
import SwiftUI

class AppState: ObservableObject {
    @Published var isShowingDropZone = false
    @Published var isShowingSettings = false
    @Published var currentUpload: UploadedFile?
    @Published var recentUploads: [UploadedFile] = []
    @Published var uploadProgress: Double = 0
    @Published var uploadStatus: String = ""
    
    private let logger = Logger(subsystem: "com.FFTPU", category: "AppState")
    
    init() {
        logger.debug("AppState initialized")
    }
    
    func setCurrentUpload(_ upload: UploadedFile?) {
        if let upload = upload {
            logger.debug("Starting upload: \(upload.filename)")
            self.currentUpload = upload
            self.uploadProgress = 0
            self.uploadStatus = "Starting upload: \(upload.filename)"
        } else {
            if let previous = currentUpload {
                logger.debug("Upload completed or failed: \(previous.filename)")
                self.uploadStatus = "Upload completed"
            }
            self.currentUpload = nil
            self.uploadProgress = 0
        }
    }
    
    func updateUploadProgress(_ progress: Double, filename: String) {
        self.uploadProgress = progress
        
        // Display progress as percentage
        let percentage = Int(progress * 100)
        self.uploadStatus = "Uploading \(filename): \(percentage)%"
        
        logger.debug("Upload progress update: \(percentage)%")
    }
    
    func logUploadError(_ upload: UploadedFile, error: Error) {
        logger.error("Upload failed for \(upload.filename): \(error.localizedDescription)")
        self.uploadStatus = "Upload failed: \(error.localizedDescription)"
    }
} 
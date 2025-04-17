import Foundation
import SwiftData

@Model
final class UploadedFile {
    var filename: String
    var originalPath: String
    var remoteURL: String
    var uploadDate: Date
    var uploadSize: Int64
    var isUploading: Bool
    var uploadProgress: Double
    var errorMessage: String?
    
    init(
        filename: String,
        originalPath: String,
        remoteURL: String = "",
        uploadDate: Date = Date(),
        uploadSize: Int64 = 0,
        isUploading: Bool = true,
        uploadProgress: Double = 0.0,
        errorMessage: String? = nil
    ) {
        self.filename = filename
        self.originalPath = originalPath
        self.remoteURL = remoteURL
        self.uploadDate = uploadDate
        self.uploadSize = uploadSize
        self.isUploading = isUploading
        self.uploadProgress = uploadProgress
        self.errorMessage = errorMessage
    }
} 
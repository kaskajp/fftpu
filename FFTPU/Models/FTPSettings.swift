import Foundation
import SwiftData

@Model
final class FTPSettings {
    var ftpServerURL: String
    var ftpUsername: String
    var ftpPassword: String
    var ftpPort: Int
    var useSFTP: Bool
    var webServerURL: String
    var ftpPath: String
    
    init(
        ftpServerURL: String = "",
        ftpUsername: String = "",
        ftpPassword: String = "",
        ftpPort: Int = 22,
        useSFTP: Bool = true,
        webServerURL: String = "",
        ftpPath: String = "/"
    ) {
        self.ftpServerURL = ftpServerURL
        self.ftpUsername = ftpUsername
        self.ftpPassword = ftpPassword
        self.ftpPort = ftpPort
        self.useSFTP = useSFTP
        self.webServerURL = webServerURL
        self.ftpPath = ftpPath
    }
} 
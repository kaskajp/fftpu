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
    
    init(
        ftpServerURL: String = "",
        ftpUsername: String = "",
        ftpPassword: String = "",
        ftpPort: Int = 21,
        useSFTP: Bool = false,
        webServerURL: String = ""
    ) {
        self.ftpServerURL = ftpServerURL
        self.ftpUsername = ftpUsername
        self.ftpPassword = ftpPassword
        self.ftpPort = ftpPort
        self.useSFTP = useSFTP
        self.webServerURL = webServerURL
    }
} 
import Foundation
import SwiftData

@Model
final class OTPRecord {
    var id: UUID
    var sender: String
    var otp: String
    var timestamp: Date

    init(sender: String, otp: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.sender = sender
        self.otp = otp
        self.timestamp = timestamp
    }
}

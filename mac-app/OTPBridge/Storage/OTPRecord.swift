import Foundation
import SwiftData

@Model
final class OTPRecord {
    var id: UUID
    var sender: String
    var otp: String
    var company: String?
    var timestamp: Date

    init(sender: String, otp: String, company: String? = nil, timestamp: Date = Date()) {
        self.id = UUID()
        self.sender = sender
        self.otp = otp
        self.company = company
        self.timestamp = timestamp
    }
}

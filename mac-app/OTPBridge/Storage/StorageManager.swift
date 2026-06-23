import Foundation
import SwiftData

@MainActor
class StorageManager {

    static let shared = StorageManager()

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    private init() {
        setupContainer()
    }

    private func setupContainer() {
        do {
            let schema = Schema([OTPRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = modelContainer?.mainContext
        } catch {
            print("Failed to setup SwiftData: \(error)")
        }
    }

    func saveOTP(sender: String, otp: String, company: String? = nil) {
        guard let context = modelContext else { return }
        let record = OTPRecord(sender: sender, otp: otp, company: company)
        context.insert(record)
        try? context.save()
    }

    func getRecentOTPs(limit: Int = 50) -> [OTPRecord] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<OTPRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func clearOldOTPs(olderThan interval: TimeInterval = 86400) {
        guard let context = modelContext else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let descriptor = FetchDescriptor<OTPRecord>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        if let records = try? context.fetch(descriptor) {
            for record in records {
                context.delete(record)
            }
            try? context.save()
        }
    }
}

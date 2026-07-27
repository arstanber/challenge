import Foundation
import Observation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "RoutineService")

@MainActor
@Observable
final class RoutineService {
    static let shared = RoutineService()

    private(set) var routines: [Routine] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private init() {}

    private struct SaveParams: Encodable {
        let routineId: UUID
        let name: String
        let icon: String
        let period: RoutinePeriod
        let activityIds: [UUID]

        enum CodingKeys: String, CodingKey {
            case routineId = "p_routine_id"
            case name = "p_name"
            case icon = "p_icon"
            case period = "p_period"
            case activityIds = "p_activity_ids"
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            routines = try await supabase
                .rpc("get_my_routines")
                .execute()
                .value
        } catch {
            logger.error("load failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func save(
        id: UUID,
        name: String,
        icon: String,
        period: RoutinePeriod,
        activityIds: [UUID]
    ) async -> Bool {
        errorMessage = nil
        do {
            let params = SaveParams(
                routineId: id,
                name: name,
                icon: icon,
                period: period,
                activityIds: activityIds
            )
            try await supabase
                .rpc("save_my_routine", params: params)
                .execute()
            await load()
            return true
        } catch {
            logger.error("save failed: \(error)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ routine: Routine) async {
        errorMessage = nil
        do {
            try await supabase
                .from("routines")
                .delete()
                .eq("id", value: routine.id.uuidString)
                .execute()
            routines.removeAll { $0.id == routine.id }
        } catch {
            logger.error("delete failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}

import Foundation
import Supabase

struct LearningGuide: Decodable {
    let title: String
    let overview: String
    let steps: [LearningGuideStep]
    let safetyNotes: [String]
    let resources: [LearningGuideResource]
    let generatedAt: String?
    let cached: Bool
}

struct LearningGuideStep: Decodable, Identifiable {
    let title: String
    let details: String

    var id: String { title + details }
}

struct LearningGuideResource: Decodable, Identifiable {
    let title: String
    let url: String
    let description: String

    var id: String { url }
    var destination: URL? { URL(string: url) }
}

final class LearningGuideService {
    static let shared = LearningGuideService()
    private init() {}

    private struct Request: Encodable {
        let activityId: UUID
        let language: String
        let forceRefresh: Bool
    }

    func guide(for activity: Activity, forceRefresh: Bool = false) async throws -> LearningGuide {
        try await supabase.functions.invoke(
            "generate-learning-guide",
            options: FunctionInvokeOptions(
                body: Request(
                    activityId: activity.id,
                    language: AppLanguage.current,
                    forceRefresh: forceRefresh
                )
            ),
            decode: { data, response in
                try JSONDecoder().decode(LearningGuide.self, from: data)
            }
        )
    }
}

import SwiftUI

struct AIResultView: View {
    let result: AIVerificationResult
    let explanation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: result.icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(result.displayName)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
            }
            if let explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var color: Color {
        switch result {
        case .approved: return .green
        case .rejected: return .red
        case .pending: return .orange
        case .notApplicable: return .blue
        }
    }
}

#Preview {
    VStack {
        AIResultView(result: .approved, explanation: "The photo clearly shows you at a gym performing exercises.")
        AIResultView(result: .rejected, explanation: "The photo does not match the challenge condition.")
        AIResultView(result: .pending, explanation: nil)
    }
    .padding()
}

import SwiftUI

// MARK: - AI Coach View (#10)
// Shown as a banner on HomeView and as a full sheet.

struct AICoachBanner: View {
    let brief: MorningBrief
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color(hex: "4580FF").opacity(0.12)).frame(width: 44, height: 44)
                    Text("🤖").font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(brief.greeting)
                        .font(.manrope(.bold, size: 14))
                        .foregroundColor(.black)
                        .lineLimit(2)
                    Text(brief.motivationTip)
                        .font(.manrope(.medium, size: 12))
                        .foregroundColor(.black.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.3))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "4580FF").opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(hex: "4580FF").opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.haptic)
    }
}

// MARK: - Full AI Coach Sheet (#10)

struct AICoachSheet: View {
    @Environment(\.dismiss) private var dismiss
    let brief: MorningBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good morning 🤖")
                        .font(.manrope(.extraBold, size: 24))
                    Text("Your AI Coach")
                        .font(.manrope(.medium, size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Greeting card
                    CoachCard(
                        emoji: "💬",
                        title: AppLanguage.t(
                            en: "Today's vibe",
                            ru: "Настрой на сегодня",
                            de: "Deine Stimmung heute",
                            kk: "Бүгінгі көңіл күй",
                            fr: "L'ambiance du jour",
                            ar: "أجواء اليوم"
                        )
                    ) {
                        Text(brief.greeting)
                            .font(.manrope(.medium, size: 15))
                            .foregroundStyle(.primary)
                    }
                    .appearEffect(delay: 0.05)

                    // Top tasks
                    if !brief.topTasks.isEmpty {
                        CoachCard(
                            emoji: "🎯",
                            title: AppLanguage.t(
                                en: "Focus on these",
                                ru: "Главное на сегодня",
                                de: "Darauf konzentrieren",
                                kk: "Осыларға назар аудар",
                                fr: "À faire en priorité",
                                ar: "ركّز على هذه"
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(brief.topTasks, id: \.self) { task in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(Color(hex: "4580FF"))
                                            .frame(width: 6, height: 6)
                                        Text(task)
                                            .font(.manrope(.medium, size: 14))
                                    }
                                }
                            }
                        }
                        .appearEffect(delay: 0.15)
                    }

                    // Motivation
                    CoachCard(
                        emoji: "⚡️",
                        title: AppLanguage.t(
                            en: "Tip of the day",
                            ru: "Совет дня",
                            de: "Tipp des Tages",
                            kk: "Күннің кеңесі",
                            fr: "Conseil du jour",
                            ar: "نصيحة اليوم"
                        )
                    ) {
                        Text(brief.motivationTip)
                            .font(.manrope(.medium, size: 15))
                            .foregroundStyle(.primary)
                    }
                    .appearEffect(delay: 0.25)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
                .readableWidth()
            }
        }
        .background(Color.white)
    }
}

private struct CoachCard<Content: View>: View {
    let emoji: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(emoji).font(.system(size: 18))
                Text(title).font(.manrope(.bold, size: 16))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.03)))
    }
}

// MARK: - Failure Analysis Sheet (#11)

struct FailureAnalysisSheet: View {
    @Environment(\.dismiss) private var dismiss
    let activity: reInspire.Activity
    @State private var userReason = ""
    @State private var analysis: FailureAnalysis?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let analysis {
                    resultView(analysis)
                } else {
                    inputView
                }
            }
            .background(Color.white)
            .navigationTitle("What happened?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { Haptics.tap(); dismiss() }
                }
            }
        }
    }

    private var inputView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\"\(activity.title)\"")
                .font(.manrope(.bold, size: 18))
                .padding(.horizontal, 22)
                .padding(.top, 24)

            Text("What made it hard? (optional)")
                .font(.manrope(.medium, size: 14))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)

            TextEditor(text: $userReason)
                .font(.manrope(.regular, size: 15))
                .padding(12)
                .frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.04)))
                .padding(.horizontal, 22)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 22)
            }

            Button {
                Haptics.tap()
                Task { await analyze() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Analyze with AI 🤖")
                            .font(.manrope(.bold, size: 16))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "4580FF")))
            }
            .padding(.horizontal, 22)
            .disabled(isLoading)

            Spacer()
        }
    }

    private func resultView(_ a: FailureAnalysis) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                CoachCard(emoji: "🔍", title: "Why it happened") {
                    Text(a.reason).font(.manrope(.medium, size: 15))
                }
                CoachCard(emoji: "💡", title: "What to do next") {
                    Text(a.suggestion).font(.manrope(.medium, size: 15))
                }
                if a.reschedule {
                    CoachCard(emoji: "📅", title: "Suggestion") {
                        Text("Try rescheduling this to tomorrow to set yourself up for success.")
                            .font(.manrope(.medium, size: 15))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .readableWidth()
        }
    }

    private func analyze() async {
        isLoading = true
        error = nil
        do {
            analysis = try await AICoachService.shared.analyzeFailure(
                activity: activity,
                userReason: userReason.isEmpty ? nil : userReason
            )
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        isLoading = false
    }
}

// MARK: - Goal Split Sheet (#12)

struct GoalSplitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let activity: reInspire.Activity
    let onConfirm: ([SplitTask]) -> Void

    @State private var split: GoalSplit?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("AI is splitting your goal…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let split {
                    resultView(split)
                } else {
                    Text(error ?? "Something went wrong")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.white)
            .navigationTitle("Break it down")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { Haptics.tap(); dismiss() }
                }
            }
        }
        .task { await loadSplit() }
    }

    private func resultView(_ g: GoalSplit) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI broke \"\(activity.title)\" into \(g.subtasks.count) steps:")
                        .font(.manrope(.bold, size: 16))
                        .padding(.bottom, 4)

                    ForEach(Array(g.subtasks.enumerated()), id: \.offset) { idx, task in
                        HStack(spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.manrope(.bold, size: 14))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color(hex: "4580FF")))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).font(.manrope(.bold, size: 15))
                                if let days = task.estimatedDays {
                                    Text("~\(days) day\(days == 1 ? "" : "s")")
                                        .font(.manrope(.medium, size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.03)))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .readableWidth()
            }

            Button {
                onConfirm(g.subtasks)
                dismiss()
            } label: {
                Text("Create \(g.subtasks.count) sub-tasks")
                    .font(.manrope(.bold, size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "2FB873")))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
            .readableWidth(480)
        }
    }

    private func loadSplit() async {
        do {
            split = try await AICoachService.shared.splitGoal(activity: activity)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

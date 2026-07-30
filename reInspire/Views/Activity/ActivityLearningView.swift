import SwiftUI

struct ActivityLearningView: View {
    @State private var vm: ActivityLearningViewModel

    let isMax: Bool
    let isActive: Bool
    let openMaxPaywall: () -> Void

    init(
        activity: Activity,
        isMax: Bool,
        isActive: Bool,
        openMaxPaywall: @escaping () -> Void
    ) {
        _vm = State(wrappedValue: ActivityLearningViewModel(activity: activity))
        self.isMax = isMax
        self.isActive = isActive
        self.openMaxPaywall = openMaxPaywall
    }

    var body: some View {
        ScrollView {
            Group {
                if !isMax {
                    lockedContent
                } else if vm.isLoading && vm.guide == nil {
                    loadingContent
                } else if let guide = vm.guide {
                    guideContent(guide)
                } else {
                    errorContent
                }
            }
            .padding()
            .readableWidth()
        }
        .task(id: isActive) {
            guard isActive, isMax else { return }
            await vm.loadIfNeeded()
        }
        .refreshable {
            guard isMax else { return }
            await vm.refresh()
        }
    }

    private var lockedContent: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 52)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.28), .blue.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 112, height: 112)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 43, weight: .semibold))
                    .foregroundStyle(.purple)
            }

            VStack(spacing: 8) {
                Text("Обучение по заданию")
                    .font(.title2.bold())
                Text("Получите персональный план, полезные советы и подходящие видео с YouTube.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Label("Доступно только в reInspire Max", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.purple.opacity(0.1), in: Capsule())

            Button {
                Haptics.tap()
                openMaxPaywall()
            } label: {
                Text("Открыть Max")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .padding(.top, 4)

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingContent: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 90)
            ProgressView()
                .controlSize(.large)
                .tint(.purple)
            Text("Ищем лучшие материалы...")
                .font(.headline)
            Text("Perplexity составляет короткий план и подбирает видео для этого задания.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 90)
        }
        .frame(maxWidth: .infinity)
    }

    private var errorContent: some View {
        ContentUnavailableView {
            Label("Обучение недоступно", systemImage: "wifi.exclamationmark")
        } description: {
            Text(vm.errorMessage ?? "Не удалось загрузить материалы.")
        } actions: {
            Button("Попробовать снова") {
                Task { await vm.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding(.top, 60)
    }

    private func guideContent(_ guide: LearningGuide) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("ОБУЧЕНИЕ", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                Text(guide.title)
                    .font(.title.bold())
                Text(guide.overview)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            sectionTitle("Пошаговый план", icon: "list.number")
            VStack(spacing: 12) {
                ForEach(Array(guide.steps.enumerated()), id: \.element.id) { index, step in
                    stepCard(step, number: index + 1)
                }
            }

            if !guide.safetyNotes.isEmpty {
                safetyCard(guide.safetyNotes)
            }

            if !guide.resources.isEmpty {
                sectionTitle("Видео", icon: "play.rectangle.fill")
                VStack(spacing: 14) {
                    ForEach(guide.resources) { resource in
                        resourceCard(resource)
                    }
                }
            }

            Button {
                Task { await vm.refresh() }
            } label: {
                Label(
                    vm.isLoading ? "Обновляем..." : "Обновить рекомендации",
                    systemImage: "arrow.clockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(vm.isLoading)
            .padding(.vertical, 8)
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func stepCard(_ step: LearningGuideStep, number: Int) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.purple, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.headline)
                Text(step.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }

    private func safetyCard(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Важно", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private func resourceCard(_ resource: LearningGuideResource) -> some View {
        Group {
            if let destination = resource.destination {
                Link(destination: destination) {
                    resourceLabel(resource)
                }
            } else {
                resourceLabel(resource)
            }
        }
        .buttonStyle(.plain)
    }

    private func resourceLabel(_ resource: LearningGuideResource) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.red.opacity(0.12))
                    .frame(width: 58, height: 58)
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(resource.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(resource.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

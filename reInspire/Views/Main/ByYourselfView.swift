import SwiftUI

// MARK: - Constants

private enum BYColors {
    static let cardBackground   = Color(hex: "F5F5F5")
    static let placeholderGray  = Color(hex: "BDBDBD")
    static let buttonBackground = Color(hex: "DEDEDE")
    static let buttonBorder     = Color(hex: "ACACAC")
    static let buttonTextGray   = Color(hex: "898989")
    static let iconBlue         = Color(red: 0.0, green: 0.282, blue: 0.886)
    static let glassBackground  = Color(hex: "DCDCDC")
}

/// One line in the notepad. A line can bind a data-source capability so the
/// task it creates is auto-verified (e.g. "Chess.com -- сыгранные партии").
private struct TaskLine: Identifiable {
    let id = UUID()
    var text: String = ""
    var capability: ConnectorCapability?
    var target: Double?
}

// MARK: - Main view

struct ByYourselfView: View {

    var workspaceId: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var lines: [TaskLine] = [TaskLine()]
    @FocusState private var focused: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// The notepad font is smaller on iPad (regular width) so more lines fit
    /// above the keyboard in landscape and a long line doesn't wrap/cramp.
    private var noteFontSize: CGFloat { hSize == .regular ? 26 : 34 }

    private var hasContent: Bool {
        lines.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    Text("reInspire.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 50)
                            .fill(BYColors.cardBackground)
                            .ignoresSafeArea(edges: .bottom)

                        VStack(alignment: .leading, spacing: 0) {
                            // Header
                            HStack(spacing: 8) {
                                BYAvatarIcon()
                                Text("By yourself")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.black)
                            }
                            .padding(.top, 28)
                            .padding(.horizontal, 24)

                            // Numbered task lines
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(lines.indices, id: \.self) { i in
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack(alignment: .center, spacing: 6) {
                                                    Text("\(i + 1).")
                                                        .font(.system(size: noteFontSize, weight: .medium))
                                                        .foregroundColor(
                                                            lines[i].text.trimmingCharacters(in: .whitespaces).isEmpty
                                                                ? BYColors.placeholderGray
                                                                : .black
                                                        )
                                                        .frame(width: 48, alignment: .trailing)
                                                        .animation(.none, value: lines.count)

                                                    ZStack(alignment: .leading) {
                                                        if lines[i].text.isEmpty && i == 0 {
                                                            Text("Write a new task...")
                                                                .font(.system(size: noteFontSize, weight: .medium))
                                                                .foregroundColor(BYColors.placeholderGray)
                                                                .allowsHitTesting(false)
                                                        }
                                                        TextField("", text: $lines[i].text)
                                                            .font(.system(size: noteFontSize, weight: .medium))
                                                            .foregroundColor(.black)
                                                            .focused($focused, equals: i)
                                                            .submitLabel(i == lines.count - 1 ? .done : .next)
                                                            .onSubmit { addLine(after: i, proxy: proxy) }
                                                    }
                                                }

                                                connectorArea(for: i)
                                                    .padding(.leading, 54)
                                            }
                                            .id(i)
                                            .contentShape(Rectangle())
                                            .onTapGesture { Haptics.selection(); focused = i }
                                        }
                                    }
                                    .padding(.top, 18)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 16)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            if let error = errorMessage {
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 6)
                            }

                            // Write up button
                            Button {
                                Task { await save() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isSaving {
                                        ProgressView().tint(BYColors.buttonTextGray)
                                    } else {
                                        HStack(spacing: 6) {
                                            Text("Write up")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(hasContent ? .white : BYColors.buttonTextGray)
                                            Image(systemName: "sparkle")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(hasContent ? .white : BYColors.buttonTextGray)
                                        }
                                    }
                                    Spacer()
                                }
                                .frame(height: 60)
                                .background(hasContent ? Color.black : BYColors.buttonBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(hasContent ? Color.clear : BYColors.buttonBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(PressableButtonStyle())
                            .disabled(!hasContent || isSaving)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    // Wider column on iPad so the notepad uses the space above
                    // the keyboard instead of a thin centered strip.
                    .readableWidth(hSize == .regular ? 920 : 560)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Haptics.tap(); dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = 0 }
        }
    }

    // MARK: - Connector capability area (per line)

    /// Below a line: a bound-source chip once chosen, otherwise -- while the line
    /// is focused and names a connector -- one-tap capability suggestions.
    @ViewBuilder
    private func connectorArea(for i: Int) -> some View {
        if let cap = lines[i].capability {
            boundChip(for: i, capability: cap)
        } else if focused == i {
            let matches = ConnectorCapability.detect(in: lines[i].text)
            if !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(matches) { cap in
                            Button { bind(cap, to: i) } label: { suggestionChip(cap) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
    }

    private func suggestionChip(_ cap: ConnectorCapability) -> some View {
        HStack(spacing: 7) {
            ConnectorGlyph(connector: cap.connector, size: 18, cornerRadius: 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(cap.connector.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                Text(cap.title)
                    .font(.system(size: 11))
                    .foregroundColor(BYColors.buttonTextGray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(cap.connector.tint.opacity(0.4), lineWidth: 1))
    }

    private func boundChip(for i: Int, capability cap: ConnectorCapability) -> some View {
        HStack(spacing: 10) {
            ConnectorGlyph(connector: cap.connector, size: 20, cornerRadius: 5)

            Text(cap.connector.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)

            Spacer(minLength: 4)

            // Target stepper -- adjusts how much counts as done.
            HStack(spacing: 10) {
                stepperButton("minus") { adjustTarget(at: i, by: -cap.targetStep) }
                Text("\(Int(lines[i].target ?? cap.defaultTarget)) \(cap.unit)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(minWidth: 70)
                stepperButton("plus") { adjustTarget(at: i, by: cap.targetStep) }
            }

            Button {
                Haptics.tap()
                lines[i].capability = nil
                lines[i].target = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(BYColors.placeholderGray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cap.connector.tint.opacity(0.35), lineWidth: 1)
        )
        .padding(.trailing, 8)
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 26, height: 26)
                .background(BYColors.cardBackground, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// Bind a capability to a line and rewrite the line into a verifiable task.
    private func bind(_ cap: ConnectorCapability, to i: Int) {
        Haptics.selection()
        lines[i].capability = cap
        lines[i].target = cap.defaultTarget
        lines[i].text = cap.taskTitle(target: cap.defaultTarget)
    }

    private func adjustTarget(at i: Int, by delta: Double) {
        guard let cap = lines[i].capability else { return }
        let current = lines[i].target ?? cap.defaultTarget
        let next = max(cap.targetStep, current + delta)
        lines[i].target = next
        lines[i].text = cap.taskTitle(target: next)
    }

    private func addLine(after index: Int, proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            lines.insert(TaskLine(), at: index + 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focused = index + 1
            withAnimation { proxy.scrollTo(index + 1, anchor: .bottom) }
        }
    }

    private func save() async {
        let items = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        // Best-effort AI categorization for all titles at once
        let titles = items.map { $0.text.trimmingCharacters(in: .whitespaces) }
        let categories = (try? await GeminiService.shared.categorize(titles: titles)) ?? []

        for (i, item) in items.enumerated() {
            let vm = CreateActivityViewModel()
            vm.title = titles[i]
            vm.frequency = .once
            vm.hasDeadline = false
            vm.reminderEnabled = false
            vm.workspaceId = workspaceId
            vm.category = i < categories.count ? categories[i] : nil
            if let cap = item.capability {
                // Auto-verified goal bound to the chosen data source.
                vm.bindConnector(cap, target: item.target ?? cap.defaultTarget)
            } else {
                vm.type = .task
            }
            await vm.create()
            if let err = vm.errorMessage {
                errorMessage = err
                isSaving = false
                Haptics.error()
                return
            }
        }

        isSaving = false
        Haptics.success()
        dismiss()
    }
}

// MARK: - Avatar icon

private struct BYAvatarIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(BYColors.glassBackground.opacity(0.65))
                .frame(width: 45, height: 45)
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
            VStack(spacing: 1) {
                Text("A")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                Rectangle()
                    .fill(BYColors.iconBlue)
                    .frame(width: 16, height: 3)
                    .cornerRadius(1)
            }
        }
    }
}

#Preview {
    ByYourselfView()
}

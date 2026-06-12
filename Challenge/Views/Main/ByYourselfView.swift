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

// MARK: - Main view

struct ByYourselfView: View {

    var workspaceId: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = [""]
    @FocusState private var focused: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var hasContent: Bool {
        lines.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    Text("The Challenge.")
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
                                            HStack(alignment: .center, spacing: 6) {
                                                Text("\(i + 1).")
                                                    .font(.system(size: 34, weight: .medium))
                                                    .foregroundColor(
                                                        lines[i].trimmingCharacters(in: .whitespaces).isEmpty
                                                            ? BYColors.placeholderGray
                                                            : .black
                                                    )
                                                    .frame(width: 48, alignment: .trailing)
                                                    .animation(.none, value: lines.count)

                                                ZStack(alignment: .leading) {
                                                    if lines[i].isEmpty && i == 0 {
                                                        Text("Write a new task...")
                                                            .font(.system(size: 34, weight: .medium))
                                                            .foregroundColor(BYColors.placeholderGray)
                                                            .allowsHitTesting(false)
                                                    }
                                                    TextField("", text: $lines[i])
                                                        .font(.system(size: 34, weight: .medium))
                                                        .foregroundColor(.black)
                                                        .focused($focused, equals: i)
                                                        .submitLabel(i == lines.count - 1 ? .done : .next)
                                                        .onSubmit { addLine(after: i, proxy: proxy) }
                                                }
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
                    .readableWidth()
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

    // MARK: - Actions

    private func addLine(after index: Int, proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            lines.insert("", at: index + 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focused = index + 1
            withAnimation { proxy.scrollTo(index + 1, anchor: .bottom) }
        }
    }

    private func save() async {
        let titles = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        // Best-effort AI categorization for all titles at once
        var categories: [String] = []
        categories = (try? await GeminiService.shared.categorize(titles: titles)) ?? []

        for (i, title) in titles.enumerated() {
            let vm = CreateActivityViewModel()
            vm.title = title
            vm.type = .task
            vm.frequency = .once
            vm.hasDeadline = false
            vm.reminderEnabled = false
            vm.workspaceId = workspaceId
            vm.category = i < categories.count ? categories[i] : nil
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

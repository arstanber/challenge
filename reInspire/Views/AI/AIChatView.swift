import SwiftUI

struct AIChatView: View {
    @Environment(\.dismiss) private var dismiss
    let todayTasks: [String]
    let streakCurrent: Int

    @State private var messages: [AIChatTurn] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    private var suggestions: [String] {
        [
            AppLanguage.t(en: "What should I focus on today?", ru: "На чём мне сосредоточиться сегодня?", de: "Worauf soll ich mich heute konzentrieren?", kk: "Бүгін неге назар аударуым керек?", fr: "Sur quoi dois-je me concentrer aujourd'hui ?", ar: "على ماذا أركز اليوم؟"),
            AppLanguage.t(en: "Help me find motivation", ru: "Помоги найти мотивацию", de: "Hilf mir, Motivation zu finden", kk: "Мотивация табуға көмектес", fr: "Aide-moi à trouver de la motivation", ar: "ساعدني في إيجاد الدافع"),
            AppLanguage.t(en: "Make my plan easier", ru: "Упрости мой план", de: "Vereinfache meinen Plan", kk: "Жоспарымды жеңілдет", fr: "Simplifie mon programme", ar: "بسّط خطتي")
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    conversation
                    composer
                }
            }
            .navigationTitle(AppLanguage.t(en: "AI Coach", ru: "AI-наставник", de: "AI-Coach", kk: "AI-тәлімгер", fr: "Coach IA", ar: "مدرب الذكاء الاصطناعي"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .accessibilityLabel(AppLanguage.t(en: "Back to Home", ru: "Вернуться на главный экран", de: "Zurück zur Startseite", kk: "Басты бетке оралу", fr: "Retour à l'accueil", ar: "العودة إلى الرئيسية"))
                }
            }
        }
        .interactiveDismissDisabled(isSending)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    if messages.isEmpty { welcome }
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(AppLanguage.t(en: "Thinking...", ru: "Думаю...", de: "Denke nach...", kk: "Ойланып жатырмын...", fr: "Je réfléchis...", ar: "أفكر..."))
                                .font(.manrope(.medium, size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .readableWidth(720)
            }
            .onChange(of: messages.count) {
                guard let id = messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Circle().fill(Color(hex: "7C4DF0").opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(hex: "7C4DF0"))
            }
            Text(AppLanguage.t(en: "Your personal coach", ru: "Твой личный наставник", de: "Dein persönlicher Coach", kk: "Сенің жеке тәлімгерің", fr: "Ton coach personnel", ar: "مدربك الشخصي"))
                .font(.manrope(.extraBold, size: 25))
            Text(AppLanguage.t(en: "I know your plan for today and can help you prioritize, recover motivation, or break a difficult goal into steps.", ru: "Я вижу твой план на сегодня и помогу расставить приоритеты, вернуть мотивацию или разбить сложную цель на шаги.", de: "Ich kenne deinen heutigen Plan und helfe bei Prioritäten, Motivation und kleinen Schritten.", kk: "Бүгінгі жоспарыңды көріп тұрмын және басымдықтарды анықтауға, мотивация табуға көмектесемін.", fr: "Je connais ton programme du jour et peux t'aider à définir tes priorités et retrouver ta motivation.", ar: "أعرف خطتك لليوم ويمكنني مساعدتك في ترتيب الأولويات واستعادة الدافع."))
                .font(.manrope(.regular, size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    Haptics.tap()
                    draft = suggestion
                    send()
                } label: {
                    HStack {
                        Text(suggestion).font(.manrope(.semibold, size: 14))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.primary)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    private func messageBubble(_ message: AIChatTurn) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 42) }
            Text(message.content)
                .font(.manrope(.regular, size: 15))
                .foregroundStyle(message.role == "user" ? Color.white : Color.primary)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(
                    message.role == "user" ? Color(hex: "7C4DF0") : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .textSelection(.enabled)
            if message.role != "user" { Spacer(minLength: 42) }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.manrope(.medium, size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(AppLanguage.t(en: "Ask me anything", ru: "Спроси что-нибудь", de: "Frag mich etwas", kk: "Кез келген сұрақ қой", fr: "Pose-moi une question", ar: "اسألني أي شيء"), text: $draft, axis: .vertical)
                    .font(.manrope(.regular, size: 15))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Color(hex: "7C4DF0"), in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        Haptics.tap()
        draft = ""
        errorMessage = nil
        inputFocused = false
        messages.append(AIChatTurn(role: "user", content: text))
        isSending = true

        Task {
            do {
                let response = try await AICoachService.shared.chat(
                    messages: messages,
                    todayTasks: todayTasks,
                    streakCurrent: streakCurrent
                )
                messages.append(AIChatTurn(role: "assistant", content: response.reply))
                Haptics.success()
            } catch {
                errorMessage = AppLanguage.t(en: "Couldn't get a reply. Try again.", ru: "Не удалось получить ответ. Попробуй ещё раз.", de: "Keine Antwort erhalten. Versuch es erneut.", kk: "Жауап алу мүмкін болмады. Қайталап көр.", fr: "Impossible d'obtenir une réponse. Réessaie.", ar: "تعذر الحصول على رد. حاول مرة أخرى.")
            }
            isSending = false
        }
    }
}

#Preview {
    AIChatView(todayTasks: ["Выпить воду", "Пробежка 20 минут"], streakCurrent: 7)
}

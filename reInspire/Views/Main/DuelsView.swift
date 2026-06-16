import SwiftUI

// MARK: - Duels list

/// Friend duels: challenge a friend to close at least one task every day.
/// Loss aversion against a real person is the strongest retention loop in
/// the app -- a missed day is no longer private.
struct DuelsView: View {
    @Environment(AuthService.self) private var authService
    @State private var service = DuelService.shared

    private struct CreatedCode: Identifiable {
        let id = UUID()
        let code: String
    }

    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showNearby = false
    @State private var joinCode = ""
    @State private var createdCode: CreatedCode?

    private var myId: UUID? { authService.currentUser?.id }

    var body: some View {
        List {
            if service.duels.isEmpty && !service.isLoading {
                Section {
                    emptyState
                }
            }

            if !service.duels.isEmpty {
                Section {
                    ForEach(service.duels) { duel in
                        NavigationLink(value: duel) {
                            DuelRowView(duel: duel, myId: myId)
                        }
                    }
                }
            }
        }
        .navigationTitle("Дуэли")
        .navigationDestination(for: Duel.self) { duel in
            DuelDetailView(duel: duel, myId: myId)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Haptics.tap()
                        showCreate = true
                    } label: {
                        Label("Вызвать друга", systemImage: "plus.circle.fill")
                    }
                    Button {
                        Haptics.tap()
                        showNearby = true
                    } label: {
                        Label("Соединить рядом (потрясти телефоны)", systemImage: "wave.3.right")
                    }
                    Button {
                        Haptics.tap()
                        showJoin = true
                    } label: {
                        Label("Ввести код", systemImage: "keyboard")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await service.load() }
        .refreshable { await service.load() }
        .sheet(isPresented: $showCreate) {
            DuelCreateSheet { days in createDuel(days: days) }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showNearby) {
            DuelNearbyConnectView { await service.load() }
        }
        .alert("Код дуэли", isPresented: $showJoin) {
            TextField("ABC123", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Вступить") {
                let code = joinCode
                joinCode = ""
                Task {
                    if await service.joinDuel(code: code) { Haptics.success() }
                }
            }
            Button("Отмена", role: .cancel) { joinCode = "" }
        } message: {
            Text("Введи код, который прислал друг")
        }
        .sheet(item: $createdCode) { item in
            DuelInviteSheet(code: item.code)
                .presentationDetents([.medium])
        }
        .alert("Ошибка", isPresented: Binding(
            get: { service.errorMessage != nil },
            set: { if !$0 { service.errorMessage = nil } }
        )) {
            Button("OK") { service.errorMessage = nil }
        } message: {
            Text(service.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("⚔️")
                .font(.system(size: 44))
            Text("Вызови друга на дуэль")
                .font(.headline)
            Text("Соревнуйтесь, кто выполнит больше дел за время дуэли. Кто закрыл больше задач -- тот и победил. Себя обмануть легко, друга -- нет.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                showCreate = true
            } label: {
                Text("Бросить вызов")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "0048E2"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func createDuel(days: Int) {
        Task {
            if let code = await service.createDuel(days: days) {
                Haptics.success()
                createdCode = CreatedCode(code: code)
            }
        }
    }
}

// MARK: - Row

private struct DuelRowView: View {
    let duel: Duel
    let myId: UUID?

    var body: some View {
        HStack(spacing: 12) {
            Text(statusEmoji)
                .font(.system(size: 28))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if duel.status == .active || duel.status == .finished {
                Text("\(duel.myTasks(myId)) : \(duel.theirTasks(myId))")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusEmoji: String {
        switch duel.status {
        case .pending:   return "⏳"
        case .active:    return "⚔️"
        case .finished:  return duel.didWin(myId) == false ? "😤" : "🏆"
        case .cancelled: return "🚫"
        }
    }

    private var title: String {
        switch duel.status {
        case .pending: return "Ожидание соперника"
        default:       return "Против \(duel.opponentName(for: myId))"
        }
    }

    private var subtitle: String {
        switch duel.status {
        case .pending:
            return "Код: \(duel.inviteCode) · \(duel.days) дн."
        case .active:
            if let left = duel.daysLeft {
                return left == 1 ? "Последний день!" : "Осталось дней: \(left)"
            }
            return "Идёт"
        case .finished:
            switch duel.didWin(myId) {
            case true?:  return "Победа!"
            case false?: return "Поражение"
            default:     return "Ничья -- оба продержались"
            }
        case .cancelled:
            return "Отменена"
        }
    }

    private var scoreColor: Color {
        let mine = duel.myTasks(myId)
        let theirs = duel.theirTasks(myId)
        if mine > theirs { return .green }
        if mine < theirs { return .red }
        return .secondary
    }
}

// MARK: - Invite sheet

private struct DuelInviteSheet: View {
    let code: String
    @Environment(\.dismiss) private var dismiss

    private var shareText: String {
        "Вызываю тебя на дуэль в reInspire ⚔️ Кто выполнит больше дел, тот и победил. Код: \(code). Скачай: https://thechallenges.app"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("⚔️")
                .font(.system(size: 52))
            Text("Дуэль создана")
                .font(.title3.bold())
            Text("Отправь код другу. Дуэль начнётся, как только он вступит.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(code)
                .font(.system(size: 36, weight: .heavy, design: .monospaced))
                .tracking(6)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                .onTapGesture {
                    UIPasteboard.general.string = code
                    Haptics.success()
                }

            ShareLink(item: shareText) {
                Label("Отправить вызов", systemImage: "paperplane.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "0048E2"))

            Button("Закрыть") { dismiss() }
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

// MARK: - Create sheet (length picker)

private struct DuelCreateSheet: View {
    let onCreate: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var days = 7

    private let quick = [7, 14, 30, 60]

    var body: some View {
        VStack(spacing: 20) {
            Text("⚔️").font(.system(size: 48))
            Text("Длительность дуэли").font(.title3.bold())
            Text("Соревнуйтесь, кто за это время выполнит больше дел.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Text("Дней:").font(.headline)
                Spacer()
                TextField("7", value: $days, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    .onChange(of: days) { _, v in days = min(90, max(3, v)) }
                Stepper("", value: $days, in: 3...90).labelsHidden()
            }
            .padding(.horizontal, 8)

            HStack(spacing: 8) {
                ForEach(quick, id: \.self) { d in
                    Button {
                        Haptics.selection(); days = d
                    } label: {
                        Text("\(d)")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .background(Capsule().fill(days == d
                                ? Color(hex: "0048E2") : Color(hex: "0048E2").opacity(0.12)))
                            .foregroundStyle(days == d ? .white : Color(hex: "0048E2"))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                onCreate(days); dismiss()
            } label: {
                Text("Бросить вызов")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "0048E2"))

            Button("Отмена") { dismiss() }
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

// MARK: - Detail

struct DuelDetailView: View {
    let duel: Duel
    let myId: UUID?

    @State private var service = DuelService.shared

    /// Latest server state of this duel (scores move as days pass).
    private var current: Duel {
        service.duels.first(where: { $0.id == duel.id }) ?? duel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scoreHeader
                if current.status == .pending {
                    pendingSection
                } else {
                    daysGrid
                }
                statusFooter
            }
            .padding(18)
            .readableWidth()
        }
        .navigationTitle("Дуэль")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await service.load() }
    }

    private var scoreHeader: some View {
        HStack(spacing: 18) {
            sideColumn(name: "Ты", score: current.myTasks(myId), highlight: true)
            Text("VS")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
            sideColumn(name: current.opponentName(for: myId),
                       score: current.theirTasks(myId), highlight: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func sideColumn(name: String, score: Int, highlight: Bool) -> some View {
        VStack(spacing: 4) {
            Text("\(score)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(highlight ? Color(hex: "0048E2") : .primary)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var pendingSection: some View {
        VStack(spacing: 14) {
            Text("Соперник ещё не вступил")
                .font(.headline)
            Text(current.inviteCode)
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .tracking(5)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    UIPasteboard.general.string = current.inviteCode
                    Haptics.success()
                }
            ShareLink(item: "Вызываю тебя на дуэль в reInspire ⚔️ Код: \(current.inviteCode). Скачай: https://thechallenges.app") {
                Label("Отправить вызов", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "0048E2"))

            Button(role: .destructive) {
                Haptics.tap()
                Task { await service.cancelDuel(current) }
            } label: {
                Text("Отменить дуэль")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    /// Day-by-day picture: my row and the opponent's row. Both sides see a
    /// missed day immediately -- that visibility is the whole mechanic.
    private var daysGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Дни с активностью")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
            dayRow(label: "Ты", done: Set(current.myDone(myId)))
            dayRow(label: current.opponentName(for: myId), done: Set(current.theirDone(myId)))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func dayRow(label: String, done: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(current.windowDays, id: \.self) { day in
                    dayDot(day: day, isDone: done.contains(day))
                }
            }
        }
    }

    private func dayDot(day: String, isDone: Bool) -> some View {
        let today = Duel.dayFormatter.string(from: Date())
        let isFuture = day > today
        return Circle()
            .fill(isDone ? Color.green
                  : isFuture ? Color.primary.opacity(0.08)
                  : day == today ? Color.orange.opacity(0.35)
                  : Color.red.opacity(0.3))
            .frame(height: 26)
            .overlay {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else if !isFuture && day != today {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red.opacity(0.7))
                }
            }
    }

    private var statusFooter: some View {
        Group {
            switch current.status {
            case .active:
                if let left = current.daysLeft {
                    Text(left == 1 ? "Последний день -- не сорвись" : "Осталось дней: \(left). Побеждает тот, кто выполнил больше дел.")
                }
            case .finished:
                switch current.didWin(myId) {
                case true?:  Text("🏆 Победа! Соперник повержен.")
                case false?: Text("😤 Поражение. Реванш расставит всё по местам.")
                default:     Text("🤝 Ничья: оба продержались до конца.")
                }
            default:
                EmptyView()
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

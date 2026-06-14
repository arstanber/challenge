import SwiftUI

struct TelegramLinkView: View {
    @State private var service = TelegramService.shared
    @State private var deepLink: URL?
    @State private var showUnlinkConfirm = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color(hex: "29A9EA").opacity(0.15))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(Color(hex: "29A9EA"))
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Telegram bot").font(.headline)
                        if service.isLinked {
                            Text(service.linkedUsername.map { "Linked as @\($0)" } ?? "Linked")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("Not linked").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if service.isLinked {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
            }

            if service.isLinked {
                Section {
                    Button(role: .destructive) {
                        Haptics.warning()
                        showUnlinkConfirm = true
                    } label: {
                        Label("Disconnect", systemImage: "link.badge.minus")
                    }
                } footer: {
                    Text("Disconnecting stops the bot from creating tasks, accepting photos, or sending you notifications.")
                }
            } else {
                Section {
                    Button {
                        Haptics.tap()
                        Task {
                            if let link = await service.generateLinkCode() {
                                deepLink = link
                                await UIApplication.shared.open(link)
                            }
                        }
                    } label: {
                        if service.isLoading {
                            ProgressView()
                        } else {
                            Label("Open Telegram to link", systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(service.isLoading)

                    if let code = service.pendingCode {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("If Telegram didn't open, send this to @\(Constants.Telegram.botUsername):")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text("/start \(code)")
                                    .font(.subheadline.monospaced().bold())
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = "/start \(code)"
                                    Haptics.success()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                        }
                    }
                } footer: {
                    Text("We'll open Telegram with a one-time code pre-filled. Send it to the bot to link this account — the code expires in 10 minutes.")
                }

                Section("What you can do once linked") {
                    Label("Create tasks by sending the bot a message", systemImage: "plus.message.fill")
                    Label("Submit photo proof for challenges", systemImage: "camera.fill")
                    Label("Get reminders and results from the bot", systemImage: "bell.fill")
                }
            }

            if let error = service.errorMessage {
                Section {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Telegram bot")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.refreshStatus() }
        .refreshable { await service.refreshStatus() }
        .alert("Disconnect Telegram?", isPresented: $showUnlinkConfirm) {
            Button("Disconnect", role: .destructive) { Task { await service.unlink() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can relink anytime from this screen.")
        }
    }
}

#Preview {
    NavigationStack { TelegramLinkView() }
}

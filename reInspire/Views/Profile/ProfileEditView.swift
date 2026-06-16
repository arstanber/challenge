import SwiftUI
import PhotosUI

/// Account & profile customization: avatar photo, display name, and account
/// info. Opened from Settings -> "Профиль".
struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @State private var vm = ProfileViewModel()

    @State private var name = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var uploading = false
    @State private var savedName = false
    @State private var showSignOut = false

    private var user: AppUser? { auth.currentUser }

    var body: some View {
        NavigationStack {
            Form {
                avatarSection
                nameSection
                accountSection
                if let error = vm.errorMessage {
                    Section { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { name = user?.displayName ?? "" }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadAndUpload(item) }
            }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $showSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) {
                    Haptics.warning(); dismiss(); auth.signOut()
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    // MARK: Avatar

    private var avatarSection: some View {
        Section {
            VStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    avatarCircle
                    if uploading {
                        ProgressView()
                            .frame(width: 96, height: 96)
                            .background(Circle().fill(.black.opacity(0.25)))
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color(hex: "0A84FF")))
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                    }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text("Изменить фото").font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private var avatarCircle: some View {
        if let pickedImage {
            Image(uiImage: pickedImage)
                .resizable().scaledToFill()
                .frame(width: 96, height: 96).clipShape(Circle())
        } else if let urlString = user?.avatarURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    initialCircle
                }
            }
            .frame(width: 96, height: 96).clipShape(Circle())
        } else {
            initialCircle.frame(width: 96, height: 96)
        }
    }

    private var initialCircle: some View {
        Circle()
            .fill(.orange.gradient)
            .overlay {
                Text(String((user?.displayLabel ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    // MARK: Name

    private var nameSection: some View {
        Section("Имя") {
            TextField("Как тебя зовут", text: $name)
                .autocorrectionDisabled()
            Button {
                Haptics.tap()
                Task {
                    await vm.updateDisplayName(name)
                    savedName = true
                    Haptics.success()
                }
            } label: {
                HStack {
                    Text("Сохранить имя")
                    Spacer()
                    if savedName && (user?.displayName ?? "") == name.trimmingCharacters(in: .whitespacesAndNewlines) {
                        Image(systemName: "checkmark").foregroundStyle(.green)
                    }
                }
            }
            .disabled(vm.isLoading)
        }
    }

    // MARK: Account

    private var accountSection: some View {
        Section("Аккаунт") {
            LabeledContent("Почта", value: user?.email ?? "--")
            if let plan = user?.plan {
                LabeledContent("Тариф", value: plan.displayName)
            }
            Button(role: .destructive) {
                Haptics.warning(); showSignOut = true
            } label: {
                Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: Upload

    private func loadAndUpload(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        pickedImage = image
        guard let jpeg = image.compressedForUpload(maxDimension: 512, quality: 0.8) else { return }
        let ok = await vm.uploadAvatar(jpeg)
        if ok { Haptics.success() }
    }
}

#Preview {
    ProfileEditView().environment(AuthService.shared)
}

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Location Reminder Picker (#10)

struct LocationReminderPicker: View {
    let activity: Activity
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    @State private var centerCoordinate = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    @State private var placeName = ""
    @State private var radius: Double = 150
    @State private var existingReminder: String?
    @State private var isSaving = false
    @State private var alertMessage: String?
    @State private var showOpenSettings = false

    private let service = LocationReminderService.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition)
                    .onMapCameraChange { context in
                        centerCoordinate = context.region.center
                    }
                    .ignoresSafeArea(edges: .top)

                // Center pin
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(hex: "4580FF"))
                    .background(Circle().fill(.white).frame(width: 18, height: 18))
                    .offset(y: -18)
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity, alignment: .center)

                // Bottom panel
                VStack(spacing: 14) {
                    TextField("Название места (например, Спортзал)", text: $placeName)
                        .font(.manrope(.medium, size: 15))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

                    HStack {
                        Text("Радиус")
                            .font(.manrope(.medium, size: 13))
                            .foregroundStyle(.secondary)
                        Slider(value: $radius, in: 100...1000, step: 50)
                            .tint(Color(hex: "4580FF"))
                            .hapticFeedback(.selection, trigger: radius)
                        Text("\(Int(radius)) м")
                            .font(.manrope(.bold, size: 13))
                            .frame(width: 50, alignment: .trailing)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text(existingReminder == nil ? "Поставить напоминание здесь" : "Обновить напоминание")
                            }
                        }
                        .font(.manrope(.bold, size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "4580FF")))
                    }
                    .disabled(placeName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                    if existingReminder != nil {
                        Button(role: .destructive) {
                            Haptics.warning()
                            service.removeReminder(activityId: activity.id)
                            existingReminder = nil
                        } label: {
                            Text("Удалить напоминание")
                                .font(.manrope(.bold, size: 14))
                        }
                    }
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .readableWidth(560)
            }
            .navigationTitle("Напоминание по месту")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { Haptics.tap(); dismiss() }
                }
            }
            .alert("Не получилось", isPresented: .init(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil; showOpenSettings = false } }
            )) {
                if showOpenSettings {
                    Button("Открыть настройки") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Button("Понятно", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onAppear {
                existingReminder = service.reminderPlaceName(for: activity.id)
                if let existing = existingReminder { placeName = existing }
                centerOnUserIfPossible()
            }
        }
    }

    private func centerOnUserIfPossible() {
        guard let location = service.currentLocation else { return }
        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        cameraPosition = .region(region)
        centerCoordinate = location.coordinate
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        switch await service.ensureAuthorized() {
        case .notificationsDenied:
            showOpenSettings = true
            alertMessage = "Уведомления выключены. Разрешите их в настройках, чтобы напоминание сработало."
            return
        case .locationDenied:
            showOpenSettings = true
            alertMessage = "Нет доступа к геолокации. Разрешите доступ в настройках, чтобы напоминание сработало."
            return
        case .granted:
            break
        }

        do {
            try await service.setReminder(
                activityId: activity.id,
                title: activity.title,
                coordinate: centerCoordinate,
                radius: radius,
                placeName: placeName.trimmingCharacters(in: .whitespaces)
            )
            Haptics.success()
            dismiss()
        } catch {
            alertMessage = "Система не приняла напоминание: \(error.localizedDescription)"
        }
    }
}

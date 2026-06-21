import SwiftUI
import MapKit
import CoreLocation

// MARK: - Locations (Settings -> Локации)
// A standalone list of saved places. Arriving at any of them fires a push
// reminding the user to photograph and complete their tasks.

struct LocationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let service = LocationReminderService.shared
    private let blue = Color(hex: "4580FF")

    @State private var places: [PlaceReminder] = []
    @State private var showPicker = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    intro

                    if places.isEmpty {
                        emptyState
                    } else {
                        placesList
                    }

                    if places.count < LocationReminderService.maxPlaces {
                        addButton
                    } else {
                        Text("Достигнут лимит в \(LocationReminderService.maxPlaces) мест.")
                            .font(.manrope(.medium, size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 64)
                .padding(.bottom, 50)
                .readableWidth()
            }

            header
        }
        .sheet(isPresented: $showPicker, onDismiss: reload) {
            PlaceReminderPicker()
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        places = service.savedPlaces()
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Локации")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            HStack {
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Напоминания по месту")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
            Text("Выберите место и радиус на карте. Когда вы окажетесь рядом, придёт уведомление -- пора сфотографировать и выполнить задачу.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 40))
                .foregroundStyle(blue)
            Text("Пока нет сохранённых мест")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemBackground)))
    }

    private var placesList: some View {
        VStack(spacing: 0) {
            ForEach(places) { place in
                HStack(spacing: 16) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(blue)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("Радиус \(Int(place.radius)) м")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Haptics.warning()
                        service.removePlace(id: place.id)
                        reload()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.red.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)

                if place.id != places.last?.id {
                    Rectangle().fill(Color.primary.opacity(0.08))
                        .frame(height: 1).padding(.leading, 58)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemBackground)))
    }

    private var addButton: some View {
        Button {
            Haptics.tap(); showPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                Text("Добавить место")
            }
            .font(.manrope(.bold, size: 16))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 16).fill(blue))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Place Reminder Picker

private struct PlaceReminderPicker: View {
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var centerCoordinate = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
    @State private var placeName = ""
    @State private var radius: Double = 150
    @State private var isSaving = false
    @State private var alertMessage: String?
    @State private var showOpenSettings = false

    private let service = LocationReminderService.shared
    private let blue = Color(hex: "4580FF")

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onMapCameraChange { context in
                    centerCoordinate = context.region.center
                }
                .ignoresSafeArea(edges: .top)

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(blue)
                    .background(Circle().fill(.white).frame(width: 18, height: 18))
                    .offset(y: -18)
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity, alignment: .center)

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
                            .tint(blue)
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
                                Text("Сохранить место")
                            }
                        }
                        .font(.manrope(.bold, size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(blue))
                    }
                    .disabled(placeName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .readableWidth(560)
            }
            .navigationTitle("Новое место")
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
            .task { await centerOnUser() }
        }
    }

    private func centerOnUser() async {
        guard let location = await service.requestCurrentLocation() else { return }
        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        withAnimation {
            cameraPosition = .region(region)
        }
        centerCoordinate = location.coordinate
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        switch await service.ensureAuthorized() {
        case .notificationsDenied:
            showOpenSettings = true
            alertMessage = String(localized: "Уведомления выключены. Разрешите их в настройках, чтобы напоминание сработало.")
            return
        case .locationDenied:
            showOpenSettings = true
            alertMessage = String(localized: "Нет доступа к геолокации. Разрешите доступ в настройках, чтобы напоминание сработало.")
            return
        case .granted:
            break
        }

        do {
            _ = try await service.addPlace(
                name: placeName.trimmingCharacters(in: .whitespaces),
                coordinate: centerCoordinate,
                radius: radius
            )
            Haptics.success()
            dismiss()
        } catch {
            alertMessage = String(localized: "Система не приняла напоминание: \(error.localizedDescription)")
        }
    }
}

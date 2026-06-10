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
                    TextField("Place name (e.g. Gym)", text: $placeName)
                        .font(.manrope(.medium, size: 15))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.05)))

                    HStack {
                        Text("Radius")
                            .font(.manrope(.medium, size: 13))
                            .foregroundColor(.black.opacity(0.5))
                        Slider(value: $radius, in: 100...1000, step: 50)
                            .tint(Color(hex: "4580FF"))
                            .sensoryFeedback(.selection, trigger: radius)
                        Text("\(Int(radius))m")
                            .font(.manrope(.bold, size: 13))
                            .frame(width: 50, alignment: .trailing)
                    }

                    Button {
                        save()
                    } label: {
                        Text(existingReminder == nil ? "Set reminder here" : "Update reminder")
                            .font(.manrope(.bold, size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "4580FF")))
                    }
                    .disabled(placeName.trimmingCharacters(in: .whitespaces).isEmpty)

                    if existingReminder != nil {
                        Button(role: .destructive) {
                            Haptics.warning()
                            service.removeReminder(activityId: activity.id)
                            existingReminder = nil
                        } label: {
                            Text("Remove reminder")
                                .font(.manrope(.bold, size: 14))
                        }
                    }
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("Location reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { Haptics.tap(); dismiss() }
                }
            }
            .onAppear {
                service.requestAuthorization()
                existingReminder = service.reminderPlaceName(for: activity.id)
                if let existing = existingReminder { placeName = existing }
            }
        }
    }

    private func save() {
        service.setReminder(
            activityId: activity.id,
            title: activity.title,
            coordinate: centerCoordinate,
            radius: radius,
            placeName: placeName.trimmingCharacters(in: .whitespaces)
        )
        Haptics.success()
        dismiss()
    }
}

import SwiftUI

struct AddActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var location = ""
    @State private var active = false
    @State private var seasonal = false
    @State private var home = false
    @State private var dateSpecific = false
    @State private var dateActive = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        formField(label: "Name", icon: "figure.run") {
                            TextField("Activity name", text: $name)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Location (optional)", icon: "mappin") {
                            TextField("Where is this?", text: $location)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Status", icon: "tag") {
                            VStack(spacing: 8) {
                                Toggle("Active?", isOn: $active)
                                    .tint(.sunAccent)
                                    .padding()
                                    .background(Color.sunSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(Color.sunText)

                                Toggle("Seasonal?", isOn: $seasonal)
                                    .tint(.sunAccent)
                                    .padding()
                                    .background(Color.sunSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(Color.sunText)

                                Toggle("Home?", isOn: $home)
                                    .tint(.sunAccent)
                                    .padding()
                                    .background(Color.sunSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(Color.sunText)
                            }
                        }

                        formField(label: "Date", icon: "calendar") {
                            VStack(spacing: 0) {
                                Toggle("Date-Specific?", isOn: $dateSpecific.animation())
                                    .tint(.sunAccent)
                                    .padding()
                                    .background(Color.sunSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(Color.sunText)

                                if dateSpecific {
                                    DatePicker("", selection: $dateActive, displayedComponents: .date)
                                        .datePickerStyle(.graphical)
                                        .tint(.sunAccent)
                                        .padding(.horizontal)
                                        .padding(.bottom)
                                        .background(Color.sunSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundStyle(.red)
                        }

                        Button { Task { await save() } } label: {
                            HStack(spacing: 10) {
                                if isSaving { ProgressView().tint(.sunBackground) }
                                Text(isSaving ? "Saving..." : "Save Activity")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(name.isEmpty ? Color.sunSurface : Color.sunAccent)
                            .foregroundStyle(name.isEmpty ? Color.sunSecondary : Color.sunBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(name.isEmpty || isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.sunSecondary)
                }
            }
        }
    }

    private func formField<C: View>(label: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sunSecondary)
            content()
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let a = Activity(
                id:             UUID().uuidString,
                name:           name,
                location:       location,
                dateSpecific:   dateSpecific,
                dateActive:     dateSpecific ? dateActive : nil,
                active:         active,
                seasonal:       seasonal,
                home:           home,
                calendarSynced: false
            )
            try await NotionService.shared.createActivity(a)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotionService.shared.invalidateActivities()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

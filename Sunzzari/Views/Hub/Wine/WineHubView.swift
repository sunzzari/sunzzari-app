import SwiftUI

struct WineHubView: View {
    @State private var showAdd = false
    @State private var showPicker = false

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            List {
                NavigationLink(destination: MyWineView()) {
                    hubCell(icon: "wineglass", title: "My Wine", subtitle: "Browse your cellar")
                }
                .listRowBackground(Color.sunSurface)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                Button { showAdd = true } label: {
                    hubCell(icon: "plus.circle", title: "Add Wine", subtitle: "Log a bottle")
                }
                .listRowBackground(Color.sunSurface)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                Button { showPicker = true } label: {
                    hubCell(icon: "wand.and.stars", iconColor: .sunAccent, title: "Wine Picker", subtitle: "Let Claude choose for us")
                }
                .listRowBackground(Color.sunSurface)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Wine")
        .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAdd) { AddWineView() }
        .sheet(isPresented: $showPicker) { WinePickerView() }
    }

    private func hubCell(icon: String, iconColor: Color = .sunAccent, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.sunText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.sunSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sunSecondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

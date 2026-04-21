import SwiftUI

struct RestaurantHubView: View {
    @State private var showAdd = false

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            List {
                NavigationLink(destination: MyRestaurantsView()) {
                    hubCell(icon: "fork.knife", title: "My Restaurants", subtitle: "Browse & filter your guide")
                }
                .listRowBackground(Color.sunSurface)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                Button { showAdd = true } label: {
                    hubCell(icon: "plus.circle", title: "Add Restaurant", subtitle: "Log a new spot")
                }
                .listRowBackground(Color.sunSurface)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Restaurants")
        .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAdd) { AddRestaurantView() }
    }

    private func hubCell(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.sunAccent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.sunSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

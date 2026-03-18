import SwiftUI

struct ActivitiesHubView: View {
    @State private var showAdd = false

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            List {
                NavigationLink(destination: MyActivitiesView()) {
                    hubCell(icon: "figure.run", title: "My Activities", subtitle: "Browse your list")
                }
                .listRowBackground(Color.sunSurface)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                Button { showAdd = true } label: {
                    hubCell(icon: "plus.circle", title: "Add Activity", subtitle: "Log something to do")
                }
                .listRowBackground(Color.sunSurface)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Activities")
        .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAdd) { AddActivityView() }
    }

    private func hubCell(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.sunAccent)
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

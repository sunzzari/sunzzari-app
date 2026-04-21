import SwiftUI

struct InfoDetailView: View {
    let entry: SunzzariInfoEntry
    @State private var blocks: [InfoBlock] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                SerifNavHeader(entry.title)

                if isLoading {
                    Spacer()
                    ProgressView().tint(.sunAccent)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36, design: .serif))
                            .foregroundStyle(Color.sunAccent)
                        Text(error)
                            .foregroundStyle(Color.sunSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Retry") { Task { await load() } }
                            .foregroundStyle(Color.sunAccent)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                blockView(block)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            blocks = try await NotionService.shared.fetchInfoBlocks(pageID: entry.id)
        } catch {
            errorMessage = "Couldn't load content."
        }
        isLoading = false
    }

    @ViewBuilder
    private func blockView(_ block: InfoBlock) -> some View {
        switch block {
        case .heading2(let text):
            Text(text)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .fontDesign(.serif)
                .foregroundStyle(Color.sunText)
                .padding(.top, 24)
                .padding(.bottom, 8)

        case .heading3(let text):
            Text(text)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(Color.sunSecondary)
                .padding(.top, 16)
                .padding(.bottom, 4)

        case .bullet(let text, let url):
            bulletRow(text: text, url: url)

        case .tableGrid(let rows):
            tableView(rows: rows)
                .padding(.vertical, 8)

        case .paragraph(let text):
            Text(text)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Color.sunText.opacity(0.85))
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func bulletRow(text: String, url: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(hex: entry.category.color))
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            if let urlStr = url, let link = URL(string: urlStr) {
                Link(text, destination: link)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Color(hex: entry.category.color))
                    .underline(false)
            } else {
                Text(text)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Color.sunText.opacity(0.9))
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func tableView(rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                tableRow(cells: row, isHeader: index == 0)
                if index < rows.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.08))
                }
            }
        }
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func tableRow(cells: [String], isHeader: Bool) -> some View {
        let columnCount = cells.count

        if columnCount == 2 {
            HStack(spacing: 0) {
                cellText(cells[0], isHeader: isHeader, flex: 1)
                Divider().background(Color.white.opacity(0.08))
                cellText(cells[1], isHeader: isHeader, flex: 2)
            }
            .frame(minHeight: 40)
            .background(isHeader ? Color.white.opacity(0.06) : Color.clear)
        } else if columnCount >= 3 {
            HStack(spacing: 0) {
                cellText(cells[0], isHeader: isHeader, flex: 2)
                Divider().background(Color.white.opacity(0.08))
                cellText(cells[1], isHeader: isHeader, flex: 3)
                Divider().background(Color.white.opacity(0.08))
                cellText(cells[2], isHeader: isHeader, flex: 3)
            }
            .frame(minHeight: 40)
            .background(isHeader ? Color.white.opacity(0.06) : Color.clear)
        } else if columnCount == 1 {
            cellText(cells[0], isHeader: isHeader, flex: 1)
                .frame(minHeight: 40)
                .background(isHeader ? Color.white.opacity(0.06) : Color.clear)
        }
    }

    @ViewBuilder
    private func cellText(_ text: String, isHeader: Bool, flex: Int) -> some View {
        Text(text)
            .font(isHeader
                ? .system(size: 13, weight: .semibold, design: .serif)
                : .system(size: 13, design: .serif))
            .foregroundStyle(isHeader ? Color(hex: entry.category.color) : Color.sunText.opacity(0.85))
            .lineLimit(nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

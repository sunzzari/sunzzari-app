import SwiftUI

struct BenefitsView: View {

    enum BenefitType: String {
        case lounge       = "Lounge"
        case hotelStatus  = "Hotel Status"
        case rentalStatus = "Rental Status"

        var colorHex: String {
            switch self {
            case .lounge:       return "#60A5FA"
            case .hotelStatus:  return "#FBBF24"
            case .rentalStatus: return "#34D399"
            }
        }
    }

    struct BenefitRow {
        let benefit: String
        let type: BenefitType
        let person: String
        let notes: String
    }

    struct CardGroup {
        let cardName: String
        let cardColorHex: String
        let benefits: [BenefitRow]
    }

    let groups: [CardGroup] = [
        CardGroup(cardName: "Amex Platinum", cardColorHex: "#60A5FA", benefits: [
            BenefitRow(benefit: "Centurion Lounge",      type: .lounge,       person: "Both",  notes: "Amex Centurion Lounges worldwide"),
            BenefitRow(benefit: "Priority Pass Select",  type: .lounge,       person: "Both",  notes: "1,300+ airport lounges globally"),
            BenefitRow(benefit: "Delta Sky Club",        type: .lounge,       person: "Both",  notes: "10 visits/year (when flying Delta)"),
            BenefitRow(benefit: "Marriott Bonvoy Gold",  type: .hotelStatus,  person: "Both",  notes: "Enroll via MyBenefits portal"),
            BenefitRow(benefit: "Hilton Honors Gold",    type: .hotelStatus,  person: "Both",  notes: "Enroll via MyBenefits portal"),
            BenefitRow(benefit: "Hertz Gold Plus",       type: .rentalStatus, person: "Both",  notes: "Gold status with Hertz"),
            BenefitRow(benefit: "Avis Preferred Plus",   type: .rentalStatus, person: "Both",  notes: "Preferred Plus with Avis"),
        ]),
        CardGroup(cardName: "Venture X", cardColorHex: "#A78BFA", benefits: [
            BenefitRow(benefit: "Capital One Lounge",    type: .lounge,       person: "Elisa", notes: "Free access + 2 guest passes/year"),
            BenefitRow(benefit: "Plaza Premium Lounge",  type: .lounge,       person: "Elisa", notes: "Via Capital One partnership"),
            BenefitRow(benefit: "Priority Pass",         type: .lounge,       person: "Elisa", notes: "Unlimited access"),
            BenefitRow(benefit: "Hertz President's Circle", type: .rentalStatus, person: "Elisa", notes: "Enroll via Capital One portal"),
            BenefitRow(benefit: "Wyndham Diamond",       type: .hotelStatus,  person: "Elisa", notes: "Wyndham Diamond status"),
        ]),
        CardGroup(cardName: "Bilt Palladium", cardColorHex: "#34D399", benefits: [
            BenefitRow(benefit: "Hyatt Discoverist",     type: .hotelStatus,  person: "Cathy", notes: "World of Hyatt Discoverist status"),
            BenefitRow(benefit: "IHG Platinum Elite",    type: .hotelStatus,  person: "Cathy", notes: "IHG One Rewards Platinum Elite"),
        ]),
    ]

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            List {
                ForEach(groups, id: \.cardName) { group in
                    Section {
                        ForEach(group.benefits, id: \.benefit) { b in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(b.benefit)
                                        .font(.system(size: 14, weight: .medium, design: .serif))
                                        .foregroundStyle(Color.sunText)
                                    Text(b.notes)
                                        .font(.system(size: 12, design: .serif))
                                        .foregroundStyle(Color.sunSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    CategoryChip(label: b.type.rawValue, colorHex: b.type.colorHex)
                                    Text(b.person)
                                        .font(.system(size: 11, design: .serif))
                                        .foregroundStyle(Color.sunSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.sunSurface)
                        }
                    } header: {
                        Text(group.cardName)
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(Color(hex: group.cardColorHex))
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Benefits & Status")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.sunSurface, for: .navigationBar)
    }
}

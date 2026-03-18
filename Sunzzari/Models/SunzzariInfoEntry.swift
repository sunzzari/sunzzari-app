import Foundation

struct SunzzariInfoEntry: Identifiable {
    let id: String
    let title: String
    let category: Category
    let tags: [String]

    enum Category: String, CaseIterable {
        case addresses = "Addresses"
        case contacts  = "Contacts"
        case finance   = "Finance"
        case health    = "Health"
        case travel    = "Travel"
        case other     = "Other"

        var icon: String {
            switch self {
            case .addresses: return "mappin.circle.fill"
            case .contacts:  return "person.circle.fill"
            case .finance:   return "dollarsign.circle.fill"
            case .health:    return "heart.circle.fill"
            case .travel:    return "airplane.circle.fill"
            case .other:     return "square.grid.2x2.fill"
            }
        }

        var color: String {
            switch self {
            case .addresses: return "#60A5FA"
            case .contacts:  return "#34D399"
            case .finance:   return "#FBBF24"
            case .health:    return "#F87171"
            case .travel:    return "#FB923C"
            case .other:     return "#A78BFA"
            }
        }
    }
}

enum InfoBlock {
    case heading2(String)
    case heading3(String)
    case bullet(text: String, url: String?)
    case tableGrid(rows: [[String]])
    case paragraph(String)
}

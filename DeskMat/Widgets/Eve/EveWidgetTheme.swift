import SwiftUI

enum EveWidgetTheme: String, CaseIterable {
    case auto
    case amarr
    case caldari
    case gallente
    case minmatar
    case nullSec
}

extension EveWidgetTheme {
    var color: Color? {
        switch self {
        case .auto:     return nil
        case .amarr:    return Color(red: 150/255, green: 118/255, blue:  68/255, opacity: 0.90) // dark gold
        case .caldari:  return Color(red:  38/255, green:  88/255, blue: 135/255, opacity: 0.90) // dark steel blue
        case .gallente: return Color(red:  44/255, green: 108/255, blue:  90/255, opacity: 0.90) // dark teal
        case .minmatar: return Color(red: 125/255, green:  38/255, blue:  38/255, opacity: 0.90) // dark red
        case .nullSec:  return Color(red:  48/255, green:  40/255, blue:  68/255, opacity: 0.90) // dark void purple
        }
    }

    var labelTint: Color {
        switch self {
        case .auto:     return .white
        case .amarr:    return Color(red: 1.00, green: 0.97, blue: 0.90) // warm ivory
        case .caldari:  return Color(red: 0.88, green: 0.93, blue: 1.00) // cool blue-white
        case .gallente: return Color(red: 0.88, green: 0.96, blue: 0.94) // pale teal-white
        case .minmatar: return Color(red: 1.00, green: 0.91, blue: 0.91) // faint rose-white
        case .nullSec:  return Color(red: 0.90, green: 0.88, blue: 1.00) // pale lavender-white
        }
    }

    static func from(factionId: Int?) -> EveWidgetTheme {
        switch factionId {
        case nil:    return .auto      // not in sovereignty map (WH, or highsec outside FW)
        case 500001: return .caldari
        case 500002: return .minmatar
        case 500003: return .amarr
        case 500004: return .gallente
        default:     return .nullSec   // in sov map but no empire faction (null sec, pirate NPC)
        }
    }

    static func from(raceId: Int?) -> EveWidgetTheme {
        switch raceId {
        case 1: return .caldari
        case 2: return .minmatar
        case 4: return .amarr
        case 8: return .gallente
        default: return .auto
        }
    }

    var displayName: String {
        switch self {
        case .auto:     return "Auto"
        case .amarr:    return "Amarr"
        case .caldari:  return "Caldari"
        case .gallente: return "Gallente"
        case .minmatar: return "Minmatar"
        case .nullSec:  return "Null Sec"
        }
    }
}

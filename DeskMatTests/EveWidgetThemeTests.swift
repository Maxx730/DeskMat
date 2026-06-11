import Testing
import Foundation
@testable import DeskMat

// MARK: - Enum structure

struct EveWidgetThemeEnumTests {

    @Test func allCasesContainsSixCases() {
        #expect(EveWidgetTheme.allCases.count == 6)
    }

    @Test func rawValuesAreStable() {
        #expect(EveWidgetTheme.auto.rawValue     == "auto")
        #expect(EveWidgetTheme.amarr.rawValue    == "amarr")
        #expect(EveWidgetTheme.caldari.rawValue  == "caldari")
        #expect(EveWidgetTheme.gallente.rawValue == "gallente")
        #expect(EveWidgetTheme.minmatar.rawValue == "minmatar")
        #expect(EveWidgetTheme.nullSec.rawValue  == "nullSec")
    }

    @Test func displayNames() {
        #expect(EveWidgetTheme.auto.displayName     == "Auto")
        #expect(EveWidgetTheme.amarr.displayName    == "Amarr")
        #expect(EveWidgetTheme.caldari.displayName  == "Caldari")
        #expect(EveWidgetTheme.gallente.displayName == "Gallente")
        #expect(EveWidgetTheme.minmatar.displayName == "Minmatar")
        #expect(EveWidgetTheme.nullSec.displayName  == "Null Sec")
    }

    @Test func autoHasNilColor() {
        #expect(EveWidgetTheme.auto.color == nil)
    }

    @Test func allNonAutoThemesHaveColor() {
        let nonAuto = EveWidgetTheme.allCases.filter { $0 != .auto }
        for theme in nonAuto {
            #expect(theme.color != nil, "Expected non-nil color for \(theme)")
        }
    }
}

// MARK: - from(factionId:) — empire systems

struct EveWidgetThemeFromFactionIdTests {

    @Test func nilFactionReturnsAuto() {
        #expect(EveWidgetTheme.from(factionId: nil) == .auto)
    }

    @Test func caldariStateId() {
        #expect(EveWidgetTheme.from(factionId: 500001) == .caldari)
    }

    @Test func minmatarRepublicId() {
        #expect(EveWidgetTheme.from(factionId: 500002) == .minmatar)
    }

    @Test func amarrEmpireId() {
        #expect(EveWidgetTheme.from(factionId: 500003) == .amarr)
    }

    @Test func gallenteId() {
        #expect(EveWidgetTheme.from(factionId: 500004) == .gallente)
    }

    // Null sec: in sovereignty map but no empire faction (stored as 0 sentinel)
    @Test func zeroSentinelReturnsNullSec() {
        #expect(EveWidgetTheme.from(factionId: 0) == .nullSec)
    }

    // Pirate / NPC null factions are in the sov map with a non-empire faction_id
    @Test func unknownFactionIdReturnsNullSec() {
        #expect(EveWidgetTheme.from(factionId: 500010) == .nullSec)
        #expect(EveWidgetTheme.from(factionId: 999999) == .nullSec)
        #expect(EveWidgetTheme.from(factionId: 1)      == .nullSec)
    }
}

// MARK: - from(raceId:) — ship / character race fallback

struct EveWidgetThemeFromRaceIdTests {

    @Test func nilRaceReturnsAuto() {
        #expect(EveWidgetTheme.from(raceId: nil) == .auto)
    }

    @Test func caldariRaceId() {
        #expect(EveWidgetTheme.from(raceId: 1) == .caldari)
    }

    @Test func minmatarRaceId() {
        #expect(EveWidgetTheme.from(raceId: 2) == .minmatar)
    }

    @Test func amarrRaceId() {
        #expect(EveWidgetTheme.from(raceId: 4) == .amarr)
    }

    @Test func gallenteRaceId() {
        #expect(EveWidgetTheme.from(raceId: 8) == .gallente)
    }

    @Test func unknownRaceIdReturnsAuto() {
        #expect(EveWidgetTheme.from(raceId: 0)   == .auto)
        #expect(EveWidgetTheme.from(raceId: 99)  == .auto)
        #expect(EveWidgetTheme.from(raceId: -1)  == .auto)
    }
}

// MARK: - Resolution priority (factionId takes precedence over raceId)

struct EveWidgetThemeResolutionTests {

    @Test func factionIdOverridesWhenBothPresent() {
        // If the system is Caldari space but the ship is Amarr race,
        // the faction lookup wins.
        let bySystem = EveWidgetTheme.from(factionId: 500001) // caldari
        let byShip   = EveWidgetTheme.from(raceId: 4)        // amarr
        #expect(bySystem == .caldari)
        #expect(byShip   == .amarr)
        // Caller picks bySystem first — only falls through when bySystem == .auto
        let effective = bySystem != .auto ? bySystem : byShip
        #expect(effective == .caldari)
    }

    @Test func nullFactionFallsThroughToRace() {
        // System not in sov map (WH / highsec outside FW) → nil → .auto → use race
        let bySystem = EveWidgetTheme.from(factionId: nil)  // .auto
        let byShip   = EveWidgetTheme.from(raceId: 8)      // gallente
        let effective = bySystem != .auto ? bySystem : byShip
        #expect(effective == .gallente)
    }

    @Test func nullSecSystemDoesNotFallThrough() {
        // Null sec system (sentinel 0) → .nullSec — race is ignored
        let bySystem = EveWidgetTheme.from(factionId: 0)  // .nullSec
        let byShip   = EveWidgetTheme.from(raceId: 4)    // amarr
        let effective = bySystem != .auto ? bySystem : byShip
        #expect(effective == .nullSec)
    }
}

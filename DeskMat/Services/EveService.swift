import Foundation
import OSLog

private let log = Logger(subsystem: "com.kinghorn.deskmat", category: "EveService")

// MARK: - ESI Decoder

private let esiDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

// MARK: - ESI Response Models

private struct OnlineResponse: Decodable {
    let online: Bool
}

private struct LocationResponse: Decodable {
    let solar_system_id: Int
}

private struct ShipResponse: Decodable {
    let ship_type_id: Int
}

private struct DogmaAttribute: Decodable {
    let attribute_id: Int
    let value: Double
}

private struct ShipTypeResponse: Decodable {
    let name: String
    let race_id: Int?
    let dogma_attributes: [DogmaAttribute]?

    var resolvedRaceId: Int? {
        if let r = race_id { return r }
        // Fallback: dogma attribute 1692 encodes raceID on ships where
        // the top-level race_id field is absent (e.g. Navy faction hulls)
        guard let attr = dogma_attributes?.first(where: { $0.attribute_id == 1692 }) else { return nil }
        return Int(attr.value)
    }
}

private struct SkillQueueItem: Decodable {
    let queue_position: Int
    let skill_id: Int
    let finished_level: Int
    let finish_date: Date?
}

private struct UniverseName: Decodable {
    let name: String
}

private struct CharacterInfoResponse: Decodable {
    let race_id: Int
}

private struct SovereigntyEntry: Decodable {
    let system_id: Int
    let faction_id: Int?
}

private struct SkillsResponse: Decodable {
    let total_sp: Int
    let unallocated_sp: Int?
}

private struct IndustryJob: Decodable {
    let status: String
}

// MARK: - EveService

@Observable
final class EveService {
    private(set) var isOnline:           Bool   = false
    private(set) var lastSeen:           Date?  = nil
    private(set) var locationName:       String = ""
    private(set) var shipName:           String = ""
    private(set) var walletFormatted:    String = ""
    private(set) var trainingSkill:      String = ""
    private(set) var trainingRemaining:  String = ""
    private(set) var shipRaceId:       Int?   = nil
    private(set) var characterRaceId:  Int?   = nil
    private(set) var systemFactionId:  Int?   = nil
    private(set) var totalSP:          String = ""
    private(set) var unallocatedSP:    String = ""
    private(set) var activeJobs:       Int    = 0
    private(set) var isLoading:        Bool   = false
    private(set) var isAuthFailed:     Bool   = false

    let auth: EveAuthService
    private let nameCacheLock = NSLock()
    private var nameCache: [Int: String] = [:]
    private var sovereigntyCache: [Int: Int] = [:]  // system_id → faction_id
    private var sovereigntyFetchedAt: Date?

    init(auth: EveAuthService) {
        self.auth = auth
    }

    // MARK: - Refresh

    func refresh() async {
        guard auth.isAuthenticated else { return }
        await MainActor.run { isLoading = true }

        guard let token = try? await auth.validAccessToken() else {
            await MainActor.run { isLoading = false; isAuthFailed = true }
            return
        }
        await MainActor.run { isAuthFailed = false }
        let id = auth.characterId

        async let onlineResult     = fetchOnline(id: id, token: token)
        async let locationResult   = fetchLocation(id: id, token: token)
        async let shipResult       = fetchShip(id: id, token: token)
        async let walletResult     = fetchWallet(id: id, token: token)
        async let skillResult      = fetchSkillQueue(id: id, token: token)
        async let characterResult  = fetchCharacterInfo(id: id, token: token)
        async let skillsResult     = fetchSkills(id: id, token: token)
        async let jobsResult       = fetchIndustryJobs(id: id, token: token)

        let onlineData      = await onlineResult
        let locationData    = await locationResult          // (name, systemId)
        let factionData     = await fetchSystemFaction(systemId: locationData.1)
        let shipData        = await shipResult
        let walletData      = await walletResult
        let skillData       = await skillResult
        let characterData   = await characterResult
        let skillsData      = await skillsResult
        let jobsData        = await jobsResult

        await MainActor.run {
            isOnline          = onlineData.0
            lastSeen          = onlineData.1
            locationName      = locationData.0
            systemFactionId   = factionData
            shipName          = shipData.0
            shipRaceId        = shipData.1
            characterRaceId   = characterData
            walletFormatted   = walletData
            trainingSkill     = skillData.0
            trainingRemaining = skillData.1
            totalSP           = skillsData.0
            unallocatedSP     = skillsData.1
            activeJobs        = jobsData
            isLoading         = false
        }
    }

    // MARK: - Fetchers

    private func fetchOnline(id: Int, token: String) async -> (Bool, Date?) {
        do {
            let data = try await esiRequest(path: "/characters/\(id)/online/", token: token)
            let r = try esiDecoder.decode(OnlineResponse.self, from: data)
            return (r.online, nil)
        } catch {
            log.warning("fetchOnline error: \(error.localizedDescription)")
            return (false, nil)
        }
    }

    private func fetchLocation(id: Int, token: String) async -> (String, Int) {
        do {
            let data = try await esiRequest(path: "/characters/\(id)/location/", token: token)
            let r = try esiDecoder.decode(LocationResponse.self, from: data)
            let name = await resolveName(id: r.solar_system_id, path: "/universe/systems/\(r.solar_system_id)/")
            return (name, r.solar_system_id)
        } catch {
            log.warning("fetchLocation: \(error.localizedDescription)")
            return ("", 0)
        }
    }

    private func fetchSystemFaction(systemId: Int) async -> Int? {
        guard systemId != 0 else { return nil }
        if !sovereigntyCache.isEmpty,
           let fetchedAt = sovereigntyFetchedAt,
           Date().timeIntervalSince(fetchedAt) < 3600 {
            return sovereigntyCache[systemId]
        }
        do {
            let data = try await esiRequest(path: "/sovereignty/map/")
            let entries = try esiDecoder.decode([SovereigntyEntry].self, from: data)
            sovereigntyCache = Dictionary(
                uniqueKeysWithValues: entries.map { e in
                    (e.system_id, e.faction_id ?? 0)
                }
            )
            sovereigntyFetchedAt = Date()
            return sovereigntyCache[systemId]
        } catch {
            log.warning("fetchSystemFaction: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchShip(id: Int, token: String) async -> (String, Int?) {
        do {
            let shipData = try await esiRequest(path: "/characters/\(id)/ship/", token: token)
            let ship = try esiDecoder.decode(ShipResponse.self, from: shipData)
            let typeData = try await esiRequest(path: "/universe/types/\(ship.ship_type_id)/")
            let type_ = try esiDecoder.decode(ShipTypeResponse.self, from: typeData)
            nameCacheLock.withLock { nameCache[ship.ship_type_id] = type_.name }
            return (type_.name, type_.resolvedRaceId)
        } catch {
            log.warning("fetchShip: \(error.localizedDescription)")
            return ("", nil)
        }
    }

    private func fetchCharacterInfo(id: Int, token: String) async -> Int? {
        do {
            let data = try await esiRequest(path: "/characters/\(id)/", token: token)
            let r = try esiDecoder.decode(CharacterInfoResponse.self, from: data)
            return r.race_id
        } catch {
            log.warning("fetchCharacterInfo: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchWallet(id: Int, token: String) async -> String {
        do {
            let data = try await esiRequest(path: "/characters/\(id)/wallet/", token: token)
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let balance = Double(raw) else { return "" }
            return formatISK(balance)
        } catch {
            log.warning("fetchWallet: \(error.localizedDescription)")
            return ""
        }
    }

    private func fetchSkillQueue(id: Int, token: String) async -> (String, String) {
        do {
            let data = try await esiRequest(path: "/characters/\(id)/skillqueue/", token: token)
            let queue = try esiDecoder.decode([SkillQueueItem].self, from: data)
            guard let active = queue.first(where: { $0.queue_position == 0 }),
                  let finishDate = active.finish_date,
                  finishDate > Date() else { return ("", "") }
            let name = await resolveName(id: active.skill_id, path: "/universe/types/\(active.skill_id)/")
            return ("\(name) \(romanNumeral(active.finished_level))", formatTimeRemaining(until: finishDate))
        } catch {
            log.warning("fetchSkillQueue: \(error.localizedDescription)")
            return ("", "")
        }
    }

    private func fetchSkills(id: Int, token: String) async -> (String, String) {
        do {
            let data = try await esiRequest(path: "/characters/\(id)/skills/", token: token)
            let r = try esiDecoder.decode(SkillsResponse.self, from: data)
            let total = formatSP(r.total_sp)
            let unalloc = r.unallocated_sp.map { $0 > 0 ? "+\(formatSP($0))" : "" } ?? ""
            return (total, unalloc)
        } catch {
            log.warning("fetchSkills: \(error.localizedDescription)")
            return ("", "")
        }
    }

    private func fetchIndustryJobs(id: Int, token: String) async -> Int {
        do {
            let data = try await esiRequest(path: "/characters/\(id)/industry/jobs/?include_completed=false", token: token)
            let jobs = try esiDecoder.decode([IndustryJob].self, from: data)
            return jobs.filter { $0.status == "active" }.count
        } catch {
            log.warning("fetchIndustryJobs: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Universe Name Resolution

    private func resolveName(id: Int, path: String) async -> String {
        if let cached = nameCacheLock.withLock({ nameCache[id] }) { return cached }
        guard let data = try? await esiRequest(path: path),
              let info = try? esiDecoder.decode(UniverseName.self, from: data) else { return "Unknown" }
        nameCacheLock.withLock { nameCache[id] = info.name }
        return info.name
    }

    // MARK: - Formatting

    private func formatSP(_ sp: Int) -> String {
        switch sp {
        case 1_000_000...: return String(format: "%.1fM SP", Double(sp) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK SP", Double(sp) / 1_000)
        default:           return "\(sp) SP"
        }
    }

    private func formatISK(_ balance: Double) -> String {
        switch balance {
        case 1_000_000_000...: return String(format: "%.1fB ISK", balance / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fM ISK", balance / 1_000_000)
        case 1_000...:         return String(format: "%.1fK ISK", balance / 1_000)
        default:               return String(format: "%.0f ISK", balance)
        }
    }

    private func formatTimeRemaining(until date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let days  = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let mins  = (seconds % 3600) / 60
        if days > 0  { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private func romanNumeral(_ level: Int) -> String {
        let numerals = ["", "I", "II", "III", "IV", "V"]
        return level < numerals.count ? numerals[level] : "\(level)"
    }

    // MARK: - ESI Request

    private func esiRequest(path: String, token: String? = nil) async throws -> Data {
        let url = URL(string: "https://esi.evetech.net/latest\(path)")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("DeskMat/1.0 (max.kinghorn@gmail.com)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

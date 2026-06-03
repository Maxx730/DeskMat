import Foundation

struct AppFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var shortcuts: [AppShortcut]
    var iconFileName: String?

    init(name: String, shortcuts: [AppShortcut] = [], iconFileName: String? = nil) {
        self.id = UUID()
        self.name = name
        self.shortcuts = shortcuts
        self.iconFileName = iconFileName
    }
}

enum DockItem: Identifiable, Codable, Equatable {
    case shortcut(AppShortcut)
    case folder(AppFolder)

    var id: UUID {
        switch self {
        case .shortcut(let s): return s.id
        case .folder(let f):   return f.id
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum ItemType: String, Codable {
        case shortcut, folder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .shortcut:
            self = .shortcut(try container.decode(AppShortcut.self, forKey: .value))
        case .folder:
            self = .folder(try container.decode(AppFolder.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shortcut(let shortcut):
            try container.encode(ItemType.shortcut, forKey: .type)
            try container.encode(shortcut, forKey: .value)
        case .folder(let folder):
            try container.encode(ItemType.folder, forKey: .type)
            try container.encode(folder, forKey: .value)
        }
    }
}

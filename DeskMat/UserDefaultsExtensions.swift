import Foundation

extension UserDefaults {
    @objc dynamic var dockPosition: String {
        return string(forKey: "dockPosition") ?? "Bottom"
    }
    @objc dynamic var dockOffset: Int {
        return integer(forKey: "dockOffset")
    }
    @objc dynamic var appearanceMode: String {
        return string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
    }
}

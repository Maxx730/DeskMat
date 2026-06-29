import Foundation
import Observation
import SwiftUI

struct TaskItem: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var description: String = ""
    var isDone: Bool = false
}

@Observable
final class TasksStore {
    private static let defaultsKey = "tasksWidgetData"

    var tasks: [TaskItem] = []

    init() { load() }

    func add(title: String, description: String = "") {
        tasks.append(TaskItem(title: title, description: description))
        save()
    }

    func toggle(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i].isDone.toggle()
        save()
    }

    func delete(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) else { return }
        tasks = decoded
    }
}

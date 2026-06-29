import Testing
import Foundation
@testable import DeskMat

// MARK: - TaskItem pure struct tests (no UserDefaults)

@Suite struct TaskItemTests {

    @Test func defaultIsDoneIsFalse() {
        let item = TaskItem(title: "Buy milk")
        #expect(item.isDone == false)
    }

    @Test func defaultDescriptionIsEmpty() {
        let item = TaskItem(title: "Buy milk")
        #expect(item.description == "")
    }

    @Test func eachItemHasUniqueID() {
        let a = TaskItem(title: "Task A")
        let b = TaskItem(title: "Task A")
        #expect(a.id != b.id)
    }

    @Test func codableRoundTrip() throws {
        let original = TaskItem(title: "Hello")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.description == original.description)
        #expect(decoded.isDone == original.isDone)
    }

    @Test func codableRoundTripWithDescription() throws {
        var original = TaskItem(title: "Hello")
        original.description = "A detailed description"
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
        #expect(decoded.description == "A detailed description")
    }

    @Test func codableRoundTripIsDoneTrue() throws {
        var original = TaskItem(title: "Done task")
        original.isDone = true
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
        #expect(decoded.isDone == true)
    }
}

// MARK: - TasksStore (saves/restores UserDefaults around each test)

@Suite(.serialized) struct TasksStoreTests {
    private static let key = "tasksWidgetData"

    private func saveOriginal() -> Data? {
        UserDefaults.standard.data(forKey: Self.key)
    }

    private func restore(_ original: Data?) {
        if let data = original {
            UserDefaults.standard.set(data, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }

    @Test func startsEmptyWithNoPersistedData() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store = TasksStore()
        #expect(store.tasks.isEmpty)
    }

    @Test func addAppendsTask() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store = TasksStore()
        store.add(title: "Write tests")
        #expect(store.tasks.count == 1)
        #expect(store.tasks[0].title == "Write tests")
    }

    @Test func addWithDescriptionStoresDescription() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store = TasksStore()
        store.add(title: "Task", description: "Details here")
        #expect(store.tasks[0].description == "Details here")
    }

    @Test func addMultipleTasks() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store = TasksStore()
        store.add(title: "First")
        store.add(title: "Second")
        store.add(title: "Third")
        #expect(store.tasks.count == 3)
        #expect(store.tasks[0].title == "First")
        #expect(store.tasks[1].title == "Second")
        #expect(store.tasks[2].title == "Third")
    }

    @Test func toggleFlipsDoneState() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store = TasksStore()
        store.add(title: "Flip me")
        store.toggle(store.tasks[0])
        #expect(store.tasks[0].isDone == true)
    }

    @Test func toggleIdempotentOnDoubleCall() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store = TasksStore()
        store.add(title: "Toggle twice")
        store.toggle(store.tasks[0])
        store.toggle(store.tasks[0])
        #expect(store.tasks[0].isDone == false)
    }

    @Test func toggleIgnoresUnknownID() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store = TasksStore()
        store.add(title: "Real task")
        let ghost = TaskItem(title: "Ghost")
        store.toggle(ghost)
        #expect(store.tasks.count == 1)
        #expect(store.tasks[0].isDone == false)
    }

    @Test func deleteRemovesAtIndex() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store = TasksStore()
        store.add(title: "Keep me")
        store.add(title: "Delete me")
        store.delete(at: [1])
        #expect(store.tasks.count == 1)
        #expect(store.tasks[0].title == "Keep me")
    }

    @Test func deleteAllLeavesEmpty() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store = TasksStore()
        store.add(title: "First")
        store.add(title: "Second")
        store.delete(at: [0, 1])
        #expect(store.tasks.isEmpty)
    }

    @Test func persistenceRoundTrip() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store1 = TasksStore()
        store1.add(title: "Task 1")
        store1.add(title: "Task 2")
        let store2 = TasksStore()
        #expect(store2.tasks.count == 2)
        #expect(store2.tasks[0].title == "Task 1")
        #expect(store2.tasks[1].title == "Task 2")
    }

    @Test func togglePersists() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store1 = TasksStore()
        store1.add(title: "Toggle me")
        store1.toggle(store1.tasks[0])
        let store2 = TasksStore()
        #expect(store2.tasks[0].isDone == true)
    }

    @Test func deletePersists() {
        let original = saveOriginal()
        defer { restore(original) }
        UserDefaults.standard.removeObject(forKey: Self.key)
        let store1 = TasksStore()
        store1.add(title: "Delete me")
        store1.add(title: "Keep me")
        store1.delete(at: [0])
        let store2 = TasksStore()
        #expect(store2.tasks.count == 1)
        #expect(store2.tasks[0].title == "Keep me")
    }
}

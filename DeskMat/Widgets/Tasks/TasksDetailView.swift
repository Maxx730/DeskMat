import SwiftUI

struct TasksDetailView: View {
    let store: TasksStore
    @State private var newTaskTitle = ""
    @State private var newTaskDescription = ""
    @State private var isAddingTask = false

    private enum TaskField { case title, description }
    @FocusState private var focusedField: TaskField?

    var body: some View {
        VStack(spacing: 0) {
            if store.tasks.isEmpty && !isAddingTask {
                Text("No tasks yet")
                    .font(.custom("Marker Felt Thin", size: 13))
                    .foregroundStyle(.black.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.tasks.filter { !$0.isDone }) { task in
                        TaskRow(task: task, onToggle: { store.toggle(task) })
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onDelete { store.delete(at: $0) }

                    if isAddingTask {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                TextField("New task", text: $newTaskTitle)
                                    .font(.custom("Marker Felt Thin", size: 16))
                                    .foregroundStyle(.black.opacity(0.8))
                                    .focused($focusedField, equals: .title)
                                    .onSubmit { focusedField = .description }
                            }
                            HStack(spacing: 8) {
                                Color.clear.frame(width: 22)
                                TextField("Description", text: $newTaskDescription)
                                    .font(.custom("Marker Felt Thin", size: 13))
                                    .foregroundStyle(.black.opacity(0.5))
                                    .focused($focusedField, equals: .description)
                                    .onSubmit { commitNewTask() }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)  // tint comes from parent VStack
            }

            HStack {
                Button {
                    isAddingTask = true
                    focusedField = .title
                } label: {
                    Label("", systemImage: "plus")
                        .font(.custom("Marker Felt Thin", size: 13))
                        .foregroundStyle(.black.opacity(0.45))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(width: 260, height: 300)
    }

    private func commitNewTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            store.add(title: trimmed, description: newTaskDescription.trimmingCharacters(in: .whitespaces))
        }
        newTaskTitle = ""
        newTaskDescription = ""
        isAddingTask = false
        focusedField = nil
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.custom("Marker Felt Thin", size: 16))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Color.black.opacity(0.3) : Color.black.opacity(0.8))

                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.custom("Marker Felt Thin", size: 13))
                        .foregroundStyle(.black.opacity(0.45))
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

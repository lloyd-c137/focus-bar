import SwiftData
import SwiftUI

struct TodayPanel: View {
  @AppStorage("showCompleted") private var showCompleted = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(TaskStore.self) private var store
  @State private var selected = LocalDay(.now)
  @State private var editor: TaskEditorRoute?
  @State private var deleting: VisibleTask?
  @State private var showDeleteConfirmation = false
  @State private var deleteSeries = false
  @State private var showCompletedRows = false

  private var today: LocalDay { LocalDay(.now) }
  private var items: [VisibleTask] { store.tasks(on: selected, today: today) }
  private var sections:
    (
      overdue: [VisibleTask], scheduled: [VisibleTask], anytime: [VisibleTask],
      completed: [VisibleTask]
    )
  {
    daySections(tasks: items, selected: selected, today: today)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if !sections.overdue.isEmpty {
            taskSection(String(localized: "Overdue"), tasks: sections.overdue)
          }
          if !sections.scheduled.isEmpty {
            taskSection(nil, tasks: sections.scheduled, showTimes: true)
          }
          if !sections.anytime.isEmpty {
            taskSection(String(localized: "Anytime"), tasks: sections.anytime)
          }
          if showCompleted && !sections.completed.isEmpty {
            Button {
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                showCompletedRows.toggle()
              }
            } label: {
              Label(
                "\(String(localized: "Completed")) (\(sections.completed.count))",
                systemImage: showCompletedRows ? "chevron.down" : "chevron.right"
              )
              .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
            if showCompletedRows { taskSection(nil, tasks: sections.completed) }
          }
          if items.isEmpty
            || (sections.overdue.isEmpty && sections.scheduled.isEmpty && sections.anytime.isEmpty
              && !sections.completed.isEmpty && !showCompleted)
          {
            emptyState
          }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
      }
      .scrollIndicators(.visible)
      Divider()
      HStack {
        Button {
          editor = .new(selected)
        } label: {
          Label("Add a task", systemImage: "plus")
        }
        .buttonStyle(.plain).font(.system(size: 13, weight: .medium))
        .keyboardShortcut("n", modifiers: .command)
        Spacer()
        SettingsLink { Image(systemName: "gearshape") }
          .labelStyle(.iconOnly).buttonStyle(.plain).help(String(localized: "Settings…"))
        Menu {
          Button(String(localized: "Quit Focus Bar"), systemImage: "power") { NSApp.terminate(nil) }
        } label: {
          Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton).fixedSize().help(String(localized: "More"))
      }.padding(.horizontal, 16).padding(.vertical, 12)
    }
    .frame(width: 360, height: 500)
    .background(.regularMaterial)
    .sheet(item: $editor) { route in
      switch route {
      case .new(let day): TaskEditor(day: day) { draft in store.save(draft) }
      case .edit(let item):
        TaskEditor(day: item.day, item: item) { draft in store.save(draft, editing: item) }
      }
    }
    .confirmationDialog(
      String(localized: "Delete task?"), isPresented: $showDeleteConfirmation,
      titleVisibility: .visible, presenting: deleting
    ) { item in
      Button(String(localized: deleteSeries ? "Delete Series" : "Delete"), role: .destructive) {
        if deleteSeries { store.deleteSeries(item) } else { store.delete(item) }
        deleteSeries = false
      }
      Button(String(localized: "Cancel"), role: .cancel) { deleteSeries = false }
    } message: { _ in
      Text(String(localized: "This cannot be undone."))
    }
    .alert(
      String(localized: "Unable to save. Try again."),
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    ) {
      Button(String(localized: "Close"), role: .cancel) { store.error = nil }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      store.refreshBadge()
      if selected == today { selected = LocalDay(.now) }
    }
  }

  private var selectedTitle: String {
    if selected == today { return String(localized: "Today") }
    if selected == today.addingDays(1) { return String(localized: "Tomorrow") }
    return selected.date.formatted(date: .abbreviated, time: .omitted)
  }

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 3) {
        Button {
          selected = today
        } label: {
          Text(selectedTitle)
            .font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.primary)
        }.buttonStyle(.plain)
        Text(selected.date.formatted(date: .complete, time: .omitted))
          .font(.system(size: 12)).foregroundStyle(.secondary)
      }
      Spacer()
      Menu {
        Button(String(localized: "Today")) { selected = today }
        Button(String(localized: "Tomorrow")) { selected = today.addingDays(1) }
        Divider()
        DatePicker(
          String(localized: "Choose a date"),
          selection: Binding(get: { selected.date }, set: { selected = LocalDay($0) }),
          displayedComponents: .date)
      } label: {
        Image(systemName: "calendar").font(.system(size: 14, weight: .medium)).frame(
          width: 30, height: 30
        ).contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton).fixedSize().help(String(localized: "Choose a date"))
    }
    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      if !sections.completed.isEmpty {
        Text(String(localized: "All done for this day."))
          .font(.system(size: 13)).foregroundStyle(.secondary)
      } else {
        Text(
          selected == today
            ? String(localized: "Nothing scheduled for today.")
            : String(localized: "No items for this day.")
        )
        .font(.system(size: 13)).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity).padding(.vertical, 48)
  }

  @ViewBuilder private func taskSection(
    _ title: String?, tasks: [VisibleTask], showTimes: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title {
        Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.7)
          .foregroundStyle(.tertiary)
      }
      ForEach(tasks) { item in
        TaskRow(item: item, showTime: showTimes, onToggle: { store.toggle(item) })
          .contextMenu {
            Button(String(localized: "Edit")) { editor = .edit(item) }
            Button(String(localized: "Move to Tomorrow")) {
              store.moveToTomorrow(item, today: today)
            }
            Button(String(localized: "Change Date")) { editor = .edit(item) }
            Divider()
            if item.isRecurring {
              Button(String(localized: "Delete This Occurrence"), role: .destructive) {
                deleting = item
                deleteSeries = false
                showDeleteConfirmation = true
              }
              Button(String(localized: "Delete Series"), role: .destructive) {
                deleting = item
                deleteSeries = true
                showDeleteConfirmation = true
              }
            } else {
              Button(String(localized: "Delete"), role: .destructive) {
                deleting = item
                deleteSeries = false
                showDeleteConfirmation = true
              }
            }
          }
      }
    }
  }
}

private struct TaskRow: View {
  let item: VisibleTask
  let showTime: Bool
  let onToggle: () -> Void
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 9) {
      Button(action: onToggle) {
        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 17)).foregroundStyle(
            item.completed ? Color.accentColor : Color.secondary
          )
          .frame(width: 22, height: 26)
      }.buttonStyle(.plain).accessibilityLabel(
        item.completed ? "Reopen \(item.title)" : "Complete \(item.title)")
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title).font(.system(size: 13)).foregroundStyle(
          item.completed ? .secondary : .primary
        )
        .strikethrough(item.completed).lineLimit(2).textSelection(.enabled)
        if item.overdue {
          Text(item.day.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2)
            .foregroundStyle(.secondary)
        } else if showTime, let minute = item.minuteOfDay {
          Text(formatMinuteOfDay(minute)).font(.caption).foregroundStyle(.secondary)
        }
        if !item.notes.isEmpty {
          Text(item.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
      }
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
  }
}

private struct TaskEditor: View {
  @Environment(\.dismiss) private var dismiss
  @FocusState private var titleFocused: Bool
  @State private var draft: TaskDraft
  @State private var saveFailed = false
  private let item: VisibleTask?
  private let onSave: (TaskDraft) -> Bool

  init(day: LocalDay, item: VisibleTask? = nil, onSave: @escaping (TaskDraft) -> Bool) {
    self.item = item
    self.onSave = onSave
    _draft = State(
      initialValue: TaskDraft(
        title: item?.title ?? "", notes: item?.notes ?? "", day: item?.day ?? day,
        minuteOfDay: item?.minuteOfDay, frequency: .never))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      TextField(String(localized: "Task title"), text: $draft.title)
        .textFieldStyle(.plain).font(.system(size: 16, weight: .medium)).focused($titleFocused)
        .onSubmit(save)
      if saveFailed {
        Text(String(localized: "Unable to save. Try again.")).font(.caption).foregroundStyle(.red)
      }
      DisclosureGroup(String(localized: "Details")) {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
          GridRow {
            Text(String(localized: "Date"))
            DatePicker(
              String(localized: "Date"),
              selection: Binding(get: { draft.day.date }, set: { draft.day = LocalDay($0) }),
              displayedComponents: .date
            ).labelsHidden()
          }
          GridRow {
            Text(String(localized: "Time"))
            DatePicker(
              String(localized: "Time"),
              selection: Binding(
                get: { timeDate },
                set: {
                  let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                  draft.minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                }), displayedComponents: .hourAndMinute
            ).labelsHidden()
            Button {
              draft.minuteOfDay = nil
            } label: {
              Image(systemName: "xmark.circle")
            }.buttonStyle(.plain).help(String(localized: "Anytime"))
          }
          if item == nil {
            GridRow {
              Text(String(localized: "Repeat"))
              Picker(String(localized: "Repeat"), selection: $draft.frequency) {
                ForEach(TaskFrequency.allCases) { Text($0.label).tag($0) }
              }.labelsHidden()
            }
          }
          GridRow {
            Text(String(localized: "Notes"))
            TextField(String(localized: "Notes"), text: $draft.notes, axis: .vertical).lineLimit(
              2...4
            ).textFieldStyle(.roundedBorder)
          }
        }.font(.system(size: 12)).padding(.top, 8)
      }
      HStack {
        Spacer()
        Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
        Button(String(localized: "Save"), action: save).keyboardShortcut(.defaultAction).disabled(
          draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(18).frame(width: 340).onAppear { titleFocused = true }
  }

  private var timeDate: Date {
    Calendar.current.date(
      bySettingHour: (draft.minuteOfDay ?? 9 * 60) / 60, minute: (draft.minuteOfDay ?? 9 * 60) % 60,
      second: 0, of: draft.day.date) ?? draft.day.date
  }
  private func save() {
    guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    if onSave(draft) { dismiss() } else { saveFailed = true }
  }
}

private enum TaskEditorRoute: Identifiable {
  case new(LocalDay)
  case edit(VisibleTask)
  var id: String {
    switch self {
    case .new(let day): "new-\(day.key)"
    case .edit(let item): "edit-\(item.id)"
    }
  }
}

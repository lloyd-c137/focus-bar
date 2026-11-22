import AppKit
import SwiftData
import SwiftUI

struct TodayPanel: View {
  @AppStorage("showCompleted") private var showCompleted = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(TaskStore.self) private var store
  @Environment(CalendarState.self) private var calendarState
  @FocusState private var quickAddFocused: Bool
  @State private var navigation = DateNavigationState()
  @State private var editor: VisibleTask?
  @State private var quickAddActive = false
  @State private var isSubmittingQuickAdd = false
  @State private var quickDraft = TaskDraft(day: LocalDay(.now))
  @State private var quickDetailsExpanded = false
  @State private var quickAddFailed = false
  @State private var panelHeight: CGFloat = 520
  @State private var deleting: VisibleTask?
  @State private var showDeleteConfirmation = false
  @State private var deleteSeries = false
  @State private var showCompletedRows = false

  private var today: LocalDay { calendarState.dateContext.today }
  private var selected: LocalDay { navigation.displayedDay(today: today) }
  private func select(_ day: LocalDay) {
    navigation.select(day, today: today)
  }

  private var quickAddText: Binding<String> {
    Binding(
      get: { quickDraft.title },
      set: {
        quickDraft.title = $0
        quickAddFailed = false
      })
  }

  private var quickTimeDate: Date {
    let minute = quickDraft.minuteOfDay ?? 9 * 60
    return Calendar.current.date(
      bySettingHour: minute / 60, minute: minute % 60, second: 0, of: quickDraft.day.date)
      ?? quickDraft.day.date
  }

  private func beginQuickAdd() {
    quickDraft = TaskDraft(day: selected)
    isSubmittingQuickAdd = false
    quickDetailsExpanded = false
    quickAddFailed = false
    quickAddActive = true
  }

  private func submitQuickAdd(_ title: String) -> Bool {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    quickDraft.title = title
    if store.save(quickDraft) {
      quickAddFailed = false
      quickAddActive = false
      return true
    }
    quickAddFailed = true
    store.clearError()
    return false
  }

  private func cancelQuickAdd() {
    quickDraft = TaskDraft(day: selected)
    isSubmittingQuickAdd = false
    quickDetailsExpanded = false
    quickAddFailed = false
    quickAddActive = false
  }

  var body: some View {
    let sections = daySections(
      tasks: store.tasks(on: selected, today: today), selected: selected, today: today)
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
          if sections.overdue.isEmpty && sections.scheduled.isEmpty && sections.anytime.isEmpty
            && (!showCompleted || sections.completed.isEmpty)
          {
            emptyState(sections: sections, selected: selected, today: today)
          }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
      }
      .scrollIndicators(.visible)
      .frame(maxHeight: max(80, panelHeight - quickAddHeightReservation))
      Divider()
      if quickAddActive {
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            TextField(String(localized: "Task title"), text: quickAddText)
              .textFieldStyle(.plain).font(.body).focused($quickAddFocused)
              .onSubmit {
                let hasMarkedText =
                  (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
                guard
                  canSubmitQuickAdd(
                    title: quickDraft.title, hasMarkedText: hasMarkedText,
                    isSubmitting: isSubmittingQuickAdd)
                else { return }
                isSubmittingQuickAdd = true
                if !submitQuickAdd(quickDraft.title) { isSubmittingQuickAdd = false }
              }
              .onExitCommand(perform: cancelQuickAdd)
              .onAppear { quickAddFocused = true }
              .frame(maxWidth: .infinity, minHeight: 28)
            Button(String(localized: "Cancel"), systemImage: "xmark") { cancelQuickAdd() }
              .labelStyle(.iconOnly).buttonStyle(.plain).help(String(localized: "Cancel"))
          }
          DisclosureGroup(String(localized: "Details"), isExpanded: $quickDetailsExpanded) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
              GridRow {
                Text(String(localized: "Date"))
                DatePicker(
                  String(localized: "Date"),
                  selection: Binding(
                    get: { quickDraft.day.date }, set: { quickDraft.day = LocalDay($0) }),
                  displayedComponents: .date
                ).labelsHidden()
              }
              GridRow {
                Text(String(localized: "Time"))
                HStack(spacing: 8) {
                  Toggle(
                    String(localized: "Set a time"),
                    isOn: Binding(
                      get: { quickDraft.minuteOfDay != nil },
                      set: {
                        quickDraft.minuteOfDay = $0 ? (quickDraft.minuteOfDay ?? 9 * 60) : nil
                      }
                    ))
                  if quickDraft.minuteOfDay != nil {
                    DatePicker(
                      String(localized: "Time"),
                      selection: Binding(
                        get: { quickTimeDate },
                        set: {
                          let components = Calendar.current.dateComponents(
                            [.hour, .minute], from: $0)
                          quickDraft.minuteOfDay =
                            (components.hour ?? 9) * 60 + (components.minute ?? 0)
                        }),
                      displayedComponents: .hourAndMinute
                    ).labelsHidden()
                  }
                }
              }
              GridRow {
                Text(String(localized: "Repeat"))
                Picker(String(localized: "Repeat"), selection: $quickDraft.frequency) {
                  ForEach(TaskFrequency.allCases) { Text($0.label).tag($0) }
                }.labelsHidden()
              }
              GridRow {
                Text(String(localized: "Notes"))
                TextField(String(localized: "Notes"), text: $quickDraft.notes, axis: .vertical)
                  .lineLimit(1...3).textFieldStyle(.roundedBorder)
              }
            }
            .font(.callout).padding(.top, 6)
          }
          .font(.caption)
          if quickAddFailed {
            Text(String(localized: "Unable to save. Try again."))
              .font(.caption).foregroundStyle(.red).padding(.leading, 30)
          }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
      } else {
        HStack {
          Button {
            beginQuickAdd()
          } label: {
            Label("Add a task", systemImage: "plus")
          }
          .buttonStyle(.plain).font(.body.weight(.medium))
          .keyboardShortcut("n", modifiers: .command)
          Spacer()
          SettingsLink { Image(systemName: "gearshape") }
            .labelStyle(.iconOnly).buttonStyle(.plain).help(String(localized: "Settings…"))
          Menu {
            Button(String(localized: "Quit Focus Bar"), systemImage: "power") {
              NSApp.terminate(nil)
            }
          } label: {
            Image(systemName: "ellipsis")
          }
          .menuStyle(.borderlessButton).fixedSize().help(String(localized: "More"))
        }.padding(.horizontal, 16).padding(.vertical, 12)
      }
    }
    .frame(width: 360, height: panelHeight, alignment: .top)
    .background(.regularMaterial)
    .onAppear {
      let screenHeight =
        NSApp.keyWindow?.screen?.visibleFrame.height
        ?? NSScreen.screens.first?.visibleFrame.height ?? 800
      panelHeight = min(520, max(360, screenHeight - 100))
      calendarState.refresh()
    }
    .sheet(item: $editor) { item in
      TaskEditor(day: item.day, item: item) { draft in store.save(draft, editing: item) }
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
      "Focus Bar",
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.clearError() } })
    ) {
      Button(String(localized: "Close"), role: .cancel) { store.clearError() }
    } message: {
      Text(store.error ?? String(localized: "Unable to save. Try again."))
    }
  }

  private var quickAddHeightReservation: CGFloat {
    if quickAddActive && quickDetailsExpanded { return 320 }
    if quickAddActive { return 190 }
    return 150
  }

  private var selectedTitle: String {
    if navigation.followsToday { return String(localized: "Today") }
    if selected == today.addingDays(1) { return String(localized: "Tomorrow") }
    return selected.date.formatted(date: .abbreviated, time: .omitted)
  }

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 3) {
        Button {
          navigation.returnToToday()
        } label: {
          Text(selectedTitle)
            .font(.title2.weight(.semibold)).foregroundStyle(.primary)
        }.buttonStyle(.plain)
        Text(selected.date.formatted(date: .complete, time: .omitted))
          .font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Menu {
        Button(String(localized: "Today")) { navigation.returnToToday() }
        Button(String(localized: "Tomorrow")) { select(today.addingDays(1)) }
        Divider()
        DatePicker(
          String(localized: "Choose a date"),
          selection: Binding(get: { selected.date }, set: { select(LocalDay($0)) }),
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

  private func emptyState(sections: DaySections, selected: LocalDay, today: LocalDay) -> some View {
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
    .frame(maxWidth: .infinity).padding(.vertical, 32)
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
            Button(String(localized: "Edit")) { editor = item }
            Button(String(localized: "Move to Tomorrow")) {
              store.moveToTomorrow(item, today: today)
            }
            Button(String(localized: "Change Date")) { editor = item }
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
        String(format: String(localized: item.completed ? "Reopen %@" : "Complete %@"), item.title))
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title).font(.body).foregroundStyle(
          item.completed ? .secondary : .primary
        )
        .strikethrough(item.completed).lineLimit(2).textSelection(.enabled)
        if item.overdue {
          Text(item.day.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2)
            .foregroundStyle(.secondary)
        }
        if let movedFrom = item.movedFromDay {
          Text(
            String(
              format: String(localized: "Moved from %@"),
              movedFrom.date.formatted(date: .abbreviated, time: .omitted))
          )
          .font(.caption2).foregroundStyle(.secondary)
        }
        if !item.overdue, showTime, let minute = item.minuteOfDay {
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
        .textFieldStyle(.plain).font(.title3.weight(.medium)).focused($titleFocused)
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
        }.font(.callout).padding(.top, 8)
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

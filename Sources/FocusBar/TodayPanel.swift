import AppKit
import SwiftData
import SwiftUI

// MARK: - Panel

struct TodayPanel: View {
  @AppStorage("showCompleted") private var showCompleted = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openSettings) private var openSettings
  @Environment(TaskStore.self) private var store
  @Environment(CalendarState.self) private var calendarState

  @State private var navigation = DateNavigationState()
  @State private var showCalendar = false
  @State private var completedExpanded = false
  /// Tasks that were just checked off stay in place briefly before moving to Completed.
  @State private var lingering: Set<String> = []

  @FocusState private var listFocused: Bool
  @FocusState private var editFocus: String?
  @FocusState private var addFocused: Bool
  @State private var selectedID: String?
  @State private var editingID: String?
  @State private var editText = ""
  @State private var inspectingID: String?

  @State private var draft = TaskDraft(day: LocalDay(.now))
  @State private var draftDayPinned = false
  @State private var isSubmitting = false

  @State private var contentHeight: CGFloat = 0
  @State private var maxListHeight: CGFloat = 480
  @State private var toast: PanelToast?

  private var today: LocalDay { calendarState.dateContext.today }
  private var selected: LocalDay { navigation.displayedDay(today: today) }
  private var motion: Animation? { reduceMotion ? nil : .easeOut(duration: 0.18) }

  var body: some View {
    let sections = visibleSections
    VStack(spacing: 0) {
      header
      if contentHeight > maxListHeight { Divider() }
      ScrollViewReader { proxy in
        ScrollView {
          list(sections)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: max(1, min(contentHeight, maxListHeight)))
        .onChange(of: selectedID) { _, id in
          if let id { withAnimation(motion) { proxy.scrollTo(id) } }
        }
      }
      .overlay(alignment: .bottom) { toastView }
      Divider()
      quickAddBar
    }
    .frame(width: 340)
    .background { shortcuts }
    .onAppear {
      calendarState.refresh()
      let screen = NSScreen.main ?? NSScreen.screens.first
      maxListHeight = max(200, (screen?.visibleFrame.height ?? 800) * 0.7 - 120)
      if !draftDayPinned { draft.day = selected }
    }
    .onChange(of: selected) { _, day in
      if !draftDayPinned { draft.day = day }
      selectedID = nil
      editingID = nil
    }
    .onChange(of: store.error) { _, message in
      guard let message else { return }
      show(PanelToast(message: message, isError: true))
      store.clearError()
    }
    .onChange(of: editFocus) { _, focus in
      if let id = editingID, focus != id { commitEdit() }
    }
    .task(id: toast?.id) {
      guard toast != nil else { return }
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled else { return }
      withAnimation(motion) { toast = nil }
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 6) {
      Button {
        showCalendar.toggle()
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(dayTitle(selected)).font(.headline).foregroundStyle(.primary)
          Text(headerSubtitle).font(.subheadline).foregroundStyle(.secondary)
          Image(systemName: "chevron.down")
            .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(String(localized: "Choose a date"))
      .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
        DatePicker(
          String(localized: "Choose a date"),
          selection: Binding(
            get: { selected.date },
            set: {
              select(LocalDay($0))
              showCalendar = false
            }),
          displayedComponents: .date
        )
        .datePickerStyle(.graphical).labelsHidden().padding(10)
      }

      Spacer(minLength: 4)

      HStack(spacing: 0) {
        PanelIconButton(systemImage: "chevron.left", help: String(localized: "Previous Day")) {
          select(selected.addingDays(-1))
        }
        Button(String(localized: "Today")) { navigation.returnToToday() }
          .buttonStyle(HoverButtonStyle())
          .font(.callout)
          .disabled(navigation.followsToday)
        PanelIconButton(systemImage: "chevron.right", help: String(localized: "Next Day")) {
          select(selected.addingDays(1))
        }
        Menu {
          Toggle(String(localized: "Show completed tasks"), isOn: $showCompleted)
          Divider()
          Button(String(localized: "Settings…"), action: showSettings)
            .keyboardShortcut(",")
          Button(String(localized: "Quit Focus Bar")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.leading, 6)
        .help(String(localized: "More"))
      }
    }
    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
  }

  private func dayTitle(_ day: LocalDay) -> String {
    if day == today { return String(localized: "Today") }
    if day == today.addingDays(1) { return String(localized: "Tomorrow") }
    if day == today.addingDays(-1) { return String(localized: "Yesterday") }
    return day.date.formatted(.dateTime.month(.abbreviated).day())
  }

  private var headerSubtitle: String {
    let date = selected.date
    let isRelative =
      selected == today || selected == today.addingDays(1) || selected == today.addingDays(-1)
    let otherYear = selected.key.prefix(4) != today.key.prefix(4)
    if isRelative {
      return date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
    }
    return otherYear
      ? date.formatted(.dateTime.weekday(.abbreviated).year())
      : date.formatted(.dateTime.weekday(.wide))
  }

  private func select(_ day: LocalDay) {
    navigation.select(day, today: today)
  }

  // MARK: List

  private struct Sections {
    var overdue: [VisibleTask]
    var scheduled: [VisibleTask]
    var anytime: [VisibleTask]
    var completed: [VisibleTask]
    var hasOpen: Bool { !(overdue.isEmpty && scheduled.isEmpty && anytime.isEmpty) }
  }

  private var visibleSections: Sections {
    let tasks = store.tasks(on: selected, today: today).map {
      $0.completed && lingering.contains($0.id) ? $0.reopenedCopy : $0
    }
    let s = daySections(tasks: tasks, selected: selected, today: today)
    return Sections(
      overdue: s.overdue, scheduled: s.scheduled, anytime: s.anytime, completed: s.completed)
  }

  private func flatOrder(_ s: Sections) -> [VisibleTask] {
    s.overdue + s.scheduled + s.anytime
      + (showCompleted && completedExpanded ? s.completed : [])
  }

  private func list(_ s: Sections) -> some View {
    let openGroups = [s.overdue, s.scheduled, s.anytime].filter { !$0.isEmpty }.count
    let showHeaders = openGroups > 1
    return VStack(alignment: .leading, spacing: 8) {
      if !s.hasOpen {
        emptyState(allDone: !s.completed.isEmpty)
      }
      group(
        String(localized: "Overdue"), tint: .red, tasks: s.overdue, showsHeader: true)
      group(
        String(localized: "Scheduled"), tasks: s.scheduled, showsHeader: showHeaders)
      group(
        String(localized: "Anytime"), tasks: s.anytime, showsHeader: showHeaders)
      if showCompleted && !s.completed.isEmpty {
        completedGroup(s.completed)
      }
    }
    .padding(.horizontal, 6).padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(motion, value: s.completed.count)
    .focusable()
    .focusEffectDisabled()
    .focused($listFocused)
    .onKeyPress(.upArrow) { moveSelection(by: -1) }
    .onKeyPress(.downArrow) { moveSelection(by: 1) }
    .onKeyPress(.space) {
      guard editingID == nil, let item = selectedItem else { return .ignored }
      toggle(item)
      return .handled
    }
    .onKeyPress(.return) {
      guard editingID == nil, let item = selectedItem else { return .ignored }
      beginEdit(item)
      return .handled
    }
    .onKeyPress(.delete) {
      guard editingID == nil, let item = selectedItem else { return .ignored }
      delete(item, series: false)
      return .handled
    }
    .onKeyPress(.escape) {
      guard editingID == nil, selectedID != nil else { return .ignored }
      selectedID = nil
      return .handled
    }
  }

  @ViewBuilder private func group(
    _ title: String, tint: Color? = nil, tasks: [VisibleTask], showsHeader: Bool
  ) -> some View {
    if !tasks.isEmpty {
      VStack(alignment: .leading, spacing: 1) {
        if showsHeader { SectionHeader(title: title, tint: tint) }
        ForEach(tasks) { row($0) }
      }
    }
  }

  private func completedGroup(_ tasks: [VisibleTask]) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Button {
        withAnimation(motion) { completedExpanded.toggle() }
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.bold))
            .rotationEffect(.degrees(completedExpanded ? 90 : 0))
          Text(String(localized: "Completed"))
          Text(tasks.count.formatted()).foregroundStyle(.tertiary)
          Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(
        String(localized: completedExpanded ? "Expanded" : "Collapsed"))
      if completedExpanded {
        ForEach(tasks) { row($0) }
      }
    }
  }

  private func emptyState(allDone: Bool) -> some View {
    let message: String
    if allDone {
      message =
        selected == today
        ? String(localized: "All done for today.") : String(localized: "All done for this day.")
    } else {
      message =
        selected == today
        ? String(localized: "Nothing scheduled for today.")
        : String(localized: "No items for this day.")
    }
    return VStack(spacing: 6) {
      Image(systemName: allDone ? "checkmark.circle" : "checklist")
        .font(.system(size: 24, weight: .light))
        .foregroundStyle(.tertiary)
      Text(message).font(.callout).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 22)
    .accessibilityElement(children: .combine)
  }

  private func row(_ item: VisibleTask) -> some View {
    TaskRowView(
      item: item,
      isChecked: item.completed || lingering.contains(item.id),
      isSelected: selectedID == item.id,
      listFocused: listFocused,
      isEditing: editingID == item.id,
      editText: $editText,
      editFocus: $editFocus,
      showsInspector: Binding(
        get: { inspectingID == item.id },
        set: { presented in
          if presented {
            inspectingID = item.id
          } else if inspectingID == item.id {
            inspectingID = nil
          }
        }),
      onToggle: { toggle(item) },
      onSelect: {
        if let editingID, editingID != item.id { commitEdit() }
        selectedID = item.id
        listFocused = true
      },
      onBeginEdit: { beginEdit(item) },
      onCommitEdit: commitEdit,
      onCancelEdit: cancelEdit,
      onSaveDetails: { store.save($0, editing: item) }
    )
    .id(item.id)
    .contextMenu { contextMenu(for: item) }
  }

  @ViewBuilder private func contextMenu(for item: VisibleTask) -> some View {
    Button(String(localized: "Edit Details…"), systemImage: "info.circle") {
      selectedID = item.id
      inspectingID = item.id
    }
    Button(String(localized: "Rename"), systemImage: "pencil") { beginEdit(item) }
    Divider()
    if item.day != today || item.overdue {
      Button(String(localized: "Move to Today"), systemImage: "arrow.uturn.backward") {
        store.move(item, to: today)
      }
    }
    if item.day != today.addingDays(1) {
      Button(String(localized: "Move to Tomorrow"), systemImage: "arrow.right") {
        store.move(item, to: today.addingDays(1))
      }
    }
    Divider()
    if item.isRecurring {
      Menu(String(localized: "Delete")) {
        Button(String(localized: "Delete This Occurrence"), role: .destructive) {
          delete(item, series: false)
        }
        Button(String(localized: "Delete Series"), role: .destructive) {
          delete(item, series: true)
        }
      }
    } else {
      Button(String(localized: "Delete"), systemImage: "trash", role: .destructive) {
        delete(item, series: false)
      }
    }
  }

  // MARK: Commands

  private var selectedItem: VisibleTask? {
    guard let selectedID else { return nil }
    return flatOrder(visibleSections).first { $0.id == selectedID }
  }

  private func moveSelection(by delta: Int) -> KeyPress.Result {
    guard editingID == nil else { return .ignored }
    let ids = flatOrder(visibleSections).map(\.id)
    guard !ids.isEmpty else { return .ignored }
    if let current = selectedID, let index = ids.firstIndex(of: current) {
      selectedID = ids[max(0, min(ids.count - 1, index + delta))]
    } else {
      selectedID = delta > 0 ? ids.first : ids.last
    }
    listFocused = true
    return .handled
  }

  private func toggle(_ item: VisibleTask) {
    let wasLingering = lingering.contains(item.id)
    store.toggle(item)
    guard store.error == nil else { return }
    if wasLingering {
      lingering.remove(item.id)
      return
    }
    guard !item.completed, !reduceMotion else { return }
    lingering.insert(item.id)
    Task {
      try? await Task.sleep(for: .milliseconds(900))
      withAnimation(motion) { _ = lingering.remove(item.id) }
    }
  }

  private func delete(_ item: VisibleTask, series: Bool) {
    let ids = flatOrder(visibleSections).map(\.id)
    if series { store.deleteSeries(item) } else { store.delete(item) }
    guard store.error == nil else { return }
    if selectedID == item.id, let index = ids.firstIndex(of: item.id) {
      let remaining = ids.filter { $0 != item.id }
      selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
    }
    show(
      PanelToast(
        message: String(format: String(localized: "Deleted “%@”"), item.title),
        isError: false, deleted: item, series: series))
  }

  private func undoDelete(_ item: VisibleTask, series: Bool) {
    store.restore(item, series: series)
    withAnimation(motion) { toast = nil }
  }

  private func beginEdit(_ item: VisibleTask) {
    if let editingID, editingID != item.id { commitEdit() }
    selectedID = item.id
    editText = item.title
    editingID = item.id
  }

  private func commitEdit() {
    guard let id = editingID, !hasMarkedText else { return }
    editingID = nil
    defer { listFocused = true }
    let title = editText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty,
      let item = store.tasks(on: selected, today: today).first(where: { $0.id == id }),
      title != item.title
    else { return }
    var updated = item.draft
    updated.title = title
    _ = store.save(updated, editing: item)
  }

  private func cancelEdit() {
    editingID = nil
    listFocused = true
  }

  private func showSettings() {
    NSApp.activate(ignoringOtherApps: true)
    openSettings()
  }

  private var hasMarkedText: Bool {
    (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
  }

  // MARK: Quick add

  private var quickAddBar: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "plus.circle.fill")
          .font(.system(size: 16))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        TextField(String(localized: "Add a task"), text: $draft.title)
          .textFieldStyle(.plain)
          .focused($addFocused)
          .onSubmit(submitQuickAdd)
          .onExitCommand {
            resetDraft()
            addFocused = false
          }
          .padding(.leading, 2)
        FieldPopoverButton(
          systemImage: "calendar", isActive: draft.day != selected,
          help: String(localized: "Date")
        ) { presented in
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              Button(String(localized: "Today")) {
                setDraftDay(today)
                presented.wrappedValue = false
              }
              Button(String(localized: "Tomorrow")) {
                setDraftDay(today.addingDays(1))
                presented.wrappedValue = false
              }
            }
            .controlSize(.small)
            DatePicker(
              String(localized: "Date"),
              selection: Binding(
                get: { draft.day.date },
                set: {
                  setDraftDay(LocalDay($0))
                  presented.wrappedValue = false
                }),
              displayedComponents: .date
            )
            .datePickerStyle(.graphical).labelsHidden()
          }
          .padding(10)
        }
        FieldPopoverButton(
          systemImage: "clock", isActive: draft.minuteOfDay != nil,
          help: String(localized: "Time")
        ) { presented in
          HStack(spacing: 8) {
            DatePicker(
              String(localized: "Time"),
              selection: Binding(
                get: { dateForMinute(draft.minuteOfDay ?? nextHourMinute(), on: draft.day) },
                set: { draft.minuteOfDay = minuteOfDay(from: $0) }),
              displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.stepperField).labelsHidden()
            Button(String(localized: "Clear")) {
              draft.minuteOfDay = nil
              presented.wrappedValue = false
            }
            .controlSize(.small)
          }
          .padding(10)
          .onAppear {
            if draft.minuteOfDay == nil { draft.minuteOfDay = nextHourMinute() }
          }
        }
        Menu {
          Picker(String(localized: "Repeat"), selection: $draft.frequency) {
            ForEach(TaskFrequency.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } label: {
          Image(systemName: "repeat")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(draft.frequency == .never ? .secondary : .accentColor)
        .help(String(localized: "Repeat"))
        .accessibilityLabel(String(localized: "Repeat"))
      }
      if draft.day != selected || draft.minuteOfDay != nil || draft.frequency != .never {
        HStack(spacing: 6) {
          if draft.day != selected {
            FieldChip(text: dayTitle(draft.day), systemImage: "calendar") {
              draft.day = selected
              draftDayPinned = false
            }
          }
          if let minute = draft.minuteOfDay {
            FieldChip(text: formatMinuteOfDay(minute), systemImage: "clock") {
              draft.minuteOfDay = nil
            }
          }
          if draft.frequency != .never {
            FieldChip(text: draft.frequency.label, systemImage: "repeat") {
              draft.frequency = .never
            }
          }
        }
        .padding(.leading, 24)
        .transition(.opacity)
      }
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .animation(motion, value: draft.minuteOfDay)
    .animation(motion, value: draft.frequency)
  }

  private func setDraftDay(_ day: LocalDay) {
    draft.day = day
    draftDayPinned = day != selected
  }

  private func resetDraft() {
    draft = TaskDraft(day: selected)
    draftDayPinned = false
  }

  private func submitQuickAdd() {
    guard
      canSubmitQuickAdd(
        title: draft.title, hasMarkedText: hasMarkedText, isSubmitting: isSubmitting)
    else { return }
    isSubmitting = true
    defer { isSubmitting = false }
    let targetDay = draft.day
    guard store.save(draft) else { return }
    resetDraft()
    addFocused = true
    if targetDay != selected {
      show(
        PanelToast(
          message: String(format: String(localized: "Added to %@"), dayTitle(targetDay)),
          isError: false))
    }
  }

  // MARK: Feedback & shortcuts

  private func show(_ newToast: PanelToast) {
    withAnimation(motion) { toast = newToast }
  }

  @ViewBuilder private var toastView: some View {
    if let toast {
      HStack(spacing: 8) {
        Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle")
          .foregroundStyle(toast.isError ? Color.yellow : Color.secondary)
        Text(toast.message).lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 4)
        if let item = toast.deleted {
          Button(String(localized: "Undo")) { undoDelete(item, series: toast.series) }
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
        } else {
          Button {
            withAnimation(motion) { self.toast = nil }
          } label: {
            Image(systemName: "xmark").font(.caption.weight(.semibold))
          }
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
          .accessibilityLabel(String(localized: "Close"))
        }
      }
      .font(.callout)
      .padding(.horizontal, 10).padding(.vertical, 7)
      .background(.bar, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.08))
      )
      .padding(.horizontal, 10).padding(.bottom, 8)
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .accessibilityElement(children: .contain)
    }
  }

  /// Panel-wide keyboard shortcuts. Kept invisible; they only exist so the key equivalents work.
  private var shortcuts: some View {
    ZStack {
      Button("") { addFocused = true }.keyboardShortcut("n")
      Button("") {
        if let selectedID { inspectingID = selectedID }
      }
      .keyboardShortcut("i")
      Button("") { select(selected.addingDays(-1)) }.keyboardShortcut("[")
      Button("") { select(selected.addingDays(1)) }.keyboardShortcut("]")
      Button("") { navigation.returnToToday() }.keyboardShortcut("t")
      Button("", action: showSettings).keyboardShortcut(",")
      Button("") {
        if let toast, let item = toast.deleted { undoDelete(item, series: toast.series) }
      }
      .keyboardShortcut("z")
      .disabled(toast?.deleted == nil)
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
  }
}

// MARK: - Toast model

private struct PanelToast: Identifiable {
  let id = UUID()
  let message: String
  let isError: Bool
  var deleted: VisibleTask? = nil
  var series = false
}

// MARK: - Row

private struct TaskRowView: View {
  let item: VisibleTask
  let isChecked: Bool
  let isSelected: Bool
  let listFocused: Bool
  let isEditing: Bool
  @Binding var editText: String
  var editFocus: FocusState<String?>.Binding
  @Binding var showsInspector: Bool
  let onToggle: () -> Void
  let onSelect: () -> Void
  let onBeginEdit: () -> Void
  let onCommitEdit: () -> Void
  let onCancelEdit: () -> Void
  let onSaveDetails: (TaskDraft) -> Bool
  @State var hovering = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      CheckCircle(isOn: isChecked, title: item.title, action: onToggle)
      VStack(alignment: .leading, spacing: 2) {
        title
        if let meta = metaText {
          meta.font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer(minLength: 6)
      if let minute = item.minuteOfDay, !item.overdue {
        Text(formatMinuteOfDay(minute))
          .font(.callout).monospacedDigit()
          .foregroundStyle(isChecked ? .tertiary : .secondary)
      }
      Button {
        showsInspector = true
      } label: {
        Image(systemName: "info.circle")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .opacity(infoVisible ? 1 : 0)
      .allowsHitTesting(infoVisible)
      .help(String(localized: "Edit Details…"))
      .accessibilityLabel(String(localized: "Edit Details…"))
      .popover(isPresented: $showsInspector, arrowEdge: .trailing) {
        TaskInspector(item: item, onSave: onSaveDetails)
      }
    }
    .padding(.horizontal, 6).padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous).fill(background)
    )
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .modifier(RowTapModifier(enabled: !isEditing, single: onSelect, double: onBeginEdit))
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var infoVisible: Bool { hovering || isSelected || showsInspector }

  private var background: Color {
    if isSelected { return Color.accentColor.opacity(listFocused ? 0.2 : 0.1) }
    if hovering { return Color.primary.opacity(0.06) }
    return .clear
  }

  @ViewBuilder private var title: some View {
    if isEditing {
      TextField(String(localized: "Title"), text: $editText)
        .textFieldStyle(.plain)
        .focused(editFocus, equals: item.id)
        .onSubmit(onCommitEdit)
        .onExitCommand(perform: onCancelEdit)
        .onAppear { editFocus.wrappedValue = item.id }
    } else {
      Text(item.title)
        .foregroundStyle(isChecked ? .secondary : .primary)
        .lineLimit(2)
    }
  }

  private var metaText: Text? {
    var parts: [Text] = []
    if item.overdue {
      parts.append(Text(shortDate(item.day)).foregroundStyle(.red))
    }
    if item.isRecurring {
      parts.append(Text(Image(systemName: "repeat")))
    }
    if let moved = item.movedFromDay {
      parts.append(Text(String(format: String(localized: "Moved from %@"), shortDate(moved))))
    }
    if let due = item.dueDay {
      parts.append(Text(String(format: String(localized: "Due %@"), shortDate(due))))
    }
    if let note = item.notes.split(whereSeparator: \.isNewline).first {
      parts.append(Text(String(note)))
    }
    guard let first = parts.first else { return nil }
    return parts.dropFirst().reduce(first) { $0 + Text(" · ") + $1 }
  }
}

private struct RowTapModifier: ViewModifier {
  let enabled: Bool
  let single: () -> Void
  let double: () -> Void

  @ViewBuilder func body(content: Content) -> some View {
    if enabled {
      content
        .onTapGesture(count: 2, perform: double)
        .onTapGesture(perform: single)
    } else {
      content
    }
  }
}

private struct CheckCircle: View {
  let isOn: Bool
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 16))
        .foregroundStyle(
          isOn ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(HierarchicalShapeStyle.secondary)
        )
        .contentTransition(.symbolEffect(.replace))
        .frame(width: 18, height: 18)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
    .accessibilityLabel(
      String(format: String(localized: isOn ? "Reopen %@" : "Complete %@"), title))
  }
}

private struct SectionHeader: View {
  let title: String
  var tint: Color? = nil

  var body: some View {
    Text(title)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(
        tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(HierarchicalShapeStyle.secondary)
      )
      .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
      .accessibilityAddTraits(.isHeader)
  }
}

// MARK: - Inspector

private struct TaskInspector: View {
  @Environment(\.dismiss) private var dismiss
  private let item: VisibleTask
  private let onSave: (TaskDraft) -> Bool
  @State private var draft: TaskDraft

  init(item: VisibleTask, onSave: @escaping (TaskDraft) -> Bool) {
    self.item = item
    self.onSave = onSave
    _draft = State(initialValue: item.draft)
  }

  var body: some View {
    Form {
      TextField(String(localized: "Title"), text: $draft.title)
        .onSubmit { dismiss() }
      TextField(String(localized: "Notes"), text: $draft.notes, axis: .vertical)
        .lineLimit(2...5)
      DatePicker(
        String(localized: "Date"),
        selection: Binding(get: { draft.day.date }, set: { draft.day = LocalDay($0) }),
        displayedComponents: .date)
      LabeledContent(String(localized: "Time")) {
        HStack(spacing: 6) {
          if let minute = draft.minuteOfDay {
            DatePicker(
              String(localized: "Time"),
              selection: Binding(
                get: { dateForMinute(minute, on: draft.day) },
                set: { draft.minuteOfDay = minuteOfDay(from: $0) }),
              displayedComponents: .hourAndMinute
            )
            .labelsHidden()
          }
          Toggle(
            String(localized: "Set a time"),
            isOn: Binding(
              get: { draft.minuteOfDay != nil },
              set: { draft.minuteOfDay = $0 ? (draft.minuteOfDay ?? nextHourMinute()) : nil })
          )
          .toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
      }
      LabeledContent(String(localized: "Deadline")) {
        HStack(spacing: 6) {
          if let dueDay = draft.dueDay {
            DatePicker(
              String(localized: "Deadline"),
              selection: Binding(get: { dueDay.date }, set: { draft.dueDay = LocalDay($0) }),
              displayedComponents: .date
            )
            .labelsHidden()
          }
          Toggle(
            String(localized: "Set a deadline"),
            isOn: Binding(
              get: { draft.dueDay != nil },
              set: { draft.dueDay = $0 ? (draft.dueDay ?? draft.day) : nil })
          )
          .toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
      }
      if item.isRecurring {
        Text(String(localized: "Changes apply to this day only."))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.columns)
    .padding(14)
    .frame(width: 300)
    .onDisappear(perform: saveIfChanged)
  }

  private func saveIfChanged() {
    let original = item.draft
    var edited = draft
    edited.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !edited.title.isEmpty else { return }
    let changed =
      edited.title != original.title || edited.notes != original.notes
      || edited.day != original.day || edited.minuteOfDay != original.minuteOfDay
      || edited.dueDay != original.dueDay
    if changed { _ = onSave(edited) }
  }
}

// MARK: - Small controls

private struct PanelIconButton: View {
  let systemImage: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 18, height: 22)
    }
    .buttonStyle(HoverButtonStyle())
    .help(help)
    .accessibilityLabel(help)
  }
}

/// Borderless button with the subtle hover/pressed background used by system menu bar panels.
private struct HoverButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    HoverButtonBody(configuration: configuration)
  }
}

private struct HoverButtonBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.isEnabled) private var isEnabled
  @State var hovering = false

  var body: some View {
    configuration.label
      .padding(.horizontal, 5).padding(.vertical, 2)
      .foregroundStyle(
        isEnabled
          ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
          : AnyShapeStyle(HierarchicalShapeStyle.quaternary)
      )
      .background(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(
            Color.primary.opacity(
              configuration.isPressed ? 0.12 : (hovering && isEnabled ? 0.07 : 0)))
      )
      .contentShape(Rectangle())
      .onHover { hovering = $0 }
  }
}

private struct FieldPopoverButton<Content: View>: View {
  let systemImage: String
  let isActive: Bool
  let help: String
  let content: (Binding<Bool>) -> Content
  @State var presented = false

  var body: some View {
    Button {
      presented.toggle()
    } label: {
      Image(systemName: systemImage)
        .font(.system(size: 13))
        .frame(width: 18, height: 20)
        .foregroundStyle(
          isActive
            ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
    }
    .buttonStyle(HoverButtonStyle())
    .help(help)
    .accessibilityLabel(help)
    .popover(isPresented: $presented, arrowEdge: .top) {
      content($presented)
    }
  }
}

private struct FieldChip: View {
  let text: String
  let systemImage: String
  let onClear: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: systemImage).imageScale(.small)
      Text(text)
      Button(action: onClear) {
        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(format: String(localized: "Remove %@"), text))
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 7).padding(.vertical, 3)
    .background(Capsule().fill(Color.primary.opacity(0.07)))
  }
}

// MARK: - Helpers

extension VisibleTask {
  fileprivate var reopenedCopy: VisibleTask {
    VisibleTask(
      id: id, title: title, notes: notes, day: day, dueDay: dueDay, minuteOfDay: minuteOfDay,
      completed: false, completedAt: nil, overdue: overdue, isRecurring: isRecurring,
      sourceID: sourceID, sortOrder: sortOrder, occurrenceDay: occurrenceDay,
      movedFromDay: movedFromDay)
  }

  fileprivate var draft: TaskDraft {
    TaskDraft(
      title: title, notes: notes, day: day, minuteOfDay: minuteOfDay, dueDay: dueDay,
      frequency: .never)
  }
}

private func shortDate(_ day: LocalDay) -> String {
  day.date.formatted(.dateTime.month(.abbreviated).day())
}

private func dateForMinute(_ minute: Int, on day: LocalDay) -> Date {
  Calendar.current.date(
    bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day.date) ?? day.date
}

private func minuteOfDay(from date: Date) -> Int {
  let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
  return (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
}

private func nextHourMinute() -> Int {
  min(23, Calendar.current.component(.hour, from: .now) + 1) * 60
}

import AppKit
import SwiftData
import SwiftUI

// MARK: - Motion Tokens

private enum FocusMotion {
  /// Hover background, icon visibility, focus border highlights.
  static func micro(_ reduce: Bool) -> Animation? {
    reduce ? nil : .easeOut(duration: 0.12)
  }
  /// Button press/bounce, checkbox completion, chips, toast slide.
  static func snappy(_ reduce: Bool) -> Animation? {
    reduce ? nil : .spring(response: 0.26, dampingFraction: 0.76)
  }
  /// Row insertion/removal/reordering, disclosure, inspector controls.
  static func smooth(_ reduce: Bool) -> Animation? {
    reduce ? nil : .spring(response: 0.34, dampingFraction: 0.86)
  }
  /// Panel height interpolation, highlight fade, empty-state entrance.
  static func gentle(_ reduce: Bool) -> Animation? {
    reduce ? nil : .easeInOut(duration: 0.28)
  }
}

// MARK: - Panel

struct TodayPanel: View {
  @AppStorage("showCompleted") private var showCompleted = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openSettings) private var openSettings
  @Environment(TaskStore.self) private var store
  @Environment(CalendarState.self) private var calendarState

  @State private var completedExpanded = false
  /// Tasks that were just checked off stay in place briefly before moving to Completed.
  @State private var lingering: Set<String> = []
  /// Newly created task ID highlighted briefly so the user can spot where it landed.
  @State private var recentlyAddedID: String?
  /// Increments on Quick Add submission to trigger a subtle confirmation pulse.
  @State private var submitPulse = 0
  /// Briefly illuminates the Completed header when a lingering task archives into it.
  @State private var completedHeaderPulse = false

  @FocusState private var listFocused: Bool
  @FocusState private var editFocus: String?
  @FocusState private var addFocused: Bool
  @State private var selectedID: String?
  @State private var editingID: String?
  @State private var editText = ""
  @State private var inspectingID: String?

  @State private var draft = TaskDraft()
  @State private var isSubmitting = false

  @State private var contentHeight: CGFloat = 0
  @State private var maxListHeight: CGFloat = 480
  @State private var toast: PanelToast?
  @State private var cachedTasks: [VisibleTask] = []
  @State private var loadedRevision = -1
  @State private var loadedDay: LocalDay?

  private var today: LocalDay { calendarState.dateContext.today }
  private var microMotion: Animation? { FocusMotion.micro(reduceMotion) }
  private var snappyMotion: Animation? { FocusMotion.snappy(reduceMotion) }
  private var smoothMotion: Animation? { FocusMotion.smooth(reduceMotion) }
  private var gentleMotion: Animation? { FocusMotion.gentle(reduceMotion) }

  var body: some View {
    let sections = visibleSections
    let openCount = sections.overdue.count + sections.scheduled.count + sections.anytime.count
    let effectiveHeight = max(1, min(contentHeight, maxListHeight))

    VStack(spacing: 0) {
      header(openCount: openCount)
      Divider()
        .opacity(contentHeight > maxListHeight ? 1 : 0)
        .animation(microMotion, value: contentHeight > maxListHeight)
      ScrollViewReader { proxy in
        ScrollView {
          list(sections)
            .onGeometryChange(for: CGFloat.self) {
              $0.size.height
            } action: { newHeight in
              if abs(contentHeight - newHeight) > 0.5 {
                contentHeight = newHeight
              }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: effectiveHeight)
        .onChange(of: selectedID) { _, id in
          if let id { withAnimation(smoothMotion) { proxy.scrollTo(id) } }
        }
        .onChange(of: recentlyAddedID) { _, id in
          if let id {
            withAnimation(smoothMotion) { proxy.scrollTo(id, anchor: .center) }
          }
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
      reloadTasks()
      let screen = NSScreen.main ?? NSScreen.screens.first
      maxListHeight = max(200, (screen?.visibleFrame.height ?? 800) * 0.7 - 120)
    }
    .onChange(of: store.revision) { _, _ in
      reloadTasks()
    }
    .onChange(of: today) { _, _ in
      reloadTasks()
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
      withAnimation(snappyMotion) { toast = nil }
    }
  }

  // MARK: Header

  private func header(openCount: Int) -> some View {
    HStack(spacing: 6) {
      Text(String(localized: "Tasks"))
        .font(.headline)
        .foregroundStyle(.primary)
      if openCount > 0 {
        Text(openCount.formatted())
          .font(.caption.weight(.medium))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
          .padding(.horizontal, 6)
          .padding(.vertical, 1.5)
          .background(Capsule().fill(Color.primary.opacity(0.06)))
          .transition(.opacity.combined(with: .scale(scale: 0.85)))
      }
      Spacer()
      MoreMenuButton(
        showCompleted: $showCompleted,
        reduceMotion: reduceMotion,
        onSettings: showSettings
      )
    }
    .animation(snappyMotion, value: openCount)
    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
  }

  // MARK: List

  private func reloadTasks() {
    let rev = store.revision
    let day = today
    guard loadedRevision != rev || loadedDay != day else { return }
    cachedTasks = store.tasks(today: day)
    loadedRevision = rev
    loadedDay = day
  }

  private var visibleSections: TaskSections {
    let source =
      (loadedRevision == store.revision && loadedDay == today)
      ? cachedTasks
      : store.tasks(today: today)
    let tasks = source.map {
      $0.completed && lingering.contains($0.id) ? $0.reopenedCopy : $0
    }
    return taskSections(tasks: tasks)
  }

  private func flatOrder(_ s: TaskSections) -> [VisibleTask] {
    s.overdue + s.scheduled + s.anytime
      + (showCompleted && completedExpanded ? s.completed : [])
  }

  private func list(_ s: TaskSections) -> some View {
    let openGroups = [s.overdue, s.scheduled, s.anytime].filter { !$0.isEmpty }.count
    let showHeaders = openGroups > 1

    return VStack(alignment: .leading, spacing: 8) {
      if !s.hasOpen {
        emptyState(allDone: !s.completed.isEmpty)
          .transition(.opacity.combined(with: .scale(scale: 0.94)))
      }
      group(
        String(localized: "Overdue"), tint: .red, tasks: s.overdue, showsHeader: true)
      group(
        String(localized: "Timed"), tasks: s.scheduled, showsHeader: showHeaders)
      group(
        String(localized: "Anytime"), tasks: s.anytime, showsHeader: showHeaders)
      if showCompleted && !s.completed.isEmpty {
        completedGroup(s.completed)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 6).padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
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
      VStack(alignment: .leading, spacing: 2) {
        if showsHeader {
          SectionHeader(title: title, tint: tint)
            .transition(.opacity)
        }
        ForEach(tasks) { row($0) }
      }
      .transition(.opacity)
    }
  }

  private func completedGroup(_ tasks: [VisibleTask]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      CompletedSectionButton(
        count: tasks.count,
        expanded: completedExpanded,
        pulsing: completedHeaderPulse,
        reduceMotion: reduceMotion
      ) {
        withAnimation(smoothMotion) { completedExpanded.toggle() }
      }
      if completedExpanded {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(tasks) { row($0) }
        }
        .clipped()
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }

  private func emptyState(allDone: Bool) -> some View {
    let message =
      allDone
      ? String(localized: "All tasks completed.")
      : String(localized: "No tasks yet. Add one below.")
    return VStack(spacing: 8) {
      if allDone {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 26, weight: .regular))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.tint)
          .symbolEffect(.bounce, value: allDone && !reduceMotion)
      } else {
        Image(systemName: "checklist")
          .font(.system(size: 24, weight: .light))
          .foregroundStyle(.tertiary)
      }
      Text(message)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
    .accessibilityElement(children: .combine)
  }

  private func row(_ item: VisibleTask) -> some View {
    TaskRowView(
      item: item,
      isChecked: item.completed || lingering.contains(item.id),
      isSelected: selectedID == item.id,
      isHighlighted: recentlyAddedID == item.id,
      listFocused: listFocused,
      isEditing: editingID == item.id,
      reduceMotion: reduceMotion,
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
        withAnimation(microMotion) {
          selectedID = item.id
        }
        listFocused = true
      },
      onBeginEdit: { beginEdit(item) },
      onCommitEdit: commitEdit,
      onCancelEdit: cancelEdit,
      onSaveDetails: { store.save($0, editing: item) }
    )
    .id(item.id)
    .transition(
      .asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
        removal: .opacity.combined(with: .scale(scale: 0.96))
      )
    )
    .contextMenu { contextMenu(for: item) }
  }

  @ViewBuilder private func contextMenu(for item: VisibleTask) -> some View {
    Button(String(localized: "Edit Details…"), systemImage: "info.circle") {
      selectedID = item.id
      inspectingID = item.id
    }
    Button(String(localized: "Rename"), systemImage: "pencil") { beginEdit(item) }
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
    withAnimation(microMotion) {
      if let current = selectedID, let index = ids.firstIndex(of: current) {
        selectedID = ids[max(0, min(ids.count - 1, index + delta))]
      } else {
        selectedID = delta > 0 ? ids.first : ids.last
      }
    }
    listFocused = true
    return .handled
  }

  private func toggle(_ item: VisibleTask) {
    let wasLingering = lingering.contains(item.id)
    if wasLingering {
      withAnimation(snappyMotion) {
        _ = lingering.remove(item.id)
        store.toggle(item)
      }
      return
    }
    if item.completed || reduceMotion {
      withAnimation(smoothMotion) {
        store.toggle(item)
      }
      return
    }
    withAnimation(snappyMotion) {
      store.toggle(item)
      guard store.error == nil else { return }
      lingering.insert(item.id)
    }
    guard store.error == nil else { return }
    Task {
      try? await Task.sleep(for: .milliseconds(900))
      guard !Task.isCancelled, lingering.contains(item.id) else { return }
      withAnimation(smoothMotion) {
        _ = lingering.remove(item.id)
        completedHeaderPulse = true
      }
      try? await Task.sleep(for: .milliseconds(420))
      guard !Task.isCancelled else { return }
      withAnimation(gentleMotion) {
        completedHeaderPulse = false
      }
    }
  }

  private func delete(_ item: VisibleTask, series: Bool) {
    let ids = flatOrder(visibleSections).map(\.id)
    withAnimation(smoothMotion) {
      if series { store.deleteSeries(item) } else { store.delete(item) }
      guard store.error == nil else { return }
      if selectedID == item.id, let index = ids.firstIndex(of: item.id) {
        let remaining = ids.filter { $0 != item.id }
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
      }
    }
    guard store.error == nil else { return }
    show(
      PanelToast(
        message: String(format: String(localized: "Deleted “%@”"), item.title),
        isError: false, deleted: item, series: series))
  }

  private func undoDelete(_ item: VisibleTask, series: Bool) {
    withAnimation(smoothMotion) {
      store.restore(item, series: series)
      toast = nil
    }
    flashHighlight(for: item.id)
  }

  private func beginEdit(_ item: VisibleTask) {
    if let editingID, editingID != item.id { commitEdit() }
    withAnimation(microMotion) {
      selectedID = item.id
      editText = item.title
      editingID = item.id
    }
  }

  private func commitEdit() {
    guard let id = editingID, !hasMarkedText else { return }
    withAnimation(microMotion) {
      editingID = nil
    }
    defer { listFocused = true }
    let title = editText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty,
      let item = store.tasks(today: today).first(where: { $0.id == id }),
      title != item.title
    else { return }
    var updated = item.draft
    updated.title = title
    withAnimation(smoothMotion) {
      _ = store.save(updated, editing: item)
    }
  }

  private func cancelEdit() {
    withAnimation(microMotion) {
      editingID = nil
    }
    listFocused = true
  }

  private func showSettings() {
    NSApp.activate(ignoringOtherApps: true)
    openSettings()
  }

  private var hasMarkedText: Bool {
    (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
  }

  private func flashHighlight(for id: String) {
    guard !reduceMotion else { return }
    withAnimation(snappyMotion) {
      recentlyAddedID = id
    }
    Task {
      try? await Task.sleep(for: .milliseconds(1100))
      guard !Task.isCancelled, recentlyAddedID == id else { return }
      withAnimation(gentleMotion) {
        recentlyAddedID = nil
      }
    }
  }

  // MARK: Quick add

  private var hasDraftTitle: Bool {
    !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var quickAddBar: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "plus.circle.fill")
          .font(.system(size: 16))
          .foregroundStyle(
            hasDraftTitle || addFocused
              ? AnyShapeStyle(TintShapeStyle())
              : AnyShapeStyle(HierarchicalShapeStyle.secondary)
          )
          .symbolEffect(.bounce.up, value: reduceMotion ? 0 : submitPulse)
          .animation(microMotion, value: hasDraftTitle || addFocused)
          .accessibilityHidden(true)

        TextField(String(localized: "Add a task"), text: $draft.title)
          .textFieldStyle(.plain)
          .focused($addFocused)
          .onSubmit(submitQuickAdd)
          .onExitCommand {
            withAnimation(snappyMotion) { resetDraft() }
            addFocused = false
          }
          .padding(.leading, 2)

        if hasDraftTitle {
          Button(action: submitQuickAdd) {
            Image(systemName: "return")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 20, height: 18)
              .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                  .fill(Color.accentColor)
              )
          }
          .buttonStyle(TactilePlainButtonStyle(reduceMotion: reduceMotion))
          .help(String(localized: "Add a task"))
          .accessibilityLabel(String(localized: "Add a task"))
          .transition(.opacity.combined(with: .scale(scale: 0.78)))
        }

        FieldPopoverButton(
          systemImage: "calendar", isActive: draft.dueDay != nil,
          help: String(localized: "Deadline"),
          reduceMotion: reduceMotion
        ) { presented in
          VStack(alignment: .leading, spacing: 8) {
            DatePicker(
              String(localized: "Deadline"),
              selection: Binding(
                get: { draft.dueDay?.date ?? LocalDay(.now).date },
                set: { newDate in
                  withAnimation(snappyMotion) { draft.dueDay = LocalDay(newDate) }
                }),
              displayedComponents: .date
            )
            .datePickerStyle(.graphical).labelsHidden()
            if draft.dueDay != nil {
              Button(String(localized: "Clear")) {
                withAnimation(snappyMotion) { draft.dueDay = nil }
                presented.wrappedValue = false
              }
              .controlSize(.small)
            }
          }
          .padding(10)
        }

        FieldPopoverButton(
          systemImage: "clock", isActive: draft.minuteOfDay != nil,
          help: String(localized: "Time"),
          reduceMotion: reduceMotion
        ) { presented in
          HStack(spacing: 8) {
            DatePicker(
              String(localized: "Time"),
              selection: Binding(
                get: { dateForMinute(draft.minuteOfDay ?? nextHourMinute()) },
                set: { newDate in
                  withAnimation(snappyMotion) { draft.minuteOfDay = minuteOfDay(from: newDate) }
                }),
              displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.stepperField).labelsHidden()
            Button(String(localized: "Clear")) {
              withAnimation(snappyMotion) { draft.minuteOfDay = nil }
              presented.wrappedValue = false
            }
            .controlSize(.small)
          }
          .padding(10)
          .onAppear {
            if draft.minuteOfDay == nil {
              withAnimation(snappyMotion) { draft.minuteOfDay = nextHourMinute() }
            }
          }
        }

        RepeatMenuButton(
          frequency: $draft.frequency,
          weekdays: $draft.weekdays,
          reduceMotion: reduceMotion
        )
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.primary.opacity(addFocused ? 0.045 : 0))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.accentColor.opacity(addFocused ? 0.35 : 0), lineWidth: 1)
      )
      .animation(microMotion, value: addFocused)
      .animation(snappyMotion, value: hasDraftTitle)

      if draft.dueDay != nil || draft.minuteOfDay != nil || draft.frequency != .never {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            if let dueDay = draft.dueDay {
              FieldChip(
                text: String(format: String(localized: "Due %@"), shortDate(dueDay)),
                systemImage: "calendar",
                reduceMotion: reduceMotion
              ) {
                withAnimation(snappyMotion) { draft.dueDay = nil }
              }
              .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            if let minute = draft.minuteOfDay {
              FieldChip(
                text: formatMinuteOfDay(minute),
                systemImage: "clock",
                reduceMotion: reduceMotion
              ) {
                withAnimation(snappyMotion) { draft.minuteOfDay = nil }
              }
              .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            if draft.frequency != .never {
              FieldChip(
                text: repeatSummary(for: draft),
                systemImage: "repeat",
                reduceMotion: reduceMotion
              ) {
                withAnimation(snappyMotion) { draft.frequency = .never }
              }
              .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
          }
          .padding(.leading, 26)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.horizontal, 8).padding(.vertical, 8)
    .animation(snappyMotion, value: draft.dueDay)
    .animation(snappyMotion, value: draft.minuteOfDay)
    .animation(snappyMotion, value: draft.frequency)
  }

  private func resetDraft() {
    draft = TaskDraft()
  }

  private func submitQuickAdd() {
    guard
      canSubmitQuickAdd(
        title: draft.title, hasMarkedText: hasMarkedText, isSubmitting: isSubmitting)
    else { return }
    isSubmitting = true
    defer { isSubmitting = false }
    var saved = false
    withAnimation(smoothMotion) {
      saved = store.save(draft)
    }
    guard saved else { return }
    submitPulse &+= 1
    withAnimation(snappyMotion) {
      resetDraft()
    }
    addFocused = true
    if let createdID = store.lastCreatedTaskID {
      flashHighlight(for: createdID)
    }
  }

  private func repeatSummary(for draft: TaskDraft) -> String {
    guard draft.frequency == .weekly else { return draft.frequency.label }
    let weekday = draft.weekdays.first ?? Calendar.current.component(.weekday, from: .now)
    let name = Calendar.current.weekdaySymbols[weekday - 1]
    return String(format: String(localized: "Weekly on %@"), name)
  }

  // MARK: Feedback & shortcuts

  private func show(_ newToast: PanelToast) {
    withAnimation(snappyMotion) { toast = newToast }
  }

  @ViewBuilder private var toastView: some View {
    if let toast {
      ToastBanner(
        toast: toast,
        reduceMotion: reduceMotion,
        onUndo: { item, series in undoDelete(item, series: series) },
        onDismiss: { withAnimation(snappyMotion) { self.toast = nil } }
      )
      .id(toast.id)
      .padding(.horizontal, 10).padding(.bottom, 8)
      .transition(.move(edge: .bottom).combined(with: .opacity))
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

// MARK: - Toast model & view

private struct PanelToast: Identifiable {
  let id = UUID()
  let message: String
  let isError: Bool
  var deleted: VisibleTask? = nil
  var series = false
}

private struct ToastBanner: View {
  let toast: PanelToast
  let reduceMotion: Bool
  let onUndo: (VisibleTask, Bool) -> Void
  let onDismiss: () -> Void
  @State private var countdownProgress: CGFloat = 1

  var body: some View {
    HStack(spacing: 8) {
      Image(
        systemName: toast.isError
          ? "exclamationmark.triangle.fill"
          : (toast.deleted != nil ? "trash" : "checkmark.circle.fill")
      )
      .foregroundStyle(toast.isError ? Color.yellow : Color.secondary)
      Text(toast.message).lineLimit(1).truncationMode(.middle)
      Spacer(minLength: 4)
      if let item = toast.deleted {
        Button(String(localized: "Undo")) { onUndo(item, toast.series) }
          .buttonStyle(HoverButtonStyle(reduceMotion: reduceMotion))
          .foregroundStyle(.tint)
          .fontWeight(.semibold)
      } else {
        Button(action: onDismiss) {
          Image(systemName: "xmark").font(.caption.weight(.semibold))
        }
        .buttonStyle(HoverButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(String(localized: "Close"))
      }
    }
    .font(.callout)
    .padding(.horizontal, 10).padding(.vertical, 8)
    .overlay(alignment: .bottomLeading) {
      if !reduceMotion {
        GeometryReader { geo in
          Rectangle()
            .fill(toast.isError ? Color.yellow.opacity(0.5) : Color.accentColor.opacity(0.45))
            .frame(width: geo.size.width * countdownProgress, height: 2)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
      }
    }
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.1))
    )
    .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    .accessibilityElement(children: .contain)
    .onAppear {
      guard !reduceMotion else { return }
      countdownProgress = 1
      withAnimation(.linear(duration: 5.0)) {
        countdownProgress = 0
      }
    }
  }
}

// MARK: - Row

private struct TaskRowView: View {
  let item: VisibleTask
  let isChecked: Bool
  let isSelected: Bool
  let isHighlighted: Bool
  let listFocused: Bool
  let isEditing: Bool
  let reduceMotion: Bool
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

  private var microMotion: Animation? { FocusMotion.micro(reduceMotion) }
  private var snappyMotion: Animation? { FocusMotion.snappy(reduceMotion) }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      CheckCircle(
        isOn: isChecked,
        title: item.title,
        reduceMotion: reduceMotion,
        action: onToggle
      )
      .padding(.top, 1)

      VStack(alignment: .leading, spacing: 2) {
        title
        if let meta = metaText {
          meta
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .opacity(isChecked ? 0.65 : 1)
        }
      }
      .padding(.top, 1)

      Spacer(minLength: 6)

      ZStack(alignment: .trailing) {
        if let minute = item.minuteOfDay, !item.overdue {
          Text(formatMinuteOfDay(minute))
            .font(.callout).monospacedDigit()
            .foregroundStyle(isChecked ? .tertiary : .secondary)
            .opacity(infoVisible ? 0 : 1)
        }
        Button {
          showsInspector = true
        } label: {
          Image(systemName: "info.circle")
            .font(.system(size: 13))
        }
        .buttonStyle(HoverButtonStyle(reduceMotion: reduceMotion))
        .opacity(infoVisible ? 1 : 0)
        .scaleEffect(infoVisible ? 1 : 0.88)
        .allowsHitTesting(infoVisible)
        .help(String(localized: "Edit Details…"))
        .accessibilityLabel(String(localized: "Edit Details…"))
        .popover(isPresented: $showsInspector, arrowEdge: .trailing) {
          TaskInspector(item: item, reduceMotion: reduceMotion, onSave: onSaveDetails)
        }
      }
      .padding(.top, 1)
      .animation(microMotion, value: infoVisible)
    }
    .padding(.leading, item.overdue && !isChecked ? 9 : 6)
    .padding(.trailing, 6)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(background)
        .animation(microMotion, value: background)
    )
    .overlay(alignment: .leading) {
      if item.overdue && !isChecked {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .fill(Color.red.opacity(0.75))
          .frame(width: 2.5)
          .padding(.vertical, 5)
          .padding(.leading, 2.5)
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(
          isEditing ? Color.accentColor.opacity(0.55) : Color.clear,
          lineWidth: 1
        )
        .animation(microMotion, value: isEditing)
    )
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .modifier(RowTapModifier(enabled: !isEditing, single: onSelect, double: onBeginEdit))
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var infoVisible: Bool { hovering || isSelected || showsInspector }

  private var background: Color {
    if isEditing { return Color(nsColor: .textBackgroundColor).opacity(0.85) }
    if isHighlighted { return Color.accentColor.opacity(0.18) }
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
        .strikethrough(isChecked, color: .secondary)
        .foregroundStyle(isChecked ? .secondary : .primary)
        .opacity(isChecked ? 0.58 : 1)
        .lineLimit(2)
    }
  }

  private var metaText: Text? {
    var parts: [Text] = []
    if item.isRecurring {
      parts.append(Text(Image(systemName: "repeat")))
    }
    if let due = item.dueDay {
      parts.append(
        Text(String(format: String(localized: "Due %@"), shortDate(due)))
          .foregroundStyle(item.overdue && !isChecked ? Color.red : Color.secondary))
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
  let reduceMotion: Bool
  let action: () -> Void

  @State private var hovering = false
  @State private var rippleScale: CGFloat = 0.85
  @State private var rippleOpacity: Double = 0

  var body: some View {
    Button(action: action) {
      ZStack {
        if !reduceMotion && rippleOpacity > 0.001 {
          Circle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: 16, height: 16)
            .scaleEffect(rippleScale)
            .opacity(rippleOpacity)
            .allowsHitTesting(false)
        }
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 16))
          .foregroundStyle(
            isOn
              ? AnyShapeStyle(TintShapeStyle())
              : (hovering
                ? AnyShapeStyle(Color.accentColor.opacity(0.75))
                : AnyShapeStyle(HierarchicalShapeStyle.secondary))
          )
          .contentTransition(.symbolEffect(.replace.downUp))
        if !isOn && hovering {
          Image(systemName: "checkmark")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(Color.accentColor.opacity(0.4))
            .transition(.opacity.combined(with: .scale(scale: 0.7)))
        }
      }
      .frame(width: 18, height: 18)
      .contentShape(Circle())
    }
    .buttonStyle(TactilePlainButtonStyle(pressedScale: 0.85, reduceMotion: reduceMotion))
    .onHover { hovering = $0 }
    .animation(FocusMotion.micro(reduceMotion), value: hovering)
    .onChange(of: isOn) { oldValue, newValue in
      guard !oldValue, newValue, !reduceMotion else { return }
      rippleScale = 0.85
      rippleOpacity = 0.45
      withAnimation(.easeOut(duration: 0.38)) {
        rippleScale = 1.65
        rippleOpacity = 0
      }
    }
    .accessibilityLabel(
      String(format: String(localized: isOn ? "Reopen %@" : "Complete %@"), title))
  }
}

private struct SectionHeader: View {
  let title: String
  var tint: Color? = nil

  var body: some View {
    HStack(spacing: 5) {
      if let tint {
        Circle()
          .fill(tint)
          .frame(width: 5, height: 5)
      }
      Text(title)
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .tracking(0.5)
        .foregroundStyle(
          tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(HierarchicalShapeStyle.secondary)
        )
    }
    .padding(.horizontal, 6).padding(.top, 5).padding(.bottom, 2)
    .accessibilityAddTraits(.isHeader)
  }
}

private struct CompletedSectionButton: View {
  let count: Int
  let expanded: Bool
  let pulsing: Bool
  let reduceMotion: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .bold))
          .rotationEffect(.degrees(expanded ? 90 : 0))
          .animation(FocusMotion.snappy(reduceMotion), value: expanded)
        Text(String(localized: "Completed"))
          .font(.caption.weight(.semibold))
          .textCase(.uppercase)
          .tracking(0.5)
        Text(count.formatted())
          .font(.caption.weight(.medium))
          .monospacedDigit()
          .foregroundStyle(pulsing ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(.tertiary))
          .contentTransition(.numericText())
          .scaleEffect(pulsing ? 1.12 : 1.0)
        Spacer(minLength: 0)
      }
      .foregroundStyle(.secondary)
      .padding(.horizontal, 6).padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(
            pulsing
              ? Color.accentColor.opacity(0.1)
              : (hovering ? Color.primary.opacity(0.05) : Color.clear)
          )
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(FocusMotion.micro(reduceMotion), value: hovering)
    .animation(FocusMotion.snappy(reduceMotion), value: pulsing)
    .animation(FocusMotion.snappy(reduceMotion), value: count)
    .accessibilityValue(
      String(localized: expanded ? "Expanded" : "Collapsed"))
  }
}

// MARK: - Inspector

private struct TaskInspector: View {
  @Environment(\.dismiss) private var dismiss
  private let item: VisibleTask
  private let reduceMotion: Bool
  private let onSave: (TaskDraft) -> Bool
  @State private var draft: TaskDraft

  init(item: VisibleTask, reduceMotion: Bool, onSave: @escaping (TaskDraft) -> Bool) {
    self.item = item
    self.reduceMotion = reduceMotion
    self.onSave = onSave
    _draft = State(initialValue: item.draft)
  }

  private var smoothMotion: Animation? { FocusMotion.smooth(reduceMotion) }

  var body: some View {
    Form {
      TextField(String(localized: "Title"), text: $draft.title)
        .onSubmit { dismiss() }
      TextField(String(localized: "Notes"), text: $draft.notes, axis: .vertical)
        .lineLimit(2...5)
      LabeledContent(String(localized: "Time")) {
        HStack(spacing: 6) {
          if let minute = draft.minuteOfDay {
            DatePicker(
              String(localized: "Time"),
              selection: Binding(
                get: { dateForMinute(minute) },
                set: { draft.minuteOfDay = minuteOfDay(from: $0) }),
              displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .transition(.opacity.combined(with: .move(edge: .trailing)))
          }
          Toggle(
            String(localized: "Set a time"),
            isOn: Binding(
              get: { draft.minuteOfDay != nil },
              set: { enabled in
                withAnimation(smoothMotion) {
                  draft.minuteOfDay = enabled ? (draft.minuteOfDay ?? nextHourMinute()) : nil
                }
              })
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
            .transition(.opacity.combined(with: .move(edge: .trailing)))
          }
          Toggle(
            String(localized: "Set a deadline"),
            isOn: Binding(
              get: { draft.dueDay != nil },
              set: { enabled in
                withAnimation(smoothMotion) {
                  draft.dueDay = enabled ? (draft.dueDay ?? LocalDay(.now)) : nil
                }
              })
          )
          .toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
      }
      if item.isRecurring {
        Text(String(localized: "Changes apply to this occurrence only."))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.columns)
    .padding(14)
    .frame(width: 300)
    .animation(smoothMotion, value: draft.minuteOfDay != nil)
    .animation(smoothMotion, value: draft.dueDay != nil)
    .onDisappear(perform: saveIfChanged)
  }

  private func saveIfChanged() {
    let original = item.draft
    var edited = draft
    edited.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !edited.title.isEmpty else { return }
    let changed =
      edited.title != original.title || edited.notes != original.notes
      || edited.minuteOfDay != original.minuteOfDay
      || edited.dueDay != original.dueDay
    if changed { _ = onSave(edited) }
  }
}

// MARK: - Small controls

private struct MoreMenuButton: View {
  @Binding var showCompleted: Bool
  let reduceMotion: Bool
  let onSettings: () -> Void
  @State private var hovering = false

  var body: some View {
    Menu {
      Toggle(String(localized: "Show completed tasks"), isOn: $showCompleted)
      Divider()
      Button(String(localized: "Settings…"), action: onSettings)
        .keyboardShortcut(",")
      Button(String(localized: "Quit Focus Bar")) { NSApp.terminate(nil) }
        .keyboardShortcut("q")
    } label: {
      Image(systemName: "ellipsis.circle")
        .font(.system(size: 14))
        .foregroundStyle(hovering ? .primary : .secondary)
        .frame(width: 22, height: 22)
        .background(
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.08 : 0))
        )
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { hovering = $0 }
    .animation(FocusMotion.micro(reduceMotion), value: hovering)
    .help(String(localized: "More"))
  }
}

private struct RepeatMenuButton: View {
  @Binding var frequency: TaskFrequency
  @Binding var weekdays: Set<Int>
  let reduceMotion: Bool
  @State private var hovering = false

  private var snappyMotion: Animation? { FocusMotion.snappy(reduceMotion) }

  var body: some View {
    Menu {
      Picker(
        String(localized: "Repeat"),
        selection: Binding(
          get: { frequency },
          set: { newValue in withAnimation(snappyMotion) { frequency = newValue } })
      ) {
        ForEach(TaskFrequency.allCases) { Text($0.label).tag($0) }
      }
      .pickerStyle(.inline)
      .labelsHidden()
      if frequency == .weekly {
        Picker(
          String(localized: "Repeat on"),
          selection: Binding(
            get: {
              weekdays.first ?? Calendar.current.component(.weekday, from: .now)
            },
            set: { newDay in withAnimation(snappyMotion) { weekdays = [newDay] } })
        ) {
          ForEach(1...7, id: \.self) { weekday in
            Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
          }
        }
        .pickerStyle(.inline)
      }
    } label: {
      Image(systemName: "repeat")
        .font(.system(size: 13))
        .frame(width: 18, height: 20)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .foregroundStyle(
          frequency == .never
            ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
            : AnyShapeStyle(TintShapeStyle())
        )
        .background(
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.07 : 0))
        )
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { hovering = $0 }
    .animation(FocusMotion.micro(reduceMotion), value: hovering)
    .help(String(localized: "Repeat"))
    .accessibilityLabel(String(localized: "Repeat"))
  }
}

private struct TactilePlainButtonStyle: ButtonStyle {
  var pressedScale: CGFloat = 0.9
  var reduceMotion: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1.0)
      .animation(FocusMotion.snappy(reduceMotion), value: configuration.isPressed)
  }
}

/// Borderless button with the subtle hover/pressed background used by system menu bar panels.
private struct HoverButtonStyle: ButtonStyle {
  var reduceMotion: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    HoverButtonBody(configuration: configuration, reduceMotion: reduceMotion)
  }
}

private struct HoverButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let reduceMotion: Bool
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
              configuration.isPressed ? 0.13 : (hovering && isEnabled ? 0.07 : 0)))
      )
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1.0)
      .animation(FocusMotion.micro(reduceMotion), value: hovering)
      .animation(FocusMotion.snappy(reduceMotion), value: configuration.isPressed)
      .contentShape(Rectangle())
      .onHover { hovering = $0 }
  }
}

private struct FieldPopoverButton<Content: View>: View {
  let systemImage: String
  let isActive: Bool
  let help: String
  let reduceMotion: Bool
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
    .buttonStyle(HoverButtonStyle(reduceMotion: reduceMotion))
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
  let reduceMotion: Bool
  let onClear: () -> Void
  @State private var clearHovering = false

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: systemImage).imageScale(.small)
      Text(text)
      Button(action: onClear) {
        Image(systemName: "xmark")
          .font(.system(size: 8, weight: .bold))
          .frame(width: 13, height: 13)
          .background(Circle().fill(Color.primary.opacity(clearHovering ? 0.12 : 0)))
      }
      .buttonStyle(TactilePlainButtonStyle(pressedScale: 0.85, reduceMotion: reduceMotion))
      .onHover { clearHovering = $0 }
      .animation(FocusMotion.micro(reduceMotion), value: clearHovering)
      .accessibilityLabel(String(format: String(localized: "Remove %@"), text))
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.leading, 7).padding(.trailing, 4).padding(.vertical, 3)
    .background(Capsule().fill(Color.primary.opacity(0.07)))
  }
}

// MARK: - Helpers

extension VisibleTask {
  fileprivate var reopenedCopy: VisibleTask {
    VisibleTask(
      id: id, title: title, notes: notes, dueDay: dueDay, minuteOfDay: minuteOfDay,
      completed: false, completedAt: nil, overdue: overdue, isRecurring: isRecurring,
      sourceID: sourceID, sortOrder: sortOrder, occurrenceDay: occurrenceDay)
  }

  fileprivate var draft: TaskDraft {
    TaskDraft(
      title: title, notes: notes, minuteOfDay: minuteOfDay, dueDay: dueDay,
      frequency: .never)
  }
}

private func shortDate(_ day: LocalDay) -> String {
  day.date.formatted(.dateTime.month(.abbreviated).day())
}

private func dateForMinute(_ minute: Int) -> Date {
  let day = LocalDay(.now)
  return Calendar.current.date(
    bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day.date) ?? day.date
}

private func minuteOfDay(from date: Date) -> Int {
  let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
  return (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
}

private func nextHourMinute() -> Int {
  min(23, Calendar.current.component(.hour, from: .now) + 1) * 60
}

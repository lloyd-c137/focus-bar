import AppKit
import SwiftUI

struct QuickAddTextField: NSViewRepresentable {
  @Binding var text: String
  let placeholder: String
  let onSubmit: (String) -> Bool
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField(string: text)
    field.delegate = context.coordinator
    field.placeholderString = placeholder
    field.font = .preferredFont(forTextStyle: .body)
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .default
    field.setAccessibilityLabel(placeholder)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    DispatchQueue.main.async {
      field.window?.makeFirstResponder(field)
    }
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text {
      field.stringValue = text
    }
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: QuickAddTextField
    private var isSubmitting = false

    init(_ parent: QuickAddTextField) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.text = field.stringValue
    }

    func control(
      _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        let title = (control as? NSTextField)?.stringValue ?? parent.text
        guard
          canSubmitQuickAdd(
            title: title, hasMarkedText: textView.hasMarkedText(), isSubmitting: isSubmitting
          )
        else {
          return isSubmitting
        }
        isSubmitting = true
        isSubmitting = parent.onSubmit(title)
        return true
      }
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        parent.onCancel()
        return true
      }
      return false
    }
  }
}

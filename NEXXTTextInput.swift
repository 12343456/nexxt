import SwiftUI
import UIKit

/// Native UIKit input used throughout NEXXT.
/// It deliberately requests first-responder status after the view is in a window.
/// This makes the iPad software keyboard appear reliably in Swift Playgrounds.
struct NEXXTTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var secure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .done
    var autoFocus: Bool = false
    var onReturn: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.delegate = context.coordinator
        field.text = text
        field.placeholder = placeholder
        field.isSecureTextEntry = secure
        field.keyboardType = keyboardType
        field.returnKeyType = returnKeyType
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
        field.borderStyle = .roundedRect
        field.backgroundColor = UIColor.secondarySystemBackground
        field.textColor = UIColor.label
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.isUserInteractionEnabled = true
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        context.coordinator.field = field
        context.coordinator.scheduleFocusIfNeeded()
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.field = uiView
        if uiView.text != text { uiView.text = text }
        if uiView.placeholder != placeholder { uiView.placeholder = placeholder }
        if uiView.keyboardType != keyboardType { uiView.keyboardType = keyboardType }
        if uiView.returnKeyType != returnKeyType { uiView.returnKeyType = returnKeyType }
        // Do not repeatedly toggle secure entry while editing: that can reset first responder.
        if uiView.isSecureTextEntry != secure && !uiView.isFirstResponder {
            uiView.isSecureTextEntry = secure
        }
        context.coordinator.scheduleFocusIfNeeded()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NEXXTTextField
        weak var field: UITextField?
        private var focusScheduled = false

        init(_ parent: NEXXTTextField) { self.parent = parent }

        @objc func editingChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.text = textField.text ?? ""
            if let action = parent.onReturn {
                action()
            } else {
                textField.resignFirstResponder()
            }
            return true
        }

        func scheduleFocusIfNeeded() {
            guard parent.autoFocus, let field, !field.isFirstResponder, !focusScheduled else { return }
            focusScheduled = true
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field else { return }
                self.focusScheduled = false
                guard field.window != nil, UIApplication.shared.applicationState == .active else { return }
                field.becomeFirstResponder()
            }
        }
    }
}

struct NEXXTTextEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 44
    var maxHeight: CGFloat = 130
    var autoFocus: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(frame: .zero)
        view.delegate = context.coordinator
        view.text = text
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.textColor = UIColor.label
        view.backgroundColor = UIColor.secondarySystemBackground
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        view.isScrollEnabled = true
        view.isUserInteractionEnabled = true
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.keyboardType = .default
        view.returnKeyType = .default
        view.textContainerInset = UIEdgeInsets(top: 9, left: 11, bottom: 9, right: 11)
        view.textContainer.lineFragmentPadding = 0
        view.accessibilityLabel = placeholder
        context.coordinator.installPlaceholder(on: view)
        context.coordinator.textView = view
        context.coordinator.scheduleFocusIfNeeded()
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = uiView
        if uiView.text != text { uiView.text = text }
        context.coordinator.updatePlaceholder(on: uiView)
        context.coordinator.scheduleFocusIfNeeded()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NEXXTTextEditor
        weak var placeholderLabel: UILabel?
        weak var textView: UITextView?
        private var focusScheduled = false

        init(_ parent: NEXXTTextEditor) { self.parent = parent }

        func installPlaceholder(on textView: UITextView) {
            let label = UILabel()
            label.text = parent.placeholder
            label.textColor = UIColor.secondaryLabel
            label.font = textView.font
            label.numberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            textView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 11),
                label.topAnchor.constraint(equalTo: textView.topAnchor, constant: 9),
                label.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -11)
            ])
            placeholderLabel = label
            updatePlaceholder(on: textView)
        }

        func updatePlaceholder(on textView: UITextView) {
            placeholderLabel?.isHidden = !textView.text.isEmpty
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updatePlaceholder(on: textView)
        }

        func scheduleFocusIfNeeded() {
            guard parent.autoFocus, let textView, !textView.isFirstResponder, !focusScheduled else { return }
            focusScheduled = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.focusScheduled = false
                guard textView.window != nil, UIApplication.shared.applicationState == .active else { return }
                textView.becomeFirstResponder()
            }
        }
    }
}

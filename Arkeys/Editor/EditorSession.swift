import Combine
import EditorKit
import InputRuntime

@MainActor
final class EditorSession {
    let controller = KeymapEditorController()
    var onWillStart: (() -> Void)?
    var onEnded: (() -> Void)?

    private weak var runtime: InputRuntime?
    private var cancellables = Set<AnyCancellable>()

    func attach(runtime: InputRuntime) {
        self.runtime = runtime
        cancellables.removeAll()
        controller.chromeCopy = EditorChromeCopy(
            cancel: String(localized: "menu.editor.cancel"),
            done: String(localized: "menu.editor.done")
        )
        runtime.$keymapButtonShape
            .sink { [weak self] shape in
                self?.controller.buttonShape = shape
            }
            .store(in: &cancellables)

        controller.onFinished = { [weak self] map in
            guard let self, let runtime = self.runtime else { return }
            runtime.keymap = map
            runtime.saveKeymap()
            runtime.isEditing = false
            runtime.onEditorKeyDown = nil
            self.onEnded?()
        }
        controller.onCancelled = { [weak self] in
            guard let self, let runtime = self.runtime else { return }
            runtime.isEditing = false
            runtime.onEditorKeyDown = nil
            self.onEnded?()
        }
    }

    func start() {
        guard let runtime,
              let bundleID = runtime.targetBundleID,
              runtime.activeSchemeID != nil else {
            return
        }
        onWillStart?()
        runtime.isEditing = true
        runtime.onEditorKeyDown = { [weak controller] code, name in
            controller?.bindKey(keyCode: code, name: name)
        }
        controller.buttonShape = runtime.keymapButtonShape
        controller.start(targetBundleID: bundleID, keymap: runtime.keymap)
    }

    func finish() {
        controller.finish()
    }

    func cancel() {
        controller.cancel()
    }
}

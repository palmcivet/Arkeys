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
            cancel: String(localized: "common.cancel"),
            done: String(localized: "editor.done"),
            idleStatus: String(localized: "editor.status.idle"),
            waitingStatus: String(localized: "editor.status.waiting"),
            selectButtonFirst: String(localized: "editor.status.selectFirst"),
            boundFormat: String(localized: "editor.status.bound"),
            deleted: String(localized: "editor.status.deleted"),
            selectedFormat: String(localized: "editor.status.selected"),
            deleteKey: String(localized: "editor.delete"),
            resizeKey: String(localized: "editor.resize"),
            deleteHelp: String(localized: "common.delete"),
            resizeHelp: String(localized: "editor.resize.help"),
            resizeHint: String(localized: "editor.resize.hint"),
            keyHint: String(localized: "editor.key.hint"),
            addKey: String(localized: "editor.addKey"),
            moveLeft: String(localized: "editor.move.left"),
            moveRight: String(localized: "editor.move.right"),
            moveUp: String(localized: "editor.move.up"),
            moveDown: String(localized: "editor.move.down")
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

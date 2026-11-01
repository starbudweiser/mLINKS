import AppKit
import SwiftUI
import mLINKSCore

/// Bouton de saisie d'un raccourci global. Échap annule, ⌫ efface.
struct ShortcutRecorder: View {
    let link: LinkItem
    @EnvironmentObject private var store: LinkStore
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space1_5) {
            HStack(spacing: Socle.M.space2) {
                Button(recording ? L("shortcut.recording") : link.hotkey.map(KeyName.label) ?? L("shortcut.none")) {
                    recording ? stop() : start()
                }
                .buttonStyle(SocleButtonStyle(.secondary))
                .fixedSize()
                if link.hotkey != nil, !recording {
                    Button(L("shortcut.clear")) { assign(nil) }.buttonStyle(SocleButtonStyle(.tertiary)).fixedSize()
                }
            }
            if let message {
                Text(message).socle(Socle.T.meta).foregroundStyle(Socle.C.danger)
            } else if store.hotkeyFailures.contains(link.id) {
                Text(L("shortcut.taken.system")).socle(Socle.T.meta).foregroundStyle(Socle.C.danger)
            } else if recording {
                Text(L("shortcut.hint")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil
        recording = true
        store.suspendHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        store.bindHotkeys()
    }

    private func handle(_ event: NSEvent) {
        let code = Int(event.keyCode)
        if code == 53 { stop(); return } // Échap
        if code == 51 { stop(); assign(nil); return } // ⌫
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        guard !flags.isEmpty || KeyName.isFunctionKey(code) else {
            message = L("shortcut.needs.modifier")
            return
        }
        let hotkey = Hotkey(keyCode: code, modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        if let owner = store.library.owner(of: hotkey, excluding: link.id) {
            message = L("shortcut.taken.link", owner.name)
            return
        }
        stop()
        assign(hotkey)
    }

    private func assign(_ hotkey: Hotkey?) {
        message = nil
        store.mutate { $0.update(link.id) { $0.hotkey = hotkey } }
    }
}

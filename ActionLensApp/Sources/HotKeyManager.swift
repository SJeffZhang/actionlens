import Carbon
import Foundation

final class HotKeyManager {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandlerInstalled = false
    private static var nextIdentifier: UInt32 = 1
    private static let eventCallback: EventHandlerUPP = { _, eventRef, _ in
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        if status == noErr, let handler = HotKeyManager.handlers[hotKeyID.id] {
            handler()
        }
        return noErr
    }

    private var hotKeyRef: EventHotKeyRef?
    private let identifier: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        identifier = Self.nextIdentifier
        Self.nextIdentifier += 1
        Self.handlers[identifier] = handler

        Self.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x414C454E), id: identifier)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status != noErr {
            Self.handlers.removeValue(forKey: identifier)
            return nil
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        Self.handlers.removeValue(forKey: identifier)
    }

    private static func installHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), eventCallback, 1, &eventType, nil, nil)

        eventHandlerInstalled = true
    }
}

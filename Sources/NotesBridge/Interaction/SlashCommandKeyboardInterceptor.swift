import CoreGraphics
import Foundation

enum SlashCommandKeyboardAction: Sendable {
    case moveUp
    case moveDown
    case commit
    case dismiss
}

final class SlashCommandKeyboardInterceptor {
    private let onAction: (SlashCommandKeyboardAction) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onAction: @escaping (SlashCommandKeyboardAction) -> Void) {
        self.onAction = onAction
    }

    func start() -> Bool {
        guard eventTap == nil else {
            return true
        }

        let eventMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let interceptor = Unmanaged<SlashCommandKeyboardInterceptor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                return interceptor.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, let action = action(for: event.getIntegerValueField(.keyboardEventKeycode)) else {
            return Unmanaged.passUnretained(event)
        }

        onAction(action)
        return nil
    }

    private func action(for keyCodeValue: Int64) -> SlashCommandKeyboardAction? {
        switch CGKeyCode(keyCodeValue) {
        case 125:
            .moveDown
        case 126:
            .moveUp
        case 36, 48, 76:
            .commit
        case 53:
            .dismiss
        default:
            nil
        }
    }
}

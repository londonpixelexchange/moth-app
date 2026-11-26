import Testing
@testable import SwiftTerm

struct MouseMotionTests {
    @Test(arguments: [1006, 1016])
    func sgrDistinguishesMotionReleaseAndWheel(protocolMode: Int) {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()
        terminal.feed(text: "\u{1b}[?1003h\u{1b}[?\(protocolMode)h")
        let coordinates = protocolMode == 1016 ? "12;18" : "3;4"
        for (flags, expected) in [(0, "0;\(coordinates)M"), (3, "0;\(coordinates)m"),
                                   (35, "35;\(coordinates)M"), (39, "39;\(coordinates)M"),
                                   (64, "64;\(coordinates)M"), (65, "65;\(coordinates)M"),
                                   (19, "16;\(coordinates)m")] {
            terminal.sendEvent(buttonFlags: flags, x: 2, y: 3, pixelX: 12, pixelY: 18)
            #expect(String(decoding: delegate.sentData.last!, as: UTF8.self) == "\u{1b}[<\(expected)")
        }
    }

    @Test func buttonTrackingIncludesDraggingButNotHover() {
        #expect(Terminal.MouseMode.buttonEventTracking.sendButtonTracking())
        #expect(!Terminal.MouseMode.buttonEventTracking.sendMotionEvent())
        #expect(Terminal.MouseMode.anyEvent.sendButtonTracking())
        #expect(Terminal.MouseMode.anyEvent.sendMotionEvent())
        #expect(!Terminal.MouseMode.vt200.sendButtonTracking())
    }
}

#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

final class PasteTests {
    private final class CaptureView: LocalProcessTerminalView {
        var sent: [UInt8] = []
        override func send(source: TerminalView, data: ArraySlice<UInt8>) {
            sent.append(contentsOf: data)
        }
    }

    @Test(arguments: ["\n", "\r\n", "\r"], [false, true])
    func pastedLinesUseReturnBytes(ending: String, bracketed: Bool) {
        let view = CaptureView(frame: CGRect(x: 0, y: 0, width: 600, height: 300))
        view.feed(text: bracketed ? "\u{1b}[?2004h" : "\u{1b}[?2004l")
        // Include blank lines, indentation and a trailing newline.
        let lines = ["testing", "testing", "1 2 3", "", "  indented", ""]
        view.insertText(lines.joined(separator: ending), replacementRange: NSRange(location: 0, length: 0), isPaste: true)
        let expected = (bracketed ? "\u{1b}[200~" : "")
            + lines.joined(separator: "\r") + (bracketed ? "\u{1b}[201~" : "")
        #expect(view.sent == Array(expected.utf8))
    }

    @Test func typedTextKeepsItsOriginalBytes() {
        let view = CaptureView(frame: CGRect(x: 0, y: 0, width: 600, height: 300))
        let text = "one\ntwo\r\nthree"
        view.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        #expect(view.sent == Array(text.utf8))
    }
}
#endif

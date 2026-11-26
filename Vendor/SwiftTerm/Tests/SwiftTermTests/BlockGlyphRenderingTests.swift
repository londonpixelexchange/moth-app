#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

@Suite(.serialized)
final class BlockGlyphRenderingTests {
    @Test(arguments: Array(0x2580...0x259F))
    func everyBlockElementUsesCellGeometry(code: Int) {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let terminal = view.getTerminal()
        terminal.resize(cols: 40, rows: 4)
        view.feed(text: String(UnicodeScalar(code)!))
        let line = view.buildAttributedString(row: 0, line: terminal.buffer.lines[0], cols: 1)
        #expect(line.blockElements.count == 1, "U+\(String(code,radix:16)) fell back to a font glyph")
    }

    @Test func customBlockRenderingRemainsOptional() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        view.customBlockGlyphs = false
        view.feed(text: "▀▟")
        let line = view.buildAttributedString(row: 0, line: view.getTerminal().buffer.lines[0], cols: 2)
        #expect(line.blockElements.isEmpty)
    }

    @Test func neighbouringSymbolsStayOutsideTheBlockRange() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        view.feed(text: "■▀")
        let line = view.buildAttributedString(row: 0, line: view.getTerminal().buffer.lines[0], cols: 2)
        #expect(line.blockElements.map(\.column) == [1])
    }
}
#endif

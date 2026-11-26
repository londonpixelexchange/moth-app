#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

@Suite(.serialized)
struct ColourCellRenderingTests {
    func view(_ text: String) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 600, height: 200))
        view.feed(text: text)
        return view
    }
    func info(_ view: TerminalView, cols: Int) -> ViewLineInfo {
        view.buildAttributedString(row: 0, line: view.getTerminal().buffer.lines[0], cols: cols)
    }
    @Test func ordinaryTextKeepsSpacesInItsShapingContext() {
        let line = info(view("abc def"), cols: 7)
        #expect(line.segments.count == 1)
        #expect(line.segments.first?.attributedString.string == "abc def")
    }
    @Test func graphicsSkipShapingWithoutMovingNeighbouringText() {
        let line = info(view("a▀ b▟c"), cols: 6)
        #expect(line.segments.map(\.column) == [0, 3, 5])
        #expect(line.segments.map { $0.attributedString.string } == ["a", "b", "c"])
        #expect(line.blockElements.map(\.column) == [1, 4])
        #expect(line.cellBackgrounds.map(\.column) == [1, 2, 4])
    }
    @Test(arguments: ["", "1;", "2;", "7;", "1;2;7;"])
    func geometricColoursMatchText(styles: String) throws {
        let view = view("\u{1b}[\(styles)38;2;21;93;117;48;2;177;63;12m▀x")
        let line = info(view, cols: 2)
        let attrs = try #require(line.segments.first?.attributedString.attributes(at: 0, effectiveRange: nil))
        #expect(line.blockElements.first?.foregroundColor == attrs[.foregroundColor] as? NSColor)
        #expect(line.cellBackgrounds.first?.color == attrs[.backgroundColor] as? NSColor)
    }
    @Test(arguments: ["4", "9"])
    func decoratedCellsKeepTextLayout(style: String) {
        let line = info(view("\u{1b}[\(style)m▀ "), cols: 2)
        #expect(line.cellBackgrounds.isEmpty)
        #expect(!line.segments.isEmpty)
    }
    @Test func selectedBlockKeepsItsForegroundAndSelectionBackground() {
        let view = view("▀")
        view.selection.setSoftStart(bufferPosition: Position(col: 0, row: 0))
        view.selection.dragExtend(bufferPosition: Position(col: 1, row: 0))
        let line = info(view, cols: 1)
        #expect(line.cellBackgrounds.first?.color == view.selectedTextBackgroundColor)
        #expect(line.blockElements.count == 1)
    }
    @Test func animatedTruecolourCachesStayBounded() {
        let view = view("")
        for n in 0..<18000 {
            view.feed(text: "\u{1b}[H\u{1b}[38;2;\(n%256);\(n/256);0mx")
            _ = info(view, cols: 1)
        }
        #expect(view.attributes.count <= 4096)
        #expect(view.trueColors.count <= 4096)
    }
}
#endif

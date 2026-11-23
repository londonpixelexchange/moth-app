#if os(macOS)
import Foundation
import Testing
@testable import SwiftTerm

@Suite(.serialized)
final class MothSearchTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
    func terminal(cols: Int = 20, rows: Int = 6, history: Int = 100) -> Terminal {
        Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: rows, scrollback: history))
    }
    @Test func literalAndCaseSensitivity() {
        let t = terminal(); t.feed(text: "Moth moth .*[test]\r\n")
        #expect(t.find("moth").matches.count == 2)
        #expect(t.find("moth", caseSensitive: true).matches.count == 1)
        #expect(t.find(".*[test]").matches.count == 1)
        #expect(t.find("").matches.isEmpty)
    }
    @Test func matchesAcrossSoftWrapsButNotNewlines() {
        let t = terminal(cols: 10); t.feed(text: "abcdefghijklmnop\r\nQRST\r\nUVWX")
        let matches = t.find("ijklmn").matches
        #expect(matches.count == 1)
        #expect(matches.first?.startRow == 0 && matches.first?.startColumn == 8)
        #expect(matches.first?.endRow == 1 && matches.first?.endColumn == 4)
        #expect(t.find("QRSTUVWX").matches.isEmpty)
    }
    @Test func unicodeGraphemesMapToTerminalCells() {
        let t = terminal(); t.feed(text: "a界e\u{301} 👩‍💻 z")
        let wide = t.find("界").matches.first
        #expect(wide?.startColumn == 1 && wide?.endColumn == 3)
        #expect(t.find("e\u{301}").matches.count == 1)
        #expect(t.find("👩‍💻").matches.count == 1)
    }
    @Test func scrollbackEvictionAndAlternateScreen() {
        let t = terminal(rows: 3, history: 4)
        t.feed(text: (0..<20).map { "record\($0)\r\n" }.joined())
        #expect(t.find("record0", caseSensitive: true).matches.isEmpty)
        #expect(t.find("record19").matches.first?.startRow ?? 0 > 0)
        t.feed(text: "\u{1b}[?1049hALTERNATE")
        #expect(t.find("record19").matches.isEmpty)
        #expect(t.find("ALTERNATE").matches.count == 1)
        t.feed(text: "\u{1b}[?1049l")
        #expect(t.find("record19").matches.count == 1)
    }
    @Test func shrinkingHistoryKeepsStableRowIndices() {
        let t = terminal(rows: 3, history: 100)
        t.feed(text: (0..<20).map { "record\($0)\r\n" }.joined())
        let recent = t.find("record19").matches.first!
        t.changeHistorySize(1)
        #expect(t.find("record19").matches.first == recent)
        #expect(t.find("record0").matches.isEmpty)
    }
    @Test func boundedResultsAndOutputRevision() {
        let t = terminal(); let version = t.searchContentVersion
        t.feed(text: "a a a a a")
        #expect(t.searchContentVersion > version)
        let result = t.find("a", limit: 3)
        #expect(result.matches.count == 3 && result.truncated)
        let beforeResize = t.searchContentVersion; t.resize(cols: 12, rows: 6)
        #expect(t.searchContentVersion > beforeResize)
    }
    @Test func wideCharacterWrapDoesNotInsertASpace() {
        let t = terminal(cols: 10, rows: 12)
        t.feed(text: "first\r\nabcdefghi界WXYZ\r\nend\r\n")
        #expect(t.find("abcdefghi界WXYZ").matches.count == 1)
        t.resize(cols: 22, rows: 12)
        #expect(t.find("abcdefghi界WXYZ").matches.count == 1)
    }
    @Test func imageAnchorsSurviveWrappedTextReflow() {
        let t = terminal(cols: 10, rows: 12)
        t.feed(text: "first\r\nabcdefghijklmnopqr\r\nend\r\n")
        t.buffer.attachImage(MockTerminalImage(col: 2), toLineAt: 2)
        t.resize(cols: 22, rows: 12)
        #expect(t.buffer.hasAnyImages)
        #expect(t.buffer.lines[1].images?.first?.col == 12)
        #expect((0..<t.buffer.lines.count).reduce(0) { $0 + (t.buffer.lines[$1].images?.count ?? 0) } == 1)
        t.resize(cols: 7, rows: 12)
        #expect(t.buffer.hasAnyImages)
        #expect((0..<t.buffer.lines.count).reduce(0) { $0 + (t.buffer.lines[$1].images?.count ?? 0) } == 1)
    }
    @Test func wideningLaterParagraphKeepsText() {
        let t = terminal(cols: 10, rows: 12)
        t.feed(text: "x\r\nabcdefghijklmnopqr\r\nend\r\n")
        #expect(t.find("abcdefghijklmnopqr").matches.count == 1)
        t.resize(cols: 22, rows: 12)
        #expect(t.find("abcdefghijklmnopqr").matches.count == 1)
        t.resize(cols: 7, rows: 12)
        #expect(t.find("abcdefghijklmnopqr").matches.count == 1)
    }
}
#endif

#if os(macOS)
extension MothSearchTests {
    @Test func regexPatternsCaseAndErrors() {
        let t = terminal(cols:40); t.feed(text:"error 123\r\nERROR 456\r\nnot-an-error")
        #expect(t.find("error [0-9]+",regularExpression:true).matches.count == 2)
        #expect(t.find("error [0-9]+",caseSensitive:true,regularExpression:true).matches.count == 1)
        #expect(t.find("[",regularExpression:true).error != nil)
        #expect(t.find("[",regularExpression:false).error == nil)
    }
    @Test func regexSoftWrapsAndUnicodeCellCoordinates() {
        let t = terminal(cols:10); t.feed(text:"abcdefghi界WXYZ\r\n👩‍💻 e\u{301}")
        let wrapped = t.find("ghi界W.*",regularExpression:true).matches.first
        #expect(wrapped?.startColumn == 6 && wrapped?.endRow == 1)
        #expect(t.find("👩‍💻.*e\\p{M}",regularExpression:true).matches.count == 1)
    }
    @Test func regexLimitAndZeroLengthMatches() {
        let t = terminal(); t.feed(text:"a a a a a")
        let result = t.find("a",limit:3,regularExpression:true)
        #expect(result.matches.count == 3 && result.truncated)
        #expect(t.find("^",regularExpression:true).matches.isEmpty)
    }
    @Test func regexBacktrackingCanBeCancelled() {
        let t = terminal(cols:1000,rows:20); t.feed(text:String(repeating:"a",count:10000)+"!")
        let start = Date(); let result = t.find("^(a+)+$",regularExpression:true)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(result.truncated)
    }
    @Test func plainTextExportJoinsSoftWraps() {
        let t = terminal(cols:10); t.feed(text:"\u{1b}[31mabcdefghijklmnop\u{1b}[0m\r\nsecond")
        #expect(t.exportPlainText().contains("abcdefghijklmnop\nsecond"))
        #expect(!t.exportPlainText().contains("\u{1b}"))
    }
}
#endif

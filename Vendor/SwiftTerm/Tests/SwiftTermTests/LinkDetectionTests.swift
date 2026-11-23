#if os(macOS)
import Testing
import Foundation
@testable import SwiftTerm
final class LinkDetectionTests {
    func terminal(_ text: String,cols: Int = 80) -> Terminal {
        var options = TerminalOptions.default; options.cols = cols
        let host = HeadlessTerminal(options:options) { _ in }
        let terminal = host.terminal!
        terminal.feed(byteArray:Array(text.utf8)); return terminal
    }
    @Test func detectsPlainWebURLsAndPunctuation() {
        let t = terminal("See https://getmoth.dev/docs/keyboard-layouts/#recovery.")
        #expect(t.detectedLink(column:15,bufferRow:0) == "https://getmoth.dev/docs/keyboard-layouts/#recovery")
        #expect(t.detectedLink(column:1,bufferRow:0) == nil)
        #expect(t.detectedLink(column:75,bufferRow:0) == nil)
    }
    @Test func softWrappedURLsStayTogether() {
        let url = "https://getmoth.dev/docs/keyboard-layouts/#recovery"
        let t = terminal(url,cols:18)
        #expect(t.detectedLink(column:4,bufferRow:1) == url)
    }
    @Test func repaintedFullWidthURLIncludesEveryRow() {
        let url = "https://cdn.discordapp.com/attachments/690251772102574089/1574230884528300103/IMG_0465.png?ex=6b04e442&is=6b0392c2&hm=994f20d30d39fdcbfcf0b50b61c9a8f7384fd98c61e3d79fc688d70c9389cea2&"
        let text = "phlud> "+url,columns = 80
        let characters = Array(text)
        let rows = stride(from:0,to:characters.count,by:columns).map { String(characters[$0..<min($0+columns,characters.count)]) }
        let t = terminal(rows.joined(separator:"\r\n"),cols:columns)
        for row in rows.indices {
            let column = row == 0 ? 10 : 2
            let match = t.detectedLinkMatch(column:column,bufferRow:row)
            #expect(match?.link == url)
            #expect(match?.range.startRow == 0)
            #expect(match?.range.startColumn == 7)
            #expect(match?.range.endRow == rows.count-1)
            #expect(match?.range.endColumn == rows.last!.count)
        }
    }
    @Test func whitespaceAtFullWidthBoundarySeparatesLinks() {
        let t = terminal("https://one.example \r\nhttps://two.example",cols:20)
        #expect(t.detectedLink(column:5,bufferRow:0) == "https://one.example")
        #expect(t.detectedLink(column:5,bufferRow:1) == "https://two.example")
    }
    @Test func hardLineBreaksNeverJoinURLs() {
        let t = terminal("https://example.\r\ncom/path")
        #expect(t.detectedLink(column:3,bufferRow:1) == nil)
    }
    @Test func unicodeBeforeURLKeepsCellMapping() {
        let t = terminal("🦋 e\u{301} https://getmoth.dev")
        #expect(t.detectedLink(column:10,bufferRow:0) == "https://getmoth.dev")
    }
    @Test func editorAndMailURLsPreserveEscapes() {
        let t = terminal("vscode://file/Users/me/My%20Project/main.swift")
        #expect(t.detectedLink(column:8,bufferRow:0) == "vscode://file/Users/me/My%20Project/main.swift")
        let mail = terminal("mailto:support@getmoth.dev")
        #expect(mail.detectedLink(column:10,bufferRow:0) == "mailto:support@getmoth.dev")
    }
    @Test func linkRangesFollowSoftWraps() {
        let t = terminal("https://getmoth.dev",cols:12)
        let match = t.detectedLinkMatch(column:2,bufferRow:1)
        #expect(match?.range.startRow == 0); #expect(match?.range.startColumn == 0)
        #expect(match?.range.endRow == 1); #expect(match?.range.endColumn == 7)
    }
    @Test func distinctLinksAreResolvedAtTheirOwnCells() {
        let t = terminal("https://one.example https://two.example")
        #expect(t.detectedLink(column:5,bufferRow:0) == "https://one.example")
        #expect(t.detectedLink(column:26,bufferRow:0) == "https://two.example")
    }
}
#endif

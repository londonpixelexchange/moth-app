#if os(macOS)
import Foundation
import Testing
@testable import SwiftTerm

@Suite(.serialized)
final class MothVTCompatibilityTests: TerminalDelegate {
    var responses = ""
    func send(source: Terminal, data: ArraySlice<UInt8>) { responses += String(decoding:data,as:UTF8.self) }
    func terminal() -> Terminal { Terminal(delegate:self,options:TerminalOptions(cols:20,rows:6,scrollback:30)) }
    @Test func doubleLineSequencesAndSingleWidthRestore() {
        let t=terminal()
        for (sequence,mode) in [("6",BufferLine.RenderLineMode.doubleWidth),("3",.doubledTop),("4",.doubledDown),("5",.single)] {
            t.feed(text:"\u{1b}#"+sequence)
            #expect(t.getLine(row:0)?.renderMode == mode)
        }
    }
    @Test func rightHalfIsErasedAndCursorClamped() {
        let t=terminal();t.feed(text:"ABCDEFGHIJKLMNOPQRST\u{1b}#6")
        #expect(t.getLine(row:0)?.translateToString(trimRight:true)=="ABCDEFGHIJ")
        #expect(t.buffer.x==9)
        t.feed(text:"\u{1b}[1;99H")
        #expect(t.buffer.x==9)
        t.feed(text:"\u{1b}[99C")
        #expect(t.buffer.x==9)
    }
    @Test func doubleSizeWrapsAtHalfTheNormalColumns() {
        let t=terminal();t.feed(text:"\u{1b}#6ABCDEFGHIJK")
        #expect(t.getLine(row:0)?.translateToString(trimRight:true)=="ABCDEFGHIJ")
        #expect(t.getLine(row:1)?.translateToString(trimRight:true)=="K")
        #expect(t.getLine(row:1)?.renderMode == .single)
    }
    @Test func disablingNormalizesBothScreensAndIgnoresNewRequests() {
        let t=terminal();t.feed(text:"\u{1b}#6normal\u{1b}[?1049h\u{1b}[H\u{1b}#3alternate")
        t.allowDoubleSizeLines=false
        #expect(t.normalBuffer.lines[0].renderMode == .single)
        #expect(t.altBuffer.lines[0].renderMode == .single)
        t.feed(text:"\u{1b}#4");#expect(t.getLine(row:0)?.renderMode == .single)
        #expect(t.getLine(row:0)?.translateToString(trimRight:true)=="alternate")
        t.allowDoubleSizeLines=true;t.feed(text:"\u{1b}#4")
        #expect(t.getLine(row:0)?.renderMode == .doubledDown)
    }
    @Test func hostPreferenceSurvivesFullReset() {
        let t=terminal();t.allowDoubleSizeLines=false;t.feed(text:"\u{1b}c\u{1b}#6TEXT")
        #expect(!t.allowDoubleSizeLines);#expect(t.getLine(row:0)?.renderMode == .single)
    }
    @Test func scrollingRetainsLineSizeAndRecycledRowsAreNormal() {
        let t=terminal();t.feed(text:"\u{1b}#6WIDE\r\n"+String(repeating:"normal\r\n",count:8))
        #expect(t.getScrollInvariantLine(row:0)?.renderMode == .doubleWidth)
        t.feed(text:String(repeating:"normal\r\n",count:80))
        #expect(t.getLine(row:5)?.renderMode == .single)
    }
    @Test func doubleHeightHalvesSurviveResizeWithoutJoining() {
        let t=terminal();t.feed(text:"\u{1b}#3ABCDE\r\n\u{1b}#4ABCDE\r\nordinary text")
        t.resize(cols:12,rows:6)
        #expect(t.getLine(row:0)?.renderMode == .doubledTop)
        #expect(t.getLine(row:1)?.renderMode == .doubledDown)
        #expect(t.getLine(row:0)?.translateToString(trimRight:true)=="ABCDE")
        t.resize(cols:30,rows:6)
        #expect(t.getLine(row:0)?.renderMode == .doubledTop)
        #expect(t.getLine(row:1)?.renderMode == .doubledDown)
    }
    @Test func movementAndTabsRespectDestinationLineWidth() {
        let t=terminal();t.feed(text:"\u{1b}#6WIDE\r\n\u{1b}[2;19H\u{1b}[A")
        #expect(t.buffer.x==9 && t.buffer.y==0)
        t.feed(text:"\r\t\t");#expect(t.buffer.x==9)
        t.feed(text:"\u{1b}[99G");#expect(t.buffer.x==9)
    }
    @Test func lineCopiesKeepSizeAttributes() {
        let t=terminal();t.feed(text:"\u{1b}#6WIDE")
        let copy=BufferLine(cols:20);copy.copyFrom(line:t.buffer.lines[0])
        #expect(copy.renderMode == .doubleWidth)
        copy.clear(with:CharData.defaultAttr);#expect(copy.renderMode == .single)
    }
    @Test func backarrowModeSetResetAndReports() {
        let t=terminal();#expect(t.backarrowSendsBackspace == nil)
        t.feed(text:"\u{1b}[?67h\u{1b}[?67$p")
        #expect(t.backarrowSendsBackspace == true);#expect(responses.hasSuffix("\u{1b}[?67;1$y"))
        t.feed(text:"\u{1b}[?67l\u{1b}[?67$p")
        #expect(t.backarrowSendsBackspace == false);#expect(responses.hasSuffix("\u{1b}[?67;2$y"))
        t.softReset();#expect(t.backarrowSendsBackspace == nil)
        t.feed(text:"\u{1b}[?67h\u{1b}c");#expect(t.backarrowSendsBackspace == nil)
    }
    @Test func reverseScreenModePreservesAttributesAndReportsIndependently() {
        let t=terminal();t.feed(text:"\u{1b}[31;1mRED");let attr=t.currentAttribute
        t.feed(text:"\u{1b}[?5h\u{1b}[?5$p")
        #expect(t.reverseVideo && t.currentAttribute==attr)
        #expect(responses.hasSuffix("\u{1b}[?5;1$y"))
        t.feed(text:"\u{1b}[?5l\u{1b}[7m\u{1b}[?5$p")
        #expect(!t.reverseVideo && t.currentAttribute.style.contains(.inverse))
        #expect(responses.hasSuffix("\u{1b}[?5;2$y"))
        t.feed(text:"\u{1b}[?5h\u{1b}c");#expect(!t.reverseVideo)
    }
    @Test func vt100OriginAndScrollingMargins() {
        let t=terminal();t.feed(text:"\u{1b}[2;5r\u{1b}[?6h\u{1b}[1;1HREGION")
        #expect(t.getLine(row:1)?.translateToString(trimRight:true)=="REGION")
        t.feed(text:"\u{1b}[99;99H");#expect(t.buffer.y==4 && t.buffer.x==19)
        t.feed(text:"\u{1b}[?6l\u{1b}[1;1HTOP")
        #expect(t.getLine(row:0)?.translateToString(trimRight:true)=="TOP")
    }
    @Test func vt100SpecialGraphicsSaveRestoreAndAlignment() {
        let t=terminal();t.feed(text:"\u{1b}(0lqk\u{1b}(B\u{1b}7\u{1b}[4;4Hother\u{1b}8Z")
        #expect(t.getLine(row:0)?.translateToString(trimRight:true)=="┌─┐Z")
        t.feed(text:"\u{1b}#8")
        #expect((0..<6).allSatisfy { t.getLine(row:$0)?.translateToString(trimRight:true)==String(repeating:"E",count:20) })
    }
}
#endif

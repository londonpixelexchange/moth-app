#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm
private final class BitmapScaleView: TerminalView {
    var imageScale: CGFloat = 2
    override func getImageScale() -> CGFloat { imageScale }
}
@Suite(.serialized)
struct BitmapRetinaSizingTests {
    @Test(arguments: [(600,300),(800,400),(1000,400),(240,120)])
    func retinaBitmapFitsUsingPointDimensions(_ sample:(Int,Int)) throws {
        let view=BitmapScaleView(frame:CGRect(x:0,y:0,width:400,height:200))
        view.feed(text:"\u{1b}[1;5H")
        var pixels=[UInt8](repeating:255,count:sample.0*24*4)
        view.createImageFromBitmap(source:view.getTerminal(),bytes:&pixels,width:sample.0,height:24)
        let image=try #require(view.getTerminal().buffer.lines[0].images?.first as? TerminalView.AppleImage)
        #expect(image.pixelWidth == sample.1)
        #expect(image.col == 4)
    }
    @Test func standardDisplayKeepsOriginalPixelSize() throws {
        let view=BitmapScaleView(frame:CGRect(x:0,y:0,width:400,height:200));view.imageScale=1
        var pixels=[UInt8](repeating:255,count:240*24*4)
        view.createImageFromBitmap(source:view.getTerminal(),bytes:&pixels,width:240,height:24)
        let image=try #require(view.getTerminal().buffer.lines[0].images?.first as? TerminalView.AppleImage)
        #expect(image.pixelWidth == 240)
    }
}
#endif

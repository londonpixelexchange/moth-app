//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 4/16/23.
//

import Foundation
import CoreText

extension CaretView {
    func drawCursor (in context: CGContext, hasFocus: Bool) {
        guard let ctline else {
            return
        }
        guard let terminal else {
            return
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: [bounds])
        context.clear(bounds)
        
        if !hasFocus {
            context.setStrokeColor(bgColor)
            context.setLineWidth(3)
            context.stroke(bounds)
            return
        }
        context.setFillColor(bgColor)
        let region: CGRect
        switch style {
        case .blinkBar, .steadyBar:
            region = CGRect (x: 0, y: 0, width: 2, height: bounds.height)
        case .blinkBlock, .steadyBlock:
            region = bounds
        case .blinkUnderline, .steadyUnderline:
            region = CGRect (x: 0, y: 0, width: bounds.width, height: 2)
        }
        #if os(macOS)
        fillPaint(in: context, region: region)
        #else
        context.fill([region])
        #endif

        let lineDescent = CTFontGetDescent(terminal.fontSet.normal)
        let lineLeading = CTFontGetLeading(terminal.fontSet.normal)
        var yOffset = ceil(lineDescent+lineLeading)
        #if os(macOS)
        let naturalHeight = ceil(CTFontGetAscent(terminal.fontSet.normal)+lineDescent+lineLeading)
        yOffset += floor((bounds.height-naturalHeight)/2)
        #endif
        
        guard style == .steadyBlock || style  == .blinkBlock else {
            return
        }
        #if os(macOS)
        context.setShouldAntialias(terminal.antialiasText)
        context.setAllowsAntialiasing(terminal.antialiasText)
        context.setShouldSmoothFonts(terminal.antialiasText)
        context.setAllowsFontSmoothing(terminal.antialiasText)
        #endif
        let buffer = terminal.terminal.displayBuffer
        switch buffer.lines[buffer.yBase+buffer.y].renderMode {
        case .single: break
        case .doubleWidth: context.scaleBy(x:2,y:1)
        case .doubledTop:
            context.translateBy(x:0,y:-bounds.height); context.scaleBy(x:2,y:2)
        case .doubledDown: context.scaleBy(x:2,y:2)
        }
        let caretFG = caretTextColor ?? terminal.nativeForegroundColor
        context.setFillColor(caretFG.cgColor)
        for run in CTLineGetGlyphRuns(ctline) as? [CTRun] ?? [] {
            let runGlyphsCount = CTRunGetGlyphCount(run)
            let runAttributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any] ?? [:]
            let runFont = runAttributes[.font] as! TTFont

            let runGlyphs = [CGGlyph](unsafeUninitializedCapacity: runGlyphsCount) { (bufferPointer, count) in
                CTRunGetGlyphs(run, CFRange(), bufferPointer.baseAddress!)
                count = runGlyphsCount
            }

            var positions = runGlyphs.enumerated().map { (i: Int, glyph: CGGlyph) -> CGPoint in
                CGPoint(x: 0, y: yOffset)
            }
            CTFontDrawGlyphs(runFont, runGlyphs, &positions, positions.count, context)
        }
    }
}

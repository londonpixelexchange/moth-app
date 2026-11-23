//
//  MacCaretView.swift
//  
// Implements the caret in the Mac caret view
// TODO: looks like I can kill sub now. unless it can be used to draw a border when out of focus
//
//  Created by Miguel de Icaza on 3/20/20.
//

#if os(macOS)
import Foundation
import AppKit
import CoreText
import CoreGraphics
import CoreText

// The CaretView is used to show the cursor
class CaretView: NSView, CALayerDelegate {
    weak var terminal: TerminalView?
    var ctline: CTLine?
    var bgColor: CGColor
    var paintType = "solid"
    var paintColors: [CGColor] = []
    var paintAngle: Double = 90
    func fillPaint(in context: CGContext, region: CGRect) {
        guard let first = paintColors.first else { context.fill([region]); return }
        guard paintType != "solid", paintColors.count > 1,
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: paintColors as CFArray, locations: nil) else {
            context.setFillColor(first); context.fill([region]); return
        }
        context.saveGState(); defer { context.restoreGState() }; context.clip(to: region)
        let center = CGPoint(x: region.midX, y: region.midY)
        if paintType == "radial" {
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(region.width, region.height)/2, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else {
            let a = paintAngle * .pi/180
            let dx = cos(a)*region.width/2, dy = sin(a)*region.height/2
            context.drawLinearGradient(gradient, start: CGPoint(x: center.x-dx, y: center.y-dy), end: CGPoint(x: center.x+dx, y: center.y+dy), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }
    var tracksFocus = true
    var animationMode = "breathe"
    var animationPeriod: TimeInterval = 1.4
    
    public init (frame: CGRect, cursorStyle: CursorStyle, terminal: TerminalView)
    {
        self.terminal = terminal
        style = cursorStyle
        bgColor = caretColor.cgColor
        super.init(frame: frame)
        wantsLayer = true
        
        updateView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setText (ch: CharData) {
        let character = terminal?.terminal.getCharacter(for: ch) ?? " "
        let res = NSAttributedString (
            string: String (character),
            attributes: terminal?.getAttributedValue(ch.attribute, usingFg: caretColor, andBg: caretTextColor ?? terminal?.nativeForegroundColor ?? NSColor.black))
        ctline = CTLineCreateWithAttributedString(res)

        setNeedsDisplay(bounds)
    }
    
    var style: CursorStyle {
        didSet {
            updateCursorStyle ()
        }
    }
    
    func updateCursorStyle () {
        let styleAnimates: Bool
        switch style {
        case .blinkUnderline, .blinkBlock, .blinkBar: styleAnimates = true
        case .steadyBar, .steadyBlock, .steadyUnderline: styleAnimates = false
        }
        let focused = !tracksFocus || (terminal?.hasFocus ?? false)
        updateAnimation(to: styleAnimates && focused && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        updateView()
    }

    private var activeAnimationSignature: String?
    func updateAnimation(to animate: Bool) {
        guard animate, animationMode != "noblink" else { disableAnimations(); return }
        let signature = "\(animationMode):\(animationPeriod)"
        // Rendering and host config refreshes must not restart an unchanged blink cycle.
        if activeAnimationSignature == signature, layer?.animation(forKey:"opacity") != nil { return }
        disableAnimations()
        activeAnimationSignature = signature
        if animationMode == "blink" {
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [1, 0, 1]
            animation.keyTimes = [0, 0.5, 1]
            animation.calculationMode = .discrete
            animation.duration = animationPeriod
            animation.repeatCount = .infinity
            layer?.add(animation, forKey: "opacity")
        } else {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1; animation.toValue = 0.12
            animation.duration = animationPeriod / 2
            animation.autoreverses = true; animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(animation, forKey: "opacity")
        }
    }

    func disableAnimations () {
        activeAnimationSignature = nil
        layer?.removeAllAnimations()
        layer?.opacity = 1
    }
    
    public var defaultCaretColor = NSColor.selectedControlColor
    
    public var caretColor: NSColor = NSColor.selectedControlColor {
        didSet {
            bgColor = caretColor.cgColor
            updateView()
        }
    }

    public var defaultCaretTextColor: NSColor? = nil
    public var caretTextColor: NSColor? = nil {
        didSet {
            updateView()
        }
    }

    public var focused: Bool = false {
        didSet {
            updateView()
        }
    }

    func updateView() {
        setNeedsDisplay(bounds)
    }
    
    func draw(_ layer: CALayer, in context: CGContext) {
        drawCursor (in: context, hasFocus: tracksFocus ? (terminal?.hasFocus ?? true) : true)
    }
    
    override func draw(_ dirtyRect: NSRect) {
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // we do not want to steal hits, let the terminal view take them
        return nil
    }
}
#endif

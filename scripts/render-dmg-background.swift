// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: GPL-3.0-or-later
// Licensed under GNU GPL version 3 or later. See LICENSE.

import AppKit
import ImageIO
import CoreText

let root=URL(fileURLWithPath:CommandLine.arguments[1])
let fontURL=root.appendingPathComponent("Packaging/IBMPlexSans-Variable.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL,.process,nil)
func plex(_ size:CGFloat,_ weight:Double)->NSFont {
 let descriptor=NSFontDescriptor(fontAttributes:[.name:"IBMPlexSans-Regular",.variation:[NSNumber(value:0x77676874):NSNumber(value:weight)]])
 let font=NSFont(descriptor:descriptor,size:size)!
 precondition(font.fontName.hasPrefix("IBMPlexSans"),"IBM Plex Sans is required")
 return font
}
let width:CGFloat=760,height:CGFloat=480
for scale in [1,2] {
 let ctx=CGContext(data:nil,width:Int(width)*scale,height:Int(height)*scale,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 ctx.scaleBy(x:CGFloat(scale),y:CGFloat(scale))
 ctx.setFillColor(CGColor(srgbRed:0.065,green:0.067,blue:0.075,alpha:1));ctx.fill(CGRect(x:0,y:0,width:width,height:height))
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false)
 func text(_ string:String,top:CGFloat,size:CGFloat,color:NSColor,weight:Double){
  let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
  (string as NSString).draw(in:NSRect(x:30,y:height-top-size*1.5,width:width-60,height:size*1.5),withAttributes:[.font:plex(size,weight),.foregroundColor:color,.paragraphStyle:paragraph])
 }
 text("Moth",top:34,size:34,color:NSColor(white:0.91,alpha:1),weight:500)
 text("Drag Moth to Applications",top:382,size:20,color:NSColor(white:0.82,alpha:1),weight:400)
 // Finder draws file names in black over image backgrounds. Give the native
 // labels a quiet light surface rather than depending on system appearance.
 NSColor(white:0.82,alpha:1).setFill()
 for (name,center):(String,CGFloat) in [("Moth",180),("Applications",580)] {
  let labelWidth=ceil((name as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:14)]).width)+14
  NSBezierPath(roundedRect:NSRect(x:center-labelWidth/2,y:height-347,width:labelWidth,height:24),xRadius:5,yRadius:5).fill()
 }
 NSGraphicsContext.restoreGraphicsState()
 // A quiet, slightly rising arc between the actual Finder icons.
 ctx.setStrokeColor(CGColor(srgbRed:0.66,green:0.66,blue:0.73,alpha:1));ctx.setLineWidth(2.5);ctx.setLineCap(.round);ctx.setLineJoin(.round)
 let path=CGMutablePath();let y=height-260
 path.move(to:CGPoint(x:300,y:y));path.addCurve(to:CGPoint(x:452,y:y),control1:CGPoint(x:350,y:y+13),control2:CGPoint(x:407,y:y+13));ctx.addPath(path);ctx.strokePath()
 let head=CGMutablePath();head.move(to:CGPoint(x:439,y:y+10));head.addLine(to:CGPoint(x:453,y:y));head.addLine(to:CGPoint(x:439,y:y-9));ctx.addPath(head);ctx.strokePath()
 let rep=NSBitmapImageRep(cgImage:ctx.makeImage()!);rep.size=NSSize(width:width,height:height)
 let file=root.appendingPathComponent("Packaging/installer-background\(scale==2 ? "@2x":"").png")
 try rep.representation(using:.png,properties:[:])!.write(to:file)
}

// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import CoreText
import MetalKit
import QuartzCore
import simd

/// The hidden About interaction is deliberately local to its window and has no persistent state.
final class MothLogoView: NSImageView {
    var reveal: (() -> Void)?
    private var presses = 0
    private var firstPress: TimeInterval = 0
    private var lastPress: TimeInterval = 0
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { registerPress(at: event.timestamp) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 { registerPress(at:event.timestamp) }
        else { super.keyDown(with:event) }
    }
    override func accessibilityPerformPress() -> Bool { registerPress(at:ProcessInfo.processInfo.systemUptime); return true }
    func registerPress(at time: TimeInterval) {
        if time-lastPress > 0.6 || time-firstPress > 2 { presses = 0; firstPress = time }
        lastPress = time; presses += 1
        if presses == 6 { presses = 0; reveal?() }
    }
}

struct MothGlyphParticle {
    var unit: SIMD2<Float>
    var velocity: SIMD2<Float>
    var phase: Float
    var frequency: Float
    var delay: Float
    var size: Float
    var opacity: Float
    var glyph: UInt32
}

struct MothGlyphInstance {
    var positionSize: SIMD4<Float>
    var atlas: SIMD4<Float>
    var appearance: SIMD4<Float> // rotation, opacity, horizontal flutter, brightness
    var optics: SIMD4<Float> // depth-of-field radius in atlas pixels
}

private struct MothRandom {
    var state: UInt64 = 0x4d6f746841534349
    mutating func value() -> Float {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Float(state & 0xffffff)/Float(0xffffff)
    }
}

/// A short, continuous flight field. The renderer uses a glyph atlas, not a layer per letter.
final class MothSwarmView: NSView {
    static let duration: Double = 11.4
    let particles: [MothGlyphParticle]
    let sourceRect: NSRect
    let reducedMotion: Bool
    var onFrame: ((Double) -> Void)?
    var onFinish: (() -> Void)?
    private(set) var isFinished = false
    private var surface: MTKView!
    private var renderer: MothSwarmRenderer!
    private var observers: [NSObjectProtocol] = []
    private var started = CACurrentMediaTime()
    var elapsed: Double { CACurrentMediaTime()-started }
    var actualDuration: Double { reducedMotion ? 4.2 : Self.duration }
    var framesPerSecond: Int { surface.preferredFramesPerSecond }
    static let shutterSamples = 7
    static let maximumInstances = 780*shutterSamples
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    init?(frame: NSRect,image: NSImage,sourceRect: NSRect,reducedMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard let device = MTLCreateSystemDefaultDevice(),let particles = Self.sample(image),!particles.isEmpty else { return nil }
        self.particles = particles; self.sourceRect = sourceRect; self.reducedMotion = reducedMotion
        super.init(frame:frame)
        guard let renderer = MothSwarmRenderer(device:device) else { return nil }
        self.renderer = renderer; renderer.owner = self
        surface = MTKView(frame:bounds,device:device)
        surface.autoresizingMask = [.width,.height]; surface.colorPixelFormat = .bgra8Unorm
        surface.framebufferOnly = false; surface.layer?.isOpaque = false
        surface.clearColor = MTLClearColorMake(0,0,0,0)
        surface.preferredFramesPerSecond = 24
        surface.enableSetNeedsDisplay = false; surface.isPaused = false; surface.delegate = renderer
        addSubview(surface)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("Moth in flight"); setAccessibilityHelp("Press Escape to return to About Moth.")
        started = CACurrentMediaTime()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { finish() } else { super.keyDown(with:event) } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        guard let window else { surface?.isPaused = true; return }
        for name in [NSWindow.willCloseNotification,NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main) { [weak self] _ in self?.finish() })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main) { [weak self] _ in self?.finish() })
    }
    deinit {
        surface?.isPaused = true
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    func finish() {
        guard !isFinished else { return }; isFinished = true
        surface.isPaused = true; surface.delegate = nil
        let completion = onFinish; onFinish = nil; onFrame = nil; completion?()
    }
    static func smooth(_ a: Float,_ b: Float,_ x: Float) -> Float { let t = min(1,max(0,(x-a)/(b-a))); return t*t*t*(t*(t*6-15)+10) }
    func sceneTime(_ elapsed: Double) -> Float { Float(elapsed/actualDuration*Self.duration) }
    func instances(at elapsed: Double,includingTrails: Bool = true) -> [MothGlyphInstance] {
        let rect = sourceRect
        let origin = SIMD2(Float(rect.midX),Float(rect.midY))
        let target = SIMD2(Float(bounds.midX),Float(bounds.height)*0.56)
        // A 180-degree shutter at 24 fps integrates actual curved trajectories.
        // Weighted samples replace the old pair of detached ghost trails.
        let samples = includingTrails && !reducedMotion ? Self.shutterSamples : 1
        let weights: [Float] = [1,3,6,8,6,3,1]
        var instances: [MothGlyphInstance] = []; instances.reserveCapacity(particles.count*samples)
        for sample in 0..<samples {
            let shutterOffset = samples == 1 ? 0 : Double(samples-1-sample)/Double(samples-1)/48
            let t = sceneTime(max(0,elapsed-shutterOffset))
            let exposure = samples == 1 ? Float(1) : weights[sample]/28
            let dolly = reducedMotion ? 0 : Self.smooth(2.2,4.0,t)
            let anchor = origin+(target-origin)*(dolly*0.7)
            let reveal = Self.smooth(0.3,2.2,t)*(1-Self.smooth(8.4,10.9,t))
            for p in particles {
                let age = max(0,t-p.delay)
                // Ease into flight, gather speed, then drift into the distance.
                let motion = 6*(1-exp(-pow(age/4.1,2.35)))
                let released = Self.smooth(0,1.5,age)
                let depth = (sin(p.phase*1.7)+1)*0.5
                let wingTime = age*(0.35+0.65*Self.smooth(0,3,age))
                var position = anchor+(p.unit-SIMD2(repeating:0.5))*SIMD2(Float(rect.width),Float(rect.height))*(1+dolly*0.35)
                if !reducedMotion {
                    position += p.velocity*motion
                    position.y += (14+8*sin(p.phase))*motion*motion
                    position.x += (sin(wingTime*p.frequency+p.phase)-sin(p.phase))*(6+motion*2)*released
                    position.y += (cos(wingTime*p.frequency*0.63+p.phase)-cos(p.phase))*8*released
                } else { position += SIMD2(sin(p.phase+age)*3,Self.smooth(0,6,age)*10)*released }
                let rotation = reducedMotion ? 0 : (sin(p.phase+wingTime*p.frequency)*0.9+sin(age*0.7)*0.25)*released
                let flutter = reducedMotion ? 1 : 1-released*0.65*abs(sin(wingTime*p.frequency*0.72+p.phase))
                let size = p.size*(1+released*(0.55+depth*1.5))
                let alpha = p.opacity*reveal*(1-Self.smooth(4.2,6.5,age))*exposure
                let blur = reducedMotion ? Float(0.3) : 0.3+released*(pow(depth,3)*7+Self.smooth(3,6,age)*2)
                let uv = SIMD4(Float(p.glyph%16)/16,Float(7-p.glyph/16)/8,1/16,1/8)
                instances.append(MothGlyphInstance(positionSize:SIMD4(position.x,position.y,size,size),atlas:uv,appearance:SIMD4(rotation,alpha,flutter,0.83+0.17*sin(p.phase)*sin(p.phase)),optics:SIMD4(blur,0,0,0)))
            }
        }
        return instances
    }
    func advance(_ elapsed: Double) {
        onFrame?(Double(sceneTime(elapsed)))
        if elapsed >= actualDuration { finish() }
    }
    func renderedFrame(at elapsed: Double) -> NSBitmapImageRep? { renderer.snapshot(self,time:elapsed) }

    func compositeFrame(at time: Double,controller: AboutWindowController) -> NSBitmapImageRep? {
        guard let root = controller.window?.contentView,let metal = renderedFrame(at:time)?.cgImage else { return nil }
        controller.applyMothFlightFrame(Double(sceneTime(time)))
        isHidden = true
        let frame = root.superview ?? root
        frame.layoutSubtreeIfNeeded(); frame.displayIfNeeded()
        guard let base = frame.bitmapImageRepForCachingDisplay(in:frame.bounds) else { isHidden = false; return nil }
        frame.cacheDisplay(in:frame.bounds,to:base); isHidden = false
        guard let output = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:base.pixelsWide,pixelsHigh:base.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context = NSGraphicsContext(bitmapImageRep:output),let cg = base.cgImage else { return nil }
        let rect = root.convert(root.bounds,to:frame)
        let scale = CGFloat(base.pixelsWide)/frame.bounds.width
        context.cgContext.scaleBy(x:scale,y:scale)
        context.cgContext.draw(cg,in:frame.bounds)
        context.cgContext.draw(metal,in:rect)
        return output
    }
    private static func sample(_ image: NSImage) -> [MothGlyphParticle]? {
        guard let data = image.tiffRepresentation,let bitmap = NSBitmapImageRep(data:data) else { return nil }
        var random = MothRandom(), particles: [MothGlyphParticle] = []
        let symbols = Array(".:-+*#%MWx/\\|01{}[]<>".utf8)
        for y in 0..<52 { for x in 0..<44 {
            let u = (Float(x)+0.5)/44, v = (Float(y)+0.5)/52
            guard let c = bitmap.colorAt(x:min(bitmap.pixelsWide-1,Int(u*Float(bitmap.pixelsWide))),y:min(bitmap.pixelsHigh-1,Int(v*Float(bitmap.pixelsHigh))))?.usingColorSpace(.deviceRGB) else { continue }
            let luminance = Float(c.redComponent*0.21+c.greenComponent*0.72+c.blueComponent*0.07)
            let strength = Float(c.alphaComponent)*luminance
            guard strength > 0.075 else { continue }
            let unit = SIMD2(u,1-v)
            let character = UInt32(symbols[min(symbols.count-1,Int(random.value()*Float(symbols.count)))])-32
            particles.append(MothGlyphParticle(unit:unit,velocity:SIMD2((random.value()-0.5)*100,-22-random.value()*42),phase:random.value()*Float.pi*2,frequency:1.6+random.value()*2.4,delay:2.2+v*0.55+random.value()*0.9,size:5+random.value()*4,opacity:min(1,0.25+strength*0.8),glyph:character))
        } }
        if particles.count > 780 { particles = particles.enumerated().filter { $0.offset%2 == 0 }.map(\.element) }
        return Array(particles.prefix(780))
    }
}

private final class MothSwarmRenderer: NSObject,MTKViewDelegate {
    weak var owner: MothSwarmView?
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let atlas: MTLTexture
    private let sampler: MTLSamplerState
    private let buffers: [MTLBuffer]
    private let available = DispatchSemaphore(value:3)
    private var frame = 0
    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue(),let atlas = Self.makeAtlas(device),let sampler = device.makeSamplerState(descriptor:Self.samplerDescriptor()) else { return nil }
        self.queue = queue; self.atlas = atlas; self.sampler = sampler
        do {
            let library = try device.makeLibrary(source:Self.shader,options:nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name:"moth_vertex")
            descriptor.fragmentFunction = library.makeFunction(name:"moth_fragment")
            let colour = descriptor.colorAttachments[0]!
            colour.pixelFormat = .bgra8Unorm; colour.isBlendingEnabled = true
            colour.sourceRGBBlendFactor = .one; colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colour.sourceAlphaBlendFactor = .one; colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor:descriptor)
        } catch { return nil }
        var buffers: [MTLBuffer] = []
        for _ in 0..<3 { guard let buffer = device.makeBuffer(length:MothSwarmView.maximumInstances*MemoryLayout<MothGlyphInstance>.stride,options:.storageModeShared) else { return nil }; buffers.append(buffer) }
        self.buffers = buffers; super.init()
    }
    func mtkView(_ view: MTKView,drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let owner,!owner.isFinished else { view.isPaused = true; return }
        let time = owner.elapsed; owner.advance(time)
        guard !owner.isFinished,available.wait(timeout:.now()) == .success else { return }
        guard let drawable = view.currentDrawable,let descriptor = view.currentRenderPassDescriptor,let command = queue.makeCommandBuffer() else { available.signal(); return }
        let buffer = buffers[frame%3]; frame += 1
        encode(owner,time:time,descriptor:descriptor,command:command,buffer:buffer)
        let semaphore = available
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable); command.commit()
    }
    private func encode(_ owner: MothSwarmView,time: Double,descriptor: MTLRenderPassDescriptor,command: MTLCommandBuffer,buffer: MTLBuffer) {
        let t = owner.sceneTime(time)
        let darkness = Double(MothSwarmView.smooth(2.0,3.5,t)*(1-MothSwarmView.smooth(9.4,11.4,t)))*0.91
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.025*darkness,0.025*darkness,0.027*darkness,darkness)
        let instances = owner.instances(at:time)
        guard !instances.isEmpty,let encoder = command.makeRenderCommandEncoder(descriptor:descriptor) else { return }
        instances.withUnsafeBytes { source in buffer.contents().copyMemory(from:source.baseAddress!,byteCount:source.count) }
        var viewport = SIMD2(Float(owner.bounds.width),Float(owner.bounds.height))
        encoder.setRenderPipelineState(pipeline); encoder.setVertexBuffer(buffer,offset:0,index:0)
        encoder.setVertexBytes(&viewport,length:MemoryLayout<SIMD2<Float>>.stride,index:1)
        encoder.setFragmentTexture(atlas,index:0); encoder.setFragmentSamplerState(sampler,index:0)
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6,instanceCount:instances.count); encoder.endEncoding()
    }
    func snapshot(_ owner: MothSwarmView,time: Double) -> NSBitmapImageRep? {
        let width = max(1,Int(owner.bounds.width*2)),height = max(1,Int(owner.bounds.height*2))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
        d.usage = [.renderTarget]; d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor:d),let command = queue.makeCommandBuffer(),let buffer = device.makeBuffer(length:MothSwarmView.maximumInstances*MemoryLayout<MothGlyphInstance>.stride,options:.storageModeShared) else { return nil }
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = texture
        encode(owner,time:time,descriptor:pass,command:command,buffer:buffer)
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed,let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bitmapFormat:[],bytesPerRow:width*4,bitsPerPixel:32),let bytes = rep.bitmapData else { return nil }
        var raw = [UInt8](repeating:0,count:width*height*4)
        raw.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0) }
        for index in stride(from:0,to:raw.count,by:4) {
            bytes[index] = raw[index+2]; bytes[index+1] = raw[index+1]
            bytes[index+2] = raw[index]; bytes[index+3] = raw[index+3]
        }
        return rep
    }
    private static func samplerDescriptor() -> MTLSamplerDescriptor { let d = MTLSamplerDescriptor(); d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear; return d }
    private static func makeAtlas(_ device: MTLDevice) -> MTLTexture? {
        let width = 1024,height = 512
        var bytes = [UInt8](repeating:0,count:width*height)
        let success = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data:raw.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray:1,alpha:1); context.setShouldAntialias(true)
            let name = NSFont(name:"WumpusMonoNFM",size:48)?.fontName ?? NSFont.monospacedSystemFont(ofSize:48,weight:.regular).fontName
            let font = CTFontCreateWithName(name as CFString,48,nil)
            for index in 0..<95 {
                var code = UniChar(index+32),glyph = CGGlyph()
                CTFontGetGlyphsForCharacters(font,&code,&glyph,1)
                var point = CGPoint(x:(index%16)*64+8,y:(index/16)*64+12)
                CTFontDrawGlyphs(font,&glyph,&point,1,context)
            }
            return true
        }
        guard success else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.r8Unorm,width:width,height:height,mipmapped:true)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor:descriptor) else { return nil }
        bytes.withUnsafeBytes { texture.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:width) }
        guard let queue = device.makeCommandQueue(),let command = queue.makeCommandBuffer(),let blit = command.makeBlitCommandEncoder() else { return nil }
        blit.generateMipmaps(for:texture); blit.endEncoding()
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        return texture
    }
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Glyph { float4 positionSize; float4 atlas; float4 appearance; float4 optics; };
    struct Vertex { float4 position [[position]]; float2 uv; float opacity; float brightness; float blur; float4 cell [[flat]]; };
    vertex Vertex moth_vertex(uint v [[vertex_id]],uint i [[instance_id]],const device Glyph* glyphs [[buffer(0)]],constant float2& viewport [[buffer(1)]]) {
        const float2 corners[6] = {float2(0,0),float2(1,0),float2(0,1),float2(0,1),float2(1,0),float2(1,1)};
        Glyph glyph = glyphs[i]; float2 corner = corners[v];
        float2 local = (corner-0.5)*glyph.positionSize.zw;
        local.x *= glyph.appearance.z;
        float c = cos(glyph.appearance.x),s = sin(glyph.appearance.x);
        float2 point = glyph.positionSize.xy+float2(c*local.x-s*local.y,s*local.x+c*local.y);
        Vertex out; out.position = float4(point/viewport*2-1,0,1);
        out.uv = glyph.atlas.xy+float2(corner.x,1-corner.y)*glyph.atlas.zw;
        out.opacity = glyph.appearance.y; out.brightness = glyph.appearance.w;
        out.blur = glyph.optics.x; out.cell = glyph.atlas; return out;
    }
    fragment float4 moth_fragment(Vertex in [[stage_in]],texture2d<float> atlas [[texture(0)]],sampler sampling [[sampler(0)]]) {
        float2 texel = 1.0/float2(atlas.get_width(),atlas.get_height());
        float2 lo = in.cell.xy+texel*0.5;
        float2 hi = in.cell.xy+in.cell.zw-texel*0.5;
        float coverage = 0;
        // Normalised Gaussian depth of field, constrained to this glyph's atlas cell.
        const float weights[5] = {0.06136,0.24477,0.38774,0.24477,0.06136};
        for (int y = -2; y <= 2; ++y) {
            for (int x = -2; x <= 2; ++x) {
                float2 uv = clamp(in.uv+float2(x,y)*texel*in.blur,lo,hi);
                coverage += atlas.sample(sampling,uv,level(max(0.0,log2(max(1.0,in.blur))))).r*weights[x+2]*weights[y+2];
            }
        }
        float alpha = coverage*in.opacity;
        return float4(float3(in.brightness)*alpha,alpha);
    }
    """
}

/// Explicit developer verification only, sharing the isolated screenshot-launch contract.
enum MothSwarmReview {
    static func run(_ app: App,output: URL) {
        app.showAboutWindow(nil); NSApp.activate(ignoringOtherApps:true)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3) {
            var checks: [String:Bool] = [:]
            guard let about = app.aboutWindow,let window = about.window else { exit(2) }
            window.makeKeyAndOrderFront(nil)
            let gate = MothLogoView(); var count = 0; gate.reveal = { count += 1 }
            for n in 0..<6 { gate.registerPress(at:Double(n)) }
            checks["ordinaryClicksDoNotTrigger"] = count == 0
            for n in 0..<6 { gate.registerPress(at:20+Double(n)*0.1) }
            checks["sixRapidClicksTriggerOnce"] = count == 1
            for n in 0..<6 { about.logoView.registerPress(at:50+Double(n)*0.1) }
            guard let effect = about.swarm else { checks["metalEffectCreated"] = false; write(checks,output:output); exit(2) }
            checks["metalEffectCreated"] = true
            checks["cinemaFrameRate24"] = effect.framesPerSecond == 24
            checks["noMouseTracking"] = effect.trackingAreas.isEmpty
            let beforeMouse = effect.instances(at:3,includingTrails:false).map(\.positionSize)
            if let move = NSEvent.mouseEvent(with:.mouseMoved,location:NSPoint(x:100,y:200),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:0,pressure:0) { effect.mouseMoved(with:move) }
            checks["mouseDoesNotChangeFlight"] = beforeMouse == effect.instances(at:3,includingTrails:false).map(\.positionSize)
            checks["depthOfFieldVariesByGlyph"] = Set(effect.instances(at:3,includingTrails:false).map { Int($0.optics.x*10) }).count > 5
            checks["hundredsOfAsciiGlyphs"] = (250...780).contains(effect.particles.count)
            about.startMothFlight(); checks["reentryDoesNotStackEffects"] = about.swarm === effect
            let frames = output.appendingPathComponent("frames")
            try? FileManager.default.createDirectory(at:frames,withIntermediateDirectories:true)
            var rendered = 0
            let totalFrames = Int(ceil(effect.actualDuration*24))
            for index in 0..<totalFrames {
                autoreleasepool {
                    if let rep = effect.compositeFrame(at:Double(index)/24,controller:about),let png = rep.representation(using:.png,properties:[:]) {
                        try? png.write(to:frames.appendingPathComponent(String(format:"%04d.png",index)),options:.atomic); rendered += 1
                    }
                }
            }
            checks["allMetalFramesRendered"] = rendered == totalFrames
            if let frame = effect.renderedFrame(at:3),let colour = frame.colorAt(x:5,y:5)?.usingColorSpace(.deviceRGB) {
                checks["gpuReadbackUsesNeutralChannels"] = abs(colour.redComponent-colour.blueComponent) < 0.03 && abs(colour.redComponent-colour.greenComponent) < 0.03
            }
            let flight = effect.instances(at:3)
            checks["finiteParticleGeometry"] = flight.allSatisfy { [$0.positionSize.x,$0.positionSize.y,$0.positionSize.z,$0.positionSize.w,$0.appearance.x,$0.appearance.y,$0.appearance.z].allSatisfy(\.isFinite) }
            checks["boundedInstanceBuffers"] = flight.count <= MothSwarmView.maximumInstances
            let first = effect.instances(at:1,includingTrails:false),last = effect.instances(at:5,includingTrails:false)
            checks["glyphsTravelAway"] = zip(first,last).contains { simd_distance(SIMD2($0.0.positionSize.x,$0.0.positionSize.y),SIMD2($0.1.positionSize.x,$0.1.positionSize.y)) > 80 }
            if let reduced = MothSwarmView(frame:effect.frame,image:about.logoView.image!,sourceRect:effect.sourceRect,reducedMotion:true) {
                checks["reduceMotionHasShorterDuration"] = reduced.actualDuration < effect.actualDuration
                let a = reduced.instances(at:0.1,includingTrails:false),b = reduced.instances(at:2,includingTrails:false)
                checks["reduceMotionAvoidsLongFlight"] = zip(a,b).allSatisfy { simd_distance(SIMD2($0.0.positionSize.x,$0.0.positionSize.y),SIMD2($0.1.positionSize.x,$0.1.positionSize.y)) < 25 }
                reduced.finish()
            }
            if let escape = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53) { effect.keyDown(with:escape) }
            checks["escapeRemovesEffect"] = about.swarm == nil && effect.isFinished
            checks["aboutOpacityRestored"] = about.contentStack.arrangedSubviews.allSatisfy { $0.alphaValue == 1 }
            about.startMothFlight()
            if let again = about.swarm { again.advance(again.actualDuration+0.1) }
            checks["naturalCompletionRestoresAbout"] = about.swarm == nil && about.contentStack.arrangedSubviews.allSatisfy { $0.alphaValue == 1 }
            write(checks,output:output)
            app.windows.forEach { $0.stop() }
            exit(checks.values.allSatisfy { $0 } ? 0 : 2)
        }
    }
    private static func write(_ checks: [String:Bool],output: URL) {
        try? JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("SwarmChecks.json"),options:.atomic)
        print(checks)
    }
}

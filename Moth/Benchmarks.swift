// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import QuartzCore
import Darwin

/// Opt-in, isolated release-build measurements. Never runs during ordinary app use.
enum MothBenchmark {
    static let enabled = CommandLine.arguments.contains("--benchmark")
    static var mainStarted = ProcessInfo.processInfo.systemUptime
    private static let gpuLock = NSLock()
    private static var gpuSeconds: Double = 0
    private static var frames = 0
    private static var receivedBytes: UInt64 = 0
    private static var result: [String:Any] = [:]
    private static var stages: [[String:Any]] = []
    private static var ownedApp: App?
    private static var window: TerminalWindowController?
    private static var intervalTimer: Timer?
    private static var renderCount = 0
    private static var renderWallSeconds: Double = 0
    private static var reportURL: URL { URL(fileURLWithPath:ProcessInfo.processInfo.environment["MOTH_BENCH_RESULT"]!) }
    static var mode: String { ProcessInfo.processInfo.environment["MOTH_BENCH_MODE"] ?? "default" }
    static func prepare() {
        guard enabled else { return }
        guard ProcessInfo.processInfo.environment["MOTH_BENCH_RESULT"] != nil else { fputs("MOTH_BENCH_RESULT is required.\n",stderr); exit(2) }
        do {
            var config = Configuration()
            config.showLayoutsOnLaunch = false; config.closeOnExit = false
            config.shell = "/bin/zsh"; config.advanced.loginShell = false
            config.advanced.environment["ZDOTDIR"] = Configuration.url.deletingLastPathComponent().path
            config.advanced.workingDirectory = Configuration.url.deletingLastPathComponent().path
            if mode == "minimal" { config.background.style = "solid"; config.cursor.animation = "noblink"; config.window.frosted = false; config.window.opacity = 1 }
            try Configuration.save(config)
        } catch { fputs("Benchmark configuration: \(error)\n",stderr); exit(2) }
    }
    static func recordGPU(seconds: Double) {
        guard enabled,seconds.isFinite,seconds >= 0 else { return }
        gpuLock.lock(); gpuSeconds += seconds; frames += 1; gpuLock.unlock()
    }
    static func recordReceivedBytes(_ count: Int) { gpuLock.lock(); receivedBytes += UInt64(count); gpuLock.unlock() }
    private static func receivedSample() -> UInt64 { gpuLock.lock(); defer { gpuLock.unlock() }; return receivedBytes }
    private static func gpuSample() -> (Double,Int) { gpuLock.lock(); defer { gpuLock.unlock() }; return (gpuSeconds,frames) }
    private static func metrics(_ pid: pid_t = getpid()) -> MothProcessMetrics {
        var metrics = MothProcessMetrics(); guard moth_benchmark_metrics(pid,&metrics) == 0 else { fail("Cannot read process metrics for \(pid)") }; return metrics
    }
    private static func saveProgress(_ phase: String,complete: Bool = false) {
        result["phase"] = phase; result["complete"] = complete; result["stages"] = stages
        if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:reportURL,options:.atomic) }
    }
    private static func fail(_ text: String) -> Never {
        result["error"] = text; saveProgress("failed"); ownedApp?.windows.forEach { $0.stop() }; fputs("\(text)\n",stderr); exit(2)
    }
    private static func waitFor(_ condition: @escaping ()->Bool,timeout: Double,_ done: @escaping ()->Void) {
        let end = ProcessInfo.processInfo.systemUptime+timeout
        func poll() {
            if condition() { done() }
            else if ProcessInfo.processInfo.systemUptime >= end { fail("Timed out in \(result["phase"] ?? "unknown phase")") }
            else { DispatchQueue.main.asyncAfter(deadline:.now()+0.015) { poll() } }
        }
        poll()
    }
    static func run(_ app: App) {
        guard enabled else { return }; ownedApp = app; window = app.active
        guard let host = window else { fail("No benchmark window") }
        let screenScale = host.window?.backingScaleFactor ?? 1
        result = ["pid":getpid(),"shellPid":host.workspace.active.terminal.process.shellPid,"mode":mode,
                  "buildIdentifier":MothBuild.identifier,"commit":MothBuild.identity?.commit ?? "",
                  "version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") ?? "", "build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") ?? "",
                  "windowWidthPoints":host.window!.contentView!.bounds.width,"windowHeightPoints":host.window!.contentView!.bounds.height,"backingScale":screenScale,"windowOccludedAtStart":!(host.window?.occlusionState.contains(.visible) ?? false),
                  "scrollbackLimit":app.config.scrollback,"font":app.config.fontName,"fontSize":app.config.fontSize,
                  "reduceMotion":NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,"reduceTransparency":NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                  "lowPowerMode":ProcessInfo.processInfo.isLowPowerModeEnabled,"thermalStateAtStart":ProcessInfo.processInfo.thermalState.rawValue,
                  "cpuPercentDefinition":"100% equals one fully occupied logical CPU core", "memoryDefinition":"OS physical footprint, app process only; shell reported separately",
                  "gpuDefinition":"Sum of measured Metal command-buffer execution durations; excludes WindowServer and compositor work"]
        DispatchQueue.main.asyncAfter(deadline:.now()+100) { fail("Benchmark watchdog expired") }
        saveProgress("starting")
        let marker = "MOTH_BENCH_READY_"+UUID().uuidString
        host.workspace.active.terminal.sendUserText("unsetopt zle; stty -echo; printf '\\r\\n\(marker)\\r\\n'\r")
        waitFor({ host.workspace.active.terminal.getTerminal().exportPlainText().components(separatedBy:"\n").contains(marker) },timeout:10) {
            host.content.layoutSubtreeIfNeeded(); host.content.displayIfNeeded(); CATransaction.flush()
            let now = ProcessInfo.processInfo.systemUptime, process = metrics()
            result["processToReadySeconds"] = now-process.process_start_seconds; result["mainToReadySeconds"] = now-mainStarted
            result["terminalCols"] = host.workspace.active.terminal.getTerminal().cols; result["terminalRows"] = host.workspace.active.terminal.getTerminal().rows
            result["processClockSanitySeconds"] = mainStarted-process.process_start_seconds
            saveProgress("warming")
            if ProcessInfo.processInfo.environment["MOTH_BENCH_QUICK"] == "1" {
                result["quickWorkloadValidation"] = true
                DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { workload("plain") { workload("ansi") { renderWorkload { finish() } } } }; return
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+3) {
                sampleIdle("idle_visible",seconds:15) {
                    func minimized() {
                        host.window?.miniaturize(nil)
                        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                            sampleIdle("idle_minimized",seconds:10) {
                                host.window?.deminiaturize(nil); host.window?.makeKeyAndOrderFront(nil)
                                DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                                    workload("plain") { workload("ansi") { renderWorkload { finish() } } }
                                }
                            }
                        }
                    }
                    if mode == "default" {
                        let original = app.config
                        app.config.background.style = "solid"; app.config.cursor.animation = "noblink"; app.applyAppearance()
                        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                            sampleIdle("idle_effects_disabled_after_use",seconds:10) {
                                app.config = original; app.applyAppearance(); minimized()
                            }
                        }
                    } else { minimized() }
                }
            }
        }
    }
    private static func sampleIdle(_ name: String,seconds: Double,_ done: @escaping ()->Void) {
        func checkVisibility(){
            if name != "idle_minimized",window?.window?.occlusionState.contains(.visible) != true { fail("Visible-window sample rejected: window is fully occluded or the desktop is locked") }
        }
        checkVisibility()
        saveProgress(name)
        let start = metrics(), startGPU = gpuSample(), startTime = ProcessInfo.processInfo.systemUptime
        var footprints: [UInt64] = [start.physical_bytes], resident: [UInt64] = [start.resident_bytes], shellFootprints: [UInt64] = []
        intervalTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { _ in
            checkVisibility()
            let sample = metrics(); footprints.append(sample.physical_bytes); resident.append(sample.resident_bytes)
            if let pid = window?.workspace.active.terminal.process.shellPid { shellFootprints.append(metrics(pid).physical_bytes) }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+seconds) {
            intervalTimer?.invalidate(); intervalTimer = nil
            checkVisibility()
            let end = metrics(), gpu = gpuSample(), duration = ProcessInfo.processInfo.systemUptime-startTime
            let cpu = Double(end.cpu_ns-start.cpu_ns)/1e9
            func median(_ values: [UInt64]) -> Double { let ordered = values.sorted(); return ordered.isEmpty ? 0 : Double(ordered[ordered.count/2]) }
            var stage: [String:Any] = ["name":name,"durationSeconds":duration,"cpuSeconds":cpu,"cpuPercentOneCore":cpu/duration*100,
                "physicalFootprintMedianBytes":median(footprints),"physicalFootprintMaxBytes":footprints.max() ?? 0,"residentMedianBytes":median(resident),
                "shellPhysicalFootprintMedianBytes":median(shellFootprints),"interruptWakeupsPerSecond":Double(end.interrupt_wakeups-start.interrupt_wakeups)/duration,
                "packageIdleWakeupsPerSecond":Double(end.package_idle_wakeups-start.package_idle_wakeups)/duration,"metalSeconds":gpu.0-startGPU.0,"metalFrames":gpu.1-startGPU.1,
                "appActiveAtEnd":NSApp.isActive,"thermalStateAtEnd":ProcessInfo.processInfo.thermalState.rawValue,"windowVisible":window?.window?.isVisible ?? false,"windowOccluded":!(window?.window?.occlusionState.contains(.visible) ?? false)]
            if end.energy_supported != 0,end.energy_nj > start.energy_nj { stage["osAccountedEnergyJoules"] = Double(end.energy_nj-start.energy_nj)/1e9 }
            stages.append(stage); saveProgress(name+"_complete"); done()
        }
    }
    private static func workload(_ name: String,_ done: @escaping ()->Void) {
        guard let terminal = window?.workspace.active.terminal,let folder = ProcessInfo.processInfo.environment["MOTH_BENCH_PAYLOADS"] else { fail("Missing workload folder") }
        let file = URL(fileURLWithPath:folder).appendingPathComponent(name+".txt")
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath:file.path)[.size]) as? NSNumber else { fail("Missing workload: \(name)") }
        terminal.getTerminal().resetFromHost()
        let marker = "MOTH_BENCH_DONE_"+UUID().uuidString
        let before = metrics(), beforeGPU = gpuSample(), beforeBytes = receivedSample(), start = ProcessInfo.processInfo.systemUptime
        saveProgress("output_"+name)
        terminal.sendUserText("/bin/cat \(ShellView.quotePath(file.path)); moth_bench_status=$?; printf '\\r\\n\(marker):%s\\r\\n' \"$moth_bench_status\"\r")
        var completionLine: String?
        func visibleLines() -> [String] { let row = terminal.getTerminal().buffer.y; return (max(0,row-5)...row).compactMap { terminal.getTerminal().getLine(row:$0)?.translateToString(trimRight:true) } }
        waitFor({ completionLine = visibleLines().first { $0.hasPrefix(marker+":") }; return completionLine != nil },timeout:30) {
            let received = receivedSample()-beforeBytes
            guard completionLine == marker+":0",received >= bytes.uint64Value,terminal.getTerminal().buffer.yDisp == 10000 else {
                result["invalidWorkload"] = ["name":name,"status":completionLine ?? "","receivedBytes":received,"expectedBytes":bytes,"scrollbackPosition":terminal.getTerminal().buffer.yDisp,"lastVisibleLines":visibleLines()]
                fail("Incomplete output workload rejected")
            }
            let duration = ProcessInfo.processInfo.systemUptime-start, after = metrics(), afterGPU = gpuSample()
            stages.append(["name":"output_"+name,"bytes":bytes.intValue,"durationSeconds":duration,"mibPerSecond":bytes.doubleValue/1048576/duration,
                "verifiedCommandExitStatus":0,"receivedPTYBytes":received,"cpuSeconds":Double(after.cpu_ns-before.cpu_ns)/1e9,"physicalFootprintAfterBytes":after.physical_bytes,"lifetimePeakPhysicalBytes":after.peak_physical_bytes,
                "metalSeconds":afterGPU.0-beforeGPU.0,"metalFrames":afterGPU.1-beforeGPU.1,"scrollbackPosition":terminal.getTerminal().buffer.yDisp])
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { done() }
        }
    }
    private static func renderWorkload(_ done: @escaping ()->Void) {
        guard let terminal = window?.workspace.active.terminal else { fail("Missing renderer") }
        saveProgress("render_visible_grid")
        terminal.getTerminal().resetFromHost()
        let line = "\u{1b}[38;2;170;190;230m"+String(repeating:"abc->!=0123456789 ",count:10)+"\u{1b}[0m\r\n"
        terminal.feed(text:String(repeating:line,count:terminal.getTerminal().rows))
        let scale: CGFloat = window?.window?.backingScaleFactor ?? 2, size = terminal.bounds.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width*scale),pixelsHigh:Int(size.height*scale),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context = NSGraphicsContext(bitmapImageRep:bitmap) else { fail("Cannot allocate render target") }
        renderCount = 0; renderWallSeconds = 0
        func frame() {
            let start = ProcessInfo.processInfo.systemUptime
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            context.cgContext.saveGState(); context.cgContext.scaleBy(x:scale,y:scale); terminal.draw(terminal.bounds); context.cgContext.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
            renderWallSeconds += ProcessInfo.processInfo.systemUptime-start; renderCount += 1
            if renderCount < 30 { DispatchQueue.main.async { frame() } }
            else { stages.append(["name":"render_visible_grid","frames":renderCount,"meanMilliseconds":renderWallSeconds/Double(renderCount)*1000,"pixelsWide":bitmap.pixelsWide,"pixelsHigh":bitmap.pixelsHigh]); done() }
        }
        frame()
    }
    private static func finish() {
        result["finalPhysicalFootprintBytes"] = metrics().physical_bytes
        saveProgress("complete",complete:true)
        ownedApp?.windows.forEach { $0.stop() }; exit(0)
    }
}

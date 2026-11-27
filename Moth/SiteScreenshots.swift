// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: GPL-3.0-or-later
// Licensed under GNU GPL version 3 or later. See LICENSE.

import AppKit
import QuartzCore
import Darwin

/// Explicitly requested, isolated website examples. Ordinary launches never run this code.
/// Example commands execute inside live PTYs using the real terminal parser and renderer.
enum SiteScreenshots {
    static let enabled = CommandLine.arguments.contains("--site-screenshots")
    private static var app: App?
    private static var manifest: [[String:Any]] = []
    private static var output: URL!
    private static var fixtures: URL { Configuration.url.deletingLastPathComponent().appendingPathComponent("Fixtures") }

    static func prepare() {
        guard enabled else { return }
        do {
            guard let destination = ProcessInfo.processInfo.environment["MOTH_SITE_SCREENSHOT_DIR"],destination.hasPrefix("/"),
                  let path = ProcessInfo.processInfo.environment["MOTH_CONFIG_PATH"],path.hasPrefix("/") else {
                throw Configuration.invalid("Site screenshots require absolute MOTH_CONFIG_PATH and MOTH_SITE_SCREENSHOT_DIR paths.")
            }
            guard !CommandLine.arguments.contains("--self-test"),!CommandLine.arguments.contains("--benchmark") else {
                throw Configuration.invalid("Site screenshots cannot be combined with test or benchmark modes.")
            }
            // A fresh temporary parent prevents accidental changes to any existing preference tree.
            let parent = Configuration.url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            let temporaryRoots = [URL(fileURLWithPath:"/private/tmp"),FileManager.default.temporaryDirectory].map { $0.standardizedFileURL.resolvingSymlinksInPath().path+"/" }
            guard temporaryRoots.contains(where: { parent.path.hasPrefix($0) }),
                  !FileManager.default.fileExists(atPath:Configuration.url.path) else {
                throw Configuration.invalid("Site screenshots require a new configuration file inside a temporary directory.")
            }
            output = URL(fileURLWithPath:destination,isDirectory:true)
            try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            try FileManager.default.createDirectory(at:fixtures,withIntermediateDirectories:true)
            let launcher = parent.appendingPathComponent("example-session")
            // Only trusted local demo scripts are dispatched. Every displayed command executes
            // in this PTY; no command output or environment listing is fabricated.
            let script = """
            #!/bin/bash
            /bin/stty sane -echo
            printf 'MOTH_SITE_READY\\n'
            while IFS= read -r fixture; do
              case "$fixture" in
                spectral|notes|config|scratch|light) /bin/bash "$MOTH_SITE_FIXTURES/$fixture.sh" ;;
              esac
            done
            """
            try script.write(to:launcher,atomically:true,encoding:.utf8)
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
            var config = Configuration()
            config.theme = "graphite"
            config.palette = Configuration.Palette(background:"141414",foreground:"DEDEDE",accent:"BDBDBD")
            config.fontSize = 14; config.typography.lineHeight = 1.16
            config.showLayoutsOnLaunch = false; config.closeOnExit = false
            config.shell = launcher.path; config.advanced.loginShell = false
            config.advanced.workingDirectory = parent.path
            config.advanced.environment = ["HOME":parent.path,"BASH_ENV":"/dev/null","ENV":"/dev/null","MOTH_SITE_FIXTURES":fixtures.path,"PATH":"/opt/homebrew/bin:/usr/bin:/bin","COLORTERM":"truecolor"]
            config.closeConfirmation.enabled = false
            config.cursor.animation = "noblink"; config.cursor.shape = "block"
            config.background.style = "solid"; config.background.animated = false; config.background.intensity = 0.08
            config.background.effectColors = ["28384D","313044","173B3B"]
            config.window.borderColor = "535353"
            try Configuration.save(config)
            try writeFixtures()
            if CommandLine.arguments.contains("--vector-reference"),let source = ProcessInfo.processInfo.environment["MOTH_VECTOR_INPUT_DIR"] {
                let directory = URL(fileURLWithPath:source).standardizedFileURL.resolvingSymlinksInPath()
                guard directory.path.hasPrefix(parent.path+"/") else { throw Configuration.invalid("Vector inputs must be inside the temporary capture directory.") }
                for name in ["before.toml","appearance.toml","nerd-fonts.txt"] {
                    let target = parent.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath:target.path) { try FileManager.default.removeItem(at:target) }
                    try FileManager.default.copyItem(at:directory.appendingPathComponent(name),to:target)
                }
            }
        } catch { fail("Preparing site screenshots: \(error)") }
    }

    static func run(_ application: App) {
        guard enabled else { return }; app = application
        DispatchQueue.main.asyncAfter(deadline:.now()+60) { fail("Site screenshot watchdog expired") }
        if CommandLine.arguments.contains("--swarm-review") {
            MothSwarmReview.run(application,output:output)
            return
        }
        if CommandLine.arguments.contains("--about") {
            NSApp.activate(ignoringOtherApps:true)
            application.showAboutWindow(nil)
            after(0.5) {
                guard let window = application.aboutWindow?.window else { fail("No About window") }
                capture(window,"moth-about.png",caption:"Native dark About Moth with the supplied white moth artwork and licence credits.")
                finish()
            }
            return
        }
        guard let host = application.active,let window = host.window else { fail("No screenshot window") }
        if CommandLine.arguments.contains("--vector-reference") { vectorReference(application,host:host,window:window); return }
        NSApp.activate(ignoringOtherApps:true)
        window.setContentSize(NSSize(width:1220,height:800)); window.center()
        host.content.layoutSubtreeIfNeeded()
        host.workspace.split(vertical:true,config:host.config)
        host.content.layoutSubtreeIfNeeded()
        if let split = host.workspace.root.subviews.first as? NSSplitView { split.setPosition(770,ofDividerAt:0) }
        let main = host.workspace.panes[0], notes = host.workspace.panes[1]
        host.newTab(nil); let second = host.workspace.active!
        host.newTab(nil); let third = host.workspace.active!
        host.selectTab(at:0); host.workspace.active = main; host.workspace.highlight(); host.refreshFooter()
        waitFor({ [main,notes,second,third].allSatisfy { $0.terminal.getTerminal().exportPlainText().contains("MOTH_SITE_READY") } }) {
            send("spectral",to:main); send("notes",to:notes); send("config",to:second); send("scratch",to:third)
            waitFor({ main.terminal.getTerminal().buffer.hasAnyImages && main.title == "aircraft" && notes.title == "field notes" && FileManager.default.fileExists(atPath:fixtures.appendingPathComponent("spectral.done").path) && FileManager.default.fileExists(atPath:fixtures.appendingPathComponent("notes.done").path) }) {
                window.makeKeyAndOrderFront(nil); window.makeFirstResponder(main.terminal)
                after(0.7) {
                    capture(window,"moth-dark-sixel.png",caption:"Graphite with a neutral grey palette, a Sixel image rendered from PTY output, tabs and split panes.",extra:["sixelDecoded":true,"fixtureTransport":"real PTY"])
                    captureLight(application)
                }
            }
        }
    }

    private static func vectorReference(_ application: App,host: TerminalWindowController,window: NSWindow) {
        NSApp.activate(ignoringOtherApps:true)
        window.setContentSize(NSSize(width:1220,height:960)); window.center()
        host.content.layoutSubtreeIfNeeded(); host.workspace.split(vertical:true,config:host.config)
        host.content.layoutSubtreeIfNeeded()
        if let split = host.workspace.root.subviews.first as? NSSplitView { split.setPosition(750,ofDividerAt:0) }
        let image = host.workspace.panes[0], diff = host.workspace.panes[1]
        host.workspace.active = diff; host.workspace.split(vertical:false,config:host.config)
        let glyphs = host.workspace.active!
        if let split = diff.superview as? NSSplitView { split.setPosition(620,ofDividerAt:0) }
        host.newTab(nil); let second = host.workspace.active!
        host.newTab(nil); let third = host.workspace.active!
        host.selectTab(at:0); host.workspace.active = diff; host.workspace.highlight(); host.refreshFooter()
        let panes = [image,diff,glyphs]
        waitFor({ (panes+[second,third]).allSatisfy { $0.terminal.getTerminal().exportPlainText().contains("MOTH_SITE_READY") } }) {
            for (pane,title) in zip(panes,["aircraft","project","glyphs"]) { pane.terminal.feed(text:"\u{1b}]0;"+title+"\u{7}\u{1b}[2J\u{1b}[H\u{1b}[?25l") }
            window.makeKeyAndOrderFront(nil); host.refreshFooter()
            after(0.3) {
                capture(window,"native-chrome.png",caption:"Unmodified native Moth window chrome with cleared terminal cells.")
                let normal = vectorGeometry(host,panes:panes)
                host.findBar.field.stringValue = "fontName|shape|animation"; host.findBar.regex.state = .on
                host.showFind(); host.findBar.count.stringValue = "1 of 6"
                host.content.layoutSubtreeIfNeeded()
                if let split = host.workspace.root.subviews.first as? NSSplitView { split.setPosition(750,ofDividerAt:0) }
                after(1.0) {
                    capture(window,"native-chrome-search.png",caption:"Native full-window Find controls, with cleared terminal cells.")
                    let search = vectorGeometry(host,panes:panes)
                    do {
                        let geometry: [String:Any] = ["normal":normal,"search":search]
                        try JSONSerialization.data(withJSONObject:geometry,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("native-geometry.json"),options:.atomic)
                    } catch { fail("Saving native vector geometry: \(error)") }
                    finish()
                }
            }
        }
    }
    private static func vectorGeometry(_ host: TerminalWindowController,panes: [Pane]) -> [String:Any] {
        let frame = host.content.superview ?? host.content
        func rect(_ view: NSView) -> [String:Double] {
            let r = view.convert(view.bounds,to:frame)
            return ["x":r.minX,"y":frame.isFlipped ? r.minY : frame.bounds.height-r.maxY,"width":r.width,"height":r.height]
        }
        return ["width":frame.bounds.width,"height":frame.bounds.height,"ansiColors":host.config.resolvedANSIColors,"panes":panes.map { pane -> [String:Any] in
            let view = pane.terminal, font = view.font, cell = view.caretFrame.size
            let naturalHeight = ceil(font.ascender-font.descender+font.leading)
            let baseline = cell.height-ceil(-font.descender+font.leading)-floor((cell.height-naturalHeight)/2)
            return ["rect":rect(view),"cellWidth":cell.width,"cellHeight":cell.height,"baseline":baseline,"fontSize":font.pointSize,"fontName":font.fontName,"cols":view.getTerminal().cols,"rows":view.getTerminal().rows]
        }]
    }

    private static func captureLight(_ application: App) {
        application.config.palette = nil
        application.config.theme = "moth-light"; application.config.background.style = "solid"
        application.config.typography.lineHeight = 1.2
        application.newWindow(nil)
        guard let host = application.windows.last,let window = host.window else { fail("No light window") }
        window.setContentSize(NSSize(width:1060,height:640)); window.center(); window.makeKeyAndOrderFront(nil)
        host.content.layoutSubtreeIfNeeded()
        waitFor({ host.workspace.active.terminal.getTerminal().exportPlainText().contains("MOTH_SITE_READY") }) {
            send("light",to:host.workspace.active)
            waitFor({ host.workspace.active.title == "field journal" && FileManager.default.fileExists(atPath:fixtures.appendingPathComponent("light.done").path) }) {
                after(0.5) {
                    capture(window,"moth-light-journal.png",caption:"Moth Light theme with configuration text and a 100-column 24-bit truecolor gradient produced by awk -f truecolor.awk.")
                    application.config.theme = "graphite"; application.config.background.style = "flow"
                    application.config.fontName = "JetBrainsMonoNFM-Regular"
                    application.config.typography.ligatures = true
                    // Use a real named profile, persisted only inside the temporary fixture tree.
                    var example = application.config
                    example.shell = "/bin/zsh"; example.advanced.loginShell = true
                    example.advanced.workingDirectory = ""
                    example.advanced.environment = ["EDITOR":"vim","LANG":"en_US.UTF-8"]
                    let profile = TerminalProfile(name:"Spectral",configuration:example)
                    do { try ProfileStore.save(profile,base:application.config,in:application.profileDirectory) } catch { fail("Saving example profile: \(error)") }
                    application.reloadProfiles(); application.applyAppearance()
                    application.showSettings(nil)
                    application.appearancePanel?.selectProfile(profile.id)
                    captureSettings(application,section:"Font",filename:"moth-font-settings.png") {
                        if let panel = application.appearancePanel,
                           let scroll = panel.scrollViews["Font"],let document = scroll.documentView,
                           let heading = panel.pages["Font"]?.arrangedSubviews.compactMap({ $0 as? NSTextField }).first(where:{ $0.stringValue == "OpenType features" }) {
                            let point = heading.convert(heading.bounds,to:document).origin
                            scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,point.y-12))); scroll.reflectScrolledClipView(scroll.contentView)
                        }
                        after(0.4) {
                            if let window = application.appearancePanel?.window { capture(window,"moth-opentype-settings.png",caption:"Native OpenType controls discovered from the bundled JetBrains Mono font; staged profile settings.") }
                            captureSettings(application,section:"Advanced",filename:"moth-advanced-settings.png") {
                                application.showAboutWindow(nil)
                                after(0.5) {
                                    if let window = application.aboutWindow?.window { capture(window,"moth-about.png",caption:"The native dark About Moth window with the supplied white moth artwork and credits.") }
                                    finish()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    private static func captureSettings(_ application: App,section: String,filename: String,then: @escaping ()->Void) {
        guard let panel = application.appearancePanel,let window = panel.window else { fail("No settings window") }
        window.appearance = NSAppearance(named:.darkAqua)
        window.setContentSize(NSSize(width:1120,height:930)); window.center()
        panel.tabs.selectTabViewItem(withIdentifier:section); panel.refresh()
        window.contentView?.layoutSubtreeIfNeeded()
        after(0.7) {
            capture(window,filename,caption:"Native \(section) settings with an isolated staged example configuration.")
            then()
        }
    }
    private static func send(_ fixture: String,to pane: Pane) { pane.terminal.sendUserText(fixture+"\r") }
    private static func after(_ seconds: Double,_ action: @escaping ()->Void) { DispatchQueue.main.asyncAfter(deadline:.now()+seconds,execute:action) }
    private static func waitFor(_ condition: @escaping ()->Bool,_ done: @escaping ()->Void) {
        let deadline = ProcessInfo.processInfo.systemUptime+25
        func poll() {
            if condition() { done() }
            else if ProcessInfo.processInfo.systemUptime > deadline {
                if let host = app?.windows.first,let window = host.window {
                    for pane in host.workspace.panes { fputs("title=\(pane.title) images=\(pane.terminal.getTerminal().buffer.hasAnyImages) output=\(pane.terminal.getTerminal().exportPlainText().prefix(200))\n",stderr) }
                    capture(window,"capture-diagnostic.png",caption:"Screenshot fixture diagnostic")
                }
                fail("Timed out waiting for screenshot PTY output")
            }
            else { after(0.05,poll) }
        }
        poll()
    }
    private static func capture(_ window: NSWindow,_ name: String,caption: String,extra: [String:Any] = [:]) {
        guard let content = window.contentView else { fail("Missing window content") }
        // Capture the native frame view as well as content, retaining AppKit titlebar/traffic lights.
        let frame = content.superview ?? content
        NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil); frame.layoutSubtreeIfNeeded(); frame.displayIfNeeded(); CATransaction.flush()
        if CommandLine.arguments.contains("--native-window-capture") {
            let destination = output.appendingPathComponent(name)
            // The capture host owns Screen Recording permission; the temporary example app does not.
            let request = output.appendingPathComponent("window-capture-request.json")
            do {
                try JSONSerialization.data(withJSONObject:["windowID":window.windowNumber,"path":destination.path]).write(to:request,options:.atomic)
            } catch { fail("Requesting native window capture: \(error)") }
            let deadline = Date().addingTimeInterval(45)
            while !FileManager.default.fileExists(atPath:destination.path),Date() < deadline {
                RunLoop.current.run(until:Date().addingTimeInterval(0.05))
            }
            guard let data = try? Data(contentsOf:destination),let bitmap = NSBitmapImageRep(data:data) else {
                fail("Native window capture failed; check Screen Recording permission.")
            }
            var record: [String:Any] = ["file":name,"caption":caption,"width":bitmap.pixelsWide,"height":bitmap.pixelsHigh,"nativeChrome":true,"nativeShadow":true,"staged":true]
            record.merge(extra) { _,new in new }; manifest.append(record)
            return
        }
        guard let bitmap = frame.bitmapImageRepForCachingDisplay(in:frame.bounds) else { fail("Cannot allocate screenshot") }
        frame.cacheDisplay(in:frame.bounds,to:bitmap)
        guard let png = bitmap.representation(using:.png,properties:[:]) else { fail("Cannot encode screenshot") }
        do { try png.write(to:output.appendingPathComponent(name),options:.atomic) } catch { fail("Saving screenshot: \(error)") }
        var record: [String:Any] = ["file":name,"caption":caption,"width":bitmap.pixelsWide,"height":bitmap.pixelsHigh,"nativeChrome":content.superview != nil,"staged":true]
        record.merge(extra) { _,new in new }; manifest.append(record)
    }
    private static func finish() {
        do {
            let record: [String:Any] = ["buildIdentifier":MothBuild.identifier,"commit":MothBuild.identity?.commit ?? "","version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") ?? "","build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") ?? "","renderer":"AppKit + SwiftTerm + CoreText/CoreGraphics; native background","assets":manifest,"artwork":"User-supplied aircraft photograph converted by img2sixel inside the captured PTY."]
            try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
        } catch { fail("Saving manifest: \(error)") }
        app?.windows.forEach { $0.stop() }; exit(0)
    }
    private static func fail(_ message: String) -> Never { fputs(message+"\n",stderr); app?.windows.forEach { $0.stop() }; exit(2) }

    private static func writeFixtures() throws {
        let parent = Configuration.url.deletingLastPathComponent()
        func write(_ name: String,_ text: String) throws {
            try text.write(to:parent.appendingPathComponent(name),atomically:true,encoding:.utf8)
        }
        // These are real input files used by the commands below, not printed transcripts.
        try write("appearance.toml", #"""
        theme = "moth-light"
        fontName = "WumpusMonoPro-Regular"
        fontSize = 14.0

        [typography]
        lineHeight = 1.2
        antialias = true

        [cursor]
        shape = "bar"
        animation = "noblink"

        """#)
        try write("truecolor.awk", #"""
        BEGIN {
            if (!width) width = 100
            pi = atan2(0, -1)
            for (row = 0; row < 3; row++) {
                for (column = 0; column < width; column++) {
                    phase = column / (width - 1) * 2 * pi
                    red = int(155 + 90 * cos(phase))
                    green = int(155 + 90 * cos(phase - 2 * pi / 3))
                    blue = int(155 + 90 * cos(phase + 2 * pi / 3))
                    printf "\033[48;2;%d;%d;%dm ", red, green, blue
                }
                printf "\033[0m\n"
            }
            print "24-bit truecolor"
        }
        """#)
        try write("palette.sh", #"""
        #!/bin/sh
        for index in 0 1 2 3 4 5 6 7; do
            printf '\033[4%sm    ' "$index"
        done
        printf '\033[0m\n'
        for index in 0 1 2 3 4 5 6 7; do
            printf '\033[10%sm    ' "$index"
        done
        printf '\033[0m\n'
        """#)
        try write("nerd-fonts.txt", """
        Wumpus Mono Pro
        Nerd Font glyphs

            Terminal
            Projects
            Git branch
            Python
            C
            TypeScript
            Browser

            Docker
            Rust
            Databases

        """)
        let common = #"""
        set -euo pipefail
        cd "$HOME"
        run() {
            printf '$ %s\n' "$1"
            printf '%s\n' "$1" >> "$MOTH_SITE_FIXTURES/$demo.commands"
            eval "$1" | /usr/bin/tee -a "$MOTH_SITE_FIXTURES/$demo.stdout"
            printf '\n'
        }
        """#
        func session(_ name: String,title: String,commands: [String]) throws {
            // Single-quote each complete shell command so the exact displayed string is
            // also the string evaluated by bash. Inputs are owned by this capture harness.
            var script = common+"\n"+"demo="+name+"\n"
            script += "printf '\\033]0;"+title+"\\007\\033[2J\\033[H\\033[?25l\\n'\n"
            for command in commands {
                script += "run '"+command.replacingOccurrences(of:"'",with:"'\\''")+"'\n"
            }
            script += "printf '$ ' \n: > \"$MOTH_SITE_FIXTURES/"+name+".done\"\n"
            try script.write(to:fixtures.appendingPathComponent(name+".sh"),atomically:true,encoding:.utf8)
        }
        try session("spectral",title:"aircraft",commands:[
            "img2sixel -p 256 -w 1320 aircraft.png 2>image-conversion.log"
        ])
        try session("notes",title:"field notes",commands:[
            "cat nerd-fonts.txt",
            "sh palette.sh"
        ])
        try session("config",title:"config.toml",commands:["cat config.toml"])
        try session("scratch",title:"scratch",commands:["pwd"])
        try session("light",title:"field journal",commands:[
            "cat appearance.toml", "awk -f truecolor.awk"
        ])
    }
}

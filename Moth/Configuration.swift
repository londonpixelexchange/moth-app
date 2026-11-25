// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import CoreText
import Darwin
import TOMLKit

struct Configuration: Codable {
    struct Typography: Codable, Equatable {
        var lineHeight: Double = 1
        var characterSpacing: Double = 0
        var ligatures = false
        var antialias = true
        var useBold = true
        var useItalic = true
        var features: [String:Int] = [:]
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy:CodingKeys.self)
            lineHeight = try c.number(forKey:.lineHeight,default:1)
            characterSpacing = try c.number(forKey:.characterSpacing,default:0)
            ligatures = try c.decodeIfPresent(Bool.self,forKey:.ligatures) ?? false
            antialias = try c.decodeIfPresent(Bool.self,forKey:.antialias) ?? true
            useBold = try c.decodeIfPresent(Bool.self,forKey:.useBold) ?? true
            useItalic = try c.decodeIfPresent(Bool.self,forKey:.useItalic) ?? true
            features = try c.decodeIfPresent([String:Int].self,forKey:.features) ?? [:]
        }
    }
    struct Palette: Codable {
        var background: String
        var foreground: String
        var accent: String
        var enabled = true
        init(background: String, foreground: String, accent: String) { self.background = background; self.foreground = foreground; self.accent = accent }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            background = try c.decodeIfPresent(String.self, forKey: .background) ?? "151820"
            foreground = try c.decodeIfPresent(String.self, forKey: .foreground) ?? "DFE4EF"
            accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "A5B8FF"
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
        var valid: Bool { [background, foreground, accent].allSatisfy(Configuration.validHex) }
    }
    struct Paint: Codable {
        var type = "solid"
        var colors: [String] = [] // Empty inherits the existing theme/colour.
        var angle: Double = 90
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? "solid"
            if type == "radial" { type = "linear" } // Retain colours from older configurations.
            colors = try c.decodeIfPresent([String].self, forKey: .colors) ?? []
            angle = try c.number(forKey: .angle, default: 90)
        }
        var valid: Bool { ["solid", "linear"].contains(type) && colors.count <= 6 && colors.allSatisfy(Configuration.validHex) && angle.isFinite && (0...360).contains(angle) && (colors.isEmpty || type == "solid" || colors.count >= 2) }
        func resolved(_ fallback: NSColor) -> [NSColor] { colors.isEmpty ? [fallback, fallback] : colors.map(NSColor.hex) }
    }
    struct Window: Codable {
        var showStatusBar = true
        var showTabBar = true
        var showBorder = true
        var chromePosition = "bottom"
        var borderColor = "596582"
        var borderPaint = Paint()
        var borderWidth: Double = 1
        var opacity: Double = 1
        var frosted = false
        var frostIntensity: Double = 1
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showStatusBar = try c.decodeIfPresent(Bool.self, forKey: .showStatusBar) ?? true
            showTabBar = try c.decodeIfPresent(Bool.self, forKey: .showTabBar) ?? true
            chromePosition = try c.decodeIfPresent(String.self,forKey:.chromePosition) ?? "bottom"
            borderColor = try c.decodeIfPresent(String.self, forKey: .borderColor) ?? "596582"
            borderPaint = try c.decodeIfPresent(Paint.self, forKey: .borderPaint) ?? Paint()
            borderWidth = try c.number(forKey: .borderWidth, default: 1)
            showBorder = try c.decodeIfPresent(Bool.self,forKey:.showBorder) ?? (borderWidth > 0)
            opacity = try c.number(forKey: .opacity, default: 1)
            frosted = try c.decodeIfPresent(Bool.self, forKey: .frosted) ?? false
            frostIntensity = try c.number(forKey:.frostIntensity,default:1)
        }
    }
    struct Background: Codable {
        enum CodingKeys: String, CodingKey { case paint, effectColors, style, colors, intensity, animated, speed, imagePath, imageScale, imageOpacity }
        static let legacyPalettes: [String: [String]] = [
            "aurora": ["6654B8", "24526B", "387969"],
            "fire": ["E26120", "D69747", "6A1726"],
            "dusk": ["774876", "BB7260", "30365D"],
            "snow": ["62829C", "B9C9D5", "394A69"],
            "abyss": ["071B31", "0E5B65", "23374F"],
            "eclipse": ["30233E", "9A6848", "1D273D"],
            "wraith": ["718D85", "493B65", "273243"],
            "cinder": ["8E3C32", "946844", "342332"],
            "veil": ["69647D", "688B8A", "34344B"],
            "void": ["102437", "233054", "1D545A"]
        ]
        var imagePath = ""
        var imageScale = "fill"
        var imageOpacity: Double = 0.35
        var paint = Paint()
        var effectColors: [String] = []
        var style = "flow"
        var colors = ["6654B8", "24526B", "387969"]
        var intensity: Double = 0.22
        var animated = true
        var speed: Double = 0.5
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            imagePath = try c.decodeIfPresent(String.self,forKey:.imagePath) ?? ""
            imageScale = try c.decodeIfPresent(String.self,forKey:.imageScale) ?? "fill"
            imageOpacity = try c.number(forKey:.imageOpacity,default:0.35)
            paint = try c.decodeIfPresent(Paint.self, forKey: .paint) ?? Paint()
            effectColors = try c.decodeIfPresent([String].self, forKey: .effectColors) ?? []
            style = try c.decodeIfPresent(String.self, forKey: .style) ?? "flow"
            colors = try c.decodeIfPresent([String].self, forKey: .colors) ?? ["6654B8", "24526B", "387969"]
            intensity = try c.number(forKey: .intensity, default: 0.22)
            animated = try c.decodeIfPresent(Bool.self, forKey: .animated) ?? true
            speed = try c.number(forKey: .speed, default: 0.5)
            if style == "custom" {
                style = "aurora"
                if paint.colors.isEmpty { paint.type = "linear"; paint.colors = colors }
            }
            if !c.contains(.effectColors), style != "solid", !paint.colors.isEmpty {
                effectColors = paint.colors.count == 1 ? [paint.colors[0], paint.colors[0]] : paint.colors
            }
            if let palette = Self.legacyPalettes[style] {
                if effectColors.isEmpty { effectColors = palette }
                style = "flow"
            }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(imagePath,forKey:.imagePath); try c.encode(imageScale,forKey:.imageScale); try c.encode(imageOpacity,forKey:.imageOpacity)
            try c.encode(paint, forKey: .paint); try c.encode(effectColors, forKey: .effectColors)
            try c.encode(style, forKey: .style); try c.encode(intensity, forKey: .intensity)
            try c.encode(animated, forKey: .animated); try c.encode(speed, forKey: .speed)
        }
        var resolvedColors: [String] { effectColors.isEmpty ? Self.defaultColors : effectColors }
        static let defaultColors = ["6654B8", "24526B", "387969"]
        mutating func resetAnimation() {
            effectColors = []; intensity = 0.22; speed = 0.5; animated = true
        }
    }
    struct Cursor: Codable {
        var paint = Paint()
        var shape = "block"
        var animation = "breathe"
        var period: Double = 1.4
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            paint = try c.decodeIfPresent(Paint.self, forKey: .paint) ?? Paint()
            shape = try c.decodeIfPresent(String.self, forKey: .shape) ?? "block"
            animation = try c.decodeIfPresent(String.self, forKey: .animation) ?? "breathe"
            if animation == "steady" { animation = "noblink" }
            period = try c.number(forKey: .period, default: 1.4)
        }
    }
    struct Bell: Codable {
        var badge = true
        var mode = "visual"
        var style = "border"
        var intensity: Double = 1
        var thickness: Double = 3
        var sound = "Glass"
        var volume: Double = 0.5
        var duration: Double = 0.2
        var color = ""
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            badge = try c.decodeIfPresent(Bool.self, forKey: .badge) ?? true
            mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "visual"
            style = try c.decodeIfPresent(String.self, forKey: .style) ?? "border"
            intensity = try c.number(forKey: .intensity, default: 1)
            thickness = try c.number(forKey: .thickness, default: 3)
            sound = try c.decodeIfPresent(String.self, forKey: .sound) ?? "Glass"
            volume = try c.number(forKey: .volume, default: 0.5)
            duration = try c.number(forKey: .duration, default: 0.2)
            color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        }
    }
    struct KeyboardSound: Codable {
        var enabled = false
        var style = "drip"
        var volume: Double = 0.12
        var key = "C"
        var mode = "lydian"
        var pattern = "random"
        var reverb: Double = 0.15
        var musical = false
        var files: [String] = []
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy:CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self,forKey:.enabled) ?? false
            style = try c.decodeIfPresent(String.self,forKey:.style) ?? "drip"
            volume = try c.number(forKey:.volume,default:0.12)
            key = try c.decodeIfPresent(String.self,forKey:.key) ?? "C"
            mode = try c.decodeIfPresent(String.self,forKey:.mode) ?? "lydian"
            pattern = try c.decodeIfPresent(String.self,forKey:.pattern) ?? "random"
            reverb = try c.number(forKey:.reverb,default:0.15)
            musical = try c.decodeIfPresent(Bool.self,forKey:.musical) ?? false
            files = try c.decodeIfPresent([String].self,forKey:.files) ?? []
        }
    }
    static let keyboardSoundOptions: [(id:String,title:String,symbol:String)] = [
        ("drip","Drips","drop"),("tink","Tinks","sparkles"),("wood","Wood","leaf"),("notes","Soft Keys","pianokeys"),
        ("glass","Glass","wineglass"),("pluck","Pluck","guitars"),("bells","Bells","bell"),("marimba","Marimba","square.grid.2x2")
    ]
    static let keyboardSoundStyles = keyboardSoundOptions.map(\.id)
    static let musicalPatterns = ["ascending","descending","random","arpeggiating"]
    static let musicalKeys = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    static let musicalModes: [(String,[Int])] = [
        ("ionian",[0,2,4,5,7,9,11]), ("dorian",[0,2,3,5,7,9,10]),
        ("phrygian",[0,1,3,5,7,8,10]), ("lydian",[0,2,4,6,7,9,11]),
        ("mixolydian",[0,2,4,5,7,9,10]), ("aeolian",[0,2,3,5,7,8,10]),
        ("locrian",[0,1,3,5,6,8,10])
    ]
    static let bellStyles = ["border", "flash", "window-border"]
    struct CloseConfirmation: Codable {
        var enabled = true
        var ignorePrograms = ["zsh", "bash", "fish", "sh", "dash", "tcsh", "csh", "nu"]
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            ignorePrograms = try c.decodeIfPresent([String].self, forKey: .ignorePrograms) ?? ignorePrograms
        }
    }
    struct Updates: Codable {
        var checkAtLaunch = true
        init() {}
        init(from decoder: Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            checkAtLaunch=try c.decodeIfPresent(Bool.self,forKey:.checkAtLaunch) ?? true
        }
    }
    struct Advanced: Codable {
        var environment: [String:String] = [:]
        var workingDirectory = ""
        var inheritWorkingDirectory = true
        var loginShell = true
        var sessionRecovery = true
        var allowDoubleSizeLines = true
        var logDirectory = ""
        var allowRemoteClipboard = false
        var copyOnSelect = false
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy:CodingKeys.self)
            environment = try c.decodeIfPresent([String:String].self,forKey:.environment) ?? [:]
            workingDirectory = try c.decodeIfPresent(String.self,forKey:.workingDirectory) ?? ""
            inheritWorkingDirectory = try c.decodeIfPresent(Bool.self,forKey:.inheritWorkingDirectory) ?? true
            loginShell = try c.decodeIfPresent(Bool.self,forKey:.loginShell) ?? true
            sessionRecovery = try c.decodeIfPresent(Bool.self,forKey:.sessionRecovery) ?? true
            allowDoubleSizeLines = try c.decodeIfPresent(Bool.self,forKey:.allowDoubleSizeLines) ?? true
            logDirectory = try c.decodeIfPresent(String.self,forKey:.logDirectory) ?? ""
            allowRemoteClipboard = try c.decodeIfPresent(Bool.self,forKey:.allowRemoteClipboard) ?? false
            copyOnSelect = try c.decodeIfPresent(Bool.self,forKey:.copyOnSelect) ?? false
        }
    }
    struct Lookup: Codable {
        var forceClickAction = "definition"
        var commandClickManual = true
        var manualPresentation = "popover"
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy:CodingKeys.self)
            forceClickAction = try c.decodeIfPresent(String.self,forKey:.forceClickAction) ?? "definition"
            commandClickManual = try c.decodeIfPresent(Bool.self,forKey:.commandClickManual) ?? true
            manualPresentation = try c.decodeIfPresent(String.self,forKey:.manualPresentation) ?? "popover"
            if manualPresentation == "split" { manualPresentation = "window" }
        }
    }
    struct Macro: Codable {
        var text = ""
        var keys: [String] = []
        var delays: [Double] = []
        var shortcut = ""
        var submit = false
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy:CodingKeys.self)
            text = try c.decodeIfPresent(String.self,forKey:.text) ?? ""
            keys = try c.decodeIfPresent([String].self,forKey:.keys) ?? []
            delays = try c.decodeIfPresent([Double].self,forKey:.delays) ?? Array(repeating:0,count:keys.count)
            shortcut = try c.decodeIfPresent(String.self,forKey:.shortcut) ?? ""
            submit = try c.decodeIfPresent(Bool.self,forKey:.submit) ?? false
        }
    }
    struct Theme {
        let name: String
        let background: Int
        let foreground: Int
        let accent: Int
        var light = false
        var ansiColors: [String] = []
    }
    static let darkMothANSI = ["252B36","FF8386","83C35D","D3A813","86ACFF","DD8BE2","13C7C0","D3D8E2","727D90","FFC0BF","AFE592","F2CF6E","BED3FE","FAB8FE","5DECE4","F7F5EF"]
    static let lightMothANSI = ["1F2631","972430","336407","695200","2B4EA7","7C2F82","0A625E","656B76","838994","82031E","275003","534104","183897","6A1571","054E4B","414854"]
    // GitHub VS Code colourblind themes, using its pinned @primer/primitives 7.10.0 tokens.
    // Source and MIT licences are included in THIRD-PARTY-NOTICES.
    static let githubDarkColorblindANSI = ["484F58","EC8E2C","58A6FF","D29922","58A6FF","BC8CFF","39C5CF","B1BAC4","6E7681","FDAC54","79C0FF","E3B341","79C0FF","D2A8FF","56D4DD","FFFFFF"]
    static let githubLightColorblindANSI = ["24292F","B35900","0550AE","4D2D00","0969DA","8250DF","1B7C83","6E7781","57606A","8A4600","0969DA","633C01","218BFF","A475F9","3192AA","8C959F"]
    static let themes: [Theme] = [
        Theme(name:"system",background:0x171922,foreground:0xE6E2DA,accent:0xB8B2E8),
        Theme(name:"moth-dark",background:0x171922,foreground:0xE6E2DA,accent:0xB8B2E8,ansiColors:darkMothANSI),
        Theme(name:"moth-light",background:0xF4F2F7,foreground:0x36333F,accent:0x695590,light:true,ansiColors:lightMothANSI),
        Theme(name:"github-dark-colorblind",background:0x0D1117,foreground:0xC9D1D9,accent:0x58A6FF,ansiColors:githubDarkColorblindANSI),
        Theme(name:"github-light-colorblind",background:0xFFFFFF,foreground:0x24292F,accent:0x0969DA,light:true,ansiColors:githubLightColorblindANSI),
        Theme(name: "midnight", background: 0x151820, foreground:0xB8CEFF, accent: 0xA5B8FF,ansiColors:["252B36","F37287","86B334","CD9716","62A2FC","C97FE3","10BAA7","D3D8E2","727D90","FFABB5","AFD575","F0BD58","A2C8FE","E8AAFE","45E1CC","F7F5EF"]),
        Theme(name: "paper", background: 0xF5F2EA, foreground:0x4B4536, accent: 0x9C4B22, light: true,ansiColors:["1F2631","852F28","1D5F1C","5D5005","3B4891","75326C","095B5E","656B76","838994","731713","004D03","493E01","2B3480","631C5A","03484A","414854"]),
        Theme(name: "forest", background: 0x101C19, foreground:0xADD7A0, accent: 0xA5CF99,ansiColors:["252B36","F2846E","66BF72","BAAA2B","929EFE","DF83C8","03BEC9","D3D8E2","727D90","FDB9AB","99E1A0","DBCF73","BFC8FE","FDAFE8","5FE2EC","F7F5EF"]),
        Theme(name: "fire", background: 0x221717, foreground:0xFFC18C, accent: 0xEFA96D,ansiColors:["252B36","FD8775","65C86B","C5AF0E","97A7FD","EA84D6","14C5CD","D3D8E2","727D90","FEC2B7","9AEA9C","E7D568","C6D0FE","FFB8EF","48ECF4","F7F5EF"]),
        Theme(name: "dusk", background: 0x211C2B, foreground:0xD7B4EE, accent: 0xD5A0CA,ansiColors:["252B36","F98696","96BE56","DAA42F","78B0FF","D191E8","22C8B4","D3D8E2","727D90","FFBFC6","BEE18D","F8CB77","B8D5FE","EDBFFD","70EBD8","F7F5EF"]),
        Theme(name: "snow", background: 0xEAF0F5, foreground:0x244F75, accent: 0x356886, light: true,ansiColors:["1F2631","90272D","2B6207","645001","304B9F","79307A","095F5D","656B76","838994","7D0419","204E02","4F3F04","1E368E","671769","044B4A","414854"]),
        Theme(name: "abyss", background: 0x0B1720, foreground:0x8FD8E8, accent: 0x76C4CD,ansiColors:["252B36","FA868E","8CC05E","D4A72E","82ADFC","D78FE2","12C8BC","D3D8E2","727D90","FEC1C2","B7E393","F3CE76","BCD4FE","F5BBFE","6BEBDF","F7F5EF"]),
        Theme(name: "eclipse", background: 0x19161E, foreground:0xF0ADA6, accent: 0xD7A37E,ansiColors:["252B36","F97774","6FBB52","C3A11B","7FA0FD","D97DD7","17BCB9","D3D8E2","727D90","FFB2AD","9EDD88","E6C75B","B2C8FE","F7AAF4","3CE3E0","F7F5EF"]),
        Theme(name: "wraith", background: 0x181E20, foreground:0xB4D1BD, accent: 0xA8C7BA,ansiColors:["252B36","EB8373","6DBA70","B8A636","8D9DF5","D684C5","15BBC2","D3D8E2","727D90","FEB3A6","9DDC9E","D9CB77","B9C5FE","F5AFE5","68DEE4","F7F5EF"]),
        Theme(name: "graphite", background: 0x202124, foreground:0xD1D3D6, accent: 0xA8B5C8,ansiColors:["252B36","F49191","90C273","CFAD4E","8CAFFE","D896DB","35C9C2","D3D8E2","727D90","FEC5C4","BAE5A3","EFD489","C3D6FF","F7C0FA","82EBE4","F7F5EF"]),
        Theme(name: "sepia", background: 0xF0E4CF, foreground:0x765024, accent: 0x985A42, light: true,ansiColors:["1F2631","86281D","045E17","584E02","3B4392","752B69","03585C","656B76","838994","730A03","054911","453C03","2B2E82","631257","044548","414854"]),
        Theme(name: "moonlight", background: 0x1A1D30, foreground:0xB8B1F2, accent: 0xB9B5ED,ansiColors:["252B36","F17993","93B33A","D79700","5EA8FC","C586E7","1FBEA5","D3D8E2","727D90","FEB0BD","BAD679","F5BF66","A3CDFE","E3B3FE","5EE3C9","F7F5EF"]),
        Theme(name:"nocturne",background:0x111C2C,foreground:0x9CBFD9,accent:0x9EBCE2,ansiColors:["252B36","FB7887","86BB43","D29F0D","74A8FD","D384E5","19C1B2","D3D8E2","727D90","FEB6BB","B0DD80","F3C55E","B0CEFD","EFB2FD","4AE8D7","F7F5EF"]),
        Theme(name:"copper",background:0x251D1B,foreground:0xE8AD90,accent:0xDEA987,ansiColors:["252B36","F18A76","6FC179","BBAD3F","96A2FC","DF8AC9","0BC1CC","D3D8E2","727D90","FEBDB0","A0E3A7","DDD27E","C3CCFE","FDB5E9","6FE4ED","F7F5EF"]),
        Theme(name:"hemlock",background:0x14201D,foreground:0xD0D897,accent:0xB2CBAE,ansiColors:["252B36","FA887F","7AC46E","C8AD2F","91A9FD","E08BD7","1DC6C7","D3D8E2","727D90","FEC2BB","A9E69E","E9D377","C3D1FE","FFB7F5","67EAEB","F7F5EF"]),
        Theme(name:"vellum",background:0xF6F0E5,foreground:0x82443C,accent:0x85624A,light:true,ansiColors:["1F2631","892A27","1C600F","5E4F04","374796","762F70","095C5C","656B76","838994","770D12","0F4C03","4A3E01","263385","64185F","034849","414854"]),
        Theme(name:"lilac",background:0xF0EDF8,foreground:0x70468A,accent:0x795C9D,light:true,ansiColors:["1F2631","941328","2E5E01","624D02","2346A6","78257F","025C59","656B76","838994","78031C","244A03","4D3C04","103096","67016E","054846","414854"]),
        Theme(name:"tideline",background:0xEAF3F0,foreground:0x205D58,accent:0x396F79,light:true,ansiColors:["1F2631","8C2C33","316106","655008","2E4D99","753479","095F5B","656B76","838994","7A1020","254D02","503F03","1C3989","631D68","034C48","414854"])
    ]
    static func themeTitle(_ name: String) -> String {
        ["github-dark-colorblind":"GitHub Dark Colourblind","github-light-colorblind":"GitHub Light Colourblind","system":"System","moth-dark":"Moth Dark","moth-light":"Moth Light","fire": "Ember", "dusk": "Afterglow", "snow": "Porcelain", "abyss": "Deepwater", "eclipse": "Obsidian", "wraith": "Lichen"][name] ?? name.capitalized
    }
    static var themeNames: [String] { themes.map(\.name) }
    static var systemIsDark: Bool { NSApp.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua }
    func resolvedTheme(systemDark: Bool) -> Theme { Self.themes.first { $0.name == (theme == "system" ? (systemDark ? "moth-dark" : "moth-light") : theme) } ?? Self.themes[1] }
    var selectedTheme: Theme { resolvedTheme(systemDark:Self.systemIsDark) }
    static let backgroundStyles = ["solid", "flow", "image"]
    // Strength controls the single animated colour field.
    var backgroundFieldOpacity: Double { background.intensity * 0.75 }
    static let defaultANSIColors = ["000000","C23621","25BC24","ADAD27","492EE1","D338D3","33BBC8","CBCCCD","818383","FC391F","31E722","EAEC23","5833FF","F935F8","14F0F0","E9EBEB"]
    static let ansiPresets: [(String,[String])] = [
        ("Moth Classic",defaultANSIColors),
        ("GitHub Dark Colourblind",githubDarkColorblindANSI),
        ("GitHub Light Colourblind",githubLightColorblindANSI),
        ("Lavender Haze",["252635","E8A5AE","B6D5BA","E9D7A5","ACBFE7","D4B2DF","9ED6D2","E0DFE8","77758A","F7C5CD","D0E8D2","F5E8C4","CAD7F7","E8CFF0","C3EEEA","FAF8FF"]),
        ("Sea Glass",["20302F","E7AAA2","ADD2B5","E5D5A9","A6C8DB","CDB9DA","9BD1C7","DCE6E1","70857E","F5CBC4","C9E5CD","F6E8CA","C5DFED","E3D3ED","C0E9DF","F4FCF7"]),
        ("Rose Ash",["302831","DEA1AE","B7C9B0","DDCAA5","ADBBD3","CEACCD","ABCBC9","E3DBDE","857683","F2C1CE","D3E0CC","F1E3C5","CED8EA","E4C9E4","CEE5E0","FFF6FA"])
    ]
    var ansiColors: [String] = []
    var resolvedANSIColors: [String] { ansiColors.isEmpty ? (selectedTheme.ansiColors.isEmpty ? Self.defaultANSIColors : selectedTheme.ansiColors) : ansiColors }
    var palette: Palette? = nil
    var theme = "system"
    static let defaultFontName = "WumpusMonoPro-Regular"
    static let bundledFonts = [("Wumpus Mono Pro", "WumpusMonoPro-Regular"),("JetBrains Mono · Nerd Font", "JetBrainsMonoNFM-Regular"),("IBM Plex Mono", "IBMPlexMono")]
    var fontName = Configuration.defaultFontName
    var fontSize: Double = 14
    var typography = Typography()
    var showLayoutsOnLaunch = false
    var defaultProfileID = ""
    var scrollback = 10000
    var alternateScreenScrollback = true
    var closeOnExit = true
    var textEncoding = "UTF-8"
    var enabledEncodings = TerminalTextEncoding.choices.map(\.id)
    var shell = "/bin/zsh"
    var optionAsMeta = false
    var window = Window()
    var background = Background()
    var cursor = Cursor()
    var bell = Bell()
    var keyboardSound = KeyboardSound()
    var closeConfirmation = CloseConfirmation()
    var advanced = Advanced()
    var updates = Updates()
    var lookup = Lookup()
    var macros: [String:Macro] = [:]
    static var defaultKeybindings: [String: String] {
        var bindings = ["newWindow": "cmd+n", "newTab": "cmd+t", "splitRight": "cmd+d", "splitDown": "cmd+shift+d", "closePane": "cmd+w", "nextPane": "cmd+]", "toggleMaximizePane":"cmd+shift+return", "nextTab": "cmd+shift+]", "reloadConfig": "cmd+alt+r", "openLayouts": "cmd+shift+r", "resetTerminal": "cmd+r", "toggleKeyboardSounds": "cmd+alt+k", "openManualPage":"cmd+ctrl+m"]
        for number in 1...9 { bindings["selectTab\(number)"] = "cmd+\(number)" }
        return bindings
    }
    var keybindings = Configuration.defaultKeybindings
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ansiColors = try c.decodeIfPresent([String].self,forKey:.ansiColors) ?? []
        palette = try c.decodeIfPresent(Palette.self, forKey: .palette)
        if palette?.enabled == false { palette = nil }
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? theme
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? fontName
        if fontName == "WumpusMonoNFM" { fontName = Self.defaultFontName }
        fontSize = try c.number(forKey: .fontSize, default: fontSize)
        typography = try c.decodeIfPresent(Typography.self,forKey:.typography) ?? typography
        showLayoutsOnLaunch = try c.decodeIfPresent(Bool.self,forKey:.showLayoutsOnLaunch) ?? false
        defaultProfileID = try c.decodeIfPresent(String.self,forKey:.defaultProfileID) ?? ""
        scrollback = try c.decodeIfPresent(Int.self, forKey: .scrollback) ?? scrollback
        alternateScreenScrollback = try c.decodeIfPresent(Bool.self, forKey: .alternateScreenScrollback) ?? true
        closeOnExit = try c.decodeIfPresent(Bool.self,forKey:.closeOnExit) ?? true
        textEncoding = try c.decodeIfPresent(String.self,forKey:.textEncoding) ?? "UTF-8"
        enabledEncodings = try c.decodeIfPresent([String].self,forKey:.enabledEncodings) ?? TerminalTextEncoding.choices.map(\.id)
        shell = try c.decodeIfPresent(String.self, forKey: .shell) ?? shell
        optionAsMeta = try c.decodeIfPresent(Bool.self, forKey: .optionAsMeta) ?? optionAsMeta
        window = try c.decodeIfPresent(Window.self, forKey: .window) ?? window
        background = try c.decodeIfPresent(Background.self, forKey: .background) ?? background
        cursor = try c.decodeIfPresent(Cursor.self, forKey: .cursor) ?? cursor
        bell = try c.decodeIfPresent(Bell.self, forKey: .bell) ?? bell
        keyboardSound = try c.decodeIfPresent(KeyboardSound.self,forKey:.keyboardSound) ?? keyboardSound
        closeConfirmation = try c.decodeIfPresent(CloseConfirmation.self, forKey: .closeConfirmation) ?? closeConfirmation
        advanced = try c.decodeIfPresent(Advanced.self,forKey:.advanced) ?? advanced
        updates = try c.decodeIfPresent(Updates.self,forKey:.updates) ?? updates
        lookup = try c.decodeIfPresent(Lookup.self,forKey:.lookup) ?? lookup
        macros = try c.decodeIfPresent([String:Macro].self,forKey:.macros) ?? [:]
        let storedKeybindings=try c.decodeIfPresent([String:String].self,forKey:.keybindings)
        keybindings=storedKeybindings ?? keybindings
        if keybindings["resetTerminal"] == nil && !keybindings.values.contains("cmd+r") { keybindings["resetTerminal"] = "cmd+r" }
        if keybindings["openLayouts"] == nil {
            if keybindings["reloadConfig"] == "cmd+shift+r" { keybindings["reloadConfig"] = "cmd+alt+r" }
            let occupied = keybindings.values.contains { value in guard let shortcut = Self.shortcut(value) else { return false }; return shortcut.0 == "r" && shortcut.1 == [.command,.shift] }
            keybindings["openLayouts"] = occupied ? "" : "cmd+shift+r"
        }
        if keybindings["openManualPage"] == nil {
            let existing = Array(keybindings.values)+macros.values.map(\.shortcut)
            let occupied = existing.contains { Self.shortcut($0).map { $0.0 == "m" && $0.1 == [.command,.control] } ?? false }
            keybindings["openManualPage"] = occupied ? "" : "cmd+ctrl+m"
        }
        if keybindings["toggleKeyboardSounds"] == nil {
            let occupied = keybindings.values.contains { Self.shortcut($0).map { $0.0 == "k" && $0.1 == [.command,.option] } ?? false }
            keybindings["toggleKeyboardSounds"] = occupied ? "" : "cmd+alt+k"
        }
        if storedKeybindings?["toggleMaximizePane"] == nil {
            let existing=keybindings.filter{$0.key != "toggleMaximizePane"}.map{$0.value}+macros.values.map{$0.shortcut}
            let occupied=existing.contains { Self.shortcut($0).map{$0.0=="\r" && $0.1 == [.command,.shift]} ?? false }
            keybindings["toggleMaximizePane"]=occupied ? "":"cmd+shift+return"
        }
        // Existing configurations predate the New Window action.
        if keybindings["newWindow"] == nil { keybindings["newWindow"] = "cmd+n" }
        for number in 1...9 {
            let action = "selectTab\(number)", binding = "cmd+\(number)"
            let alreadyUsed = keybindings.values.contains { value in
                guard let shortcut = Self.shortcut(value) else { return false }
                return shortcut.0 == String(number) && shortcut.1 == .command
            }
            if keybindings[action] == nil && !alreadyUsed { keybindings[action] = binding }
        }
    }
    static var url: URL {
        if let root = RecoveryHostFixture.root { return root.appendingPathComponent("config.toml") }
        if CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--benchmark") || CommandLine.arguments.contains("--site-screenshots") {
            if let path = ProcessInfo.processInfo.environment["MOTH_CONFIG_PATH"] { return URL(fileURLWithPath: path) }
            return FileManager.default.temporaryDirectory.appendingPathComponent("moth-selftest-\(getpid())/config.toml")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/moth/config.toml")
    }
    static func validHex(_ string: String) -> Bool { string.count == 6 && Int(string, radix: 16) != nil }
    static func load(from url: URL = Configuration.url) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        let data = try Data(contentsOf: url)
        guard data.count <= 65536 else { throw invalid("Configuration is larger than 64 KB.") }
        guard let text = String(data: data, encoding: .utf8) else { throw invalid("TOML configuration must be UTF-8.") }
        let table = try TOMLDocument.parse(text)
        let config = try TOMLDecoder().decode(Configuration.self, from: table)
        try config.validate()
        return config
    }
    func validate() throws {
        guard ["off","definition","manual"].contains(lookup.forceClickAction),["popover","window"].contains(lookup.manualPresentation) else { throw Self.invalid("Choose a valid force-click action and manual-page presentation.") }
        for path in [advanced.workingDirectory,advanced.logDirectory] where !path.isEmpty {
            var directory: ObjCBool = false
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath:path,isDirectory:&directory),directory.boolValue else { throw Self.invalid("Advanced directories must be existing absolute folder paths, or empty for defaults.") }
        }
        guard advanced.environment.count <= 128,advanced.environment.allSatisfy({ key,value in !key.isEmpty && !key.contains("=") && !key.contains("\0") && !value.contains("\0") }),advanced.environment.reduce(0,{$0+$1.key.utf8.count+$1.value.utf8.count}) <= 8192 else { throw Self.invalid("Environment overrides must be valid NAME=value entries, up to 8 KB in total.") }
        guard macros.count <= 64, macros.reduce(0,{$0+$1.key.utf8.count+$1.value.text.utf8.count+$1.value.keys.reduce(0,{$0+$1.utf8.count})}) <= 32768 else { throw Self.invalid("Use up to 64 macros and 32 KB of macro text/keys in total.") }
        for (name,macro) in macros {
            guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count <= 64,!name.unicodeScalars.contains(where:{$0.value < 32}),macro.text.utf8.count <= 8192,macro.keys.count <= 512,macro.keys.count == macro.delays.count,macro.delays.allSatisfy({$0.isFinite && (0...5).contains($0)}),macro.delays.reduce(0,+) <= 120,macro.text.isEmpty || macro.keys.isEmpty else { throw Self.invalid("Macro ‘\(name)’ needs a name, either text or recorded keys, and matching delays (0–5 seconds, 120 seconds total).") }
        }

        guard (Self.keyboardSoundStyles+["custom"]).contains(keyboardSound.style), (0...1).contains(keyboardSound.volume), (0...1).contains(keyboardSound.reverb), Self.musicalPatterns.contains(keyboardSound.pattern), Self.musicalKeys.contains(keyboardSound.key), Self.musicalModes.contains(where: { $0.0 == keyboardSound.mode }) else { throw Self.invalid("Keyboard sound: choose a built-in style; volume/reverb 0–1; ascending, descending, random or arpeggiating pattern; musical key C–B (use # for sharps), and a diatonic mode such as lydian or locrian.") }

        guard keyboardSound.files.count <= 16, keyboardSound.files.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else { throw Self.invalid("Use up to 16 absolute audio-file paths for keyboard sounds.") }
        if keyboardSound.style == "custom" {
            guard !keyboardSound.files.isEmpty else { throw Self.invalid("Choose at least one custom keyboard sound file.") }
            for path in keyboardSound.files { _ = try KeyboardSoundPlayer.audioFile(path) }
        }
        guard (ansiColors.isEmpty || ansiColors.count == 16), ansiColors.allSatisfy(Self.validHex) else { throw Self.invalid("ANSI colours must contain 16 six-digit colours (normal 0–7, then bright 8–15), or [] for defaults.") }
        guard window.borderPaint.valid, background.paint.valid, cursor.paint.valid else { throw Self.invalid("Paint type: solid or linear. Use 2–6 six-digit colours for gradients, or an empty list to inherit; angle: 0–360 degrees.") }
        guard (1...2).contains(typography.lineHeight), (0...6).contains(typography.characterSpacing), typography.features.count <= 128,
              typography.features.allSatisfy({ $0.key.utf8.count == 4 && $0.key.utf8.allSatisfy { (32...126).contains($0) } && (0...99).contains($0.value) }) else {
            throw Self.invalid("Typography: line height 1–2, character spacing 0–6 pt, and four-character OpenType tags with values 0–99.")
        }
        guard TerminalTextEncoding.choices.contains(where: { $0.id == textEncoding }),!enabledEncodings.isEmpty,Set(enabledEncodings).count == enabledEncodings.count,enabledEncodings.allSatisfy({ id in TerminalTextEncoding.choices.contains { $0.id == id } }) else { throw Self.invalid("Choose a supported text encoding and enable at least one encoding for the menus.") }
        guard defaultProfileID.isEmpty || UUID(uuidString:defaultProfileID) != nil else { throw Self.invalid("Default profile must be empty or a valid profile ID.") }
        guard palette?.valid != false, (9...32).contains(fontSize), (0...100000).contains(scrollback), Self.themeNames.contains(theme), FileManager.default.isExecutableFile(atPath: shell), NSFont(name: fontName, size: fontSize) != nil else {
            throw Self.invalid("Check the theme, font, font size (9–32), history limit (0–100000), and executable shell path.")
        }
        guard ["bottom","titlebar"].contains(window.chromePosition),Self.validHex(window.borderColor), (0...6).contains(window.borderWidth), (0...1).contains(window.opacity), (0...1).contains(window.frostIntensity), Self.backgroundStyles.contains(background.style), (background.effectColors.isEmpty || (2...6).contains(background.effectColors.count)), background.effectColors.allSatisfy(Self.validHex), (2...6).contains(background.colors.count), background.colors.allSatisfy(Self.validHex), (0...1).contains(background.intensity), (0.05...3).contains(background.speed) else {
            throw Self.invalid("Check the window border and background settings. Window opacity must be 0–1. Colours need six hexadecimal digits, without #.")
        }
        guard ["fill","fit"].contains(background.imageScale),(0...1).contains(background.imageOpacity),background.imagePath.utf8.count <= 4096,!background.imagePath.contains("\0") else { throw Self.invalid("Background image: use fit or fill, strength 0–1 and a local file path.") }
        guard ["block", "underline", "bar"].contains(cursor.shape), ["blink", "breathe", "noblink"].contains(cursor.animation), (0.2...5).contains(cursor.period) else {
            throw Self.invalid("Cursor shape: block, underline, or bar. Animation: blink, breathe, or noblink. Period: 0.2–5 seconds.")
        }
        guard ["off","visual","sound","both"].contains(bell.mode), Self.bellStyles.contains(bell.style), (0...1).contains(bell.intensity), (1...12).contains(bell.thickness), (0...1).contains(bell.volume), (0.08...1).contains(bell.duration), bell.color.isEmpty || Self.validHex(bell.color),
              (bell.sound.hasPrefix("/") ? NSSound(contentsOfFile: bell.sound, byReference: true) != nil : NSSound(named: NSSound.Name(bell.sound)) != nil) else {
            throw Self.invalid("Bell mode: off, visual, sound, or both. Style: border, flash, or window-border; intensity 0–1; thickness 1–12 points. Use a system sound name or absolute audio file path, volume 0–1, duration 0.08–1 seconds, and an optional six-digit colour.")
        }
        guard closeConfirmation.ignorePrograms.count <= 128, closeConfirmation.ignorePrograms.allSatisfy({ !$0.isEmpty && !$0.contains("*") && !$0.contains("?") && (!$0.contains("/") || $0.hasPrefix("/")) && !$0.unicodeScalars.contains(where: { $0.value < 32 }) }) else {
            throw Self.invalid("Close confirmation exceptions must be exact program names or absolute executable paths, without wildcards.")
        }
        var shortcuts = Set<String>()
        for (action, binding) in keybindings {
            guard Self.actions.contains(action) else { throw Self.invalid("Unknown shortcut action: \(action)") }
            if binding.isEmpty { continue }
            guard let shortcut = Self.shortcut(binding) else { throw Self.invalid("Invalid shortcut: \(action) = \(binding)") }
            let normalized = "\(shortcut.1.rawValue):\(shortcut.0)"
            guard shortcuts.insert(normalized).inserted else { throw Self.invalid("Shortcuts must be unique.") }
        }
        let reserved = ["cmd+,","cmd+q","cmd+h","cmd+m","cmd+c","cmd+v","cmd+a","cmd+f","cmd+g","cmd+shift+g","cmd+s","cmd+p","cmd+shift+p","cmd+ctrl+f","cmd++","cmd+-"]
        for binding in reserved { if let key = Self.shortcut(binding) { shortcuts.insert("\(key.1.rawValue):\(key.0)") } }
        for (name,macro) in macros where !macro.shortcut.isEmpty {
            guard let key = Self.shortcut(macro.shortcut),shortcuts.insert("\(key.1.rawValue):\(key.0)").inserted else { throw Self.invalid("Macro ‘\(name)’ has an invalid, duplicate or reserved shortcut.") }
        }
    }
    static func invalid(_ text: String) -> Error { NSError(domain: "Moth", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    static let actions = ["newWindow", "newTab", "splitRight", "splitDown", "closePane", "toggleMaximizePane", "nextPane", "nextTab", "reloadConfig", "resetTerminal", "openLayouts", "toggleKeyboardSounds", "openManualPage"] + (1...9).map { "selectTab\($0)" }
    static func shortcut(_ text: String) -> (String, NSEvent.ModifierFlags)? {
        let parts = text.lowercased().split(separator: "+").map(String.init)
        guard let rawKey = parts.last else { return nil }
        let key = ["return","enter"].contains(rawKey) ? "\r":rawKey
        guard key.count == 1, parts.contains("cmd"), parts.dropLast().allSatisfy({ ["cmd", "shift", "alt", "ctrl"].contains($0) }) else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for p in parts.dropLast() { flags.formUnion(["cmd": .command, "shift": .shift, "alt": .option, "ctrl": .control][p]!) }
        return (key, flags)
    }
    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [] { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
    /// Create or migrate the config, then fill missing defaults without removing comments.
    @discardableResult
    static func expandFile(at url: URL = Configuration.url) throws -> Configuration {
        if !FileManager.default.fileExists(atPath: url.path) {
            let legacy = url.deletingLastPathComponent().appendingPathComponent("config.json")
            if FileManager.default.fileExists(atPath: legacy.path) {
                let bytes = try Data(contentsOf: legacy)
                var config = try JSONDecoder().decode(Configuration.self, from: bytes)
                if config.background.style == "flow", config.background.colors != Background().colors, config.background.paint.colors.isEmpty { config.background.effectColors = config.background.colors }
                try config.validate()
                let backup = legacy.appendingPathExtension("before-toml")
                if !FileManager.default.fileExists(atPath: backup.path) { try bytes.write(to: backup, options: .atomic) }
                var object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
                object.removeValue(forKey: "_help")
                let extra = TOMLDocument.table(fromJSON: object)
                let desired: TOMLTable = try TOMLEncoder().encode(config)
                TOMLDocument.merge(into: extra, from: desired)
                try TOMLDocument.write(TOMLDocument.render(extra), to: url)
            } else { try save(Configuration(), to: url) }
        }
        var config = try load(from:url)
        let fontBackup = url.appendingPathExtension("before-moth-16-defaults")
        if !FileManager.default.fileExists(atPath:fontBackup.path) {
            try Data(contentsOf:url).write(to:fontBackup,options:.atomic)
            if config.fontName == "JetBrainsMonoNFM-Regular" { config.fontName = Self.defaultFontName }
            if config.theme == "midnight" { config.theme = "system" }
        }
        try save(config, to: url)
        return config
    }
    static func save(_ config: Configuration, to url: URL = Configuration.url) throws {
        let desired: TOMLTable = try TOMLEncoder().encode(config)
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try String(contentsOf: url, encoding: .utf8)
            let old = try TOMLDocument.parse(existing)
            if config.palette == nil, old["palette"] != nil { desired["palette"] = TOMLTable(["enabled": false]) }
            if old["background"]?["colors"] != nil {
                let backup = url.appendingPathExtension("before-background-palette")
                if !FileManager.default.fileExists(atPath: backup.path) { try Data(existing.utf8).write(to: backup, options: .atomic) }
            }
            let source = try TOMLDocument.removingLegacyBackgroundColors(existing)
                .replacingOccurrences(of: "# type: solid | linear | radial.", with: "# type: solid | linear.")
                .replacingOccurrences(of: "# Border paint: type = solid | linear | radial;", with: "# Border paint: type = solid | linear;")
                .replacingOccurrences(of: "; also solid and custom.", with: "; solid turns the effect off.")
                .replacingOccurrences(of: "# Custom uses colors below; the named styles have their own palettes. Motion respects Reduce Motion.", with: "# Personalise any effect with background.paint below. Motion respects Reduce Motion.")
                .replacingOccurrences(of: "# Dynamic styles: aurora, fire, dusk, snow, abyss, eclipse, wraith, cinder, veil, void; solid turns the effect off.", with: "# style: flow for the animation, or solid for a plain background.")
                .replacingOccurrences(of: "# Personalise any effect with background.paint below. Motion respects Reduce Motion.", with: "# effectColors: 2–6 animation colours; [] uses the default palette. background.paint applies only to Off. Motion respects Reduce Motion.")
                .replacingOccurrences(of:"# Musical key and mode apply to notes; shortcuts and pasted text stay silent.",with:"# Key, mode and pattern apply to every sound; shortcuts and pasted text stay silent.")
                .replacingOccurrences(of:"# style: drip | tink | wood | notes. volume: 0–1 (quiet default 0.12).",with:"# style: drip | tink | wood | notes (Soft Keys) | glass | pluck | bells | marimba.\n# volume: 0–1 (quiet default 0.12). reverb: 0–1 (dry to spacious).")
                .replacingOccurrences(of:"# Choose colours and motion in View > Appearance.",with:"# Choose colours and motion in Settings (Cmd+,).")
                .replacingOccurrences(of:"# Key, mode and pattern apply to every sound; shortcuts and pasted text stay silent.",with:"# musical: false plays the natural sound; true enables key, mode and pattern.\n# files: absolute audio paths for style = custom; multiple clips rotate as you type.\n# Custom pitching treats recordings as C4 and changes speed. Shortcuts and pasted text stay silent.")
            let updated = try TOMLDocument.updating(source, with: desired)
            if updated != existing { try TOMLDocument.write(updated, to: url) }
        } else {
            try TOMLDocument.write(TOMLDocument.render(desired), to: url)
        }
    }
    static func resetPreferences(at url: URL = Configuration.url) throws -> (Configuration,URL?) {
        let defaults = Configuration(); try defaults.validate()
        var backup: URL?
        if FileManager.default.fileExists(atPath:url.path) {
            let stamp = ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")
            let target = url.appendingPathExtension("before-reset-"+stamp+"-"+UUID().uuidString.prefix(6))
            try Data(contentsOf:url).write(to:target,options:.atomic); backup = target
        }
        try TOMLDocument.write(try document(defaults),to:url)
        return (defaults,backup)
    }
    static func document(_ config: Configuration) throws -> String { let table: TOMLTable = try TOMLEncoder().encode(config); return TOMLDocument.render(table) }
    var windowBackgroundOpacity: CGFloat { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : CGFloat(window.opacity) }
    var usesFrosting: Bool { window.frosted && window.frostIntensity > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    var colors: (NSColor, NSColor, NSColor) {
        if let p = palette, p.valid { return (.hex(p.background), .hex(p.foreground), .hex(p.accent)) }
        let selected = selectedTheme
        return (.hex(selected.background), .hex(selected.foreground), .hex(selected.accent))
    }
}

/// Watches the directory as well as the file: editors commonly save by atomic rename.
final class ConfigWatcher {
    private let url: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var fallback: Timer?
    private var lastData: Data?
    private var fileIdentity: UInt64?
    var changed: (() -> Void)?
    init(url: URL) {
        self.url = url
        lastData = try? Data(contentsOf: url)
        directorySource = watch(url.deletingLastPathComponent())
        armFile()
        // Recovers after directory replacement or a previously missing parent directory.
        fallback = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.check() }
    }
    private func watch(_ url: URL) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let isFile = url == self.url
            let events = (isFile ? self.fileSource?.data : self.directorySource?.data) ?? []
            if !events.intersection([.delete, .rename]).isEmpty {
                if isFile { self.fileSource?.cancel(); self.fileSource = nil }
                else { self.directorySource?.cancel(); self.directorySource = nil }
            }
            self.schedule()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }
    private func armFile() {
        let identity = (try? FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber]) as? UInt64
        if fileSource == nil || identity != fileIdentity {
            fileSource?.cancel(); fileSource = watch(url); fileIdentity = identity
        }
    }
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.2, execute: work)
    }
    private func check() {
        armFile()
        if directorySource == nil { directorySource = watch(url.deletingLastPathComponent()) }
        let data = try? Data(contentsOf: url)
        guard data != lastData else { return }
        lastData = data; changed?()
    }
    deinit { pending?.cancel(); fallback?.invalidate(); directorySource?.cancel(); fileSource?.cancel() }
}

extension NSColor {
    static func hex(_ string: String) -> NSColor { .hex(Int(string, radix: 16) ?? 0) }
    static func hex(_ value: Int) -> NSColor { NSColor(srgbRed: CGFloat((value >> 16) & 255)/255, green: CGFloat((value >> 8) & 255)/255, blue: CGFloat(value & 255)/255, alpha: 1) }
}

private extension KeyedDecodingContainer {
    func number(forKey key: Key, default fallback: Double) throws -> Double {
        guard contains(key), try !decodeNil(forKey: key) else { return fallback }
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        return try decode(Double.self, forKey: key)
    }
}

/// OpenType tags come from the font's actual GSUB/GPOS feature lists.
enum FontTypography {
    static func styledFont(_ base: NSFont,traits: NSFontTraitMask) -> NSFont? {
        guard let prefix = ["WumpusMonoPro-","WumpusMonoProNFM-"].first(where: { base.fontName.hasPrefix($0) }) else { return nil }
        let style = String(base.fontName.dropFirst(prefix.count)),italic = style.hasSuffix("Italic") || style == "Italic" || traits.contains(.italicFontMask)
        var weight = style.replacingOccurrences(of:"Italic",with:"")
        if weight.isEmpty { weight = "Regular" }
        if traits.contains(.boldFontMask) { weight = "Bold" }
        let face = italic ? (weight == "Regular" ? "Italic" : weight+"Italic") : weight
        return NSFont(name:prefix+face,size:base.pointSize)
    }

    static func supportedTags(_ font: NSFont) -> [String] {
        var tags = Set<String>()
        for table: CTFontTableTag in [0x47535542,0x47504F53] {
            guard let data = CTFontCopyTable(font,table,[]) as Data? else { continue }
            let bytes = [UInt8](data)
            func u16(_ offset: Int) -> Int? { guard offset >= 0,offset+1 < bytes.count else { return nil }; return Int(bytes[offset]) << 8 | Int(bytes[offset+1]) }
            guard let start = u16(6),let count = u16(start),count <= 4096,start+2+count*6 <= bytes.count else { continue }
            for i in 0..<count {
                let offset = start+2+i*6
                if let tag = String(bytes:bytes[offset..<offset+4],encoding:.ascii) { tags.insert(tag) }
            }
        }
        return tags.sorted()
    }
    static func label(_ tag: String) -> String {
        let names = ["zero":"Slashed zero","calt":"Contextual alternates","liga":"Standard ligatures","dlig":"Discretionary ligatures","hlig":"Historical ligatures","salt":"Stylistic alternates","aalt":"All alternates","case":"Case-sensitive forms","cpsp":"Capital spacing","frac":"Fractions","ordn":"Ordinals","tnum":"Tabular numbers","pnum":"Proportional numbers","lnum":"Lining numbers","onum":"Old-style numbers","kern":"Kerning","locl":"Localised forms"]
        if let name = names[tag] { return name }
        if tag.hasPrefix("ss"),let n = Int(tag.suffix(2)) { return "Stylistic set \(n)" }
        if tag.hasPrefix("cv"),let n = Int(tag.suffix(2)) { return "Character variant \(n)" }
        return tag
    }
    static func font(_ config: Configuration) -> NSFont {
        let base = NSFont(name:config.fontName,size:config.fontSize) ?? .monospacedSystemFont(ofSize:config.fontSize,weight:.regular)
        var features = config.typography.features
        if config.typography.ligatures {
            if features["liga"] == nil { features["liga"] = 1 }; if features["calt"] == nil { features["calt"] = 1 }
        } else { for tag in ["liga","calt","dlig","hlig"] { features[tag] = 0 } }
        let settings = features.sorted { $0.key < $1.key }.map { [kCTFontOpenTypeFeatureTag as String:$0.key,kCTFontOpenTypeFeatureValue as String:$0.value] as [String:Any] }
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings:settings,.cascadeList:[NSFontDescriptor(name:"MothNerdSymbolsMono-Regular",size:config.fontSize)]])
        return NSFont(descriptor:descriptor,size:config.fontSize) ?? base
    }
}

// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import AVFoundation

/// One step per accepted keystroke. Changing scale/pattern begins a new phrase.
struct KeyboardNoteSequence {
    private var step = 0
    private var signature = ""
    mutating func next(_ config: Configuration.KeyboardSound, randomIndex: () -> Int = { Int.random(in:0..<7) }) -> Int {
        guard config.musical else { signature = ""; step = 0; return 60 }
        let nextSignature = "\(config.key):\(config.mode):\(config.pattern)"
        if signature != nextSignature { signature = nextSignature; step = 0 }
        let notes = KeyboardSoundPlayer.midiNotes(config)
        let index: Int
        switch config.pattern {
        case "ascending": index = step % 7
        case "descending": index = 6-step % 7
        case "arpeggiating": index = [0,2,4,6,4,2][step % 6]
        default: index = max(0,min(6,randomIndex()))
        }
        step = (step+1) % 42
        return notes[index]
    }
}

/// Cached voices mixed through one native stereo reverb. No work on the audio thread.
final class KeyboardSoundPlayer {
    static let shared = KeyboardSoundPlayer()
    private let engine = AVAudioEngine()
    private let voiceMixer = AVAudioMixerNode()
    private let reverbUnit = AVAudioUnitReverb()
    private let format = AVAudioFormat(standardFormatWithSampleRate:44100,channels:1)!
    private var voices: [AVAudioPlayerNode] = []
    private var cache: [String:AVAudioPCMBuffer] = [:]
    private var cacheOrder: [String] = []
    private var sourceCache: [String:[Float]] = [:]
    private var customIndex = 0
    private var previewCustomIndex = 0
    private var voice = 0
    private var sequence = KeyboardNoteSequence()
    private var previewSequence = KeyboardNoteSequence()
    private var previewTimer: Timer?
    private var auditionConfiguration: Configuration.KeyboardSound?
    private var lastTime: TimeInterval = 0
    private var typingEnabled = false
    private(set) var scheduledCount = 0
    private(set) var lastMIDI: Int?
    private(set) var lastCustomFile: String?
    private(set) var lastFrameCount = 0
    private(set) var lastError: String?
    var routesThroughReverb: Bool { !voices.isEmpty && engine.outputConnectionPoints(for:voiceMixer,outputBus:0).contains { $0.node === reverbUnit } && engine.outputConnectionPoints(for:reverbUnit,outputBus:0).contains { $0.node === engine.mainMixerNode } }
    var reverbMix: Float { reverbUnit.wetDryMix }

    static func shouldPlay(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
              let text = event.characters, !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { ($0.value >= 32 && $0.value < 0xF700) || [8,9,13,127].contains($0.value) }
    }
    static func midiNotes(_ config: Configuration.KeyboardSound) -> [Int] {
        let root = Configuration.musicalKeys.firstIndex(of:config.key) ?? 0
        let intervals = Configuration.musicalModes.first(where: { $0.0 == config.mode })?.1 ?? [0,2,4,6,7,9,11]
        return intervals.map { 60+root+$0 }
    }
    static func samples(style: String, midi: Int, sampleRate: Double = 44100) -> [Float] {
        if style == "pluck" { return pluckedString(midi:midi,sampleRate:sampleRate) }
        let duration: Double
        switch style { case "wood": duration = 0.38; case "tink": duration = 0.19; case "bells": duration = 1.6; case "glass": duration = 1.25; case "notes": duration = 0.9; case "pluck": duration = 0.85; case "marimba": duration = 0.62; case "drip": duration = 0.32; default: duration = 0.72 }
        let frequency = 440*pow(2,Double(midi-69)/12)
        var noiseState: UInt32 = 0x41c64e6d
        var previousNoise: Double = 0
        return (0..<Int(duration*sampleRate)).map { i in
            let t = Double(i)/sampleRate, phase = 2*Double.pi*frequency*t
            noiseState ^= noiseState << 13; noiseState ^= noiseState >> 17; noiseState ^= noiseState << 5
            let noise = Double(noiseState)/Double(UInt32.max)*2-1
            let click = noise-previousNoise; previousNoise = noise
            let attack = min(1,t/(style == "wood" || style == "tink" ? 0.0006 : 0.0015))
            let end = min(1,(duration-t)/0.02)
            // Each material has independent, inharmonic resonances and decay times.
            // Unlike a single pitched oscillator, this preserves the struck object's character.
            func mode(_ ratio: Double, _ decay: Double, _ weight: Double, base: Double = 1) -> Double {
                guard frequency*ratio*base < sampleRate*0.45 else { return 0 }
                return weight*sin(phase*ratio*base)*exp(-t*decay)
            }
            let signal: Double
            switch style {
            case "tink":
                signal = mode(1,34,0.85,base:8)+mode(2.76,70,0.24,base:8)+mode(1.003,42,0.16,base:8)
            case "glass":
                let bloom = (1-exp(-t*26))*exp(-t*3)
                signal = mode(1,4.5,0.52,base:2)+mode(1.003,5.5,0.26,base:2)+mode(2.32,11,0.22,base:2)+mode(4.25,22,0.12,base:2)+0.10*sin(phase*4.002)*bloom
            case "bells":
                signal = mode(0.5,2.2,0.28,base:2)+mode(1,2.8,0.49,base:2)+mode(1.183,4.2,0.19,base:2)+mode(1.506,6,0.14,base:2)+mode(2,9,0.14,base:2)+mode(2.514,14,0.09,base:2)+mode(3.01,21,0.06,base:2)
            case "wood":
                signal = mode(1,70,0.80,base:0.5)+mode(2.71,110,0.28,base:0.5)+mode(5.82,170,0.12,base:0.5)+0.16*click*exp(-t*700)+0.008*sin(phase*0.25)*(1-exp(-t*150))*exp(-t*8)
            case "drip":
                // A damped rising bubble chirp, with a smaller follow-up bubble
                // and a quiet reflection, keeps the sound recognisably liquid.
                func bubble(_ time: Double,_ target: Double,_ decay: Double) -> Double {
                    guard time >= 0 else { return 0 }
                    let tau = 0.008
                    let integral = time-0.65*tau*(1-exp(-time/tau))
                    return sin(2*Double.pi*target*integral)*exp(-time*decay)*min(1,time/0.0008)
                }
                signal = 0.82*bubble(t,frequency*8,42)+0.20*bubble(t-0.014,frequency*4,55)+0.07*bubble(t-0.058,frequency*8,30)+0.04*click*exp(-t*400)
            case "pluck": signal = mode(0.5,5,0.75)+mode(0.5015,7,0.22)+mode(1,22,0.20)+mode(1.5,38,0.09)
            case "marimba": signal = mode(0.5,8,0.85)+mode(2,32,0.28)+mode(2.76,52,0.12)+mode(0.25,4,0.06)*(1-exp(-t*60))
            default: signal = (mode(0.5,4,0.68)+mode(0.501,5,0.28)+mode(1,12,0.10))*min(1,t/0.012)
            }
            return Float(signal*attack*end*0.18)
        }
    }
    /// A noise-excited, damped string: a short pick transient followed by harmonics
    /// that darken as they decay, distinct from the rounded Soft Keys oscillators.
    private static func pluckedString(midi: Int,sampleRate: Double) -> [Float] {
        let frequency = 440*pow(2,Double(midi-69)/12)*0.5
        let length = max(2,Int((sampleRate/frequency-0.5).rounded()))
        var state: UInt32 = 0x79a31f05
        var ring = (0..<length).map { _ -> Double in
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return Double(state)/Double(UInt32.max)*2-1
        }
        let mean = ring.reduce(0,+)/Double(length)
        for i in ring.indices { ring[i] -= mean }
        let peak = ring.reduce(0) { max($0,abs($1)) }
        for i in ring.indices { ring[i] /= max(1,peak) }
        let duration = 0.85, count = Int(duration*sampleRate)
        var position = 0
        return (0..<count).map { index in
            let current = ring[position], next = ring[(position+1)%length]
            ring[position] = (current+next)*0.5*0.997
            position = (position+1)%length
            let time = Double(index)/sampleRate
            let envelope = min(1,time/0.0008)*min(1,(duration-time)/0.02)*exp(-time*2.8)
            return Float(current*envelope*0.18)
        }
    }
    /// Inspect metadata without decoding the whole recording during configuration validation.
    static func audioFile(_ path: String) throws -> AVAudioFile {
        do {
            let url = URL(fileURLWithPath:path)
            let size = (try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
            guard size <= 32*1024*1024 else { throw Configuration.invalid("Keyboard sound files must be 32 MB or smaller.") }
            let file = try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
            let rate = file.processingFormat.sampleRate
            guard rate >= 8000,rate <= 384000,file.processingFormat.channelCount <= 8,file.length > 0,Double(file.length)/rate <= 10 else { throw Configuration.invalid("Use a non-empty audio clip up to 10 seconds long, with at most eight channels.") }
            return file
        } catch { throw Configuration.invalid("Cannot use keyboard sound ‘\(URL(fileURLWithPath:path).lastPathComponent)’: \(error.localizedDescription)") }
    }
    static func resample(_ source: [Float], rate: Double) -> [Float] {
        guard !source.isEmpty else { return [] }
        return (0..<max(1,Int(Double(source.count)/rate))).map { index in
            let position = min(Double(source.count-1),Double(index)*rate), lo = Int(position), hi = min(source.count-1,lo+1)
            return source[lo]+(source[hi]-source[lo])*Float(position-Double(lo))
        }
    }
    private func customSamples(_ path: String, midi: Int, musical: Bool) throws -> (String,[Float]) {
        let url = URL(fileURLWithPath:path), values = try url.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
        let stamp = "\(path):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.fileSize ?? 0)"
        if sourceCache[stamp] == nil {
            let file = try Self.audioFile(path)
            guard let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else { throw Configuration.invalid("Cannot allocate sound buffer.") }
            try file.read(into:buffer)
            let count = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
            guard let data = buffer.floatChannelData else { throw Configuration.invalid("Cannot decode this audio format.") }
            var mono = (0..<count).map { i in (0..<channels).reduce(Float(0)) { $0+data[$1][i] }/Float(channels) }
            mono = Self.resample(mono,rate:buffer.format.sampleRate/44100)
            for i in mono.indices where !mono[i].isFinite { mono[i] = 0 }
            let peak = mono.reduce(Float(0)) { max($0,abs($1)) }, gain = peak > 0.25 ? 0.25/peak : 1
            for i in mono.indices { mono[i] *= gain*Float(min(1,Double(i)/88))*Float(min(1,Double(mono.count-1-i)/441)) }
            if sourceCache.count >= 16 { sourceCache.removeAll() }
            sourceCache[stamp] = mono
        }
        let pitch = musical ? midi : 60, key = "custom:\(stamp):\(pitch)"
        if cache[key] != nil { return (key,[]) }
        return (key,Self.resample(sourceCache[stamp]!,rate:pow(2,Double(pitch-60)/12)))
    }
    private func buffer(_ config: Configuration.KeyboardSound, midi: Int, preview: Bool) throws -> AVAudioPCMBuffer {
        let key: String, samples: [Float]
        if config.style == "custom" {
            guard !config.files.isEmpty else { throw Configuration.invalid("Choose a custom sound file.") }
            let index = preview ? previewCustomIndex : customIndex
            if preview { previewCustomIndex = (index+1) % config.files.count } else { customIndex = (index+1) % config.files.count }
            let path = config.files[index % config.files.count]; lastCustomFile = path
            (key,samples) = try customSamples(path,midi:midi,musical:config.musical)
        } else {
            lastCustomFile = nil
            key = "\(config.style):\(midi)"
            samples = cache[key] == nil ? Self.samples(style:config.style,midi:midi) : []
        }
        if let buffer = cache[key] { return buffer }
        guard let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)) else { throw Configuration.invalid("Cannot allocate sound buffer.") }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from:$0.baseAddress!,count:$0.count) }
        if cacheOrder.count >= 32 { cache.removeValue(forKey:cacheOrder.removeFirst()) }
        cacheOrder.append(key); cache[key] = buffer
        return buffer
    }
    func update(_ config: Configuration.KeyboardSound,enforceEnabledState: Bool = true) {
        if enforceEnabledState {
            if typingEnabled && !config.enabled { stop() }
            typingEnabled = config.enabled
        }
        if previewTimer?.isValid == true { auditionConfiguration = config }
        engine.mainMixerNode.outputVolume = Float(config.volume)
        reverbUnit.wetDryMix = Float(config.reverb*100)
    }
    private func prepare(_ config: Configuration.KeyboardSound,startEngine: Bool = true) throws {
        if voices.isEmpty {
            let stereo = AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)!
            engine.attach(voiceMixer); engine.attach(reverbUnit)
            reverbUnit.loadFactoryPreset(.mediumHall)
            engine.connect(voiceMixer,to:reverbUnit,format:stereo)
            engine.connect(reverbUnit,to:engine.mainMixerNode,format:stereo)
            for _ in 0..<8 {
                let node = AVAudioPlayerNode(); engine.attach(node)
                engine.connect(node,to:voiceMixer,format:format); voices.append(node)
            }
        }
        update(config,enforceEnabledState:false)
        if startEngine && !engine.isRunning { engine.prepare(); try engine.start() }
    }
    @discardableResult func play(_ config: Configuration.KeyboardSound, preview: Bool = false) -> Bool {
        guard (config.enabled || preview), config.volume > 0 else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        guard preview || now-lastTime >= 0.025 else { return false }
        let midi = preview ? previewSequence.next(config) : sequence.next(config)
        let buffer: AVAudioPCMBuffer
        do { buffer = try self.buffer(config,midi:midi,preview:preview); try prepare(config) }
        catch { lastError = error.localizedDescription; return false }
        let node = voices[voice]; voice = (voice+1)%voices.count
        node.stop(); node.volume = 1; node.scheduleBuffer(buffer)
        node.play(); lastTime = now; lastMIDI = midi; lastFrameCount = Int(buffer.frameLength); scheduledCount += 1; lastError = nil
        return true
    }
    func audition(_ config: Configuration.KeyboardSound) {
        stopAudition(); auditionConfiguration = config; previewSequence = KeyboardNoteSequence(); if config.musical { previewCustomIndex = 0 }
        guard play(config,preview:true) else { return }
        guard config.musical else { return }
        var remaining = 7
        previewTimer = Timer.scheduledTimer(withTimeInterval:0.16,repeats:true) { [weak self] timer in
            guard let self,remaining > 0,let config = self.auditionConfiguration else { timer.invalidate(); return }
            _ = self.play(config,preview:true); remaining -= 1
        }
    }
    /// Offline rendering of this same graph verifies gain changes on an existing
    /// sound and its reverb tail, without sending test audio to the speakers.
    func renderForValidation(_ config: Configuration.KeyboardSound,frames: Int,volumeChange: (frame:Int,value:Double)? = nil) throws -> [Float] {
        try prepare(config,startEngine:false)
        let stereo = AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)!
        try engine.enableManualRenderingMode(.offline,format:stereo,maximumFrameCount:1024)
        try engine.start(); defer { stop(); engine.disableManualRenderingMode() }
        _ = play(config,preview:true)
        let buffer = AVAudioPCMBuffer(pcmFormat:stereo,frameCapacity:1024)!
        var output: [Float] = [], changed = false, retries = 0
        while output.count < frames {
            if let volumeChange,!changed,output.count >= volumeChange.frame {
                var adjusted = config; adjusted.volume = volumeChange.value; update(adjusted,enforceEnabledState:false); changed = true
            }
            let count = AVAudioFrameCount(min(1024,frames-output.count))
            let status = try engine.renderOffline(count,to:buffer)
            if status == .success { output.append(contentsOf:UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength))); retries = 0 }
            else { retries += 1; if retries > 100 { throw Configuration.invalid("Audio renderer did not produce samples.") } }
        }
        return output
    }
    func stopAudition() { previewTimer?.invalidate(); previewTimer = nil; auditionConfiguration = nil }
    func stop() {
        stopAudition()
        voices.forEach { $0.stop() }; reverbUnit.reset(); engine.pause(); lastTime = 0
        sequence = KeyboardNoteSequence(); previewSequence = KeyboardNoteSequence(); customIndex = 0; previewCustomIndex = 0
    }
}

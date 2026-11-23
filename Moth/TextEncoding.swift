// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import AppKit
import Darwin
import CoreFoundation

struct TerminalTextEncoding {
    let id: String
    let title: String
    static let choices: [TerminalTextEncoding] = [
        .init(id:"UTF-8",title:"Unicode · UTF-8"),
        .init(id:"ASCII",title:"ASCII"),
        .init(id:"ISO-8859-1",title:"Western · ISO 8859-1"),
        .init(id:"ISO-8859-15",title:"Western · ISO 8859-15"),
        .init(id:"WINDOWS-1252",title:"Western · Windows 1252"),
        .init(id:"MACINTOSH",title:"Western · Mac OS Roman"),
        .init(id:"ISO-8859-2",title:"Central European · ISO 8859-2"),
        .init(id:"WINDOWS-1250",title:"Central European · Windows 1250"),
        .init(id:"ISO-8859-7",title:"Greek · ISO 8859-7"),
        .init(id:"ISO-8859-9",title:"Turkish · ISO 8859-9"),
        .init(id:"KOI8-R",title:"Cyrillic · KOI8-R"),
        .init(id:"WINDOWS-1251",title:"Cyrillic · Windows 1251"),
        .init(id:"SHIFT_JIS",title:"Japanese · Shift JIS"),
        .init(id:"EUC-JP",title:"Japanese · EUC-JP"),
        .init(id:"GB18030",title:"Simplified Chinese · GB18030"),
        .init(id:"BIG5",title:"Traditional Chinese · Big5"),
        .init(id:"EUC-KR",title:"Korean · EUC-KR")
    ].filter { $0.id == "UTF-8" || moth_codec_supported($0.id) != 0 }
    static func title(_ id: String) -> String { choices.first { $0.id == id }?.title ?? id }
    static func available(_ config: Configuration) -> [TerminalTextEncoding] {
        choices.filter { config.enabledEncodings.contains($0.id) || $0.id == config.textEncoding }
    }
}

/// The emulator always receives UTF-8. iconv retains incomplete legacy characters
/// across PTY reads; protocol replies and raw mouse reports bypass input conversion.
final class TerminalTranscoder {
    let id: String
    private var decoder: OpaquePointer?
    private var gbPending: [UInt8] = []
    private static let gbEncoding = String.Encoding(rawValue:CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding("GB18030" as CFString)))
    init(_ id: String) { self.id = id; if id != "UTF-8" && id != "GB18030" { decoder = moth_codec_create(id,"UTF-8",1) } }
    deinit { moth_codec_destroy(decoder) }
    private static func convert(_ bytes: ArraySlice<UInt8>,with codec: OpaquePointer,final: Bool) -> [UInt8]? {
        var output: UnsafeMutablePointer<UInt8>?, length = 0
        let status = bytes.withUnsafeBufferPointer { moth_codec_convert(codec,$0.baseAddress,$0.count,final ? 1 : 0,&output,&length) }
        defer { free(output) }
        guard status == 0 else { return nil }
        return output.map { Array(UnsafeBufferPointer(start:$0,count:length)) } ?? []
    }
    func decode(_ bytes: ArraySlice<UInt8>,final: Bool = false) -> [UInt8] {
        if id == "GB18030" { return decodeGB18030(bytes,final:final) }
        guard let decoder else { return Array(bytes) }
        return Self.convert(bytes,with:decoder,final:final) ?? Array("�".utf8)
    }
    // macOS iconv omits some GB18030 four-byte mappings. Core Foundation's
    // complete mapping is used at character boundaries, with an incremental prefix buffer.
    private func decodeGB18030(_ bytes: ArraySlice<UInt8>,final: Bool) -> [UInt8] {
        let input = gbPending+bytes; gbPending = []
        var output: [UInt8] = [], index = 0
        let replacement = Array("�".utf8)
        while index < input.count {
            let first = input[index]
            if first < 0x80 { output.append(first); index += 1; continue }
            guard (0x81...0xfe).contains(first) else { output += replacement; index += 1; continue }
            var length = 2
            if index+1 < input.count {
                let second = input[index+1]
                if (0x30...0x39).contains(second) {
                    length = 4
                    if index+2 < input.count && !(0x81...0xfe).contains(input[index+2]) { output += replacement; index += 1; continue }
                    if index+3 < input.count && !(0x30...0x39).contains(input[index+3]) { output += replacement; index += 1; continue }
                } else if second < 0x40 || second == 0x7f || second > 0xfe { output += replacement; index += 1; continue }
            }
            if index+length > input.count {
                if final { output += replacement } else { gbPending = Array(input[index...]) }; break
            }
            if let text = String(bytes:input[index..<index+length],encoding:Self.gbEncoding) { output += text.utf8 }
            else { output += replacement }
            index += length
        }
        return output
    }
    func encode(_ bytes: ArraySlice<UInt8>) -> [UInt8]? {
        guard id != "UTF-8",bytes.contains(where: { $0 >= 128 }) else { return Array(bytes) }
        if id == "GB18030" { return String(bytes:bytes,encoding:.utf8)?.data(using:Self.gbEncoding,allowLossyConversion:false).map { Array($0) } }
        guard let encoder = moth_codec_create("UTF-8",id,0) else { return nil }; defer { moth_codec_destroy(encoder) }
        return Self.convert(bytes,with:encoder,final:true)
    }
}

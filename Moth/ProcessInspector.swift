// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

import Foundation
import Darwin

struct RunningProgram: Equatable {
    let pid: pid_t
    let path: String
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct CloseAssessment {
    var programs: [RunningProgram] = []
    var uncertain = false
    func requiringConfirmation(_ policy: Configuration.CloseConfirmation) -> [String] {
        guard policy.enabled else { return [] }
        var names = programs.filter { program in
            !policy.ignorePrograms.contains { item in item.hasPrefix("/") ? item == program.path : item == program.name }
        }.map(\.name)
        if uncertain { names.append("an unidentified running process") }
        return Array(Set(names)).sorted()
    }
}

enum ProcessInspector {
    /// Read the local shell's actual cwd. OSC 7 may describe a remote host or be stale.
    static func workingDirectory(of pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid,PROC_PIDVNODEPATHINFO,0,&info,size) == size else { return nil }
        let path = withUnsafeBytes(of:&info.pvi_cdir.vip_path) { bytes -> String? in
            guard let end = bytes.firstIndex(of:0) else { return nil }
            return String(bytes:bytes.prefix(end),encoding:.utf8)
        }
        return usableDirectory(path)
    }
    static func usableDirectory(_ path: String?) -> String? {
        guard let path,path.hasPrefix("/") else { return nil }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath:path,isDirectory:&directory),directory.boolValue,access(path,X_OK) == 0 else { return nil }
        return path
    }

    /// Inspect the shell and all descendants, including jobs in other foreground groups.
    static func assess(shellPID: pid_t, foregroundGroup: pid_t = -1) -> CloseAssessment {
        var result = CloseAssessment(), seen = Set<pid_t>(), pending = [shellPID]
        // A foreground process can be reparented; include it even if it left the shell tree.
        if foregroundGroup > 0 && foregroundGroup != shellPID { pending.append(foregroundGroup) }
        while let pid = pending.popLast() {
            guard pid > 0, seen.insert(pid).inserted else { continue }
            guard seen.count <= 512 else { result.uncertain = true; break }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
                if kill(pid, 0) == 0 || errno != ESRCH { result.uncertain = true }
                continue
            }
            if info.pbi_status == SZOMB { continue }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            if length > 0 { result.programs.append(RunningProgram(pid: pid, path: String(cString: path))) }
            else { result.uncertain = true }
            let requested = proc_listchildpids(pid, nil, 0)
            if requested < 0 { result.uncertain = true; continue }
            let capacity = max(32, min(1024, Int(requested) + 16))
            var children = [pid_t](repeating: 0, count: capacity)
            let count = children.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
            guard count >= 0 else { result.uncertain = true; continue }
            if Int(count) >= capacity { result.uncertain = true }
            pending.append(contentsOf: children.prefix(Int(count)).filter { $0 > 0 })
        }
        return result
    }
}

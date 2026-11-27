// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: GPL-3.0-or-later
// Licensed under GNU GPL version 3 or later. See LICENSE.

import AppKit
import CoreFoundation

enum MothBuild {
    struct Identity: Decodable { let commit:String; let shortCommit:String; let dirty:Bool }
    static let identity:Identity? = {
        guard let url=Bundle.main.url(forResource:"BuildIdentity",withExtension:"json"),let data=try? Data(contentsOf:url) else { return nil }
        return try? JSONDecoder().decode(Identity.self,from:data)
    }()
    static var identifier:String {
        guard let identity else { return "unknown" }
        return identity.shortCommit+(identity.dirty ? "-dirty":"")
    }
}

/// The public release feed contains version metadata and an HTTPS download link only.
struct MothVersion: Comparable {
    let numbers: [Int]
    let prerelease: [String]
    init?(_ string: String) {
        guard !string.isEmpty,string.count<=128 else { return nil }
        let baseAndMetadata=string.split(separator:"+",maxSplits:1,omittingEmptySubsequences:false)
        let parts=baseAndMetadata[0].split(separator:"-",maxSplits:1,omittingEmptySubsequences:false)
        let values=parts[0].split(separator:".",omittingEmptySubsequences:false)
        let parsed=values.compactMap { Int($0) }
        guard (1...3).contains(values.count),values.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),parsed.count==values.count else { return nil }
        func validIdentifiers(_ value: Substring)->Bool {
            !value.isEmpty && value.split(separator:".",omittingEmptySubsequences:false).allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0=="-") } }
        }
        if baseAndMetadata.count==2,!validIdentifiers(baseAndMetadata[1]) { return nil }
        if parts.count==2 {
            guard validIdentifiers(parts[1]) else { return nil }
            for identifier in parts[1].split(separator:".") where identifier.allSatisfy({ $0.isNumber }) {
                if identifier.count>1,identifier.first=="0" { return nil }
            }
        }
        numbers=parsed+Array(repeating:0,count:3-parsed.count)
        prerelease=parts.count==2 ? parts[1].split(separator:".").map(String.init):[]
    }
    static func <(lhs: Self,rhs: Self)->Bool {
        for (a,b) in zip(lhs.numbers,rhs.numbers) where a != b { return a<b }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (a,b) in zip(lhs.prerelease,rhs.prerelease) where a != b {
            let numericA=a.allSatisfy { $0.isNumber },numericB=b.allSatisfy { $0.isNumber }
            if numericA && numericB { return a.count==b.count ? a<b:a.count<b.count }
            if numericA { return true }
            if numericB { return false }
            return a<b
        }
        return lhs.prerelease.count<rhs.prerelease.count
    }
}

struct MothRelease: Equatable {
    let version: String
    let build: Int?
    let download: URL
    let minimumSystemVersion: String?
    var commit:String? = nil
}

enum UpdateOutcome: Equatable {
    case noPublicRelease,upToDate,available(MothRelease),requiresNewerSystem(MothRelease)
}

enum MothUpdateError: LocalizedError {
    case invalidRelease,serviceUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidRelease:return "The update service returned an unreadable release. Please try again later."
        case .serviceUnavailable:return "The update service is unavailable. Please try again later."
        }
    }
}

final class UpdateChecker {
    typealias Loader = (URLRequest,@escaping (Result<Data,Error>)->Void)->Void
    static let endpoint=URL(string:"https://getmoth.dev/api/mac-release")!
    private let loader: Loader
    private let currentVersion: String
    private let currentBuild: Int
    private let systemVersion: OperatingSystemVersion
    var onStateChange: (()->Void)?
    var presenter: ((Result<UpdateOutcome,Error>)->Void)?
    private(set) var isChecking=false
    private(set) var status=""
    private var manualRequested=false
    init(version: String=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.0.0",build: Int=Int(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "0") ?? 0,systemVersion: OperatingSystemVersion=ProcessInfo.processInfo.operatingSystemVersion,loader: @escaping Loader=UpdateChecker.load) {
        currentVersion=version;currentBuild=build;self.systemVersion=systemVersion;self.loader=loader
    }
    static func evaluate(_ data: Data,currentVersion: String,currentBuild: Int,systemVersion: OperatingSystemVersion)->UpdateOutcome? {
        guard data.count<=65536,let raw=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return nil }
        if raw.isEmpty { return .noPublicRelease }
        guard let version=raw["version"] as? String,let latest=MothVersion(version),let current=MothVersion(currentVersion),let address=raw["diskImage"] as? String,let url=URL(string:address),url.scheme=="https",url.host?.lowercased()=="getmoth.dev",url.user==nil,url.password==nil,url.port==nil || url.port==443 else { return nil }
        var build: Int?
        if let value=raw["build"] {
            if let string=value as? String { build=Int(string) }
            else if let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),number.doubleValue.rounded()==number.doubleValue,Double(number.int64Value)==number.doubleValue { build=Int(exactly:number.int64Value) }
            guard let parsed=build,parsed>=0 else { return nil }
        }
        let minimum=raw["minimumSystemVersion"] as? String
        if raw["minimumSystemVersion"] != nil,minimum==nil { return nil }
        var commit:String?
        if let value=raw["commit"] {
            guard let hash=value as? String,(7...64).contains(hash.count),hash.allSatisfy({$0.isASCII && $0.isHexDigit}) else { return nil }
            commit=hash.lowercased()
        }
        var release=MothRelease(version:version,build:build,download:url,minimumSystemVersion:minimum)
        release.commit=commit
        guard latest>current || (latest==current && (build ?? currentBuild)>currentBuild) else { return .upToDate }
        if let minimum {
            guard let required=MothVersion(minimum),required.prerelease.isEmpty else { return nil }
            let system=MothVersion("\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)")!
            if system<required { return .requiresNewerSystem(release) }
        }
        return .available(release)
    }
    func check(manual: Bool) {
        manualRequested = manualRequested || manual
        guard !isChecking else { return }
        isChecking=true;status="Checking for updates…";onStateChange?()
        var request=URLRequest(url:Self.endpoint,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:12)
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.setValue("Moth/"+currentVersion,forHTTPHeaderField:"User-Agent")
        loader(request) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let outcome=result.flatMap { data -> Result<UpdateOutcome,Error> in
                    guard let value=Self.evaluate(data,currentVersion:self.currentVersion,currentBuild:self.currentBuild,systemVersion:self.systemVersion) else { return .failure(MothUpdateError.invalidRelease) }
                    return .success(value)
                }
                self.isChecking=false
                switch outcome {
                case .success(.noPublicRelease):self.status="No public release is available yet."
                case .success(.upToDate):self.status="Moth is up to date."
                case .success(.available(let release)):self.status="Moth \(release.version) is available."
                case .success(.requiresNewerSystem(let release)):self.status="Moth \(release.version) requires macOS \(release.minimumSystemVersion ?? "a newer version")."
                case .failure:self.status="Couldn’t check for updates."
                }
                let announce: Bool
                if case .success(.available)=outcome { announce=true } else { announce=self.manualRequested }
                self.manualRequested=false;self.onStateChange?()
                if announce { if let presenter=self.presenter { presenter(outcome) } else { self.present(outcome) } }
            }
        }
    }
    private static func load(_ request: URLRequest,completion: @escaping (Result<Data,Error>)->Void) {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage=nil;configuration.urlCache=nil
        configuration.timeoutIntervalForRequest=12;configuration.timeoutIntervalForResource=15
        configuration.waitsForConnectivity=false
        let session=URLSession(configuration:configuration)
        session.dataTask(with:request) { data,response,error in
            defer { session.finishTasksAndInvalidate() }
            if let error { completion(.failure(error));return }
            guard let response=response as? HTTPURLResponse,response.statusCode==200,response.url?.scheme=="https",response.url?.host==Self.endpoint.host,let data else { completion(.failure(MothUpdateError.serviceUnavailable));return }
            completion(.success(data))
        }.resume()
    }
    private func present(_ result: Result<UpdateOutcome,Error>) {
        let alert=NSAlert();alert.alertStyle = .informational
        var download: URL?
        switch result {
        case .success(.available(let release)):
            alert.messageText="A new version of Moth is available"
            alert.informativeText="Moth \(release.version)\(release.commit.map { " (\($0))" } ?? "") is available. You’re using \(currentVersion) (\(MothBuild.identifier))."
            alert.addButton(withTitle:"Download Update");alert.addButton(withTitle:"Not Now");download=release.download
        case .success(.requiresNewerSystem(let release)):
            alert.messageText="This update requires a newer macOS version"
            alert.informativeText="Moth \(release.version) requires macOS \(release.minimumSystemVersion ?? "a newer version"). Your installed copy can continue to be used."
            alert.addButton(withTitle:"OK")
        case .success(.upToDate):
            alert.messageText="Moth is up to date";alert.informativeText="You’re using Moth \(currentVersion) (\(MothBuild.identifier)).";alert.addButton(withTitle:"OK")
        case .success(.noPublicRelease):
            alert.messageText="No public release is available yet";alert.informativeText="Downloads will be available at getmoth.dev.";alert.addButton(withTitle:"OK")
        case .failure(let error):
            alert.alertStyle = .warning;alert.messageText="Couldn’t check for updates"
            alert.informativeText=(error is URLError) ? "Check your internet connection and try again.":error.localizedDescription
            alert.addButton(withTitle:"OK")
        }
        let finish: (NSApplication.ModalResponse)->Void = { response in if response == .alertFirstButtonReturn,let download { NSWorkspace.shared.open(download) } }
        if let window=NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.attachedSheet==nil }) { alert.beginSheetModal(for:window,completionHandler:finish) }
        else { finish(alert.runModal()) }
    }
}

extension App {
    @objc func checkForUpdates(_ sender: Any?) { updateChecker.check(manual:true) }
}

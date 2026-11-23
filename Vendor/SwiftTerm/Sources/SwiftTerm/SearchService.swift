import Foundation

/// Buffer coordinates use stable scrollback rows; the end column is exclusive.
public struct TerminalSearchMatch: Equatable {
    public let startRow: Int
    public let startColumn: Int
    public let endRow: Int
    public let endColumn: Int
}

public struct TerminalSearchResults {
    public let matches: [TerminalSearchMatch]
    public let truncated: Bool
    public let error: String?
    public init(matches: [TerminalSearchMatch],truncated: Bool,error: String? = nil) { self.matches = matches; self.truncated = truncated; self.error = error }
}

// Kept for the view's existing invalidation hooks. Searches take a fresh snapshot.
class SearchService {
    init(terminal: Terminal) {}
    func invalidate() {}
}

extension Terminal {
    /// Literal search of the displayed buffer, including scrollback and soft wraps.
    /// Call on the same queue as terminal input. Results are capped to bound memory.
    public func find(_ query: String, caseSensitive: Bool = false, limit: Int = 10000, regularExpression: Bool = false) -> TerminalSearchResults {
        guard !query.isEmpty, limit > 0 else { return TerminalSearchResults(matches: [], truncated: false) }
        let expression: NSRegularExpression?
        do { expression = regularExpression ? try NSRegularExpression(pattern:query,options:caseSensitive ? [] : [.caseInsensitive]) : nil }
        catch { return TerminalSearchResults(matches:[],truncated:false,error:error.localizedDescription) }
        let deadline = ProcessInfo.processInfo.systemUptime+0.15
        let buffer = displayBuffer
        var results: [TerminalSearchMatch] = []
        var text = "", starts: [(Int, Int)] = [], ends: [(Int, Int)] = []
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        func finishLine() -> Bool {
            let string = text as NSString
            if let expression {
                var complete = true
                expression.enumerateMatches(in:text,options:[.reportProgress],range:NSRange(location:0,length:string.length)) { match,_,stop in
                    if ProcessInfo.processInfo.systemUptime > deadline { complete = false; stop.pointee = true; return }
                    guard let range = match?.range,range.length > 0,range.location+range.length <= starts.count else { return }
                    if results.count >= limit { complete = false; stop.pointee = true; return }
                    let first = starts[range.location],last = ends[range.location+range.length-1]
                    results.append(TerminalSearchMatch(startRow:first.0,startColumn:first.1,endRow:last.0,endColumn:last.1))
                }
                if !complete { return false }
            } else {
                var offset = 0
                while offset < string.length {
                    let range = string.range(of:query,options:options,range:NSRange(location:offset,length:string.length-offset))
                    guard range.location != NSNotFound,range.length > 0 else { break }
                    if results.count >= limit { return false }
                    let first = starts[range.location],last = ends[range.location+range.length-1]
                    results.append(TerminalSearchMatch(startRow:first.0,startColumn:first.1,endRow:last.0,endColumn:last.1))
                    offset = range.location+range.length
                }
            }
            text.removeAll(keepingCapacity: true); starts.removeAll(keepingCapacity: true); ends.removeAll(keepingCapacity: true)
            return true
        }
        for row in 0..<buffer.lines.count {
            let line = buffer.lines[row]
            if !line.isWrapped && !text.isEmpty { if !finishLine() { return TerminalSearchResults(matches: results, truncated: true) } }
            let wrapsNext = row+1 < buffer.lines.count && buffer.lines[row+1].isWrapped
            let length = min(cols, wrapsNext ? buffer.getWrappedLineTrimmedLength(buffer.lines, row, cols) : line.getTrimmedLength())
            for col in 0..<length {
                let cell = line[col]
                if cell.width == 0 { continue } // continuation cell of a wide grapheme
                let character = getCharacter(for: cell)
                let value = character == "\0" ? " " : String(character)
                text += value
                for _ in 0..<value.utf16.count {
                    starts.append((row+buffer.linesTop, col))
                    ends.append((row+buffer.linesTop, min(cols, col+max(1, Int(cell.width)))))
                }
            }
        }
        let complete = finishLine()
        return TerminalSearchResults(matches: results, truncated: !complete)
    }
}

extension Terminal {
    /// Plain text of the visible buffer and retained history; soft wraps stay joined.
    public func exportPlainText() -> String {
        let buffer = displayBuffer
        var output = ""
        for row in 0..<buffer.lines.count {
            output += buffer.lines[row].translateToString(trimRight:true)
            if row+1 >= buffer.lines.count || !buffer.lines[row+1].isWrapped { output += "\n" }
        }
        while output.hasSuffix("\n\n") { output.removeLast() }
        return output
    }
}

#if os(macOS)
private enum TerminalLinkPatterns {
    static let detector = try? NSDataDetector(types:NSTextCheckingResult.CheckingType.link.rawValue)
    static let scheme = try! NSRegularExpression(pattern:"(?:[A-Za-z][A-Za-z0-9+.-]*://|mailto:)[^\\s<>\\\"'\\x{00}-\\x{1f}]+")
}
extension Terminal {
    /// A URL under a buffer cell, including wraps repainted as separate full-width rows.
    public func detectedLink(column: Int,bufferRow row: Int) -> String? { detectedLinkMatch(column:column,bufferRow:row)?.link }
    public func detectedLinkMatch(column: Int,bufferRow row: Int) -> (link:String,range:TerminalSearchMatch)? {
        let buffer = displayBuffer
        guard row >= 0,row < buffer.lines.count,column >= 0,column < cols else { return nil }
        // Full-screen clients can repaint a wrapped URL with cursor positioning or
        // CR/LF, losing isWrapped. Join only when text reaches the right edge and
        // the next row starts with a URL character. Short rows remain hard breaks.
        func joinsPrevious(_ y: Int) -> Bool {
            guard y > 0,y < buffer.lines.count else { return false }
            if buffer.lines[y].isWrapped { return true }
            let previous = buffer.lines[y-1],next = buffer.lines[y]
            guard previous.getTrimmedLength() == cols else { return false }
            func urlCharacter(_ cell: CharData) -> Bool {
                let c = getCharacter(for:cell)
                return c != "\0" && !c.isWhitespace && !"<>\"'".contains(c) && !c.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains)
            }
            return urlCharacter(previous[cols-1]) && urlCharacter(next[0])
        }
        var first = row,last = row
        while first > 0,joinsPrevious(first),row-first < 64 { first -= 1 }
        while last+1 < buffer.lines.count,joinsPrevious(last+1),last-first < 64 { last += 1 }
        guard !joinsPrevious(first),!joinsPrevious(last+1) else { return nil }
        var text = "",offset: Int?,utf16Length = 0
        var cells: [(offset:Int,start:Position,end:Position)] = []
        for y in first...last {
            let line = buffer.lines[y],wraps = y+1 < buffer.lines.count && buffer.lines[y+1].isWrapped
            let count = min(cols,wraps ? buffer.getWrappedLineTrimmedLength(buffer.lines,y,cols) : line.getTrimmedLength())
            for x in 0..<count {
                let cell = line[x]; if cell.width == 0 { continue }
                if y == row,column >= x,column < x+max(1,Int(cell.width)) { offset = utf16Length }
                let character = getCharacter(for:cell),value = character == "\0" ? " " : String(character)
                cells.append((utf16Length,Position(col:x,row:y),Position(col:x+max(1,Int(cell.width)),row:y)))
                text += value; utf16Length += value.utf16.count
                if utf16Length > 16384 { return nil }
            }
        }
        guard let offset else { return nil }
        let string = text as NSString,range = NSRange(location:0,length:string.length)
        func contains(_ range: NSRange) -> Bool { offset >= range.location && offset < NSMaxRange(range) }
        func result(_ link: String,_ span: NSRange) -> (link:String,range:TerminalSearchMatch)? {
            guard contains(span),let first = cells.first(where: { $0.offset >= span.location }),let last = cells.last(where: { $0.offset < NSMaxRange(span) }) else { return nil }
            return (link,TerminalSearchMatch(startRow:first.start.row,startColumn:first.start.col,endRow:last.end.row,endColumn:last.end.col))
        }
        if let match = TerminalLinkPatterns.detector?.matches(in:text,range:range).first(where: { contains($0.range) }),let url = match.url { return result(url.absoluteString,match.range) }
        if let match = TerminalLinkPatterns.scheme.matches(in:text,range:range).first(where: { contains($0.range) }) {
            var candidate = string.substring(with:match.range)
            while let last = candidate.last,".,;".contains(last) { candidate.removeLast() }
            for (open,close) in [("(",")"),("[","]"),("{","}")] {
                while candidate.hasSuffix(close),candidate.filter({ String($0)==close }).count > candidate.filter({ String($0)==open }).count { candidate.removeLast() }
            }
            guard let url = URL(string:candidate) else { return nil }
            return result(url.absoluteString,NSRange(location:match.range.location,length:candidate.utf16.count))
        }
        return nil
    }
}
#endif

//
//  SelectionService.swift
//  iOS
//
//  Created by Miguel de Icaza on 3/5/20.
//  Copyright © 2020 Miguel de Icaza. All rights reserved.
//

import Foundation

/**
 * Tracks the selection state in the terminal, the selection is determined by the `active`
 * property, and if that is true, then the `start` and `end` represents offsets within
 * the terminal's buffer.  They are guaranteed to be ordered.
 */
class SelectionService: CustomDebugStringConvertible {
    var terminal: Terminal
    
    public init (terminal: Terminal)
    {
        self.terminal = terminal
        _active = false
        start = Position(col: 0, row: 0)
        end = Position(col: 0, row: 0)
        pivot = Position(col: 0, row: 0)
        hasSelectionRange = false
    }
    
    /**
     * Controls whether the selection is active or not.   Changing the value will invoke the `selectionChanged`
     * method on the terminal's delegate if the state changes.
     */
    var _active: Bool = false
    public var active: Bool {
        get {
            return _active
        }
        set(newValue) {
            if _active != newValue {
                _active = newValue
                terminal.tdel?.selectionChanged (source: terminal)
            }
            if active == false {
                pivot = nil
            }
        }
    }
    
    // This avoids the user visible cache
    func setActiveAndNotify () {
        _active = true
        terminal.tdel?.selectionChanged (source: terminal)
    }

    /**
     * Whether any range is selected
     */
    public private(set) var hasSelectionRange: Bool

    /**
     * Returns the selection starting point in buffer coordinates
     */
    public private(set) var start: Position {
        didSet {
          hasSelectionRange = start != end
        }
    }

    /**
     * Used to track the pivot point when selection in iOS-style selection
     */
    public var pivot: Position? 

    /**
     * Returns the selection ending point in buffer coordinates
     */
    public private(set) var end: Position {
        didSet {
          hasSelectionRange = start != end
        }
    }
    
    /// True if the selection spans more than one line
    public var isMultiLine: Bool {
        return start.row != end.row
    }
    
    /**
     * Starts the selection from the specific screen-relative location
     */
    public func startSelection (row: Int, col: Int)
    {
        setSoftStart(row: row, col: col)
        selectionMode = .character
        setActiveAndNotify()
    }
        
    func clamp (_ buffer: Buffer, _ p: Position) -> Position {
        return Position(col: min (p.col, buffer.cols-1), row: min (p.row, buffer.rows-1))
    }
    /**
     * Sets the selection, this is validated against the
     */
    public func setSelection (start: Position, end: Position) {
        let buffer = terminal.displayBuffer
        let sclamped = clamp (buffer, start)
        let eclamped = clamp (buffer, end)
        
        self.start = sclamped
        self.end = eclamped
        
        setActiveAndNotify()
    }
    
    /**
     * Starts selection, the range is determined by the last start position
     */
    public func startSelection ()
    {
        end = start
        selectingRows = false
        selectionMode = .character
        setActiveAndNotify()
    }
    
    /**
     * Sets the start and end positions but does not start selection
     * this lets us record the last position of mouse clicks so that
     * drag and shift+click operations know from where to start selection
     * from.
     *
     * The location is screen-relative
     */
    public func setSoftStart (row: Int, col: Int) {
        setSoftStart (bufferPosition: Position(col: col, row: row + terminal.displayBuffer.yDisp))
    }
    
    /**
     * Sets the start and end positions but does not start selection
     * this lets us record the last position of mouse clicks so that
     * drag and shift+click operations know from where to start selection
     * from.
     *
     * The locoation is buffer-relative
     */
    public func setSoftStart (bufferPosition: Position) {
        start = bufferPosition
        end = bufferPosition
        setActiveAndNotify()
    }
    
    /**
     * Extends the selection based on the user "shift" clicking. This has
     * slightly different semantics than a "drag" extension because we can
     * shift the start to be the last prior end point if the new extension
     * is before the current start point.
     *
     * The row is screen-relative
     */
    public func shiftExtend (row: Int, col: Int)
    {
        var newPos = Position  (col: col, row: row + terminal.displayBuffer.yDisp)
        if selectingRows {
            if Position.compare(start, newPos) == .before {
                newPos.col = terminal.cols - 1
            } else {
                newPos.col = 0
            }
        }
        print("SelectinRows=\(selectingRows)")
        shiftExtend (bufferPosition: newPos)
    }
    
    /**
     * Extends the selection based on the user "shift" clicking. This has
     * slightly different semantics than a "drag" extension because we can
     * shift the start to be the last prior end point if the new extension
     * is before the current start point.
     *
     * The bufferPosition is buffer-relative
     */
    public func shiftExtend (bufferPosition newEnd: Position) {
        var adjustedNewEnd = newEnd
        
        // If we're in word selection mode, extend to word boundaries
        if selectionMode == .word {
            let direction = Position.compare(newEnd, start) == .before ? -1 : 1
            adjustedNewEnd = extendToWordBoundary(position: newEnd, in: terminal.displayBuffer, direction: direction)
        }
        
        var shouldSwapStart = false
        if Position.compare (start, end) == .before {
            // start is before end, is the new end before Start
            if Position.compare (adjustedNewEnd, start) == .before {
                // yes, swap Start and End
                shouldSwapStart = true
            }
        } else if Position.compare (start, end) == .after {
            if Position.compare (adjustedNewEnd, start) == .after {
                // yes, swap Start and End
                shouldSwapStart = true
            }
        }
        if (shouldSwapStart) {
            start = end
        }
        end = adjustedNewEnd
        
        setActiveAndNotify()
    }
    
    /**
     * Implements the iOS selection around the pivot, that is, the handle that is being dragged
     * becomes the pivot point for start/end
     *
     * The row is screen-relative, for buffer relative use the `pivotExtend(bufferPosition:)` overload
     */
    public func pivotExtend (row: Int, col: Int) {
        let newPoint = Position  (col: col, row: row + terminal.displayBuffer.yDisp)

        return pivotExtend(bufferPosition: newPoint)
    }
    
    /**
     * Implements the iOS selection around the pivot, that is, the handle that is being dragged
     * becomes the pivot point for start/end
     *
     * The position is buffer-relative, for screen relative, use `pivotExtend(row:col:)`
     */
    public func pivotExtend (bufferPosition: Position) {
        guard let pivot = pivot else {
            return
        }
        
        var adjustedPosition = bufferPosition
        
        // If we're in word selection mode, extend to word boundaries
        if selectionMode == .word {
            let direction = Position.compare(bufferPosition, pivot) == .before ? -1 : 1
            adjustedPosition = extendToWordBoundary(position: bufferPosition, in: terminal.displayBuffer, direction: direction)
        }
        
        switch Position.compare (adjustedPosition, pivot) {
        case .after:
            start = pivot
            end = adjustedPosition
        case .before:
            start = adjustedPosition
            end = pivot
        case .equal:
            start = pivot
            end = pivot
        }
        
        setActiveAndNotify()
    }
    
    /**
     * Extends the selection by moving the end point to the new point.
     * The row is in screen coordinates
     */
    public func dragExtend (row: Int, col: Int)
    {
        dragExtend(bufferPosition: Position(col: col, row: row + terminal.displayBuffer.yDisp))
    }
    
    /**
     * Extends the selection by moving the end point to the new point.
     * The position is in buffer coordinates
     */
    public func dragExtend (bufferPosition: Position) {
        var adjustedEnd = bufferPosition
        
        // If we're in word selection mode, extend to word boundaries
        if selectionMode == .word {
            let direction = Position.compare(bufferPosition, start) == .before ? -1 : 1
            adjustedEnd = extendToWordBoundary(position: bufferPosition, in: terminal.displayBuffer, direction: direction)
        }
        
        end = adjustedEnd
        setActiveAndNotify()
    }
    
    /**
     * Selects the entire buffer and triggers the selection
     */
    public func selectAll ()
    {
        start = Position(col: 0, row: 0)
        end = Position(col: terminal.cols-1, row: terminal.displayBuffer.lines.maxLength - 1)
        setActiveAndNotify()
    }
    
    public var selectingRows: Bool = false
    
    /// Tracks the current selection mode to maintain consistency during extension
    public enum SelectionMode {
        case character
        case word
        case row
    }
    
    public var selectionMode: SelectionMode = .character
    
    /**
     * Selectss the specified row and triggers the selection
     */
    public func select(row: Int)
    {
        start = Position(col: 0, row: row)
        end = Position(col: terminal.cols-1, row: row)
        selectingRows = true
        selectionMode = .row
        setActiveAndNotify()
    }

    private func character (at position: Position, in buffer: Buffer) -> Character
    {
        let cell = buffer.getChar (atBufferRelative: position)
        return terminal.getCharacter (for: cell)
    }

    /**
     * Performs a simple "word" selection based on a function that determines inclussion into the group
     */
    func simpleScanSelection (from position: Position, in buffer: Buffer, includeFunc: (Character)-> Bool)
    {
        // Look backward
        var colScan = position.col
        var left = colScan
        while colScan >= 0 {
            let ch = character (at: Position (col: colScan, row: position.row), in: buffer)
            if !includeFunc (ch) {
                break
            }
            left = colScan
            colScan -= 1
        }
        
        // Look forward
        colScan = position.col
        var right = colScan
        let limit = terminal.cols
        while colScan < limit {
            let ch = character (at: Position (col: colScan, row: position.row), in: buffer)
            if !includeFunc (ch) {
                break
            }
            colScan += 1
            right = colScan
        }
        start = Position (col: left, row: position.row)
        end = Position(col: right, row: position.row)
    }
    
    /**
     * Performs a forward search for the `end` character, but this can extend across matching subexpressions
     * made of pais of parenthesis, braces and brackets.
     */
    func balancedSearchForward (from position: Position, in buffer: Buffer)
    {
        var startCol = position.col
        var wait: [Character] = []
        
        start = position
        
        let maxRow = buffer.rows + buffer.yDisp
        if position.row >= maxRow {
            return
        }
        for line in position.row..<maxRow {
            for col in startCol..<terminal.cols {
                let p =  Position(col: col, row: line)
                let ch = character (at: p, in: buffer)
                
                if ch == "(" {
                    wait.append (")")
                } else if ch == "[" {
                    wait.append ("]")
                } else if ch == "{" {
                    wait.append ("}")
                } else if let v = wait.last {
                    if v == ch {
                        wait.removeLast()
                        if wait.count == 0 {
                            end = Position(col: p.col+1, row: p.row)
                            return
                        }
                    }
                }
            }
            startCol = 0
        }
        start = position
        end = position
    }

    /**
     * Performs a forward search for the `end` character, but this can extend across matching subexpressions
     * made of pais of parenthesis, braces and brackets.
     */
    func balancedSearchBackward (from position: Position, in buffer: Buffer)
    {
        var startCol = position.col
        var wait: [Character] = []

        end = position
        
        for line in (0...position.row).reversed() {
            for col in (0...startCol).reversed() {
                let p =  Position(col: col, row: line)
                let ch = character (at: p, in: buffer)
                
                if ch == ")" {
                    wait.append ("(")
                } else if ch == "]" {
                    wait.append ("[")
                } else if ch == "}" {
                    wait.append ("{")
                } else if let v = wait.last {
                    if v == ch {
                        wait.removeLast()
                        if wait.count == 0 {
                            end = Position(col: end.col+1, row: end.row)
                            start = p
                            return
                        }
                    }
                }
            }
            startCol = terminal.cols-1
        }
        start = position
        end = position
    }

    let nullChar = Character(UnicodeScalar(0))
    
    /**
     * Extends a position to the nearest word boundary based on the character at that position
     */
    func extendToWordBoundary(position: Position, in buffer: Buffer, direction: Int) -> Position {
        let ch = character (at: position, in: buffer)
        var includeFunc: (Character) -> Bool
        
        switch ch {
        case Character(UnicodeScalar(0)):
            includeFunc = { ch in ch == Character(UnicodeScalar(0)) }
        case " ":
            includeFunc = { ch in ch == " " }
        case let ch where ch.isLetter || ch.isNumber:
            includeFunc = { ch in ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" }
        default:
            return position
        }
        
        var result = position
        if direction < 0 {
            // Extend backward
            var col = position.col
            while col >= 0 {
                let testCh = character (at: Position(col: col, row: position.row), in: buffer)
                if !includeFunc(testCh) {
                    break
                }
                result.col = col
                col -= 1
            }
        } else {
            // Extend forward
            var col = position.col
            while col < terminal.cols {
                let testCh = character (at: Position(col: col, row: position.row), in: buffer)
                if !includeFunc(testCh) {
                    break
                }
                col += 1
                result.col = col
            }
        }
        
        return result
    }
    /**
     * Implements the behavior to select the word at the specified position or an expression
     * which is a balanced set parenthesis, braces or brackets
     */
    public func selectWordOrExpression (at uncheckedPosition: Position, in buffer: Buffer)
    {
//        let position = Position(
//            col: max (min (uncheckedPosition.col, buffer.cols-1), 0),
//            row: max (min (uncheckedPosition.row, buffer.rows-1+buffer.yDisp), buffer.yDisp))
        let position = Position (col: (min (terminal.cols, max (uncheckedPosition.col, 0))),
                                 row: (max (uncheckedPosition.row, 0)))
        switch character (at: position, in: buffer) {
        case Character(UnicodeScalar(0)):
            simpleScanSelection (from: position, in: buffer) { ch in ch == nullChar }
        case " ":
            // Select all white space
            simpleScanSelection (from: position, in: buffer) { ch in ch == " " }
        case let ch where ch.isLetter || ch.isNumber:
            simpleScanSelection (from: position, in: buffer) { ch in ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" }
        case "{":
            fallthrough
        case "(":
            fallthrough
        case "[":
            balancedSearchForward (from: position, in: buffer)
        case ")":
            fallthrough
        case "]":
            fallthrough
        case "}":
            balancedSearchBackward(from: position, in: buffer)
        default:
            // For other characters, we just stop there
            start = position
            end = position
        }
        selectionMode = .word
        setActiveAndNotify()
    }
    
    /**
     * Clears the selection
     */
    public func selectNone ()
    {
        if active {
            active = false
            selectionMode = .character
        }
    }
    
    public func getSelectedText () -> String {
        let (min, max) = if Position.compare(start, end) == .before {
            (start, end)
        } else {
            (end, start)
        }
        let r = terminal.getDisplayText(start: min, end: max)
        return r
    }
    
    public var debugDescription: String {
        return "[Selection (active=\(active), start=\(start) end=\(end) hasSR=\(hasSelectionRange) pivot=\(pivot?.debugDescription ?? "nil")]"
    }
}

extension SelectionService {
    /// Reflow changes physical row numbers. Anchor to logical lines and character
    /// boundaries instead, so moving a live view never turns a selection into other text.
    struct ReflowAnchor { let lineFromLastContent: Int; let offset: Int }
    struct ResizeState {
        let start: ReflowAnchor?
        let end: ReflowAnchor?
        let viewport: ReflowAnchor?
        let text: String?
        let alternate: Bool
        let rawStart: Position
        let rawEnd: Position
    }
    private func logicalLines() -> (starts:[Int],lastContent:Int) {
        let buffer = terminal.displayBuffer
        var starts = [Int]()
        for row in 0..<buffer.lines.count {
            if row == 0 || !buffer.lines[row].isWrapped { starts.append(row) }
        }
        let lastRow = (0..<buffer.lines.count).reversed().first { buffer.lines[$0].getTrimmedLength() > 0 } ?? 0
        return (starts,starts.lastIndex(where: { $0 <= lastRow }) ?? 0)
    }
    private func rowLength(_ row: Int) -> Int {
        let buffer = terminal.displayBuffer
        return row+1 < buffer.lines.count && buffer.lines[row+1].isWrapped
            ? buffer.getWrappedLineTrimmedLength(buffer.lines,row,terminal.cols) : buffer.lines[row].getTrimmedLength()
    }
    private func anchor(_ position: Position,_ lines: (starts:[Int],lastContent:Int)) -> ReflowAnchor? {
        let buffer = terminal.displayBuffer
        guard !lines.starts.isEmpty,position.row >= 0 else { return nil }
        let row = min(position.row,buffer.lines.count-1)
        let group = lines.starts.lastIndex(where: { $0 <= row })!
        var offset = 0
        for y in lines.starts[group]...row {
            let count = y == row ? min(terminal.cols,max(0,position.col)) : rowLength(y)
            for x in 0..<count where buffer.lines[y][x].width != 0 {
                offset += String(terminal.getCharacter(for:buffer.lines[y][x])).utf16.count
            }
        }
        return ReflowAnchor(lineFromLastContent:group-lines.lastContent,offset:offset)
    }
    private func position(_ anchor: ReflowAnchor,_ lines: (starts:[Int],lastContent:Int)) -> Position? {
        let group = lines.lastContent+anchor.lineFromLastContent,buffer = terminal.displayBuffer
        guard lines.starts.indices.contains(group) else { return nil }
        let first = lines.starts[group],last = group+1 < lines.starts.count ? lines.starts[group+1]-1 : buffer.lines.count-1
        var remaining = anchor.offset
        for y in first...last {
            let count = y == last ? terminal.cols : rowLength(y)
            for x in 0..<count where buffer.lines[y][x].width != 0 {
                if remaining == 0 { return Position(col:x,row:y) }
                remaining -= String(terminal.getCharacter(for:buffer.lines[y][x])).utf16.count
                if remaining < 0 { return nil }
            }
            if remaining == 0 { return Position(col:count,row:y) }
        }
        return nil
    }
    func captureResizeState() -> ResizeState? {
        let buffer = terminal.displayBuffer
        guard active || buffer.yDisp < buffer.yBase else { return nil }
        let alternate = terminal.isCurrentBufferAlternate,lines = logicalLines()
        return ResizeState(start:active ? anchor(start,lines) : nil,end:active ? anchor(end,lines) : nil,
                           viewport:buffer.yDisp < buffer.yBase ? anchor(Position(col:0,row:buffer.yDisp),lines) : nil,
                           text:active ? getSelectedText() : nil,alternate:alternate,rawStart:start,rawEnd:end)
    }
    func restoreResizeState(_ state: ResizeState?) {
        guard let state else { return }
        let buffer = terminal.displayBuffer,lines = logicalLines()
        if let viewport = state.viewport,let location = position(viewport,lines) { buffer.yDisp = min(buffer.yBase,max(0,location.row)) }
        guard let expected = state.text else { return }
        let a = state.alternate ? state.rawStart : state.start.flatMap { position($0,lines) }
        let b = state.alternate ? state.rawEnd : state.end.flatMap { position($0,lines) }
        guard let a,let b,a.row < buffer.lines.count,b.row < buffer.lines.count,a.col <= terminal.cols,b.col <= terminal.cols else { active = false; return }
        start = a; end = b
        // Content may genuinely have fallen out of the bounded scrollback.
        guard getSelectedText() == expected else { active = false; return }
        setActiveAndNotify()
    }
}

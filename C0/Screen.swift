/*
 Copyright 2017 S
 
 This file is part of C0.
 
 C0 is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 C0 is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with C0.  If not, see <http://www.gnu.org/licenses/>.
 */

import Cocoa

final class Screen: NSView, NSTextInputClient, StringViewDelegate {    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private var token: NSObjectProtocol?
    func setup() {
        wantsLayer = true
        if let layer = layer {
            layer.backgroundColor = Defaults.backgroundColor.cgColor
            
            rootView.allViews {
                $0.screen = self
            }
            rootView.layer = layer
            responder = rootView
            descriptionView.delegate = self
            
//            NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: self, queue: nil) { _ in
//                let local = Locale(identifier: Bundle.main.preferredLocalizations[0])
//            }
            token = NotificationCenter.default.addObserver(forName: .NSViewFrameDidChange, object: self, queue: nil) {
                ($0.object as? Screen)?.updateFrame()
            }
        }
    }
    
    deinit {
        if let token = token {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    override func becomeFirstResponder() -> Bool {
        return true
    }
    override func resignFirstResponder() -> Bool {
        return true
    }
    
    override func viewDidChangeBackingProperties() {
        if let backingScaleFactor = window?.backingScaleFactor {
            rootView.allViews {
                $0.contentsScale = backingScaleFactor
            }
        }
    }
    
    func createTrackingArea() {
        let options: NSTrackingAreaOptions = [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self))
    }
    override func updateTrackingAreas() {
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        createTrackingArea()
        super.updateTrackingAreas()
    }
    
    func updateFrame() {
        CATransaction.disableAnimation {
            contentView.frame = bounds
            descriptionView.frame = CGRect(x: 0.0, y: rootView.frame.height - descriptionHeight, width: rootView.frame.width, height: descriptionHeight)
        }
    }
    
    func point(from event: NSEvent) -> CGPoint {
        return convertToLayer(convert(event.locationInWindow, from: nil))
    }
    var currentPoint: CGPoint {
        let windowPoint = window?.mouseLocationOutsideOfEventStream ?? NSPoint()
        return convertToLayer(convert(windowPoint, from: nil))
    }
    func convertFromTopScreen(_ p: NSPoint) -> NSPoint {
        let windowPoint = window?.convertFromScreen(NSRect(origin: p, size: NSSize())).origin ?? NSPoint()
        return convert(windowPoint, from: nil)
    }
    func convertToTopScreen(_ r: CGRect) -> NSRect {
        return window?.convertToScreen(convert(r, to: nil)) ?? NSRect()
    }
    
    var actionNode = ActionNode.default
    
    var rootView = View() {
        didSet {
            oldValue.allViews {
                $0.screen = nil
            }
            rootView.allViews {
                $0.screen = self
            }
            rootView.layer = layer ?? CALayer()
        }
    }
    var rootPanelView = View() {
        didSet {
            rootView.children = [contentView, rootPanelView]
        }
    }
    var contentView = View() {
        didSet {
            rootView.children = [contentView, rootPanelView]
        }
    }
    var descriptionView = StringView(isEnabled: true), descriptionHeight = 30.0.cf
    var responder = View() {
        didSet {
            oldValue.allParents {
                $0.indication = false
            }
            oldValue.mainIndication = false
            
            responder.allParents {
                $0.indication = true
            }
            responder.mainIndication = true
        }
    }
    
    func undo(with undoManager: UndoManager) {
        if undoManager.canUndo {
            undoManager.undo()
        } else {
            tempNotAction()
        }
    }
    func redo(with undoManager: UndoManager) {
        if undoManager.canRedo {
            undoManager.redo()
        } else {
            tempNotAction()
        }
    }
    
    func copy(_ string: String, forType type: String, from view: View) {
        let pasteboard = NSPasteboard.general()
        pasteboard.declareTypes([type], owner: nil)
        pasteboard.setString(string, forType: type)
        view.highlight()
    }
    func copy(_ data: Data, forType type: String, from view: View) {
        let pasteboard = NSPasteboard.general()
        pasteboard.declareTypes([type], owner: nil)
        pasteboard.setData(data, forType: type)
        view.highlight()
    }
    func copyString(forType type: String) -> String? {
        return NSPasteboard.general().string(forType: type)
    }
    func copyData(forType type: String) -> Data? {
        return NSPasteboard.general().data(forType: type)
    }
    
    let minPasteImageWidth = 400.0.cf
    func pasteInRootView() {
        let pasteboard = NSPasteboard.general()
        let urlOptions: [String : Any] = [NSPasteboardURLReadingContentsConformToTypesKey: NSImage.imageTypes()]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: urlOptions) as? [URL], !urls.isEmpty {
            let p = rootView.currentPoint
            for url in urls {
                rootView.addChild(makeImageEditor(url: url, position: p))
            }
        } else {
            tempNotAction()
        }
    }
    private func makeImageEditor(url :URL, position p: CGPoint) -> ImageEditor {
        let imageEditor = ImageEditor()
        imageEditor.image = NSImage(byReferencing: url)
        let size = imageEditor.image.bitmapSize
        let maxWidth = max(size.width, size.height)
        let ratio = minPasteImageWidth < maxWidth ? minPasteImageWidth/maxWidth : 1
        let width = ceil(size.width*ratio), height = ceil(size.height*ratio)
        imageEditor.frame = CGRect(x: round(p.x - width/2), y: round(p.y - height/2), width: width, height: height)
        return imageEditor
    }
    
    func changeString(stringView: StringView, string: String, oldString: String, type: StringView.SendType) {
        if string.isEmpty {
            descriptionView.removeFromParent()
        }
    }
    private var popover = NSPopover()
    func showDescription(_ description: String, from view: View) {
        let vc = NSViewController(), tv = NSTextField(frame: CGRect())
        tv.stringValue = description
        tv.font = Defaults.font
        tv.isBordered = false
        tv.drawsBackground = false
        tv.isEditable = false
        tv.isSelectable = true
        tv.sizeToFit()
        tv.frame.origin = CGPoint(x: 5, y: 5)
        let v = NSView(frame: tv.bounds.inset(by: -5))
        v.addSubview(tv)
        vc.view = v
        popover.close()
        popover = NSPopover()
        popover.animates = false
        popover.contentViewController = vc
        popover.show(relativeTo: view.convert(toScreen: view.bounds), of: self, preferredEdge: .minY)
    }
    
    func errorNotification(_ error: Error) {
        if let window = window {
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }
    func infoNotification(_ string: String) {
        rootView.highlight(color: NSColor.red)
    }
    func noAction() {
        rootView.highlight(color: Defaults.noActionColor)
    }
    func tempNotAction() {
        rootView.highlight(color: Defaults.tempNotActionColor)
    }
    
    func addViewInRootPanel(_ view: View, point: CGPoint, from fromView: View) {
        CATransaction.disableAnimation {
            view.frame.origin = rootView.convert(point, from: fromView)
            rootPanelView.addChild(view)
        }
    }
    
    func moveEventWith(_ sendType: MoveEvent.SendType, _ nsEvent: NSEvent) -> MoveEvent {
        return MoveEvent(sendType: sendType, locationInWindow: nsEvent.locationInWindow, time: nsEvent.timestamp)
    }
    func dragEventWith(_ sendType: DragEvent.SendType, _ nsEvent: NSEvent) -> DragEvent {
        return DragEvent(sendType: sendType, locationInWindow: nsEvent.locationInWindow, time: nsEvent.timestamp, pressure: nsEvent.pressure.cf)
    }
    func scrollEventWith(_ sendType: ScrollEvent.SendType, _ nsEvent: NSEvent) -> ScrollEvent {
        return ScrollEvent(sendType: sendType, locationInWindow: nsEvent.locationInWindow, time: nsEvent.timestamp, scrollDeltaPoint: CGPoint(x: nsEvent.scrollingDeltaX, y: nsEvent.scrollingDeltaY), scrollMomentum: nsEvent.momentumPhase)
    }
    func pinchEventWith(_ sendType: PinchEvent.SendType, _ nsEvent: NSEvent) -> PinchEvent {
        return PinchEvent(sendType: sendType, locationInWindow: nsEvent.locationInWindow, time: nsEvent.timestamp, magnification: nsEvent.magnification)
    }
    func rotateEventWith(_ sendType: RotateEvent.SendType, _ nsEvent: NSEvent) -> RotateEvent {
        return RotateEvent(sendType: sendType, locationInWindow: nsEvent.locationInWindow, time: nsEvent.timestamp, rotation: nsEvent.rotation.cf)
    }
    
    private var isKey = false, keyAction = Action(), keyEvent: NSEvent?
    private weak var keyTextEditor: TextEditor?
    override func keyDown(with event: NSEvent) {
        if popover.isShown {
            popover.close()
        }
        if !responder.willKeyInput() {
            isKey = false
        } else if !isDown {
            isKey = true
            keyAction = actionWith(gesture: .keyInput, event: event, from: actionNode) ?? Action()
            
            if let editTextEditor = editTextEditor, keyAction.canTextKeyInput() {
                keyTextEditor = editTextEditor
                editTextEditor.keyInput(with: event)
            } else if keyAction != Action() {
                keyAction.keyInput?(responder)
            } else {
                tempNotAction()
            }
        } else {
            keyEvent = event
        }
    }
    override func keyUp(with event: NSEvent) {
        if let keyTextEditor = keyTextEditor, isKey {
            keyTextEditor.keyInput(with: event)
            self.keyTextEditor = nil
        }
    }
    
    private var oldQuasimodeAction = Action()
    private weak var oldQuasimodeView: View?
    override func flagsChanged(with event: NSEvent) {
        if !isDown, let oldQuasimodeView = oldQuasimodeView {
            oldQuasimodeAction.changeQuasimode?(oldQuasimodeView, false)
            self.oldQuasimodeView = nil
        }
        let quasimodeAction = actionWith(gesture: .drag, event: event, from: actionNode) ?? Action()
        if !isDown {
            quasimodeAction.changeQuasimode?(responder, true)
        }
        oldQuasimodeAction = quasimodeAction
        oldQuasimodeView = responder
    }
    
    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) {
        mouseMoved(with: event)
    }
    override func mouseMoved(with event: NSEvent) {
        let p = point(from: event)
        setResponder(with: p)
        updateCursor(with: p)
        responder.moveCursor(with: moveEventWith(.sending, event))
    }
    
    func setResponderFromCurrentPoint() {
        setResponder(with: currentPoint)
    }
    func setResponder(with p: CGPoint) {
        let hitView = rootView.atPoint(p) ?? contentView
        if responder !== hitView {
            responder = hitView
        }
    }
    func updateCursor(with p: CGPoint) {
        let cursor = responder.cursor(with: responder.convert(fromScreen: p))
        if cursor != NSCursor.current() {
            cursor.set()
        }
    }
    
    private let defaultDragAction = Action(drag: { $0.drag(with: $1) })
    private var isDown = false, isDrag = false, dragAction = Action()
    private weak var dragView: View?
    override func mouseDown(with nsEvent: NSEvent) {
        if popover.isShown {
            popover.close()
        }
        isDown = true
        isDrag = false
        dragView = responder
        if let dragView = dragView {
            let event = dragEventWith(.begin, nsEvent)
            if !dragView.willDrag(with: event) {
                isDown = false
            } else {
                dragAction = actionWith(gesture: .drag, event: nsEvent, from: actionNode) ?? defaultDragAction
                dragAction.drag?(dragView, event)
            }
        }
    }
    override func mouseDragged(with nsEvent: NSEvent) {
        isDrag = true
        if isDown, let dragView = dragView {
            dragAction.drag?(dragView, dragEventWith(.sending, nsEvent))
        }
    }
    override func mouseUp(with nsEvent: NSEvent) {
        if isDown {
            let event = dragEventWith(.end, nsEvent)
            if let dragView = dragView {
                dragAction.drag?(dragView, event)
            }
            if !isDrag {
                dragView?.click(with: event)
            }
            isDown = false
            isDrag = false
            
            if let keyEvent = keyEvent {
                keyDown(with: keyEvent)
                self.keyEvent = nil
            }
            
            if dragAction != oldQuasimodeAction {
                if let dragView = dragView {
                    dragAction.changeQuasimode?(dragView, false)
                }
                oldQuasimodeAction.changeQuasimode?(responder, true)
            }
        }
    }
    
    private weak var momentumScrollView: View?
    override func scrollWheel(with event: NSEvent) {
        if event.phase != .mayBegin && event.phase != .cancelled {
            mouseMoved(with: event)
            if event.momentumPhase != .changed && event.momentumPhase != .ended {
                momentumScrollView = responder
            }
            let sendType: ScrollEvent.SendType = event.phase == .began ? .begin : (event.phase == .ended ? .end : .sending)
            momentumScrollView?.scroll(with: scrollEventWith(sendType, event) )
        }
    }
    
    private enum TouchGesture {
        case none, scroll, pinch, rotate
    }
    private var blockGesture = TouchGesture.none
    override func magnify(with event: NSEvent) {
        if event.phase == .began {
            if blockGesture == .none {
                blockGesture = .pinch
                responder.zoom(with: pinchEventWith(.begin, event))
            }
        } else if event.phase == .ended {
            if blockGesture == .pinch {
                blockGesture = .none
                responder.zoom(with:pinchEventWith(.end, event))
            }
        } else {
            if blockGesture == .pinch {
                responder.zoom(with: pinchEventWith(.sending, event))
            }
        }
    }
    override func rotate(with event: NSEvent) {
        if event.phase == .began {
            if blockGesture == .none {
                blockGesture = .rotate
                responder.rotate(with: rotateEventWith(.begin, event))
            }
        } else if event.phase == .ended {
            if blockGesture == .rotate {
                blockGesture = .none
                responder.rotate(with: rotateEventWith(.end, event))
            }
        } else {
            if blockGesture == .rotate {
                responder.rotate(with: rotateEventWith(.sending, event))
            }
        }
    }
    
    private func contains(_ event: NSEvent, with quasimode: Action.Quasimode) -> Bool {
        var modifierFlags: NSEventModifierFlags = []
        if quasimode.contains(.shift) {
            modifierFlags.insert(.shift)
        }
        if quasimode.contains(.command) {
            modifierFlags.insert(.command)
        }
        if quasimode.contains(.control) {
            modifierFlags.insert(.control)
        }
        if quasimode.contains(.option) {
            modifierFlags.insert(.option)
        }
        let flipModifierFlags = modifierFlags.symmetricDifference([.shift, .command, .control, .option])
        return event.modifierFlags.contains(modifierFlags) && event.modifierFlags.intersection(flipModifierFlags) == []
    }
    private func canSend(with event: NSEvent, from action: Action) -> Bool {
        if let key = action.key {
            return event.keyCode == key.code && contains(event, with: action.quasimode)
        } else {
            return contains(event, with: action.quasimode)
        }
    }
    private func actionWith(gesture: Action.Gesture, event: NSEvent, from actionNode: ActionNode) -> Action? {
        switch gesture {
        case .keyInput:
            for action in actionNode.keyActions {
                if canSend(with: event, from: action) {
                    return action
                }
            }
        case .click:
            for action in actionNode.clickActions {
                if canSend(with: event, from: action) {
                    return action
                }
            }
        case .rightClick:
            for action in actionNode.rightClickActions {
                if canSend(with: event, from: action) {
                    return action
                }
            }
        case .drag:
            for action in actionNode.dragActions {
                if canSend(with: event, from: action) {
                    return action
                }
            }
        default:
            break
        }
        return nil
    }
    
    override func quickLook(with event: NSEvent) {
        responder.quickLook()
    }
    override func smartMagnify(with event: NSEvent) {
        responder.reset()
    }
    
    var editTextEditor: TextEditor? {
        return responder as? TextEditor
    }
    
    func hasMarkedText() -> Bool {
        return editTextEditor?.hasMarkedText() ?? false
    }
    func markedRange() -> NSRange {
        return editTextEditor?.markedRange() ?? NSRange()
    }
    func selectedRange() -> NSRange {
        return editTextEditor?.selectedRange() ?? NSRange()
    }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        editTextEditor?.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    func unmarkText() {
        editTextEditor?.unmarkText()
    }
    func validAttributesForMarkedText() -> [String] {
        return editTextEditor?.validAttributesForMarkedText() ?? []
    }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return editTextEditor?.attributedSubstring(forProposedRange: range, actualRange: actualRange)
    }
    func insertText(_ string: Any, replacementRange: NSRange) {
        editTextEditor?.insertText(string, replacementRange: replacementRange)
    }
    func characterIndex(for point: NSPoint) -> Int {
        return editTextEditor?.characterIndex(for: point) ?? 0
    }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        return editTextEditor?.firstRect(forCharacterRange: range, actualRange: actualRange) ?? NSRect()
    }
    func attributedString() -> NSAttributedString {
        return editTextEditor?.attributedString() ?? NSAttributedString()
    }
    func fractionOfDistanceThroughGlyph(for point: NSPoint) -> CGFloat {
        return editTextEditor?.fractionOfDistanceThroughGlyph(for: point) ?? 0
    }
    func baselineDeltaForCharacter(at anIndex: Int) -> CGFloat {
        return editTextEditor?.baselineDeltaForCharacter(at: anIndex) ?? 0
    }
    func windowLevel() -> Int {
        return window?.level ?? 0
    }
    func drawsVerticallyForCharacter(at charIndex: Int) -> Bool {
        return editTextEditor?.drawsVerticallyForCharacter(at: charIndex) ?? false
    }
    
    override func insertNewline(_ sender: Any?) {
        editTextEditor?.insertNewline()
    }
    override func insertTab(_ sender: Any?) {
        editTextEditor?.insertTab()
    }
    override func deleteBackward(_ sender: Any?) {
        editTextEditor?.deleteBackward()
    }
    override func deleteForward(_ sender: Any?) {
        editTextEditor?.deleteForward()
    }
    override func moveLeft(_ sender: Any?) {
        editTextEditor?.moveLeft()
    }
    override func moveRight(_ sender: Any?) {
        editTextEditor?.moveRight()
    }
}

extension NSCoding {
    static func with(_ data: Data) -> Self? {
        return data.isEmpty ? nil : NSKeyedUnarchiver.unarchiveObject(with: data) as? Self
    }
    var data: Data {
        return NSKeyedArchiver.archivedData(withRootObject: self)
    }
}
extension NSCoder {
    func decodeStruct<T: ByteCoding>(forKey key: String) -> T? {
        return T(coder: self, forKey: key)
    }
    func encodeStruct(_ byteCoding: ByteCoding, forKey key: String) {
        byteCoding.encode(in: self, forKey: key)
    }
}
extension NSColor {
    final class func checkerboardColor(_ color: NSColor, subColor: NSColor, size s: CGFloat = 5.0) -> NSColor {
        let size = NSSize(width: s*2,  height: s*2)
        let image = NSImage(size: size) { ctx in
            let rect = CGRect(origin: CGPoint(), size: size)
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
            ctx.fill(CGRect(x: 0, y: s, width: s, height: s))
            ctx.fill(CGRect(x: s, y: 0, width: s, height: s))
            ctx.setFillColor(subColor.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            ctx.fill(CGRect(x: s, y: s, width: s, height: s))
        }
        return NSColor(patternImage: image)
    }
    static func polkaDotColorWith(color: NSColor?, dotColor: NSColor, radius r: CGFloat = 1.0, distance d: CGFloat = 4.0) -> NSColor {
        let tw = (2*r + d)*cos(.pi/3), th = (2*r + d)*sin(.pi/3)
        let bw = (tw - 2*r)/2, bh = (th - 2*r)/2
        let size = CGSize(width: floor(bw*2 + tw + r*2), height: floor(bh*2 + th + r*2))
        let image = NSImage(size: size) { ctx in
            if let color = color {
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(origin: CGPoint(), size: size))
            }
            ctx.setFillColor(dotColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: bw, y: bh, width: r*2, height: r*2))
            ctx.fillEllipse(in: CGRect(x: bw + tw, y: bh + th, width: r*2, height: r*2))
        }
        return NSColor(patternImage: image)
    }
}

extension NSImage {
    convenience init(size: CGSize, handler: (CGContext) -> Void) {
        self.init(size: size)
        lockFocus()
        if let ctx = NSGraphicsContext.current()?.cgContext {
            handler(ctx)
        }
        unlockFocus()
    }
    final var bitmapSize: CGSize {
        if let tiffRepresentation = tiffRepresentation {
            if let bitmap = NSBitmapImageRep(data: tiffRepresentation) {
                return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            }
        }
        return CGSize()
    }
    final var PNGRepresentation: Data? {
        if let tiffRepresentation = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffRepresentation) {
            return bitmap.representation(using: .PNG, properties: [NSImageInterlaced: false])
        } else {
            return nil
        }
    }
    static func exportAppIcon() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.begin { [unowned panel] result in
            if result == NSFileHandlingPanelOKButton, let url = panel.url {
                for s in [16.0.cf, 32.0.cf, 64.0.cf, 128.0.cf, 256.0.cf, 512.0.cf, 1024.0.cf] {
                    try? NSImage(size: CGSize(width: s, height: s), flipped: false) { rect -> Bool in
                        let ctx = NSGraphicsContext.current()!.cgContext, c = s*0.5, r = s*0.43, l = s*0.008, fs = s*0.45, fillColor = NSColor(white: 1, alpha: 1), fontColor = NSColor(white: 0.4, alpha: 1)
                        ctx.setFillColor(fillColor.cgColor)
                        ctx.setStrokeColor(fontColor.cgColor)
                        ctx.setLineWidth(l)
                        ctx.addEllipse(in: CGRect(x: c - r, y: c - r, width: r*2, height: r*2))
                        ctx.drawPath(using: .fillStroke)
                        var textLine = TextLine()
                        textLine.string = "C\u{2080}"
                        textLine.font = NSFont(name: "Avenir Next Regular", size: fs) ?? NSFont.systemFont(ofSize: fs)
                        textLine.color = fontColor.cgColor
                        textLine.isHorizontalCenter = true
                        textLine.isCenterWithImageBounds = true
                        textLine.draw(in: rect, in: ctx)
                        return true
                        }.PNGRepresentation?.write(to: url.appendingPathComponent("\(String(Int(s))).png"))
                }
            }
        }
    }
}

extension NSAttributedString {
    static func attributes(_ font: NSFont, color: CGColor) -> [String: Any] {
        return [String(kCTFontAttributeName): font, String(kCTForegroundColorAttributeName): color]
    }
}

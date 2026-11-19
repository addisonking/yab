import AppKit
import Testing
import YabCoreClient
@testable import Fast

/// Extension popups take Chinese, Japanese and Korean input
/// (extensions parity #3): YabCore says whether the popup's focused element
/// takes text and where its caret is (popup.textInput).
struct ChromiumPopupTextInputTests {
    @Test func readsAFieldAndItsCaret() {
        let state = ChromiumPopupTextInput(["token": .string("t1"), "editable": .bool(true),
            "caret": .object(["x": .number(24), "y": .number(30), "width": .number(1), "height": .number(17)])], token: "t1")
        #expect(state == ChromiumPopupTextInput(editable: true, caret: CGRect(x: 24, y: 30, width: 1, height: 17)))
    }

    @Test func aButtonOrPasswordTakesNoComposition() {
        let state = ChromiumPopupTextInput(["token": .string("t1"), "editable": .bool(false)], token: "t1")
        #expect(state == ChromiumPopupTextInput(editable: false, caret: nil))
    }

    @Test func anotherPopupsStateOrAnUnreadableOneIsRefused() {
        #expect(ChromiumPopupTextInput(["token": .string("t2"), "editable": .bool(true)], token: "t1") == nil)
        #expect(ChromiumPopupTextInput(["token": .string("t1"), "editable": .number(1)], token: "t1") == nil)
        #expect(ChromiumPopupTextInput(["token": .string("t1")], token: "t1") == nil)
    }

    @Test func aCaretThatIsNoRectangleIsDropped() {
        for caret: [String: JSONValue] in [["x": .number(1), "y": .number(1), "width": .number(1), "height": .number(0)],
                                           ["x": .number(.nan), "y": .number(1), "width": .number(1), "height": .number(9)],
                                           ["x": .number(1), "y": .number(1), "width": .number(-1), "height": .number(9)],
                                           ["x": .number(1), "y": .number(1)]] {
            let state = ChromiumPopupTextInput(["token": .string("t1"), "editable": .bool(true), "caret": .object(caret)], token: "t1")
            #expect(state == ChromiumPopupTextInput(editable: true, caret: nil))
        }
    }

    /// Plain typing and composition use the input context in text fields.
    @MainActor @Test func editablePopupKeysUseTheInputContext() throws {
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40))
        #expect(ChromiumPage.usesInputContext(key, marked: false, editable: true))
        #expect(!ChromiumPage.usesInputContext(key, marked: false, editable: false))
        let command = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9))
        #expect(!ChromiumPage.usesInputContext(command, marked: true, editable: true))
    }

    /// #922: a plain key in the popup's field is delivered as text through
    /// the input path (keyDown, the input context, insertText), the same
    /// hop that ends in popup.send(["kind": "text"]), and not only routed
    /// by the shared Boolean. A field that takes no text gets nothing.
    @MainActor @Test func aPlainKeyIsDeliveredAsTextThroughThePopupInput() {
        final class RecordingInput: ChromiumPopupInput {
            var inserted: [String] = []
            override func insertText(_ string: Any, replacementRange: NSRange) {
                inserted.append((string as? NSAttributedString)?.string ?? (string as? String) ?? "")
                super.insertText(string, replacementRange: replacementRange)
            }
        }
        func field(_ editable: Bool) -> (RecordingInput, ChromiumExtensionPopup, ChromiumPage, Tab) {
            let tab = Tab(shy: true)
            let page = ChromiumPage(tab: tab)
            let popup = ChromiumExtensionPopup(token: "t1", extensionID: "ext922", page: page)
            popup.receiveTextInput(["token": .string("t1"), "editable": .bool(editable),
                "caret": .object(["x": .number(47), "y": .number(84), "width": .number(1), "height": .number(18)])])
            let input = RecordingInput(frame: CGRect(origin: .zero, size: CGSize(width: 480, height: 600)))
            input.popup = popup
            return (input, popup, page, tab)
        }
        func key(_ character: String, _ code: UInt16, window: Int = 0) -> NSEvent? {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: window, context: nil, characters: character, charactersIgnoringModifiers: character,
                isARepeat: false, keyCode: code)
        }

        // The host retains the popup in production; the test keeps it alive
        // the same way, as the input view holds it weakly.
        let (typing, popup, page, tab) = field(true)
        defer { page.retire(call: false, pictureInPicture: false); tab.close() }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: CGSize(width: 480, height: 600)),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = typing
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(typing)
        for (character, code) in [("t", 17), ("e", 14), ("s", 1)] as [(String, UInt16)] {
            typing.keyDown(with: key(character, code, window: window.windowNumber)!)
        }
        window.orderOut(nil)
        #expect(typing.inserted == ["t", "e", "s"])

        let (idle, _, idlePage, idleTab) = field(false)
        defer { idlePage.retire(call: false, pictureInPicture: false); idleTab.close() }
        idle.keyDown(with: key("t", 17)!)
        #expect(idle.inserted == [])
    }
}

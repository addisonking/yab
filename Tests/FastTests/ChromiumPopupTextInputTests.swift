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
}

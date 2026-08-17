//
//  ShelfActionService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import AppKit
import Foundation

/// A service providing common actions for `ShelfItem`s, such as opening, revealing, or copying paths.
@MainActor
enum ShelfActionService {

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case .file(let bookmarkData):
            Bookmark(data: bookmarkData).withAccess { url in
                NSWorkspace.shared.open(url)
            }
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }

    static func reveal(_ item: ShelfItem) {
        guard case .file(let bookmarkData) = item.kind else { return }
        Bookmark(data: bookmarkData).withAccess { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func copyPath(_ item: ShelfItem) {
        guard case .file(let bookmarkData) = item.kind else { return }
        Bookmark(data: bookmarkData).withAccess { url in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }

    static func remove(_ item: ShelfItem) {
        ShelfStateViewModel.shared.remove(item)
    }

    /// Removes the current shelf selection on Delete / Forward Delete.
    /// Returns `true` if the event was handled, so the caller can consume it rather than
    /// letting it fall through to the frontmost application.
    static func handleKeyDown(_ event: NSEvent) -> Bool {
        let deleteKey: UInt16 = 51
        let forwardDeleteKey: UInt16 = 117
        guard event.keyCode == deleteKey || event.keyCode == forwardDeleteKey else {
            return false
        }

        let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        guard !selected.isEmpty else { return false }

        ShelfSelectionModel.shared.clear()
        ShelfStateViewModel.shared.remove(selected)
        return true
    }
}


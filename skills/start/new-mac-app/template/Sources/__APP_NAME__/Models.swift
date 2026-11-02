import Foundation
import SwiftData
import __APP_NAME__Kit

@Model
final class Item {
    var title: String
    var notes: String = ""
    var isStarred: Bool = false
    var createdAt: Date = Date.now
    /// A stable id for links, sync, and the agent CLI.
    var uuid: UUID = UUID()

    init(title: String) {
        self.title = title
    }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case all, starred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Items"
        case .starred: "Starred"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray"
        case .starred: "star"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var sidebar: SidebarItem? = .all
    var selection: PersistentIdentifier?
    /// The window's undo manager, so actions here reach Edit > Undo. ContentView sets it.
    @ObservationIgnored var undoManager: UndoManager?
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(container: ModelContainer) {
        self.container = container
    }

    func addItem(title: String = "") {
        let item = Item(title: ItemTitle.clean(title))
        if sidebar == .starred { item.isStarred = true }
        container.mainContext.insert(item)
        // The id is temporary until the first save, so save before selecting.
        try? container.mainContext.save()
        selection = item.id
    }

    /// Deletes an item so that Edit > Undo brings it back. The window and the
    /// agent CLI both call this. Add each new field to the copy below.
    func deleteItem(_ item: Item) {
        let copy = (title: item.title, notes: item.notes, isStarred: item.isStarred,
                    createdAt: item.createdAt, uuid: item.uuid)
        if selection == item.id { selection = nil }
        container.mainContext.delete(item)
        try? container.mainContext.save()
        undoManager?.registerUndo(withTarget: self) { model in
            let restored = Item(title: copy.title)
            restored.notes = copy.notes
            restored.isStarred = copy.isStarred
            restored.createdAt = copy.createdAt
            restored.uuid = copy.uuid
            model.container.mainContext.insert(restored)
            try? model.container.mainContext.save()
            model.selection = restored.id
            // Registering inside an undo makes this the redo.
            model.undoManager?.registerUndo(withTarget: model) { $0.deleteItem(restored) }
        }
        undoManager?.setActionName("Delete Item")
    }
}

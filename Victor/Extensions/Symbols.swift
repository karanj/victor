import Foundation

/// Centralized SF Symbol names, so the same icon means the same thing everywhere.
enum Symbols {
    // MARK: - Actions

    enum Action {
        static let trash = "trash"
        static let refresh = "arrow.clockwise"
        static let save = "square.and.arrow.down"
        static let copy = "doc.on.doc"
        static let copyToClipboard = "doc.on.clipboard"
        static let openExternal = "arrow.up.forward.square"
        static let addCircle = "plus.circle.fill"
        static let zoomIn = "plus.magnifyingglass"
        static let zoomOut = "minus.magnifyingglass"
        static let swap = "arrow.left.arrow.right"
        static let pan = "hand.draw"
        static let more = "ellipsis.circle"
    }

    // MARK: - Navigation

    enum Navigation {
        static let chevronRight = "chevron.right"
        static let chevronLeft = "chevron.left"
        static let chevronUp = "chevron.up"
        static let chevronDown = "chevron.down"
        static let arrowRight = "arrow.right"
        static let arrowRightCircle = "arrow.right.circle"
        static let arrowUpRight = "arrow.up.right"
        static let arrowTurnDownRight = "arrow.turn.down.right"
    }

    // MARK: - Documents

    enum Document {
        static let text = "doc.text"
        static let textFill = "doc.text.fill"
        static let textSearch = "doc.text.magnifyingglass"
        static let textFillViewfinder = "doc.text.fill.viewfinder"
        static let badgeGearshape = "doc.badge.gearshape"
    }

    // MARK: - Folders

    enum Folder {
        static let folder = "folder"
        static let fill = "folder.fill"
        static let badgePlus = "folder.badge.plus"
    }

    // MARK: - Status

    enum Status {
        static let checkmarkCircleFill = "checkmark.circle.fill"
        static let warningTriangle = "exclamationmark.triangle"
        static let warningTriangleFill = "exclamationmark.triangle.fill"
        static let infoCircle = "info.circle"
    }

    // MARK: - Search

    enum Search {
        static let magnifyingGlass = "magnifyingglass"
        static let documentSearch = "doc.text.magnifyingglass"
    }

    // MARK: - Controls

    enum Control {
        static let closeCircleFill = "xmark.circle.fill"
        static let helpCircle = "questionmark.circle"
        static let helpCircleFill = "questionmark.circle.fill"
        static let gearshapeFill = "gearshape.fill"
    }

    // MARK: - Content Types

    enum Content {
        static let photoRectangle = "photo.on.rectangle.angled"
        static let globe = "globe"
        static let listBulletRectangle = "list.bullet.rectangle"
        static let rectangleGrid = "rectangle.grid.1x2"
        static let stack3D = "square.stack.3d.up"
        static let puzzlePiece = "puzzlepiece"
        static let terminal = "terminal"
    }
}

import MetalUI

/// The window the app opens at, and the smallest it may be resized to.
public let jotterWindowSize = Size(width: Pixels(900), height: Pixels(600))
public let jotterMinimumSize = Size(width: Pixels(640), height: Pixels(400))

/// Stub: the red-first commit (the tests exist, the screens do not).
@MainActor
public func rootView(model: NotesModel) -> some Element {
    Text("Jotter")
}

import Kit
@MainActor func show<E: Element>(_ label: String, _ e: E) {
    var e = e; var pass = Pass()
    _ = e.requestLayout(ID(path: [7]), pass: &pass)
    print(label, String(describing: E.self)); for l in pass.log { print("   ", l) }
}
MainActor.assumeIsolated {
    show("legacy chain", Box().padding(Pixels(4)).frame(width: Pixels(1)).background(Token()).id(3))
    show("proposal chain", Rect().padding(4).frame(width: Pixels(1)).background(Token()))
    show("proposal then legacy", Rect().padding(4).padding(Pixels(8)).background(Token()))
    show("legacy on proposal", Rect().padding(Pixels(8)).frame(width: Pixels(2)))
    show("overlay legacy", Box().overlay { Box() })
    show("overlay proposal in HStack", HStack { Rect().padding(2).overlay { Rect() } })
    show("proposal after overlay", Rect().overlay { Rect() }.padding(3))
    let stored: ModifiedElement<Box> = Box().padding(Pixels(1)).frame(width: Pixels(2))
    let storedP: ModifiedContent<Rect, LayoutModifier> = Rect().padding(1).frame()
    let viaInit = ModifiedContent(content: Rect(), modifier: .padding(1))
    show("stored", stored); show("storedP", storedP); show("init", viaInit)
    _ = HStack { viaInit }
    var m = storedP; m.modifier = .opacity(1); _ = m
    // generic over StyledElement
    @MainActor func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase> { t.padding(Pixels(8)) }
    show("generic", wrap(Box().padding(Pixels(4))))
}

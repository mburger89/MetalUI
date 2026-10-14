import Testing
import MetalUIPlatform

// `ClipboardMime` (ruling `CB-D`, spec tests 2.1 and 2.2): the pure identifier <-> mime table
// the SDL clipboard is keyed by. Portable, so macOS pins what Linux and Windows run.

/// 2.1 — `id -> mime -> id` is the identity for every built-in, a custom id, a mixed-case id and
/// a hostile one; the mime is all lower case; the text mime is the one SDL asks for.
/// Mutation: an off-by-one in the percent-encoder; the text mime `text/plain`.
@Test func clipboardMimeRoundTripsEveryBuiltInACustomAMixedCaseAndAHostileIdentifier() {
    let identifiers = [
        "public.utf8-plain-text", "public.plain-text", "public.json", "public.url", "public.data",
        "com.example.graph", "com.Example.Graph", "Com.EXAMPLE.graph", "a b/c%d;e=f\u{e9}\u{1F600}",
        "mime:image/png", "mime:application/x-foo", "mime:text/plain", "mime:Image/PNG", "mime:", "%", "%41", "",
    ]
    for identifier in identifiers {
        let mime = ClipboardMime.mime(forIdentifier: identifier)
        #expect(ClipboardMime.identifier(forMime: mime) == identifier, "\(identifier) -> \(mime)")
        #expect(mime == mime.lowercased(), "the mime of \(identifier) is lower case: \(mime)")
    }
    #expect(ClipboardMime.mime(forIdentifier: "public.utf8-plain-text") == "text/plain;charset=utf-8")
    #expect(ClipboardMime.mime(forIdentifier: "com.example.graph") == "application/x-com.example.graph")
    #expect(ClipboardMime.mime(forIdentifier: "Com.Graph") == "application/x-%43om.%47raph")
    #expect(ClipboardMime.mime(forIdentifier: "a/b") == "application/x-a%2fb")
}

/// 2.1b — decoding accepts either hex case, and a stray `%` stays literal.
@Test func clipboardMimeDecodesEitherHexCaseAndKeepsAStrayPercent() {
    #expect(ClipboardMime.identifier(forMime: "application/x-a%2Fb") == "a/b")
    #expect(ClipboardMime.identifier(forMime: "application/x-a%2fb") == "a/b")
    #expect(ClipboardMime.identifier(forMime: "application/x-100%") == "100%")
    #expect(ClipboardMime.identifier(forMime: "application/x-a%zzb") == "a%zzb")
}

/// 2.2 — a mime with no entry and no `application/x-` prefix is listed and readable by its mime
/// identifier, never dropped. Mutation: drop unknown mimes (return an empty identifier).
@Test func aForeignMimeIsListedAndReadableByItsMimeIdentifier() {
    #expect(ClipboardMime.identifier(forMime: "image/png") == "mime:image/png")
    #expect(ClipboardMime.mime(forIdentifier: "mime:image/png") == "image/png")
    #expect(ClipboardMime.identifier(forMime: "text/plain;charset=UTF-8") == "public.utf8-plain-text")
}

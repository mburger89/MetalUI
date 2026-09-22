
/// The identity of a **resolved** font: what an atlas, a shaping cache or a
/// metrics cache may safely be keyed on (spec §6.1) — for glyph identity. It
/// does NOT fully identify shaping behaviour: the UI font and `"System Font"`
/// at the same size produce equal keys and shape non-Latin text differently
/// (see `ShapingCache.fonts`; pinned wrong on purpose by
/// `twoRequestsWithEqualFontKeysShareOneShapeThoughTheyShapeDifferently`).
///
/// **Every component is read back off the `CTFont` CoreText handed us, never
/// off the request, and §6.1 measured why.** `CTFontCreateWithName` does not
/// fail on a name it cannot find — it *substitutes*. Requesting
/// `"SFMono-Regular"` by name on this machine returns a font whose PostScript
/// name is `Helvetica` — as does `"NoSuchFontXYZ"`. A key built from the
/// requested family would therefore hand out one font's glyph images for
/// another font's outlines.
///
/// **What would and would not catch that, by mechanism.** The substituted font
/// measures, shapes and lays out perfectly well, so the wrongness is confined to
/// *which glyph image* is served — and no test in this repo renders a glyph and
/// compares it: the layout corpus contains no text fixture, its WebKit oracle
/// covers boxes rather than glyphs, and the ABI probe skips without a Metal
/// device. So no *rendered* evidence exists. The key itself is a different
/// matter and is directly testable:
/// `theKeyComesFromTheRESOLVEDFontNotTheRequestedName` reddens when the key is
/// built from the request, which was measured by mutation rather than assumed.
///
/// The four components, and what each one alone would let collide:
///
/// - ``postScriptName`` — *which face* was actually resolved. This is the
///   component §6.1 is about.
/// - ``size`` — a `CTFont` carries its point size, and glyph images are
///   rasterized at it. Without this, 13pt and 26pt of one face share a key.
/// - ``variations`` — the resolved variation coordinates
///   (`CTFontCopyVariation`). Two `CTFont`s can share a PostScript name *and* a
///   size *and* a matrix and differ on every axis: a `wght` 400 and a `wght` 700
///   instance of the system font do exactly that, which is the differential
///   `everyComponentOfTheFontKeyDiscriminates` pins. This component is live in
///   production, and it is live **because** `FontResolver` pins no axis
///   (ruling TX-C): the system font resolves with `opsz` = `clamp(size, 17, 96)`
///   in its variation dictionary, so 13pt and 26pt differ here as well as in
///   ``size``. Pinning an axis to its *default* would empty this dictionary —
///   `CTFontCopyVariation` omits any axis sitting at its default — and quietly
///   make the component production-inert.
/// - ``matrix`` — `CTFontGetMatrix`. A synthesised oblique, or a flipped font,
///   is the same face and size producing different outlines.
///
/// Construct one only via `init(resolved:)` (in `MetalUIText`); there is
/// deliberately no public memberwise initialiser, because a caller that can
/// spell the components by hand can spell a *requested* name into
/// ``postScriptName`` and reintroduce exactly the bug this type exists to
/// prevent. The struct lives in `MetalUIScene`, which imports no CoreText, so
/// the atlas can key on it anywhere; its one initialiser is `package`
/// (ruling PS-D).
public struct FontKey: Hashable, Sendable {
    /// One axis of a variable font, as resolved.
    public struct VariationCoordinate: Hashable, Sendable {
        /// The four-character axis tag as an integer, e.g. `'opsz'`.
        public let axis: Int
        public let value: Double

        package init(axis: Int, value: Double) { self.axis = axis; self.value = value }
    }

    /// `CTFontGetMatrix`'s six components. `CGAffineTransform` is neither
    /// `Hashable` nor `Sendable`, so it is destructured rather than stored.
    public struct Matrix: Hashable, Sendable {
        public let a, b, c, d, tx, ty: Double

        package init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
            self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
        }
    }

    public let postScriptName: String
    public let size: Double
    /// Sorted by ``VariationCoordinate/axis`` so that two fonts with the same
    /// coordinates in a different dictionary order compare equal.
    public let variations: [VariationCoordinate]
    public let matrix: Matrix

    /// The four components above, hashed once, at the only initialiser.
    ///
    /// **Why it is stored.** A `GlyphKey` is hashed for every glyph of every
    /// visible `Text` on every built frame, and it hashes this key; a
    /// synthesized `hash(into:)` would walk the PostScript name, the variation
    /// array and the six matrix `Double`s each time. The components are fixed
    /// by the one initialiser, so this cannot fall out of step with them.
    ///
    /// **A fast reject for `==`, never a proof of equality** — the same
    /// contract as `GlobalElementID.cachedHash`, and see `==` for why it is a
    /// combination to keep. `Hasher` is seeded per process, so the value is
    /// meaningful within one run only; nothing persists it.
    ///
    /// `package` rather than private so that
    /// `aForgedHashCollisionIsSettledByTheComponents` can take its offset from
    /// `MetalUIText`'s tests.
    package let precomputedHash: Int

    /// Stores the four components and hashes them once.
    ///
    /// **Only `init(resolved:)` calls this** — it lives in `MetalUIText`, which
    /// reads the components off a resolved `CTFont` (ruling PS-D). `package`,
    /// so no module outside this Swift package can spell a key by hand, pinned
    /// by `anExternalModuleCannotSpellAFontKeyByHand`; the label names the
    /// obligation for callers inside it: every argument must have been read
    /// back off the resolved font, never off the request.
    package init(resolvedPostScriptName postScriptName: String, size: Double,
                 variations: [VariationCoordinate], matrix: Matrix) {
        var hasher = Hasher()
        hasher.combine(postScriptName)
        hasher.combine(size)
        hasher.combine(variations)
        hasher.combine(matrix)

        self.postScriptName = postScriptName
        self.size = size
        self.variations = variations
        self.matrix = matrix
        self.precomputedHash = hasher.finalize()
    }

    /// **All four components decide; ``precomputedHash`` only rejects early.**
    ///
    /// Keys that are equal component by component hashed the same values in
    /// the same order, so they agree on the hash and the early reject never
    /// refuses an equal pair. The converse does not hold: two different keys
    /// can collide, and then only the component comparison gives the right
    /// answer.
    ///
    /// **Safe alone and unsafe together**, as with `GlobalElementID`: an `==`
    /// that answered with the hash alone, or that skipped any one component, is
    /// wrong only on a collision. Measured, whole suite: each of those five
    /// spellings reddened `aForgedHashCollisionIsSettledByTheComponents` and no
    /// other test — the keys every other test compares already hash
    /// differently, so the early reject gives the right answer for the wrong
    /// reason. That test can see it because it writes a collision into a key
    /// instead of searching for one. A hash that dropped a component is the
    /// other half, a silent performance defect that
    /// `theFontKeyHashItselfDistinguishesEveryComponent` pins.
    ///
    /// **To force collisions under mutation, make the STORED hash constant**
    /// (`self.precomputedHash = 0`), not `hash(into:)`. This `==` reads
    /// ``precomputedHash`` directly, so a constant `hash(into:)` leaves the early
    /// reject fully working and proves nothing about the component comparison —
    /// measured: it left dropping `variations` or `matrix` from this body
    /// invisible to `everyComponentOfTheFontKeyDiscriminates`. With the stored
    /// hash constant, that test and `everyComponentOfTheGlyphKeyDiscriminates`
    /// both pass on the component comparison alone. Then dropping `variations`
    /// or `matrix` here reddens `everyComponentOfTheFontKeyDiscriminates`,
    /// dropping `size` reddens `theKeyDistinguishesSizes`, and answering with the
    /// hash alone reddens both discrimination tests. The `GlyphKey` test's two
    /// fonts differ in size and `opsz` at once, so no single dropped component
    /// reaches it.
    ///
    /// The comparison is **IEEE on `size`** exactly as the synthesized one was,
    /// so a NaN size is still unequal to itself.
    public static func == (lhs: FontKey, rhs: FontKey) -> Bool {
        lhs.precomputedHash == rhs.precomputedHash
            && lhs.size == rhs.size
            && lhs.matrix == rhs.matrix
            && lhs.postScriptName == rhs.postScriptName
            && lhs.variations == rhs.variations
    }

    /// Feeds ``precomputedHash`` alone. Pinned by
    /// `aFontKeyHashesOnlyItsPrecomputedHash`.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(precomputedHash)
    }
}

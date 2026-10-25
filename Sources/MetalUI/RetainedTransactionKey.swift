// `AM-D`, `AM-L` (record 146): the two transaction members are never part of a retained key.
//
// `snappingTransaction` and `disablesAnimations` only decide whether an animation *starts*, which needs a value that changed; a changed
// value is already a miss on its own conjunct (the serial moves, an observer fires, or a keyed geometry or ambient field moves). A
// `GestureState.updating` body that sets `disablesAnimations` parks it for one build (`AN-Y`), so every drag frame's root transaction
// differs from the settle frames': keyed, that is a miss of every panel on the frame the drag starts and on the frame it ends, and one
// more per panel after it (the second frame of an ambient miss, `AM-C`).
//
// The rule: every key the decisions compute and every key a record stores is normalised (`transactionNormalised`), unconditionally. An
// earlier build kept both fields for a record with animation touches; it left the drag unchanged because every filled panel touches an
// animation track, and `AM-L` retired the guard.

extension AmbientKey {
    /// This key with the transaction's two members zeroed.
    var transactionNormalised: AmbientKey {
        var key = self
        key.snappingTransaction = false
        key.disablesAnimations = false
        return key
    }
}

extension ReplayKey {
    var transactionNormalised: ReplayKey {
        var key = self
        key.ambient = ambient.transactionNormalised
        return key
    }
}

extension PrepaintKey {
    var transactionNormalised: PrepaintKey {
        var key = self
        key.ambient = ambient.transactionNormalised
        return key
    }
}

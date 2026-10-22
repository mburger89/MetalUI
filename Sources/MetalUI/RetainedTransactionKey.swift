// `AM-D` (record 146): the two transaction members of a retained key leave it for a record that holds no animation touches.
//
// `snappingTransaction` and `disablesAnimations` only decide whether an animation *starts*, which needs a value that changed; a record
// that stands has none (a changed value moves the serial, fires an observer, or moves a keyed geometry or ambient field) and touches
// no animation track. A `GestureState.updating` body that sets `disablesAnimations` parks it for one build (`AN-Y`), so every drag
// frame's root transaction differs from the settle frames': keyed, that is a miss of every panel on the frame the drag starts and on
// the frame it ends, and one more per panel after it (the second frame of an ambient miss, `AM-C`).
//
// The rule: a record stores a normalised key when its paint touched no animation entry (`finishRetainedPaint`), and a decision
// normalises the key it computes when the standing record is touch-free. A record **with** touches keeps both fields.

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

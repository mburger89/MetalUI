// SwiftUI probe: gesture composition (rulings GE-* in
// docs/superpowers/2026-10-31-gesture-composition-decisions.md; record 178).
//
// HOW TO RUN (compiled form):
//
//   xcrun swiftc docs/probes/swiftui-gesture-composition.swift -o /tmp/gc-probe && /tmp/gc-probe
//
// THE INSTRUMENT is `swiftui-gesture-state.swift`'s: a key `NSWindow` hosting an `NSHostingView`, `NSEvent`s through
// `NSWindow.sendEvent`, a run-loop spin between events. The D arms stamp each event's own `timestamp` (seconds after
// a base) and spin a different real time, so a value that follows the stamps is told from one that follows the clock.
//
// ARMS AND THEIR CONTROLS.
//   S1..S7b  `LongPressGesture(0.3 s, maxDistance 20).sequenced(before: DragGesture(...))` (S7: a tap first): the
//            value at each step, where the drag starts (S1, S2, S5b), a release right after the long press (S4,
//            S4b), a failing first member (S3, S5), `updating` (S6..S6c). S1 is the positive control; S3/S5 the
//            separating arms for "the second member only runs after the first ended".
//   X1..X2b  `updating`/`onChanged`/`onEnded` on `simultaneously` and `exclusively` composites.
//   C1..C5   custom `Gesture`s with a `body` (the `Value` of an opaque `some Gesture` body cannot be spelled, so C4
//            names its body's type).
//   D0..D15  `DragGesture.Value.time/velocity/predictedEnd*` from stamped events: steady (D1, D4, D5), decoupled
//            from the wall clock (D2, D3), accelerating (D6), stopping (D7, D8), diagonal and leftward (D9, D10), a
//            slow start then a burst (D11), one move (D12), before `minimumDistance` (D13), equal timestamps
//            (D14, D15). D0 prints `time` against the event's stamp.
//
// RECORDED 2026-10-31 by the gesture-composition lane, macOS 27.0.1, Apple Swift 6.4, Xcode-beta SDK, screen UNLOCKED.
// Two runs (this file's arms were run as two programs sharing the instrument; D0, D13..D15 in the second). Times in
// `t=` are `v.time` minus the probe's Date base (the epoch offset is meaningless; the differences are the stamps').
//
// RESULT (stdout, verbatim):
//
//   --- S: sequenced(before:) (long press 0.3 s, maxDistance 20) then drag
//       S1 hold 0.5, move 10, move 30, release: changed first(true)@0.0 | changed second(true, nil)@0.3 | changed second(true, start=(60.0,50.0) loc=(60.0,50.0) tr=(0.0,0.0))@0.5 | changed second(true, start=(60.0,50.0) loc=(80.0,50.0) tr=(20.0,0.0))@0.7 | ended second(true, start=(60.0,50.0) loc=(80.0,50.0) tr=(20.0,0.0))@0.8
//       S2 drag minimumDistance 10: hold 0.5, move 3, move 20, release: changed first(true)@0.0 | changed second(true, nil)@0.3 | changed second(true, start=(53.0,50.0) loc=(70.0,50.0) tr=(17.0,0.0))@0.7 | ended second(true, start=(53.0,50.0) loc=(70.0,50.0) tr=(17.0,0.0))@0.8
//       S3 release at 0.1 s (before the long press): changed first(true)@0.0
//       S4 hold 0.5, release without moving (drag min 0): changed first(true)@0.0 | changed second(true, nil)@0.3 | ended second(true, start=(50.0,50.0) loc=(50.0,50.0) tr=(0.0,0.0))@0.5
//       S4b hold 0.5, release without moving (drag min 10): changed first(true)@0.0 | changed second(true, nil)@0.3
//       S5 pointer leaves maxDistance 20 at 0.15 s (before the long press), release at 0.5: changed first(true)@0.0
//       S5b move 3 pt at 0.1, then 40 pt at 0.5 (after the long press ended): is drag start where?: changed first(true)@0.0 | changed second(true, nil)@0.3 | changed second(true, start=(90.0,50.0) loc=(90.0,50.0) tr=(0.0,0.0))@0.5 | ended second(true, start=(90.0,50.0) loc=(90.0,50.0) tr=(0.0,0.0))@0.7
//       S6 updating + onChanged + onEnded: hold 0.5, move, move, release: upd first(true)@0.0 | changed first(true)@0.0 | body s=1@0.0 | upd second(true, nil)@0.3 | changed second(true, nil)@0.3 | body s=2@0.3 | upd second(true, start=(60.0,50.0) loc=(60.0,50.0) tr=(0.0,0.0))@0.5 | changed second(true, start=(60.0,50.0) loc=(60.0,50.0) tr=(0.0,0.0))@0.5 | body s=3@0.5 | upd second(true, start=(60.0,50.0) loc=(80.0,50.0) tr=(20.0,0.0))@0.7 | changed second(true, start=(60.0,50.0) loc=(80.0,50.0) tr=(20.0,0.0))@0.7 | body s=4@0.7 | ended second(true, start=(60.0,50.0) loc=(80.0,50.0) tr=(20.0,0.0))@0.8 | body s=0@0.8
//       S6b updating: release at 0.1 s (sequence fails): upd first(true)@0.0 | changed first(true)@0.0 | body s=1@0.0 | body s=0@0.1
//       S6c updating: hold 0.5, release without moving: upd first(true)@0.0 | changed first(true)@0.0 | body s=1@0.0 | upd second(true, nil)@0.3 | changed second(true, nil)@0.3 | body s=2@0.3 | ended second(true, start=(50.0,50.0) loc=(50.0,50.0) tr=(0.0,0.0))@0.5 | body s=0@0.5
//       S7 tap.sequenced(before: drag 0): click, 0.1 s, press, move, release: ended second start=(50.0,50.0) loc=(50.0,50.0) tr=(0.0,0.0)@0.1
//       S7b tap.sequenced(before: drag 0): one click only: ended second start=(50.0,50.0) loc=(50.0,50.0) tr=(0.0,0.0)@0.1
//   --- X: composed `updating` / onChanged / onEnded
//       X1 simultaneous (drag 0, long press 0.3): press, move, hold to 0.5, move, release: upd first=start=(50.0,50.0) loc=(50.0,50.0) tr=(0.0,0.0) second=true@0.0 | changed first=true second=Optional(true)@0.0 | body s=1@0.0 | upd first=start=(50.0,50.0) loc=(60.0,50.0) tr=(10.0,0.0) second=true@0.1 | changed first=true second=Optional(true)@0.1 | body s=2@0.1 | upd first=start=(50.0,50.0) loc=(70.0,50.0) tr=(20.0,0.0) second=true@0.5 | changed first=true second=Optional(true)@0.5 | body s=3@0.5 | ended first=true second=Optional(true)@0.6 | body s=0@0.6
//       X2 exclusive (long press 0.3, then drag 0): press, move, move, release: upd first(true)@0.0 | body s=1@0.0 | upd first(true)@0.1 | body s=2@0.1 | ended first(true)@0.3 | body s=0@0.3
//       X2b exclusive: hold 0.5 (long press wins), move, release: upd first(true)@0.0 | body s=1@0.0 | ended first(true)@0.3 | body s=0@0.3
//   --- C: custom Gesture with a body
//       C1 HoldGesture (body is a long press 0.3 with its own onEnded): hold 0.5: inner ended@0.3
//       C2 HoldGesture().onEnded: Value is Bool: inner ended@0.3 | outer ended true@0.3
//       C3 HoldGesture().updating($s): upd true@0.0 | body s=1@0.0 | inner ended@0.3 | body s=0@0.3
//       C4 PressThenDrag (body is a sequence): onChanged/onEnded of the custom type: changed first(true)@0.0 | changed second(true, nil)@0.3 | changed second(true, start=(60.0,50.0) loc=(60.0,50.0) tr=(0.0,0.0))@0.5 | ended second(true, start=(60.0,50.0) loc=(60.0,50.0) tr=(0.0,0.0))@0.7
//       C5 custom ShiftedDrag in simultaneously(with: long press): inner changed | inner ended@0.3 | inner changed
//   --- D: DragGesture.Value time / velocity / predictedEnd (points are x,y,event-seconds; t= is v.time minus the probe's Date base)
//       D1 steady 10 pt / 0.02 s = 500 pt/s, real spin 0.02:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=30.0,50.0 vel=500.0,0.0 predTr=135.0,0.0 tr=10.0,0.0 predLoc=155.0,50.0
//           c t=-815028327.109 loc=40.0,50.0 vel=500.0,0.0 predTr=145.0,0.0 tr=20.0,0.0 predLoc=165.0,50.0
//           c t=-815028327.089 loc=50.0,50.0 vel=500.0,0.0 predTr=155.0,0.0 tr=30.0,0.0 predLoc=175.0,50.0
//           c t=-815028327.069 loc=60.0,50.0 vel=500.0,0.0 predTr=165.0,0.0 tr=40.0,0.0 predLoc=185.0,50.0
//           c t=-815028327.049 loc=70.0,50.0 vel=500.0,0.0 predTr=175.0,0.0 tr=50.0,0.0 predLoc=195.0,50.0
//           c t=-815028327.029 loc=80.0,50.0 vel=500.0,0.0 predTr=185.0,0.0 tr=60.0,0.0 predLoc=205.0,50.0
//           c t=-815028327.009 loc=90.0,50.0 vel=500.0,0.0 predTr=195.0,0.0 tr=70.0,0.0 predLoc=215.0,50.0
//           e t=-815028326.989 loc=100.0,50.0 vel=500.0,0.0 predTr=205.0,0.0 tr=80.0,0.0 predLoc=225.0,50.0
//       D2 steady 10 pt / 0.02 s event time, real spin 0.1 (decoupled):
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=30.0,50.0 vel=500.0,0.0 predTr=135.0,0.0 tr=10.0,0.0 predLoc=155.0,50.0
//           c t=-815028327.109 loc=40.0,50.0 vel=500.0,0.0 predTr=145.0,0.0 tr=20.0,0.0 predLoc=165.0,50.0
//           c t=-815028327.089 loc=50.0,50.0 vel=500.0,0.0 predTr=155.0,0.0 tr=30.0,0.0 predLoc=175.0,50.0
//           c t=-815028327.069 loc=60.0,50.0 vel=500.0,0.0 predTr=165.0,0.0 tr=40.0,0.0 predLoc=185.0,50.0
//           c t=-815028327.049 loc=70.0,50.0 vel=500.0,0.0 predTr=175.0,0.0 tr=50.0,0.0 predLoc=195.0,50.0
//           c t=-815028327.029 loc=80.0,50.0 vel=500.0,0.0 predTr=185.0,0.0 tr=60.0,0.0 predLoc=205.0,50.0
//           c t=-815028327.009 loc=90.0,50.0 vel=500.0,0.0 predTr=195.0,0.0 tr=70.0,0.0 predLoc=215.0,50.0
//           e t=-815028326.989 loc=100.0,50.0 vel=500.0,0.0 predTr=205.0,0.0 tr=80.0,0.0 predLoc=225.0,50.0
//       D3 steady 10 pt / 0.02 s event time, real spin 0:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=30.0,50.0 vel=500.0,0.0 predTr=135.0,0.0 tr=10.0,0.0 predLoc=155.0,50.0
//           c t=-815028327.109 loc=40.0,50.0 vel=500.0,0.0 predTr=145.0,0.0 tr=20.0,0.0 predLoc=165.0,50.0
//           c t=-815028327.089 loc=50.0,50.0 vel=500.0,0.0 predTr=155.0,0.0 tr=30.0,0.0 predLoc=175.0,50.0
//           c t=-815028327.069 loc=60.0,50.0 vel=500.0,0.0 predTr=165.0,0.0 tr=40.0,0.0 predLoc=185.0,50.0
//           c t=-815028327.049 loc=70.0,50.0 vel=500.0,0.0 predTr=175.0,0.0 tr=50.0,0.0 predLoc=195.0,50.0
//           c t=-815028327.029 loc=80.0,50.0 vel=500.0,0.0 predTr=185.0,0.0 tr=60.0,0.0 predLoc=205.0,50.0
//           c t=-815028327.009 loc=90.0,50.0 vel=500.0,0.0 predTr=195.0,0.0 tr=70.0,0.0 predLoc=215.0,50.0
//           e t=-815028326.989 loc=100.0,50.0 vel=500.0,0.0 predTr=205.0,0.0 tr=80.0,0.0 predLoc=225.0,50.0
//       D4 steady 2 pt / 0.02 s = 100 pt/s:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=22.0,50.0 vel=100.0,0.0 predTr=27.0,0.0 tr=2.0,0.0 predLoc=47.0,50.0
//           c t=-815028327.109 loc=24.0,50.0 vel=100.0,0.0 predTr=29.0,0.0 tr=4.0,0.0 predLoc=49.0,50.0
//           c t=-815028327.089 loc=26.0,50.0 vel=100.0,0.0 predTr=31.0,0.0 tr=6.0,0.0 predLoc=51.0,50.0
//           c t=-815028327.069 loc=28.0,50.0 vel=100.0,0.0 predTr=33.0,0.0 tr=8.0,0.0 predLoc=53.0,50.0
//           c t=-815028327.049 loc=30.0,50.0 vel=100.0,0.0 predTr=35.0,0.0 tr=10.0,0.0 predLoc=55.0,50.0
//           c t=-815028327.029 loc=32.0,50.0 vel=100.0,0.0 predTr=37.0,0.0 tr=12.0,0.0 predLoc=57.0,50.0
//           c t=-815028327.009 loc=34.0,50.0 vel=100.0,0.0 predTr=39.0,0.0 tr=14.0,0.0 predLoc=59.0,50.0
//           e t=-815028326.989 loc=36.0,50.0 vel=100.0,0.0 predTr=41.0,0.0 tr=16.0,0.0 predLoc=61.0,50.0
//       D5 steady 40 pt / 0.02 s = 2000 pt/s:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=60.0,50.0 vel=2000.0,0.0 predTr=540.0,0.0 tr=40.0,0.0 predLoc=560.0,50.0
//           c t=-815028327.109 loc=100.0,50.0 vel=2000.0,0.0 predTr=580.0,0.0 tr=80.0,0.0 predLoc=600.0,50.0
//           c t=-815028327.089 loc=140.0,50.0 vel=2000.0,0.0 predTr=620.0,0.0 tr=120.0,0.0 predLoc=640.0,50.0
//           c t=-815028327.069 loc=180.0,50.0 vel=2000.0,0.0 predTr=660.0,0.0 tr=160.0,0.0 predLoc=680.0,50.0
//           c t=-815028327.049 loc=220.0,50.0 vel=2000.0,0.0 predTr=700.0,0.0 tr=200.0,0.0 predLoc=720.0,50.0
//           c t=-815028327.029 loc=260.0,50.0 vel=2000.0,0.0 predTr=740.0,0.0 tr=240.0,0.0 predLoc=760.0,50.0
//           c t=-815028327.009 loc=300.0,50.0 vel=2000.0,0.0 predTr=780.0,0.0 tr=280.0,0.0 predLoc=800.0,50.0
//           e t=-815028326.989 loc=340.0,50.0 vel=2000.0,0.0 predTr=820.0,0.0 tr=320.0,0.0 predLoc=840.0,50.0
//       D6 accelerating: x = 20 + i^2*2, 0.02 s apart:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=22.0,50.0 vel=100.0,0.0 predTr=27.0,0.0 tr=2.0,0.0 predLoc=47.0,50.0
//           c t=-815028327.109 loc=28.0,50.0 vel=150.0,0.0 predTr=45.5,0.0 tr=8.0,0.0 predLoc=65.5,50.0
//           c t=-815028327.089 loc=38.0,50.0 vel=350.0,0.0 predTr=105.5,0.0 tr=18.0,0.0 predLoc=125.5,50.0
//           c t=-815028327.069 loc=52.0,50.0 vel=550.0,0.0 predTr=169.5,0.0 tr=32.0,0.0 predLoc=189.5,50.0
//           c t=-815028327.049 loc=70.0,50.0 vel=750.0,0.0 predTr=237.5,0.0 tr=50.0,0.0 predLoc=257.5,50.0
//           c t=-815028327.029 loc=92.0,50.0 vel=950.0,0.0 predTr=309.5,0.0 tr=72.0,0.0 predLoc=329.5,50.0
//           c t=-815028327.009 loc=118.0,50.0 vel=1150.0,0.0 predTr=385.5,0.0 tr=98.0,0.0 predLoc=405.5,50.0
//           e t=-815028326.989 loc=148.0,50.0 vel=1350.0,0.0 predTr=465.5,0.0 tr=128.0,0.0 predLoc=485.5,50.0
//       D7 moves 500 pt/s for 5 events, then stands still for 5 events at 0.02 s, release:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=30.0,50.0 vel=500.0,0.0 predTr=135.0,0.0 tr=10.0,0.0 predLoc=155.0,50.0
//           c t=-815028327.109 loc=40.0,50.0 vel=500.0,0.0 predTr=145.0,0.0 tr=20.0,0.0 predLoc=165.0,50.0
//           c t=-815028327.089 loc=50.0,50.0 vel=500.0,0.0 predTr=155.0,0.0 tr=30.0,0.0 predLoc=175.0,50.0
//           c t=-815028327.069 loc=60.0,50.0 vel=500.0,0.0 predTr=165.0,0.0 tr=40.0,0.0 predLoc=185.0,50.0
//           c t=-815028327.049 loc=60.0,50.0 vel=375.0,0.0 predTr=133.8,0.0 tr=40.0,0.0 predLoc=153.8,50.0
//           c t=-815028327.029 loc=60.0,50.0 vel=0.0,0.0 predTr=40.0,0.0 tr=40.0,0.0 predLoc=60.0,50.0
//           c t=-815028327.009 loc=60.0,50.0 vel=0.0,0.0 predTr=40.0,0.0 tr=40.0,0.0 predLoc=60.0,50.0
//           c t=-815028326.989 loc=60.0,50.0 vel=0.0,0.0 predTr=40.0,0.0 tr=40.0,0.0 predLoc=60.0,50.0
//           c t=-815028326.969 loc=60.0,50.0 vel=0.0,0.0 predTr=40.0,0.0 tr=40.0,0.0 predLoc=60.0,50.0
//           e t=-815028326.949 loc=60.0,50.0 vel=0.0,0.0 predTr=40.0,0.0 tr=40.0,0.0 predLoc=60.0,50.0
//       D8 moves 500 pt/s for 5 events, release 0.3 s later at the same spot:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=30.0,50.0 vel=500.0,0.0 predTr=135.0,0.0 tr=10.0,0.0 predLoc=155.0,50.0
//           c t=-815028327.109 loc=40.0,50.0 vel=500.0,0.0 predTr=145.0,0.0 tr=20.0,0.0 predLoc=165.0,50.0
//           c t=-815028327.089 loc=50.0,50.0 vel=500.0,0.0 predTr=155.0,0.0 tr=30.0,0.0 predLoc=175.0,50.0
//           c t=-815028327.069 loc=60.0,50.0 vel=500.0,0.0 predTr=165.0,0.0 tr=40.0,0.0 predLoc=185.0,50.0
//           e t=-815028326.769 loc=60.0,50.0 vel=375.0,0.0 predTr=133.8,0.0 tr=40.0,0.0 predLoc=153.8,50.0
//       D9 diagonal and downward: 10 right and 20 down per 0.02 s:
//           c t=-815028327.149 loc=20.0,20.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,20.0
//           c t=-815028327.129 loc=30.0,40.0 vel=500.0,1000.0 predTr=135.0,270.0 tr=10.0,20.0 predLoc=155.0,290.0
//           c t=-815028327.109 loc=40.0,60.0 vel=500.0,1000.0 predTr=145.0,290.0 tr=20.0,40.0 predLoc=165.0,310.0
//           c t=-815028327.089 loc=50.0,80.0 vel=500.0,1000.0 predTr=155.0,310.0 tr=30.0,60.0 predLoc=175.0,330.0
//           c t=-815028327.069 loc=60.0,100.0 vel=500.0,1000.0 predTr=165.0,330.0 tr=40.0,80.0 predLoc=185.0,350.0
//           c t=-815028327.049 loc=70.0,120.0 vel=500.0,1000.0 predTr=175.0,350.0 tr=50.0,100.0 predLoc=195.0,370.0
//           e t=-815028327.029 loc=80.0,140.0 vel=500.0,1000.0 predTr=185.0,370.0 tr=60.0,120.0 predLoc=205.0,390.0
//       D10 leftward 10 pt per 0.02 s:
//           c t=-815028327.149 loc=120.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=120.0,50.0
//           c t=-815028327.129 loc=110.0,50.0 vel=-500.0,0.0 predTr=-135.0,0.0 tr=-10.0,0.0 predLoc=-15.0,50.0
//           c t=-815028327.109 loc=100.0,50.0 vel=-500.0,0.0 predTr=-145.0,0.0 tr=-20.0,0.0 predLoc=-25.0,50.0
//           c t=-815028327.089 loc=90.0,50.0 vel=-500.0,0.0 predTr=-155.0,0.0 tr=-30.0,0.0 predLoc=-35.0,50.0
//           c t=-815028327.069 loc=80.0,50.0 vel=-500.0,0.0 predTr=-165.0,0.0 tr=-40.0,0.0 predLoc=-45.0,50.0
//           c t=-815028327.049 loc=70.0,50.0 vel=-500.0,0.0 predTr=-175.0,0.0 tr=-50.0,0.0 predLoc=-55.0,50.0
//           e t=-815028327.029 loc=60.0,50.0 vel=-500.0,0.0 predTr=-185.0,0.0 tr=-60.0,0.0 predLoc=-65.0,50.0
//       D11 slow start then fast: 8 events 1 pt/0.02 s, then 3 events 20 pt/0.02 s:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=21.0,50.0 vel=50.0,0.0 predTr=13.5,0.0 tr=1.0,0.0 predLoc=33.5,50.0
//           c t=-815028327.109 loc=22.0,50.0 vel=50.0,0.0 predTr=14.5,0.0 tr=2.0,0.0 predLoc=34.5,50.0
//           c t=-815028327.089 loc=23.0,50.0 vel=50.0,0.0 predTr=15.5,0.0 tr=3.0,0.0 predLoc=35.5,50.0
//           c t=-815028327.069 loc=24.0,50.0 vel=50.0,0.0 predTr=16.5,0.0 tr=4.0,0.0 predLoc=36.5,50.0
//           c t=-815028327.049 loc=25.0,50.0 vel=50.0,0.0 predTr=17.5,0.0 tr=5.0,0.0 predLoc=37.5,50.0
//           c t=-815028327.029 loc=26.0,50.0 vel=50.0,0.0 predTr=18.5,0.0 tr=6.0,0.0 predLoc=38.5,50.0
//           c t=-815028327.009 loc=27.0,50.0 vel=50.0,0.0 predTr=19.5,0.0 tr=7.0,0.0 predLoc=39.5,50.0
//           c t=-815028326.989 loc=47.0,50.0 vel=287.5,0.0 predTr=98.9,0.0 tr=27.0,0.0 predLoc=118.9,50.0
//           c t=-815028326.969 loc=67.0,50.0 vel=1000.0,0.0 predTr=297.0,0.0 tr=47.0,0.0 predLoc=317.0,50.0
//           e t=-815028326.949 loc=87.0,50.0 vel=1000.0,0.0 predTr=317.0,0.0 tr=67.0,0.0 predLoc=337.0,50.0
//       D12 one drag event only: press, one move of 30 pt after 0.05 s, release:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.099 loc=50.0,50.0 vel=600.0,0.0 predTr=180.0,0.0 tr=30.0,0.0 predLoc=200.0,50.0
//           e t=-815028327.089 loc=50.0,50.0 vel=450.0,0.0 predTr=142.5,0.0 tr=30.0,0.0 predLoc=162.5,50.0
//       D0: uptime=171953.5862625 nowTIRD=815200281.735396 1970=1793507481.7353969 | c tIRD=171952.35206316668 t1970=978479152.3520632 | e tIRD=171952.40206316666 | c tIRD=171953.84437683335 t1970=978479153.8443768 | e tIRD=171953.90156429168
//       D13 minimumDistance 10: slow 3 pt moves then 20 pt moves (does the estimator see pre-start moves?):
//           c t=-815028327.069 loc=49.0,50.0 vel=362.5,0.0 predTr=119.6,0.0 tr=29.0,0.0 predLoc=139.6,50.0
//           c t=-815028327.049 loc=69.0,50.0 vel=1000.0,0.0 predTr=299.0,0.0 tr=49.0,0.0 predLoc=319.0,50.0
//           e t=-815028327.029 loc=89.0,50.0 vel=1000.0,0.0 predTr=319.0,0.0 tr=69.0,0.0 predLoc=339.0,50.0
//       D14 duplicate timestamps: 20, 30 at 0.02, 40 at 0.02 (same), 50 at 0.04:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.129 loc=30.0,50.0 vel=500.0,0.0 predTr=135.0,0.0 tr=10.0,0.0 predLoc=155.0,50.0
//           c t=-815028327.129 loc=40.0,50.0 vel=1000.0,0.0 predTr=270.0,0.0 tr=20.0,0.0 predLoc=290.0,50.0
//           c t=-815028327.109 loc=50.0,50.0 vel=875.0,0.0 predTr=248.8,0.0 tr=30.0,0.0 predLoc=268.8,50.0
//           e t=-815028327.099 loc=50.0,50.0 vel=375.0,0.0 predTr=123.7,0.0 tr=30.0,0.0 predLoc=143.7,50.0
//       D15 press, then a move at the same timestamp as the press:
//           c t=-815028327.149 loc=20.0,50.0 vel=0.0,0.0 predTr=0.0,0.0 tr=0.0,0.0 predLoc=20.0,50.0
//           c t=-815028327.149 loc=30.0,50.0 vel=0.0,0.0 predTr=10.0,0.0 tr=10.0,0.0 predLoc=30.0,50.0
//           c t=-815028327.129 loc=40.0,50.0 vel=500.0,0.0 predTr=145.0,0.0 tr=20.0,0.0 predLoc=165.0,50.0
//           e t=-815028327.119 loc=40.0,50.0 vel=375.0,0.0 predTr=113.8,0.0 tr=20.0,0.0 predLoc=133.8,50.0
//
// READING.
//   S1: the sequence reports `.first(true)` at the PRESS (the long press's own change), `.second(true, nil)` when the
//   long press ENDS (0.3 s, still held), then `.second(true, drag)` for each drag change, `onEnded` at the release with
//   the last. The drag's startLocation is the location of the FIRST POINTER EVENT AFTER the long press ended (60,50 --
//   the first move), not the press (50,50) and not where the pointer was when the long press ended.
//   S2: with minimumDistance 10 the start is still the first event after (53,50: a 3 pt move), the report comes at 17 pt.
//   S5b: a move made BEFORE the long press ended (53) is not the start; the first event after is (90,50, tr 0).
//   S3, S5: a release before the minimum, or leaving maxDistance, fails the whole sequence: only `first(true)`, no
//   `onEnded`, nothing for a later drag. S4: held then released without moving, drag minimum 0: `onEnded
//   second(true, drag at the release point)` with NO change before it; S4b (minimum 10): nothing at all.
//   S6: `updating` runs on every reported value (first, second(nil), each drag change) before an `onChanged` declared
//   after it, one body per value; the state resets at the end (`body s=0`) and at a failure (S6b, at the release).
//   S7: `tap.sequenced(before: drag(min 0))`: the tap ends at the RELEASE and the drag, whose first event is that very
//   release, ends with it (`ended second ... start=loc=(50,50)`), one click is enough (S7b).
//   X1: a simultaneous composite reports ONCE PER EVENT, both members' latest values (`first=drag second=true`), the
//   long press's `true` kept after it ended (no update at 0.3 s); `onEnded` once at the release, `second=Optional(true)`.
//   X2, X2b: an exclusive composite whose long press wins reports `.first(true)` and ends `.first(true)`; the drag
//   behind it never reports (X2 shows ONE extra identical `upd first(true)` at the first move, 0.1 s -- unexplained,
//   not reproduced, divergence 925).
//   C1..C5: a struct with `var body: some Gesture` is a gesture; its body's callbacks run (C1); `onEnded` on it gets the
//   body's value (C2); `updating` works (C3, the state resets when the body's long press ends); a body that is a
//   sequence reports the sequence's value to the custom type's `onChanged`/`onEnded` (C4); it composes (C5). An opaque
//   `some Gesture` body makes `Value` unspellable, as in the compile error of the first draft of C4.
//   D0: `v.time` is `Date(timeIntervalSinceReferenceDate: event.timestamp)` -- tIRD 171952.352 for an event stamped
//   with the uptime 171952.352; never the wall clock (D2, D3 give the same lines as D1 whatever the real spin).
//   D1/D4/D5: a steady drag reads its speed from the second event on (500, 100, 2000 pt/s); the first event reads 0.
//   predictedEndTranslation = translation + velocity/4 (135 = 10 + 125; 27 = 2 + 25; 540 = 40 + 500) and
//   predictedEndLocation = location + velocity/4, on both axes (D9 y: 270 = 20 + 250), signed (D10).
//   VELOCITY = 0.75 * (previous interval's speed) + 0.25 * (this interval's speed), speeds being distance over the
//   difference of the two events' STAMPS: D6 reads 100, 150, 350, 550, ... for interval speeds 100, 300, 500, 700 (150 =
//   .75*100+.25*300); D7 reads 375 at the first still event (.75*500 + .25*0) and 0 at the next; D11 reads 287.5 at the
//   first burst event (.75*50 + .25*1000) then 1000; with one interval only (the first move) its speed alone (D12:
//   600 = 30/0.05), and the release is one more interval (D12: 450 = .75*600; D8: 375 at a release 0.3 s after the last
//   move -- it does NOT decay with time).
//   D13: moves made before the drag reaches minimumDistance feed the estimator (first report 362.5 = .75*150 + .25*1000).
//   D14, D15: an event stamped with the PREVIOUS event's instant REPLACES that sample (no division by zero): D14 reads
//   1000 for 20 pt in one interval then 875; D15's second event at the press's instant leaves velocity 0 and the next
//   reads 500 (the interval from the replaced sample); startLocation and translation still count from the press.
//   Not measured: a `time` against the wall clock at a real event (D0's second pair shows it tracks uptime), GestureMask
//   (`including:`), `sequenced` with a tap or a drag SECOND member's click count, a nested `sequenced(before:)`.
//
import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

nonisolated(unsafe) var currentArm = 0
func L(_ arm: Int, _ s: String) { if arm == currentArm { Log.add(s) } }

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    nonisolated(unsafe) static var t0 = Date()
    static func ts() -> String { String(format: "%.1f", Date().timeIntervalSince(t0)) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: " | ")
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

let side: CGFloat = 200

final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

@MainActor func makeWindow<V: View>(_ view: V) -> NSWindow {
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: side, height: side),
                      styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin(0.6)
    return w
}

func wp(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: side - y) }

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ pt: CGPoint, flags: NSEvent.ModifierFlags = [],
                      clicks: Int = 1) {
    let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: flags,
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clicks, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}

@MainActor func flags(_ w: NSWindow, _ f: NSEvent.ModifierFlags, key: UInt16) {
    let e = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: f,
                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                             context: nil, characters: "", charactersIgnoringModifiers: "",
                             isARepeat: false, keyCode: key)!
    if viaApp { NSApp.sendEvent(e) } else { w.sendEvent(e) }
    spin(0.15)
}
nonisolated(unsafe) var viaApp = false

func name(_ m: EventModifiers) -> String {
    var parts: [String] = []
    if m.contains(.shift) { parts.append("shift") }
    if m.contains(.command) { parts.append("command") }
    if m.contains(.option) { parts.append("option") }
    if m.contains(.control) { parts.append("control") }
    return parts.isEmpty ? "[]" : "[" + parts.joined(separator: ",") + "]"
}



// MARK: - Timestamped events

nonisolated(unsafe) var tsBase = ProcessInfo.processInfo.systemUptime
nonisolated(unsafe) var dateBase = Date()   // the Date at which systemUptime == tsBase
@MainActor func mouseT(_ w: NSWindow, _ t: NSEvent.EventType, _ pt: CGPoint, at s: Double, clicks: Int = 1) {
    let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: tsBase + s,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clicks, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}
func f1(_ x: CGFloat) -> String { String(format: "%.1f", Double(x)) }
func dragDesc(_ v: DragGesture.Value) -> String {
    "start=(\(f1(v.startLocation.x)),\(f1(v.startLocation.y))) loc=(\(f1(v.location.x)),\(f1(v.location.y))) tr=(\(f1(v.translation.width)),\(f1(v.translation.height)))"
}
func seqDesc(_ v: SequenceGesture<LongPressGesture, DragGesture>.Value) -> String {
    switch v {
    case .first(let b): return "first(\(b))"
    case .second(let b, let d): return "second(\(b), \(d.map(dragDesc) ?? "nil"))"
    }
}

@MainActor func viewArm<V: View>(_ label: String, _ v: V, _ steps: (NSWindow) -> Void) {
    let w = makeWindow(v)
    _ = Log.take(); Log.t0 = Date()
    steps(w)
    print("    \(label): \(Log.take())")
    w.close()
}

// MARK: - S: sequenced(before:)

struct SeqView: View {
    @GestureState var s = 0
    let lpMin: Double
    let dragMin: CGFloat
    let withUpdating: Bool
    var body: some View {
        let _ = Log.add("body s=\(s)@\(Log.ts())")
        let g = LongPressGesture(minimumDuration: lpMin, maximumDistance: 20)
            .sequenced(before: DragGesture(minimumDistance: dragMin))
        if withUpdating {
            Color.orange.frame(width: side, height: side).gesture(g
                .updating($s) { v, st, _ in st += 1; Log.add("upd \(seqDesc(v))@\(Log.ts())") }
                .onChanged { v in Log.add("changed \(seqDesc(v))@\(Log.ts())") }
                .onEnded { v in Log.add("ended \(seqDesc(v))@\(Log.ts())") })
        } else {
            Color.orange.frame(width: side, height: side).gesture(g
                .onChanged { v in Log.add("changed \(seqDesc(v))@\(Log.ts())") }
                .onEnded { v in Log.add("ended \(seqDesc(v))@\(Log.ts())") })
        }
    }
}
struct TapSeqView: View {
    var body: some View {
        Color.orange.frame(width: side, height: side).gesture(
            TapGesture().sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { v in
                    switch v {
                    case .first: Log.add("ended first@\(Log.ts())")
                    case .second(_, let d): Log.add("ended second \(d.map(dragDesc) ?? "nil")@\(Log.ts())")
                    }
                })
    }
}

// MARK: - Composite updating

struct SimView: View {
    @GestureState var s = 0
    var body: some View {
        let _ = Log.add("body s=\(s)@\(Log.ts())")
        Color.orange.frame(width: side, height: side).gesture(
            DragGesture(minimumDistance: 0).simultaneously(with: LongPressGesture(minimumDuration: 0.3, maximumDistance: 100))
                .updating($s) { v, st, _ in
                    st += 1
                    Log.add("upd first=\(v.first.map(dragDesc) ?? "nil") second=\(v.second.map { "\($0)" } ?? "nil")@\(Log.ts())")
                }
                .onChanged { v in Log.add("changed first=\(v.first != nil) second=\(String(describing: v.second))@\(Log.ts())") }
                .onEnded { v in Log.add("ended first=\(v.first != nil) second=\(String(describing: v.second))@\(Log.ts())") })
    }
}
struct ExcView: View {
    @GestureState var s = 0
    var body: some View {
        let _ = Log.add("body s=\(s)@\(Log.ts())")
        Color.orange.frame(width: side, height: side).gesture(
            LongPressGesture(minimumDuration: 0.3, maximumDistance: 100).exclusively(before: DragGesture(minimumDistance: 0))
                .updating($s) { v, st, _ in
                    st += 1
                    switch v {
                    case .first(let b): Log.add("upd first(\(b))@\(Log.ts())")
                    case .second(let d): Log.add("upd second \(dragDesc(d))@\(Log.ts())")
                    }
                }
                .onEnded { v in
                    switch v {
                    case .first(let b): Log.add("ended first(\(b))@\(Log.ts())")
                    case .second(let d): Log.add("ended second \(dragDesc(d))@\(Log.ts())")
                    }
                })
    }
}

// MARK: - Custom gestures

struct HoldGesture: Gesture {
    var seconds = 0.3
    var body: some Gesture {
        LongPressGesture(minimumDuration: seconds).onEnded { _ in Log.add("inner ended@\(Log.ts())") }
    }
}
struct PressThenDrag: Gesture {
    var body: SequenceGesture<LongPressGesture, DragGesture> {
        LongPressGesture(minimumDuration: 0.3, maximumDistance: 20).sequenced(before: DragGesture(minimumDistance: 0))
    }
}
struct ShiftedDrag: Gesture {
    var body: some Gesture { DragGesture(minimumDistance: 0).onChanged { _ in Log.add("inner changed") } }
}
struct CustomView<G: Gesture>: View {
    @GestureState var s = 0
    let make: (GestureState<Int>) -> G
    var body: some View {
        let _ = Log.add("body s=\(s)@\(Log.ts())")
        Color.orange.frame(width: side, height: side).gesture(make($s))
    }
}
@MainActor func customArm<G: Gesture>(_ label: String, _ make: @escaping (GestureState<Int>) -> G, _ steps: (NSWindow) -> Void) {
    viewArm(label, CustomView(make: make), steps)
}

// MARK: - D: drag value

struct DragValView: View {
    let label: String
    var minimum: CGFloat = 0
    let ref: Date
    var body: some View {
        Color.orange.frame(width: side, height: side).gesture(
            DragGesture(minimumDistance: minimum)
                .onChanged { v in Log.add(desc("c", v)) }
                .onEnded { v in Log.add(desc("e", v)) })
    }
    func desc(_ k: String, _ v: DragGesture.Value) -> String {
        let evt = v.time.timeIntervalSince(ref)
        return "\(k) t=\(String(format: "%.3f", evt)) loc=\(f1(v.location.x)),\(f1(v.location.y)) vel=\(f1(v.velocity.width)),\(f1(v.velocity.height)) predTr=\(f1(v.predictedEndTranslation.width)),\(f1(v.predictedEndTranslation.height)) tr=\(f1(v.translation.width)),\(f1(v.translation.height)) predLoc=\(f1(v.predictedEndLocation.x)),\(f1(v.predictedEndLocation.y))"
    }
}
/// `points` are (x, y, seconds-since-base); first is the press, last the release; `real` is the real spin between events.
@MainActor func dragArm(_ label: String, _ points: [(CGFloat, CGFloat, Double)], real: Double = 0.01, minimum: CGFloat = 0) {
    tsBase = ProcessInfo.processInfo.systemUptime + 0.0
    dateBase = Date()  // Date at tsBase
    let w = makeWindow(DragValView(label: label, minimum: minimum, ref: dateBase))
    _ = Log.take()
    tsBase = ProcessInfo.processInfo.systemUptime
    dateBase = Date()
    // rebuild the view with the right ref
    w.contentView = FirstMouseHost(rootView: DragValView(label: label, minimum: minimum, ref: dateBase)); spin(0.3)
    tsBase = ProcessInfo.processInfo.systemUptime; dateBase = Date()
    w.contentView = FirstMouseHost(rootView: DragValView(label: label, minimum: minimum, ref: dateBase)); spin(0.3)
    for (i, p) in points.enumerated() {
        let t: NSEvent.EventType = i == 0 ? .leftMouseDown : i == points.count - 1 ? .leftMouseUp : .leftMouseDragged
        mouseT(w, t, wp(p.0, p.1), at: p.2 + 1.0)   // events 1 s after base so they are in the "future" consistently
        spin(real)
    }
    spin(0.2)
    print("    \(label):")
    for l in Log.take().split(separator: "|") { print("        \(l.trimmingCharacters(in: .whitespaces))") }
    w.close()
}

func pts(_ a: [(Int, Int, Int, Double)]) -> [(CGFloat, CGFloat, Double)] { a.map { (CGFloat($0.1), CGFloat($0.2), $0.3) } }


@MainActor func rawTimeArm() {
    let w = makeWindow(RawTime())
    _ = Log.take()
    let up = ProcessInfo.processInfo.systemUptime
    Log.add("uptime=\(up) nowTIRD=\(Date().timeIntervalSinceReferenceDate) 1970=\(Date().timeIntervalSince1970)")
    mouseT(w, .leftMouseDown, wp(20, 50), at: 0); spin(0.05)
    mouseT(w, .leftMouseUp, wp(20, 50), at: 0.05); spin(0.2)
    mouse(w, .leftMouseDown, wp(20, 50)); spin(0.05); mouse(w, .leftMouseUp, wp(20, 50)); spin(0.2)
    print("    D0: \(Log.take())"); w.close()
}
struct RawTime: View {
    var body: some View {
        Color.orange.frame(width: side, height: side).gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in Log.add("c tIRD=\(v.time.timeIntervalSinceReferenceDate) t1970=\(v.time.timeIntervalSince1970)") }
            .onEnded { v in Log.add("e tIRD=\(v.time.timeIntervalSinceReferenceDate)") })
    }
}
@MainActor func run() {
  _ = NSApplication.shared
  NSApp.setActivationPolicy(.regular)
  NSApp.activate(ignoringOtherApps: true)
  spin(0.5)
  print("--- S: sequenced(before:) (long press 0.3 s, maxDistance 20) then drag")
  viewArm("S1 hold 0.5, move 10, move 30, release", SeqView(lpMin: 0.3, dragMin: 0, withUpdating: false)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5)
      mouse(w, .leftMouseDragged, wp(60, 50)); spin(0.15)
      mouse(w, .leftMouseDragged, wp(80, 50)); spin(0.15)
      mouse(w, .leftMouseUp, wp(80, 50)); spin(0.3)
  }
  viewArm("S2 drag minimumDistance 10: hold 0.5, move 3, move 20, release", SeqView(lpMin: 0.3, dragMin: 10, withUpdating: false)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5)
      mouse(w, .leftMouseDragged, wp(53, 50)); spin(0.15)
      mouse(w, .leftMouseDragged, wp(70, 50)); spin(0.15)
      mouse(w, .leftMouseUp, wp(70, 50)); spin(0.3)
  }
  viewArm("S3 release at 0.1 s (before the long press)", SeqView(lpMin: 0.3, dragMin: 0, withUpdating: false)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.1)
      mouse(w, .leftMouseUp, wp(50, 50)); spin(0.5)
  }
  viewArm("S4 hold 0.5, release without moving (drag min 0)", SeqView(lpMin: 0.3, dragMin: 0, withUpdating: false)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5)
      mouse(w, .leftMouseUp, wp(50, 50)); spin(0.3)
  }
  viewArm("S4b hold 0.5, release without moving (drag min 10)", SeqView(lpMin: 0.3, dragMin: 10, withUpdating: false)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5)
      mouse(w, .leftMouseUp, wp(50, 50)); spin(0.3)
  }
  viewArm("S5 pointer leaves maxDistance 20 at 0.15 s (before the long press), release at 0.5", SeqView(lpMin: 0.3, dragMin: 0, withUpdating: false)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.15)
      mouse(w, .leftMouseDragged, wp(120, 50)); spin(0.35)
      mouse(w, .leftMouseUp, wp(120, 50)); spin(0.3)
  }
  viewArm("S5b move 3 pt at 0.1, then 40 pt at 0.5 (after the long press ended): is drag start where?", SeqView(lpMin: 0.3, dragMin: 0, withUpdating: false)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.1)
      mouse(w, .leftMouseDragged, wp(53, 50)); spin(0.4)
      mouse(w, .leftMouseDragged, wp(90, 50)); spin(0.15)
      mouse(w, .leftMouseUp, wp(90, 50)); spin(0.3)
  }
  viewArm("S6 updating + onChanged + onEnded: hold 0.5, move, move, release", SeqView(lpMin: 0.3, dragMin: 0, withUpdating: true)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5)
      mouse(w, .leftMouseDragged, wp(60, 50)); spin(0.15)
      mouse(w, .leftMouseDragged, wp(80, 50)); spin(0.15)
      mouse(w, .leftMouseUp, wp(80, 50)); spin(0.3)
  }
  viewArm("S6b updating: release at 0.1 s (sequence fails)", SeqView(lpMin: 0.3, dragMin: 0, withUpdating: true)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.1)
      mouse(w, .leftMouseUp, wp(50, 50)); spin(0.5)
  }
  viewArm("S6c updating: hold 0.5, release without moving", SeqView(lpMin: 0.3, dragMin: 0, withUpdating: true)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5)
      mouse(w, .leftMouseUp, wp(50, 50)); spin(0.3)
  }
  viewArm("S7 tap.sequenced(before: drag 0): click, 0.1 s, press, move, release", TapSeqView()) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.05); mouse(w, .leftMouseUp, wp(50, 50)); spin(0.1)
      mouse(w, .leftMouseDown, wp(50, 50), clicks: 2); spin(0.1); mouse(w, .leftMouseDragged, wp(70, 50)); spin(0.1)
      mouse(w, .leftMouseUp, wp(70, 50), clicks: 2); spin(0.5)
  }
  viewArm("S7b tap.sequenced(before: drag 0): one click only", TapSeqView()) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.05); mouse(w, .leftMouseUp, wp(50, 50)); spin(0.6)
  }
  print("--- X: composed `updating` / onChanged / onEnded")
  viewArm("X1 simultaneous (drag 0, long press 0.3): press, move, hold to 0.5, move, release", SimView()) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.1)
      mouse(w, .leftMouseDragged, wp(60, 50)); spin(0.4)
      mouse(w, .leftMouseDragged, wp(70, 50)); spin(0.1)
      mouse(w, .leftMouseUp, wp(70, 50)); spin(0.3)
  }
  viewArm("X2 exclusive (long press 0.3, then drag 0): press, move, move, release", ExcView()) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.1)
      mouse(w, .leftMouseDragged, wp(60, 50)); spin(0.1)
      mouse(w, .leftMouseDragged, wp(70, 50)); spin(0.1)
      mouse(w, .leftMouseUp, wp(70, 50)); spin(0.3)
  }
  viewArm("X2b exclusive: hold 0.5 (long press wins), move, release", ExcView()) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5)
      mouse(w, .leftMouseDragged, wp(60, 50)); spin(0.1)
      mouse(w, .leftMouseUp, wp(60, 50)); spin(0.3)
  }
  print("--- C: custom Gesture with a body")
  customArm("C1 HoldGesture (body is a long press 0.3 with its own onEnded): hold 0.5", { _ in HoldGesture() }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5); mouse(w, .leftMouseUp, wp(50, 50)); spin(0.3)
  }
  customArm("C2 HoldGesture().onEnded: Value is Bool", { _ in HoldGesture().onEnded { v in Log.add("outer ended \(v)@\(Log.ts())") } }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5); mouse(w, .leftMouseUp, wp(50, 50)); spin(0.3)
  }
  customArm("C3 HoldGesture().updating($s)", { s in HoldGesture().updating(s) { v, st, _ in st = 1; Log.add("upd \(v)@\(Log.ts())") } }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5); mouse(w, .leftMouseUp, wp(50, 50)); spin(0.3)
  }
  customArm("C4 PressThenDrag (body is a sequence): onChanged/onEnded of the custom type", { _ in PressThenDrag().onChanged { v in Log.add("changed \(seqDesc(v))@\(Log.ts())") }.onEnded { v in Log.add("ended \(seqDesc(v))@\(Log.ts())") } }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5)
      mouse(w, .leftMouseDragged, wp(60, 50)); spin(0.15)
      mouse(w, .leftMouseUp, wp(60, 50)); spin(0.3)
  }
  customArm("C5 custom ShiftedDrag in simultaneously(with: long press)", { _ in ShiftedDrag().simultaneously(with: HoldGesture()) }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5)
      mouse(w, .leftMouseDragged, wp(60, 50)); spin(0.15)
      mouse(w, .leftMouseUp, wp(60, 50)); spin(0.3)
  }
  print("--- D: DragGesture.Value time / velocity / predictedEnd (points are x,y,event-seconds; t= is v.time minus the probe's Date base)")
  func steady(_ dt: Double, _ step: Int) -> [(CGFloat, CGFloat, Double)] {
      pts((0...8).map { ($0, 20 + $0 * step, 50, Double($0) * dt) })
  }
  dragArm("D1 steady 10 pt / 0.02 s = 500 pt/s, real spin 0.02", steady(0.02, 10), real: 0.02)
  dragArm("D2 steady 10 pt / 0.02 s event time, real spin 0.1 (decoupled)", steady(0.02, 10), real: 0.1)
  dragArm("D3 steady 10 pt / 0.02 s event time, real spin 0", steady(0.02, 10), real: 0.0)
  dragArm("D4 steady 2 pt / 0.02 s = 100 pt/s", steady(0.02, 2), real: 0.02)
  dragArm("D5 steady 40 pt / 0.02 s = 2000 pt/s", steady(0.02, 40), real: 0.02)
  dragArm("D6 accelerating: x = 20 + i^2*2, 0.02 s apart", pts((0...8).map { ($0, 20 + $0 * $0 * 2, 50, Double($0) * 0.02) }), real: 0.02)
  dragArm("D7 moves 500 pt/s for 5 events, then stands still for 5 events at 0.02 s, release", pts((0...4).map { ($0, 20 + $0 * 10, 50, Double($0) * 0.02) } + (5...9).map { ($0, 60, 50, Double($0) * 0.02) } + [(10, 60, 50, 0.20)]), real: 0.02)
  dragArm("D8 moves 500 pt/s for 5 events, release 0.3 s later at the same spot", pts((0...4).map { ($0, 20 + $0 * 10, 50, Double($0) * 0.02) } + [(5, 60, 50, 0.38)]), real: 0.02)
  dragArm("D9 diagonal and downward: 10 right and 20 down per 0.02 s", pts((0...6).map { ($0, 20 + $0 * 10, 20 + $0 * 20, Double($0) * 0.02) }), real: 0.02)
  dragArm("D10 leftward 10 pt per 0.02 s", pts((0...6).map { ($0, 120 - $0 * 10, 50, Double($0) * 0.02) }), real: 0.02)
  dragArm("D11 slow start then fast: 8 events 1 pt/0.02 s, then 3 events 20 pt/0.02 s", pts((0...7).map { ($0, 20 + $0, 50, Double($0) * 0.02) } + (8...10).map { ($0, 27 + ($0 - 7) * 20, 50, Double($0) * 0.02) }), real: 0.02)
  dragArm("D12 one drag event only: press, one move of 30 pt after 0.05 s, release", [(20, 50, 0), (50, 50, 0.05), (50, 50, 0.06)], real: 0.02)
  rawTimeArm()
  dragArm("D13 minimumDistance 10: slow 3 pt moves then 20 pt moves (does the estimator see pre-start moves?)", pts((0...3).map { ($0, 20 + $0 * 3, 50, Double($0) * 0.02) } + (4...6).map { ($0, 29 + ($0 - 3) * 20, 50, Double($0) * 0.02) }), real: 0.02, minimum: 10)
  dragArm("D14 duplicate timestamps: 20, 30 at 0.02, 40 at 0.02 (same), 50 at 0.04", [(20, 50, 0), (30, 50, 0.02), (40, 50, 0.02), (50, 50, 0.04), (50, 50, 0.05)], real: 0.02)
  dragArm("D15 press, then a move at the same timestamp as the press", [(20, 50, 0), (30, 50, 0), (40, 50, 0.02), (40, 50, 0.03)], real: 0.02)
}
MainActor.assumeIsolated { run() }

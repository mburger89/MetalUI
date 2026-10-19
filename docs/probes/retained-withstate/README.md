# Retained read-only state (C14b-3): measurement

The Prof harness named in the lane brief (`/private/tmp/claude-501/profiling/Prof`) is not on this machine; the repository's own
harness, `docs/probes/perf-harness` driven by `docs/probes/perf-baselines.sh`, carries the scenario instead:

    zsh docs/probes/perf-baselines.sh release --quick bracketorbit      # 3 rounds x 20 frames
    zsh docs/probes/perf-baselines.sh release bracketorbit              # 8 rounds x 40 frames

`bracketorbit` is the `.panels` arm of `BracketFixture` (1440 x 900 at scale 2) with nothing in the panels changing; each frame bumps
the viewport token (the `GPUSurface`'s `value:`), asks for a redraw and draws, which is what an orbit does. It prints the machine
line, the load average, the wall and thread-CPU median and minimum of an orbit frame and the last frame's work line.

**Reading.** A figure is a dated measurement on a shared Mac, never a pin; counts are the pins
(`Tests/MetalUITestingTests/RetainedWithStateTests.swift`). For base versus head run the script from a `git archive f557d339` tree and
from the head, alternating, three runs each, and note the load average. Results are recorded in record 121.

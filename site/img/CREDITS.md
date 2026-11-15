# Image credits

All images are real captures, none edited. Captured 2026-11-15 on a Mac (Apple Silicon, dark system appearance, 1x display).

| File | Shows | How |
| --- | --- | --- |
| `myapp-macos.webp` | `metalui new MyApp` scaffold, first launch, 640x428 | `scripts/site-capture.sh` (window by id, no input sent) |
| `jotter-macos.webp` | `Examples/Jotter` with its built-in sample notes, 900x652 | `scripts/site-capture.sh` |
| `demo-linux.webp` | The MetalUIDemo scene drawn on Linux by the SDL backend on Vulkan (Mesa llvmpipe), 920x560. It is the demo, not MyApp: no headless MyApp render path exists without new code | `Replay --portable --record` on macOS, then `DemoCapture --driver vulkan --dump` in the `metalui-portable` image; raw BGRA converted to PNG |
| `metalcreator.webp` | MetalCreator editing a demo bracket graph, 1440x932 | Window capture by the coordinator, demo project only |
| `metalflow.webp` | MetalFlow Flow Studio with a demo flow, 1440x928 | Window capture by the coordinator, demo content only |
| `alloy.webp` | Pending: Alloy capture to come from the coordinator | n/a |

No Windows image: the VM is unavailable and nothing is faked.

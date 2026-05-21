# love2d-mod-player
A MOD player made in love2d (lua) without additional dependencies

---

```
local USE_SOFTWARE_LOOP = true
```

Set to `false` for [LoveDOS](https://github.com/rxi/lovedos) (lovedos we don't have enough compute power). No other code change is needed to switch modes.

---

## The seek formula note

If you find your LÖVE2D build's `seek()` takes **source-data seconds** (`frame / 8363`) rather than wall-clock seconds, change the single seek line to:
```lua
ch.source:seek(ch.sampleFramePos / 8363, "seconds")
```
This is easy to test: at C-2 (period 428, pitch 1.0) both formulae are identical, so any loop that works at C-2 but drifts at other notes confirms the pitch-corrected form is needed.
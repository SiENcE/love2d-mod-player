# love2d-mod-player
A MOD player made in love2d (lua) without additional dependencies

---

### Cannot Fix

Notable gap (architectural — not fixed)
The software-loop approach (`source:tell()` / `source:seek()`) computes loop times in seconds at the **sample's base rate** (8363 Hz), but LÖVE's `tell()` returns playback time *after* the pitch factor applied by `setPitch(428/period)`. This means loop points will drift at any pitch other than C-2. A correct fix requires software mixing with exact sample-frame tracking, which is outside the scope of a targeted patch.
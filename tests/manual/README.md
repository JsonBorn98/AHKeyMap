# Manual Phase-2 End-to-End Checks

These scenarios stay outside the blocking CI lane for now because they depend on real desktop input timing and application-specific behavior.

Run them locally after hotkey-engine changes that affect real input routing:

1. Global hotkey behavior against a simple target app such as Notepad.
2. Path B mouse-modifier restore behavior for `MButton` / `XButton1` / `XButton2`.
3. Path C `RButton` gesture plus wheel behavior in browsers and canvas-style web apps.
4. Focus-switch timing and include/exclude scope behavior while changing the active window quickly.

When one of these scenarios becomes stable enough to automate reliably, add a new `*.test.ahk` case under `tests/gui/` or move it to a dedicated self-hosted runner lane.

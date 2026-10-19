# Bordr bug reports

## Crash: EXC_BAD_ACCESS when clearing all images

- **Date:** 2026-10-18
- **Status:** fixed (`90adfac` on `main`)
- **Affected:** `bordr/AppViewModel.swift`
- **Crash signature:**
  `Thread 1: EXC_BAD_ACCESS (code=2, address=0x16...)` /
  `Segmentation fault: 11`, top frame
  `AppViewModel._currentImageIndex.didset()`

### Symptom

Clicking **Clear All** in the sidebar (or otherwise calling
`AppViewModel.clearImages()`) terminated the app. Reproduced deterministically
by auto-calling `clearImages()` shortly after launch.

### Root cause

`currentImageIndex` had a `didSet` that clamped the index by assigning back to
`currentImageIndex`:

```swift
var currentImageIndex: Int = 0 {
    didSet {
        let maxIndex = max(originalImages.count, processedImages.count) - 1
        if maxIndex < 0 { currentImageIndex = 0 }        // <-- recursive
        else if currentImageIndex > maxIndex { currentImageIndex = maxIndex }
        // ...
    }
}
```

Under the `@Observable` macro the property becomes a computed property backed
by `_currentImageIndex`, so that self-assignment re-enters the generated setter
and `didSet` fires again, recursing until the stack overflows. A plain stored
property does not recurse here — the macro is what makes it fatal — which is why
the pattern looks harmless.

The crash trace under lldb:

```
stop reason = EXC_BAD_ACCESS (code=2, address=0x16f603ff8)
frame #0: AppViewModel._currentImageIndex.didset()
```

### Fix

Removed the `didSet`. The index does not need write-time clamping:

- reads are clamped in `currentOriginalImage` / `currentProcessedImage`
- every writer (`selectPrevious`, `selectNext`, `load`, `removeImage`,
  processing) already clamps

### Verification

- `bordrTests/clearingImagesDoesNotRecurse` — instantiates `AppViewModel`,
  calls `clearImages()`, asserts the arrays empty and index `0`.
- UI test: load 3 images, click **Clear All**, assert the empty state appears.
- Cleared images repeatedly in the running app without a crash.

### Rule to remember

Never assign to a property inside its own `didSet` when the type is
`@Observable`. Clamp at the call sites or at read time instead.

---

## Known issues (not fixed)

- **Main-thread file IO** — `AppViewModel.load(urls:replacing:)` reads every
  selected file with `Data(contentsOf:)` on the main thread; large selections
  can briefly beachball.
- **Stale renders are dropped, not cancelled** — processing uses a
  `processGeneration` token, so late results are ignored, but the underlying
  `magick` process still runs to completion.
- **Parallel arrays** — `originalImages`, `inputImageURLs` and
  `processedImages` are kept in sync by index; a single
  `[ImageItem]{url, image}` would remove the invariant.

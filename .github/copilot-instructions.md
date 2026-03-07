# ClipForge Project Guidelines

## Code Style
- Use Swift 5.9-compatible code and keep changes compatible with strict concurrency (`StrictConcurrency` is enabled in `Package.swift`).
- Keep mutable app state in `@MainActor` view models (`ClipForgeViewModel`) and use local `@State` only for transient UI state.
- Keep timeline geometry normalized to `0...1` coordinates for stored model data (zoom centers, annotation positions/sizes).
- Preserve `Codable` model compatibility. When adding model fields, provide sensible defaults so older project files can still decode.
- Keep platform-specific behavior behind `#if canImport(AppKit)` / `#if canImport(UIKit)` guards.

## Architecture
- `Sources/ClipForge/Models`: Serializable project data (`ClipForgeProject`, `ZoomSegment`, `Annotation`, `BackgroundSettings`).
- `Sources/ClipForge/ViewModels`: Coordination layer for playback, persistence, and export (`ClipForgeViewModel`).
- `Sources/ClipForge/Views`: SwiftUI UI and interaction logic (`ContentView`, timeline/editor controls, player wrappers).
- `Sources/ClipForge/Export`: AVFoundation/Core Animation export pipeline (`ExportEngine`).
- Keep boundaries clear: views should not reimplement export or persistence logic that belongs in `ClipForgeViewModel`/`ExportEngine`.

## Build and Test
- Primary validation command: `swift build`
- Release app install for macOS: `./install.command` (or `./install.command --open`)
- There is no dedicated test target yet. For feature work, run at least `swift build` and include a manual smoke check path in your notes.

## Conventions
- Projects are persisted under `~/Documents/ClipForge/<ProjectName>/` with a `.clipforge` JSON file and a copied source video.
- Keep preview/export behavior aligned. If editing zoom or annotation behavior in UI/timeline code, update `ExportEngine` logic as needed so exported output matches preview intent.
- Maintain cross-platform wrappers and stubs (for example, `ShareSheet` and player view wrappers) instead of removing platform guards.
- Be careful when editing macOS window behavior in `ContentView`; start-screen/editor window configuration is intentionally different.

## Key Files
- `Package.swift`
- `Sources/ClipForge/ViewModels/ClipForgeViewModel.swift`
- `Sources/ClipForge/Export/ExportEngine.swift`
- `Sources/ClipForge/Views/ContentView.swift`
- `Sources/ClipForge/Views/VisualTimelineView.swift`

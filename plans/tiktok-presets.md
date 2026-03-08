**Implementation Plan: Adding TikTok Style Subtitle Preset**  
### Goal
One-tap “TikTok 🔥” button that instantly applies the viral social-media look to all generated subtitles:
- Huge bold white (or bright yellow) text
- Thick black outline + heavy drop shadow
- Semi-transparent black background box
- Perfect lower-third positioning for vertical videos
- Auto-scales to any resolution

Total new code: under 150 lines. Takes ~2–3 hours max.

### Step 1: Add the TikTok Presets
Paste this extension right next to your existing `SubtitleStyle` struct:

```swift
extension SubtitleStyle {
    static let tikTok = SubtitleStyle(
        fontName: "Helvetica-Bold",
        fontSize: 52,
        textColor: .white,
        outlineColor: .black,
        outlineWidth: 7.0,
        backgroundColor: .black.withAlphaComponent(0.78),
        backgroundPadding: 18,
        shadowColor: .black,
        shadowBlur: 5,
        shadowOffset: CGSize(width: 0, height: 4),
        alignment: .center,
        verticalPosition: 0.87,
        horizontalMargin: 0.06,
        autoScaleToFit: true
    )
    
    static let tikTokYellow = SubtitleStyle(
        fontName: "Helvetica-Bold",
        fontSize: 52,
        textColor: UIColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1.0),
        outlineColor: .black,
        outlineWidth: 7.0,
        backgroundColor: .black.withAlphaComponent(0.75),
        backgroundPadding: 18,
        shadowColor: .black,
        shadowBlur: 5,
        shadowOffset: CGSize(width: 0, height: 4),
        alignment: .center,
        verticalPosition: 0.87,
        horizontalMargin: 0.06,
        autoScaleToFit: true
    )
}
```

### Step 2: Make TikTok the Default Style
Find where you create the style for a new subtitle job and change it to:

```swift
var selectedStyle: SubtitleStyle = .tikTok   // ← one-line change
```

### Step 3: Add One-Tap Buttons in the Style Selection Screen
In your style picker UI (SwiftUI), add this section at the top:

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 12) {
        Button("TikTok 🔥") {
            selectedStyle = .tikTok
            updateLivePreview()   // your existing preview refresh
        }
        .buttonStyle(.borderedProminent)
        .tint(.black)
        
        Button("TikTok Yellow") {
            selectedStyle = .tikTokYellow
            updateLivePreview()
        }
        .buttonStyle(.borderedProminent)
        .tint(.yellow)
    }
    .padding(.horizontal)
}
```

### Step 4: Connect the Style to Export (one line)
In the place where you call the subtitle applicator function, make sure it uses the selected style:

```swift
applyStyledSubtitles(
    to: videoComposition,
    segments: segments,
    style: selectedStyle,           // ← already points to .tikTok by default
    videoSize: asset.videoSize
)
```

### Step 5: Quick Polish (optional but recommended)
- In the same style picker, add a small live preview player so users instantly see how it looks on their video.
- Store the last used preset with `UserDefaults` so it remembers “TikTok” next time.
- Show a tiny tooltip on first launch: “One tap for viral-ready captions”.

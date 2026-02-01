# Video Effects Studio

A cross-platform video effects processor featuring modes like Purple Vocoder, Cursed Christmas, Sparta Pitch, and more. Originally based on NotSoBot tag commands, now available as a native application for all devices.

![Video Effects Studio](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20iOS%20%7C%20Web-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.19+-02569B?logo=flutter)
![License](https://img.shields.io/badge/License-MIT-green)
![Build Status](https://github.com/1ajh/srle-studio/actions/workflows/ci.yml/badge.svg)

## ✨ Features

- 🎬 **40+ Video Effects** - Vocoders, G Majors, Color Grading, Glitch, Audio Effects, YTPMV tools
- 📁 **Batch Processing** - Process multiple videos at once
- 🖱️ **Drag & Drop** - Simply drag videos into the app
- 📱 **Cross-Platform** - Works on Windows, macOS, Linux, Android, iOS, and Web
- 🔄 **Auto Updates** - Automatically checks for new versions from GitHub
- ⚙️ **Customizable Parameters** - Adjust effect settings to your liking
- 🎨 **Modern UI** - Beautiful dark theme with intuitive controls
- 📊 **Processing History** - Track all your processed videos
- ⭐ **Favorites** - Save your most-used effects
- 📱 **Responsive Design** - Optimized layouts for mobile, tablet, and desktop
- ⚡ **Real-time Preview** - See effect parameters before processing

## 🎭 Available Effects

### Vocoder Effects (12 effects)
- Purple Vocoder - Classic vocoder with purple tint
- Techno - Electronic dance music vocoder
- Gansta - Hip-hop style vocoder
- Xtal Vocoder - Crystal-clear vocoder effect
- Daft Vocoder - Inspired by Daft Punk's sound
- Electric - High voltage electronic voice
- CapCut Robot Effect - TikTok-style robot voice
- White Robotic Dimension - Ethereal robot vocals
- Discord Electronic Sounds - Discord call glitch effect
- Yellow Vocoder - Warm vocoder tones
- Chromatic Vocoder - Multi-colored vocoder
- Glitch Vocoder - Corrupted vocoder sound

### Color Grading (6 effects)
- Loud Rainbow - Vibrant color cycling
- Fast Color - Rapid hue rotation
- Blue Distorted Pitches - Blue-tinted distortion
- Grayscale - Black and white conversion
- Sepia - Vintage brown tones
- Posterize - Reduce color levels

### Glitch & Distortion (14 effects)
- G Major - Classic G Major effect
- G Major Kyoobur9000 - Kyoobur style
- G Major Adrian Sparino V2 - Adrian Sparino variant
- G Major 2 LTV MCA - LTV MCA series
- G Major 3 LTV MCA - LTV MCA series
- G Major Alapat1 - Alapat1's version
- Congabusher - Rhythm distortion
- Cursed Christmas V2 - Holiday horror
- JCTOTBOI G Major - JCTOTBOI style
- VHS Effect - Retro VHS tape look
- Camera Shake - Earthquake effect
- Edge Detection - Outline extraction
- Night Vision - Green military look
- Thermal Camera - Heat map view

### Audio Effects (8 effects)
- Pitch Shift (-12 to +12 semitones)
- Pitch Maker (with WAV export option)
- Bass Boost - Enhanced low frequencies
- Earrape - Extreme distortion (⚠️ loud!)
- Echo - Delay/echo effect
- Reverb - Room ambience
- Chipmunk - High-pitched voice
- Deep Voice - Low-pitched voice

### YTPMV Tools (4 effects)
- Sparta Pitch - Customizable pitch sequences
- YTPMV Base - Basic YTPMV template
- Stutter Effect - Rapid repeat/stutter
- Reverse - Play video backwards

### Speed & Transform (4 effects)
- Speed Up (2x) - Double speed
- Slow Down (0.5x) - Half speed
- Mirror Horizontal - Left-right flip
- Mirror Vertical - Top-bottom flip

### Other (3 effects)
- Diamond Video - 4-way rotation overlay
- Negative - Inverted colors
- Pixelate - Retro pixel effect

## 📥 Installation

### Pre-built Releases

Download the latest release for your platform from the [Releases](https://github.com/1ajh/srle-studio/releases) page.

| Platform | Download | Requirements | Status |
|----------|----------|--------------|--------|
| Windows | `VideoEffectsStudio-windows.zip` | Windows 10/11 | ✅ Available |
| Linux | `VideoEffectsStudio-linux.tar.gz` | GTK 3.0+ | ✅ Available |
| Web | [web.app](https://1ajh.github.io/srle-studio) | Modern browser | ✅ Available |
| macOS | `VideoEffectsStudio-macos.dmg` | macOS 10.14+ | ⚠️ Build from source |
| Android | `app-release.apk` | Android 6.0+ | ⚠️ Build from source |
| iOS | `VideoEffectsStudio-ios.ipa` | iOS 12.0+ | ⚠️ Build from source |

> **Note**: Android, iOS, and macOS builds are temporarily unavailable due to upstream FFmpeg library issues. You can build these platforms from source.

> **FFmpeg is bundled with the application** - no separate installation required! Just download and run.

### Build from Source

#### Prerequisites

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (3.24 or higher)
2. Install platform-specific dependencies:

**Windows:**
```bash
# Visual Studio with C++ Desktop development workload
```

**macOS:**
```bash
xcode-select --install
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

**Linux:**
```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

#### Building

```bash
# Clone the repository
git clone https://github.com/1ajh/srle-studio.git
cd srle-studio

# Install dependencies
flutter pub get

# Run in development mode
flutter run

# Build for specific platforms
flutter build windows --release
flutter build macos --release
flutter build linux --release
flutter build apk --release
flutter build ios --release --no-codesign
flutter build web --release
```

## 🚀 Usage

1. **Select Files**: Drag and drop video files into the left panel, or click to browse
2. **Choose Effect**: Browse or search effects in the middle panel, click to select
3. **Adjust Parameters**: If the effect has customizable parameters, adjust them in the right panel
4. **Process**: Click "Process Video" (or "Process X Files" for batch)
5. **View Results**: When complete, open the output folder to find your processed videos

### Keyboard Shortcuts (Desktop)

| Shortcut | Action |
|----------|--------|
| `Ctrl/Cmd + O` | Open file |
| `Ctrl/Cmd + Enter` | Process video |
| `Ctrl/Cmd + ,` | Open settings |
| `Ctrl/Cmd + H` | View history |
| `Escape` | Cancel/Close dialog |

## 🧩 Adding New Effects

Effects are defined in `lib/models/effects_registry.dart`. To add a new effect:

```dart
EffectMode(
  id: 'my_new_effect',
  name: 'My New Effect',
  description: 'Description of what it does',
  category: 'Glitch', // Vocoder, Color Grading, Glitch, Audio, YTPMV, Other
  ffmpegFilter: '-vf "your_filter=param1:param2" -af "audio_filter"',
  parameters: [
    EffectParameter(
      id: 'intensity',
      name: 'Intensity',
      description: 'How strong the effect is',
      type: ParameterType.slider,
      defaultValue: 1.0,
      minValue: 0.0,
      maxValue: 2.0,
    ),
  ],
),
```

### Parameter Types

- `ParameterType.slider` - Numeric slider with min/max values
- `ParameterType.dropdown` - Selection from predefined options
- `ParameterType.toggle` - Boolean on/off switch
- `ParameterType.text` - Free text input
- `ParameterType.color` - Color picker

## Remote Effects Updates

The app can fetch new effects from a remote JSON file without requiring an app update. Create an `effects_registry.json` file in your GitHub repo:

```json
{
  "version": "1.1.0",
  "effects": [
    {
      "id": "new_remote_effect",
      "name": "New Remote Effect",
      "description": "Added via remote update",
      "category": "other",
      "command_template": "ffmpeg -i \"$INPUT\" -vf \"negate\" \"$OUTPUT\""
    }
  ]
}
```

## 📁 Project Structure

```
srle-studio/
├── lib/
│   ├── main.dart                  # App entry point & responsive router
│   ├── models/
│   │   ├── effect_mode.dart       # Effect & Parameter data models
│   │   ├── effects_registry.dart  # All 40+ effects definitions
│   │   └── models.dart            # Barrel exports
│   ├── screens/
│   │   ├── home_screen.dart       # Desktop layout (>900px)
│   │   ├── tablet_home_screen.dart # Tablet layout (600-900px)
│   │   ├── mobile_home_screen.dart # Mobile layout (<600px)
│   │   ├── settings_screen.dart   # User preferences
│   │   ├── history_screen.dart    # Processing history
│   │   ├── about_screen.dart      # App information
│   │   └── help_screen.dart       # Help & FAQ
│   ├── services/
│   │   ├── app_state.dart         # Provider state management
│   │   ├── ffmpeg_service.dart    # FFmpeg video processing
│   │   ├── preferences_service.dart # Persistent settings
│   │   └── update_service.dart    # Auto-update from GitHub
│   └── widgets/
│       ├── effect_card.dart       # Effect selection card
│       ├── file_drop_zone.dart    # Drag & drop zone
│       ├── parameter_editor.dart  # Effect parameter controls
│       ├── processing_dialog.dart # Progress indicator
│       └── update_banner.dart     # Update notification
├── assets/
│   ├── icons/                     # App icons
│   └── modes/                     # Effect previews
├── test/                          # Unit & widget tests
├── android/                       # Android platform config
├── ios/                           # iOS platform config
├── macos/                         # macOS platform config
├── windows/                       # Windows platform config
├── linux/                         # Linux platform config
├── web/                           # Web platform config
└── pubspec.yaml                   # Dependencies
```

## ⚠️ Technical Notes

### Platform-Specific Features

| Feature | Desktop | Mobile | Web |
|---------|---------|--------|-----|
| Drag & Drop | ✅ | ❌ | ✅ |
| Batch Processing | ✅ | ✅ | ⚠️ Limited |
| File System Access | ✅ Full | ✅ Scoped | ⚠️ Download only |
| FFmpeg Processing | ✅ Full | ✅ Full | ⚠️ WASM (limited) |
| Background Processing | ✅ | ⚠️ Limited | ❌ |
| Notifications | ✅ | ✅ | ⚠️ Browser dependent |

### Desktop-Only Effects

Some effects (marked with 🖥️) require desktop platforms because they use:
- Wine (for autotune.exe vocoder effects)
- System-level audio processing
- Large memory allocations

On mobile/web, these effects may show a limited version or be disabled.

### FFmpeg Commands

All effects are powered by FFmpeg through the `ffmpeg_kit_flutter` package. The original NotSoBot shell commands have been converted to pure FFmpeg filter chains for cross-platform compatibility.

### Video Output Encoding

Output videos are optimized for sharing:
- **Video**: H.264 (libx264) with preset `medium`
- **Audio**: AAC at 192kbps
- **Container**: MP4 with `-movflags +faststart` for web streaming
- **Resolution**: Maintains original (or custom via settings)

This ensures videos will embed properly in Discord, Twitter, and other platforms.

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/models/effects_test.dart
```

## 🔄 CI/CD

This project uses GitHub Actions for continuous integration:

- **CI Workflow**: Runs on every push/PR to `main` and `develop`
  - Code formatting check
  - Static analysis
  - Unit tests
  - Debug build verification

- **Build Workflow**: Runs on version tags (`v*`)
  - Builds for all 6 platforms
  - Creates GitHub Release with all artifacts
  - Auto-generates release notes

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-effect`
3. Make your changes and add tests
4. Run tests: `flutter test`
5. Format code: `dart format .`
6. Commit your changes: `git commit -am 'Add new effect'`
7. Push to the branch: `git push origin feature/new-effect`
8. Submit a Pull Request

### Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/srle-studio.git
cd srle-studio

# Add upstream remote
git remote add upstream https://github.com/1ajh/srle-studio.git

# Install dependencies
flutter pub get

# Run the app
flutter run -d chrome  # or windows, macos, linux
```

## 📜 Credits

- **AJH** - Original NotSoBot tags and app development
- **GanerCodes** - AutotuneBot/autotune.exe
- **FFmpeg** - Video processing engine
- **Flutter** - Cross-platform framework
- **flutter_ffmpeg** - FFmpeg bindings for Flutter

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

<p align="center">
  Made with ❤️ by AJH
  <br>
  <a href="https://github.com/1ajh/srle-studio/issues">Report Bug</a>
  ·
  <a href="https://github.com/1ajh/srle-studio/issues">Request Feature</a>
  ·
  <a href="https://github.com/1ajh/srle-studio/discussions">Discussions</a>
</p>

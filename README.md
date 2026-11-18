# File Wheel

File Wheel is a macOS menu-bar app for converting and editing files on the machine where they already live. It has no main window.

Hold Shift and drag a file in Finder. A wheel of output formats appears around the pointer. Drop on a wedge and File Wheel writes a new file beside the original. Hold Option as well to switch the wheel to tools for that kind of file. The original is never modified.

Arrow keys move the selection, Return applies it, and Escape cancels. Several compatible files can be dropped at once. A progress window shows each job and can reveal the finished files in Finder.

## Features

- Image, audio, video, PDF, text, subtitle, and archive conversions.
- Tools for the file you dropped, including compress, crop, trim, metadata, PDF merge and split, OCR, a visual signature, protect and unlock, and archive pack and extract.
- Read aloud, which writes an MP3 beside a text, Markdown, PDF, Word, or subtitle file. It can use a macOS voice, a local model, or optional xAI text-to-speech.

About shows the formats and tools this build can actually run.

## Requirements

- macOS 13 or later
- Apple silicon

FFmpeg and unar are not included. Install them with Homebrew:

```sh
brew install ffmpeg unar
```

File Wheel looks for `ffmpeg` and `unar` in `/opt/homebrew/bin`, `/usr/local/bin`, and `/usr/bin`. If either tool is missing, the app tells you to run `brew install ffmpeg unar`. `FILEWHEEL_FFMPEG` and `FILEWHEEL_UNAR` can point at another copy.

RAR files can be extracted when unar is installed. File Wheel does not create RAR archives.

## Build

Open `FileWheel.xcodeproj` in Xcode and run the File Wheel scheme.

The shared conversion code is also a Swift package. From this directory:

```sh
swift build
swift test
```

`swift build` and `swift test` cover the FileWheelKit package. The menu-bar app is the Xcode target.

## Privacy

Conversions and tools run locally. There is no telemetry and no auto-update.

Read aloud is the only feature that can leave the Mac, and only when the xAI engine is selected. That engine sends the extracted text to the xAI API and saves the returned MP3 on this Mac. The API key is stored in the macOS Keychain. If that Keychain item is empty, File Wheel reads `XAI_API_KEY` from the environment. The macOS voice and a local model do not send the text anywhere.

## License

MIT. See [LICENSE](LICENSE).

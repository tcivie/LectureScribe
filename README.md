# LectureScribe

Live lecture transcription for macOS, fully on device. Nothing leaves your Mac.

A small glass window floats over your apps and shows the transcript as the lecturer
speaks. The full text is saved to a folder, with a proofread copy made by Apple
Intelligence.

## Features

- **On-device speech to text** with Apple's `SpeechAnalyzer`.
- **Proofread copy** made by the on-device Foundation Models. Corrected words get a
  dashed blue underline.
- **Any source**: the built-in microphone, a headset, or the audio your Mac plays
  (a video call, a browser video).
- **Microphone modes**: use Voice Isolation or Wide Spectrum from the source picker.
- **Stays out of the way**: a compact glass window that floats over full-screen apps.
  Minimize it or hide it. Recording continues.
- **Scrollback** of the last 100 lines.
- **Calendar titles**: a session gets the name of the current calendar event.

## Requirements

- macOS 27 on Apple silicon
- Apple Intelligence turned on, for the proofread copy

## Install

```bash
git clone https://github.com/tcivie/LectureScribe.git
cd LectureScribe
./install.sh          # builds and installs /Applications/LectureScribe.app
```

On the first run, macOS asks for these permissions:

- **Microphone**: to record the microphone.
- **Screen Recording**: to record the audio your Mac plays. macOS puts system audio
  behind this permission. The app records no picture.
- **Calendars** (optional): to name each session after the current event.

## Transcripts

Each session gets its own folder in `~/Desktop/LectureTranscripts/`:

| File | Content |
|---|---|
| `transcript.corrected.md` | The final, proofread transcript |
| `transcript.md` | The raw transcript, written live |
| `*.jsonl` | The same texts, one timestamped segment per line |
| `status.json` | The session state, length and word count |

`latest` links to the newest session. To use another folder:

```bash
defaults write com.tcivie.lecturescribe transcriptsFolder ~/path/to/folder
```

## Command line

```bash
./build.sh                                  # builds ./lecturescribe
./lecturescribe record --source system      # record without a window
./lecturescribe devices                     # list the audio inputs
./lecturescribe locales                     # list the supported languages
swift test                                  # run the unit tests
```

## License

MIT. See [LICENSE](LICENSE).

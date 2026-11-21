# QuietCast

QuietCast is an iOS 17+ SwiftUI podcast player for falling asleep. It stays in dark mode, limits volume, fades audio in, and can pause itself after a timer so a show does not play all night.

## Layout

Application source lives in `QuietCast/`:

- SwiftUI screens, audio playback, downloads, RSS parsing, and persistence
- `AppSettings.swift` — UserDefaults keys and defaults
- `Assets.xcassets`, `Info.plist`, and `QuietCast.entitlements`
- `silence.wav` — silent clip used to claim the Now Playing session

`requirements.md` at the repository root is the feature specification. It sits outside the app target.

Shared data uses the App Group `group.com.quietcast.shared`, with a fallback to the app Documents directory when that container is unavailable.

## Tests

Foundation-only logic is covered by `swift test` from the repository root. `Package.swift` compiles a `QuietCastLogic` library from the existing files in `QuietCast/` (it does not move them) and runs `QuietCastTests/`. Screens, audio, and downloads stay out of that library because they depend on SwiftUI, AVFoundation, UIKit, or MediaPlayer.

```bash
make check
```

`make check` is the command CI runs. It lints Swift, checks spelling and the workflow file, enforces the coverage floor and the shipped-size budget, and runs `swift test`. `AGENTS.md` lists the rules for that check.

There are no CocoaPods, Carthage, or third-party Swift package dependencies.

### Xcode

This repository does not generate an Xcode project. To run the same tests inside Xcode:

1. Open the app project.
2. File → Add Package Dependencies → Add Local… and choose this repository folder.
3. File → New → Target → Unit Testing Bundle. Name it `QuietCastTests`.
4. Remove the template test class Xcode creates.
5. Add every file in the repo's `QuietCastTests/` folder to the `QuietCastTests` target, and do not add those files to the app target.
6. In the test target's General tab, link the local package product `QuietCastLogic`. The tests use `@testable import QuietCastLogic`.
7. Leave the app sources where they are, under `QuietCast/`.

`Product → Test` then runs the bundle. `swift test` remains the check that does not need the `.xcodeproj`.

## Xcode project

This repository does not generate an Xcode project. `QuietCast.xcodeproj` has to be created in Xcode and **committed**. Clones cannot build without that project file. Add the `QuietCast/` folder to the app target, include `silence.wav` as a bundle resource, and keep the app group entitlement. Do not leave the `.xcodeproj` only on one machine.

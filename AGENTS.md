# QuietCast

iOS 17+ SwiftUI podcast player. App source lives in `QuietCast/`. There is no JavaScript, HTML, or CSS, and this repo does not deploy to GitHub Pages.

## Before finishing

Run:

```bash
make check
```

That is the only check command. It formats Swift, runs codespell and actionlint, checks the shipped-size budget, runs `swift test --enable-code-coverage`, and enforces the coverage floor. CI runs this same command.

`make lint` is the fast subset (format, spelling, workflow, size). After `lefthook install`, it runs on commit.

## Rules

- Keep it simple. No new build step. The app is the Swift sources in `QuietCast/`. `Package.swift` only exists so `swift test` can compile the Foundation logic. Do not add an Xcode project generator, a bundler, or a second toolchain.
- Don't add a dependency without a stated reason. There are no third-party Swift packages.
- Keep archived content. Leave `requirements.md` in place; it is the feature specification.
- Every bug fix gets a test.
- Never lower the coverage floor (`COVERAGE_FLOOR` in the `Makefile`, a minimum line-coverage percent) or loosen the size budget (`SIZE_BUDGET`, the maximum number of bytes in `QuietCast/`).
- Don't make visible UI changes unless asked.
- Keep existing URLs working. Feed URLs, `https://itunes.apple.com/search`, and the app group `group.com.quietcast.shared` stay as they are.

## CI

`.github/workflows/ci.yml` runs on `push` and `pull_request`. One job, `check`, with `contents: read`, on `swift:6.4.3-jammy`. The job installs codespell and actionlint, then runs `make check`.

Branch protection on `main` should require the `check` job. That setting is manual.

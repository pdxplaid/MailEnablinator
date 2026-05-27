# MailEnablinator — Claude Code Instructions

This project follows the rules in `AGENTS.md`. Key points summarized below for automatic enforcement.

## Role

Act as a **Senior iOS Engineer** specializing in SwiftUI, SwiftData, and related Apple frameworks. All code must follow Apple's Human Interface Guidelines and App Review guidelines.

## Targets

- **iOS 26.0+**, **Swift 6.2+**
- Strict Swift concurrency
- SwiftUI + `@Observable` for shared data
- No third-party frameworks without asking first
- No UIKit unless explicitly requested

## Swift

- Mark all `@Observable` classes `@MainActor`
- Prefer Swift-native string APIs (`replacing(_:with:)` over `replacingOccurrences(of:with:)`)
- Use modern Foundation APIs (`URL.documentsDirectory`, `appending(path:)`)
- Use typed format APIs — never C-style `String(format:)`
- Prefer static member lookup (`.circle`, `.borderedProminent`) over struct instances
- No `DispatchQueue.main.async` — use `async/await` instead
- Filter user text with `localizedStandardContains()`, not `contains()`
- Avoid force-unwraps and force `try` unless truly unrecoverable

## SwiftUI

- `foregroundStyle()` not `foregroundColor()`
- `clipShape(.rect(cornerRadius:))` not `.cornerRadius()`
- `Tab` API not `tabItem()`
- `@Observable` not `ObservableObject`
- `onChange` must take 2 params or 0 params — never the 1-param variant
- Use `Button` instead of `onTapGesture()` unless you need tap location or count
- `Task.sleep(for:)` not `Task.sleep(nanoseconds:)`
- Never read screen size via `UIScreen.main.bounds`
- Extract subviews into `View` structs, not computed properties
- Use Dynamic Type — no forced font sizes
- `NavigationStack` + `navigationDestination(for:)` — no `NavigationView`
- Image buttons must include a text label
- `ImageRenderer` not `UIGraphicsImageRenderer`
- `bold()` not `fontWeight(.bold)`
- Prefer `containerRelativeFrame()` or `visualEffect()` over `GeometryReader`
- `ForEach(x.enumerated(), id: \.element.id)` — no `Array()` wrapper
- `.scrollIndicators(.hidden)` not `showsIndicators: false`
- Put view logic in view models so it can be tested
- Avoid `AnyView` unless required
- No hard-coded padding/spacing unless requested
- No UIKit colors in SwiftUI

## SwiftData (when CloudKit is enabled)

- No `@Attribute(.unique)`
- All model properties must have defaults or be optional
- All relationships must be optional

## Project Structure

- Feature-based folder layout
- One type per file (structs, classes, enums)
- Unit tests for core logic; UI tests only when unit tests aren't possible
- Never commit secrets or API keys

## Before Committing

- Run SwiftLint if installed; fix all warnings and errors before committing

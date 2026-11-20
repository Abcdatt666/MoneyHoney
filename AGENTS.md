# iOS Native Design Rules (Strict Apple HIG Compliance)

- **Aesthetic & Architecture:** Design strictly as a native iOS app (iOS 26+ HIG), NOT a responsive web app. Prioritize clarity, deference to content, and high information hierarchy.
- **Components:** Use standard iOS patterns: `NavigationStack` with Large Titles, `.insetGrouped` Lists instead of floating shadowed cards, native bottom `TabView`, bottom `Sheet`s with drag indicators, and native context menus.
- **Colors:** NO hardcoded Tailwind hex colors or purple/blue ambient glow gradients. Use Apple semantic color tokens (`systemBackground`, `secondarySystemGroupedBackground`, `label`, `secondaryLabel`, `separator`) with a single clean accent color.
- **Typography & Icons:** Use SF Pro text styles (`.largeTitle`, `.headline`, `.body`, `.footnote`) and `SF Mono` (`.monospacedDigit()`) for financial/numeric data. Use SF Symbols naming conventions exclusively for icons.
- **Anti-Slop Constraints:**
  - Minimum `44x44pt` tap targets for all interactive controls.
  - Respect Safe Areas (Dynamic Island & Home Indicator); never hardcode top/bottom pixel offsets.
  - Keep microcopy concise, action-oriented, and realistic (no marketing fluff, no placeholder names like "Sarah Jenkins").
  - Reserve translucent Liquid Glass effects strictly for floating navigation/toolbars, never on primary content cards.
- **Design Workflow:** Always consult and apply the installed design, SwiftUI, and Apple HIG skills in `.agents/skills/` before designing or building any UI screens.

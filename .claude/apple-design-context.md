# Apple Design Context — Outcome

## Product
- **Name**: Outcome
- **Description**: Offline-first personal expense & dual-wallet cashflow tracker (MBBank & Ví MoMo) powered by iOS Shortcuts notification parsing and month-end balance reconciliation.
- **Category**: Finance / Personal Productivity
- **Stage**: Phase 1 Python Core Complete → Phase 2 UI/UX Spec & SwiftUI Port

## Platforms
| Platform | Supported | Min OS | Notes |
|----------|-----------|--------|-------|
| iOS | Yes | iOS 26.0 (with fallbacks where needed) | Primary target (iPhone, Portrait) |
| iPadOS | Optional later | — | Not primary in Phase 2 |
| macOS | No | — | — |
| tvOS | No | — | — |
| watchOS | No | — | — |
| visionOS | No | — | — |

## Technology Stack
- **UI Framework**: 100% SwiftUI
- **Persistence**: SwiftData (offline on-device, 1-to-1 port of `core/models.py` & `core/store.py`)
- **Automation & Notifications**: App Intents (iOS Shortcuts integration for `RawNotification` ingestion) + `UserNotifications` (local actionable notifications + monthly 12:00 PM weekday reminder)
- **Charts**: Swift Charts (horizontal segmented allocation bar / clean category breakdown)

## Approved Visual Direction: Tactile Bento
- **Reference Inspiration**: Apple Card / Apple Wallet + Apple Fitness (stripped of any neon/glow slop)
- **Surfaces & Hierarchy**:
  - Canvas: `Color(.systemGroupedBackground)`
  - Content Containers: `Color(.secondarySystemGroupedBackground)` with `RoundedRectangle(cornerRadius: 20, style: .continuous)` / `22pt` (no drop shadows)
  - Dual-Wallet Tiles: Adaptive matte semantic tints (`MBBank` cool slate tint, `Ví MoMo` soft rose tint) supporting both Light and Dark Mode seamlessly
  - Navigation & Toolbars: Native `NavigationStack` with Large Title, floating native `TabView` (`Tổng quan`, `Chờ duyệt`, `Ví`) + floating `+` action with iOS 26 Liquid Glass (`.tabBarMinimizeBehavior(.onScrollDown)`), never glass on primary content cards
- **Color Tokens**:
  - Single Primary Accent: Warm Tangerine / Coral (`AccentColor` Asset with Light/Dark variants)
  - Semantic Status: `.green` (income / matched balance), `.red` (discrepancy / badge), `.orange` (pending status), `.secondary` (internal transfer / metadata)
- **Typography**:
  - Display / Headers: `SF Pro` (`.largeTitle`, `.headline`, `.body`, `.footnote`) and `SF Pro Rounded` for key balance hero numerals
  - Financial Numbers: `.monospacedDigit()` on every monetary value and timestamp
- **Iconography**: SF Symbols exclusively (baseline-aligned, Dynamic Type aware)

## Accessibility & Ergonomics
- Minimum `44x44pt` touch targets on all interactive buttons, tag chips, and list rows
- Dynamic Type scaling across all text styles; never hardcode top/bottom safe area offsets
- Full Light Mode & Dark Mode parity
- Microcopy: Concise, realistic Vietnamese, zero marketing fluff

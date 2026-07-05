# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

### iOS Build
```bash
xcodebuild -scheme "Mantra Moment" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### macOS Build
```bash
xcodebuild -scheme "Mantra Moment" -destination 'platform=macOS' build
```

## Architecture Overview

Mantra is a cross-platform (iOS/macOS) SwiftUI app that delivers scheduled motivational notifications. The app runs as a menu bar utility on macOS and a standard app on iOS.

### Data Flow
- **Phrase**: SwiftData `@Model` storing user-customizable motivational phrases
- **Schedule**: Codable struct persisted to UserDefaults, defines notification time window and entries
- **ScheduledEntry**: Individual notification configuration with phrase/time modes (specific or random)
- **NotificationManager**: Singleton coordinating all notification scheduling and background refresh

### Key Implementation Details

**Notification Scheduling**: All notifications use repeating `UNCalendarNotificationTrigger`s, so delivery continues indefinitely without app launches or background execution. Entries with a specific phrase and specific time use one daily trigger (hour+minute). Entries with a random phrase and/or random time use one weekly trigger per weekday (weekday+hour+minute) so content varies day to day while the app stays closed. Random-time entries use intelligent spacing within the schedule window with 30-minute minimum gaps from specific times. If the weekday fan-out would exceed the 64 pending-request budget, entries degrade to a single daily trigger with a frozen phrase/time.

**Background Refresh** (variety refresh only — delivery does not depend on it):
- iOS uses `BGTaskScheduler` with `BGAppRefreshTask`
- macOS uses `NSBackgroundActivityScheduler`
- Both re-resolve random phrases/times every ~12 hours when the system allows
- Background task identifier: `com.milestonemade.Mantra.refresh`

**Phrase Caching**: Phrases are cached to UserDefaults (as `[UUID: String]`) for background task access since SwiftData context isn't available in background execution.

**Platform Differences**:
- macOS: Menu bar extra with popup settings window
- iOS: Standard tab-based navigation with TabView
- Conditional compilation with `#if os(macOS)` / `#if os(iOS)` / `#if canImport(UIKit)`

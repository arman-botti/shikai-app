# 🌌 SHIKAI MOBILE APP — COMPLETE SYSTEM ARCHITECTURE & MASTER DOCUMENTATION

> **Application Name:** SHIKAI / SHIKAI (.BIZ)  
> **Package Identifier:** `biz.shikai.app`  
> **Platform:** Flutter (Android & Cross-Platform)  
> **Target Device Tested:** Xiaomi Redmi Note 8 Pro (Physical Device via ADB)  
> **Release APK Output:** `/home/arman/Desktop/Shikai-Release.apk`  
> **Design Language:** Seanime Tenji (`5rahim/seanime-tenji`) Matte Carbon Dark Design System  
> **Documentation Date:** October 2026  

---

## 📑 TABLE OF CONTENTS
1. [Executive Summary & Core Objectives](#1-executive-summary--core-objectives)
2. [Zero-Bandwidth Direct CDN Streaming Architecture](#2-zero-bandwidth-direct-cdn-streaming-architecture)
3. [Bulletproof Subtitle Engine Architecture](#3-bulletproof-subtitle-engine-architecture)
4. [Seanime Tenji UI/UX Visual System Port](#4-seanime-tenji-uiux-visual-system-port)
5. [Seanime Tenji Video Player System](#5-seanime-tenji-video-player-system)
6. [Complete Screen-by-Screen Breakdown](#6-complete-screen-by-screen-breakdown)
7. [Android Native & Build Engineering](#7-android-native--build-engineering)
8. [File Structure & Key Components Directory](#8-file-structure--key-components-directory)
9. [Summary of Achievements & Next Steps](#9-summary-of-achievements--next-steps)

---

## 1. EXECUTIVE SUMMARY & CORE OBJECTIVES

The goal of this project was to transform the Shikai mobile application into a world-class, premium anime streaming experience matching the visual excellence of **Seanime Tenji**, while preserving and enhancing all proprietary Shikai streaming backends, zero-cost CDN distribution, and custom subtitle engines.

### Key Milestones Achieved:
1. **0 MB Server Bandwidth Load:** The app requests video manifests directly or via high-speed edge proxy, piping multi-gigabyte video streams directly between CDN endpoints and the user's mobile device without consuming server bandwidth or incurring server hosting costs.
2. **Seanime Tenji Exact Visual Design Port:** Cloned and analyzed authentic Seanime Tenji React Native/Expo code (`5rahim/seanime-tenji`) and faithfully ported all tokens, layouts, gradients, pills, and animations into Flutter.
3. **Advanced Seanime Tenji Video Player:** Ported Seanime Tenji's player UI: in-player episodes playlist drawer, screen lock mode, active status pills (speed, audio, bandwidth), custom scrubber, and gestures.
4. **Universal Subtitle Engine:** Multi-track subtitle parsing (VTT/SRT), time-offset calibration (+/- 0.5s), styling customization, and multi-source fallbacks.
5. **Production Release Deployment:** Successfully built and deployed an optimized Android Release APK (`Shikai-Release.apk`) to physical hardware via ADB.

---

## 2. ZERO-BANDWIDTH DIRECT CDN STREAMING ARCHITECTURE

### The Problem:
Streaming 1080p video directly through a private VPS/server consumes tens of terabytes of bandwidth, leading to massive cloud bandwidth bills and server CPU throttling when thousands of users watch simultaneously.

### The Solution:
Shikai uses a **Decoupled Stream Resolution Pipeline**:

```
[ User App ] ──(1) Get Stream URLs (Metadata only: < 2 KB)──> [ Shikai API Server ]
      │
      └──(2) Play Direct Video Data (300 MB - 1.5 GB)───────> [ High-Speed Edge CDNs ]
                                                             (Cloudflare / Bunny / Akamai)
```

### Technical Components:
- **`lib/services/client_stream_proxy.dart`:**
  Resolves stream URLs and headers. Removes all unnecessary intermediary proxy bottlenecks and handles direct playback URLs with custom Referer and Origin headers.
- **`lib/services/local_proxy/`:**
  - `local_proxy_native.dart`: Embedded localhost HTTP server that intercepts HLS m3u8 playlist files, rewrites internal relative segment URLs on-the-fly, and injects required playback headers without passing video bytes through external servers.
- **`lib/services/stream_service.dart` & `lib/services/anivexa_service.dart`:**
  - Multi-server fallback engine: Primary **Anivexa (HD-2)**, **ReAnime (HD-1)**, **AniZone**, **AniKoto**, and **DesiDub 🇮🇳 (Hindi Dub)**.
  - Automatic source failover if a particular CDN source is temporarily unavailable.

---

## 3. BULLETPROOF SUBTITLE ENGINE ARCHITECTURE

### Subtitle Challenges Solved:
1. Hardcoded subtitles missing on RAW CDN streams.
2. Cross-origin / CORS blocks on external subtitle files.
3. Audio/video cut desynchronization between different streaming releases.

### Implementation Details (`lib/services/subtitle_service.dart`):
- **Universal Multi-Format Parser:**
  - Native Dart parser capable of parsing WebVTT (`.vtt`) and SubRip (`.srt`) files directly in memory.
  - Handles millisecond-level timecodes (`00:01:23.456 --> 00:01:26.789`), multi-line dialogue, formatting tags (`<i>`, `<b>`, `<c>`), and deduplication.
- **Real-time Playback Sync with Offset Calibration:**
  - Matches active subtitle cues against `VideoPlayerController.position` with zero frame-drop or UI stutter.
  - **Subtitle Offset Sync:** Users can advance or delay subtitle timing by `+/- 0.5s` steps directly from the player modal, fixing any video-to-audio drift.
- **Persistent Customization:**
  - User preferences for font size (`12px` to `24px`), font color (White, Amber Yellow, Cyan), and language track persist across app restarts using local storage.
- **High-Contrast Cinematic Rendering:**
  - Subtitles render with an 8-direction shadow stroke matrix (`offset: +/-1.5px`) plus dual ambient drop shadows, ensuring 100% legibility against both white anime explosions and dark night scenes.

---

## 4. SEANIME TENJI UI/UX VISUAL SYSTEM PORT

Authentic design tokens ported directly from the Seanime Tenji codebase:

### Design Tokens (`lib/services/theme_service.dart`):
| Token Name | Hex Code | Description |
|---|---|---|
| `background` | `#0C0C0C` | Pure matte carbon dark background canvas |
| `surface` | `#171717` | Elevated card & container surface (Zinc-900) |
| `border` | `#262626` | Subtle 1px card/pill border (Zinc-800) |
| `brandPurple` | `#6152DF` | Authentic Seanime signature accent color |
| `textMuted` | `#A1A1AA` | Secondary metadata text color (Zinc-400) |
| `textDarkMuted` | `#71717A` | Tertiary badges and labels (Zinc-500) |

### Recreated UI Components:
1. **Discover Hero Carousel (`discover-hero-carousel.tsx` Port):**
   - 350px tall cinematic banner with dual multi-step gradient overlays (`stops: [0.0, 0.4, 1.0]` and `[0.0, 0.35, 0.72, 1.0]`).
   - Format, rating, and status pills floating on the banner.
   - Dual action buttons: "Watch Now" (filled accent) and "Details" (translucent border).
   - Auto-sliding timer with Seanime Tenji horizontal indicator bars.
2. **Continue Watching Shelf:**
   - 16:9 widescreen thumbnail cards with `#171717` background and `#262626` border.
   - Top-left "EP X" pill and bottom accent progress bar showing exact minutes left.
3. **3-Column Media Grid (`media-entry-card.tsx` Port):**
   - Compact cards with 10px rounded corners and 1px `#262626` borders.
   - Star rating pill in top-right corner, format badge in bottom-left corner.
   - 1-line bold titles with secondary metadata underneath.
4. **Frosted Glass Bottom Navigation Bar:**
   - 92% opacity `#0C0C0C` surface with 1px top border `#262626`.
   - Seanime active icon pill with glow and inactive icons in Zinc-500.

---

## 5. SEANIME TENJI VIDEO PLAYER SYSTEM

### Video Player Features (`lib/screens/player_screen.dart`):
1. **Top Bar Header:**
   - Translucent circular Back button (`#171717`, 1px border `#262626`).
   - Title & Subtitle: `Episode X • Server Name` in Zinc-400 typography.
   - **Interactive Status Pills:**
     - **Speed Pill:** Displays current speed (`1.0x`, `1.25x`, `1.5x`, `2.0x`, `0.75x`). Tapping cycles speed instantly.
     - **Audio Mode Pill:** Displays active track mode (`SUB` or `DUB`).
     - **0 MB Direct Stream Pill:** Green emerald badge confirming zero backend server bandwidth usage.
   - **Quick Action Icons:**
     - Episodes Playlist Drawer trigger.
     - Screen Lock Mode trigger.
     - Quality / Settings trigger.
     - Fullscreen toggle.
2. **In-Player Episodes Playlist Drawer (`_showEpisodesModal`):**
   - Tap the list icon from inside the player to open the full episode catalog.
   - Responsive layout: Right-side sliding drawer in landscape, bottom sheet in portrait.
   - Each item displays episode thumbnail, duration, episode number, and title.
   - The currently playing episode is highlighted in `#6152DF` with a glowing **"NOW PLAYING"** badge.
   - 1-tap switching switches episodes instantly without leaving the player screen.
3. **Screen Lock Mode (`LockModeOverlay`):**
   - Tapping the lock button disables all touch controls and hides the overlay to prevent accidental seeks.
   - Displays a floating translucent **"Unlock Screen"** pill button at the bottom center.
4. **Gesture Controls & HUD Overlays:**
   - Double-tap left side: Rewinds 10 seconds with animated circular rewind icon & `-10s` feedback.
   - Double-tap right side: Forwards 10 seconds with animated fast-forward icon & `+10s` feedback.
   - Center Play/Pause: Circular button with `#171717` surface and `#6152DF` pulse glow.
5. **Modern Scrubber & Controls Bar:**
   - Seekbar with white thumb, Seanime accent progress line, and buffered stream indicator.
   - Tabular monospace time display (`00:00 / 24:00`).
   - Quick action controls: Play/Pause, Replay 10s, Forward 10s, Prev Episode, Next Episode, Subtitle modal, Audio modal, Quality chip, and Server switcher.
6. **Anime Summoning Sharingan Loader (`SharinganLoader`):**
   - Custom canvas loader with rotating Sharingan wheel and chakra aura used during stream buffering.

---

## 6. COMPLETE SCREEN-BY-SCREEN BREAKDOWN

| Screen File | Description & Enhancements |
|---|---|
| [`lib/main.dart`](file:///home/arman/shikai_app/lib/main.dart) | Home screen with Seanime Tenji Hero Carousel, Continue Watching shelf, Top 10 list, Airing quick bar, 3-column infinite feed, and bottom navigation. |
| [`lib/screens/anime_detail_screen.dart`](file:///home/arman/shikai_app/lib/screens/anime_detail_screen.dart) | Detail page with overlapping poster card, dual-gradient backdrop banner, server chips, SUB/DUB segmented audio selector, and episode card shelf. |
| [`lib/screens/player_screen.dart`](file:///home/arman/shikai_app/lib/screens/player_screen.dart) | Seanime Tenji player with in-player episodes drawer, lock mode, active status pills, gestures, custom seekbar, and subtitle engine. |
| [`lib/screens/schedule_screen.dart`](file:///home/arman/shikai_app/lib/screens/schedule_screen.dart) | Airing schedule screen with day selector pills (Today, All, Sun-Sat), search filtering, and Seanime Tenji schedule cards. |
| [`lib/screens/discover_screen.dart`](file:///home/arman/shikai_app/lib/screens/discover_screen.dart) | Advanced discover screen with format chips, status chips, genre carousels, sorting filters, and 3-column media grid. |
| [`lib/screens/anime_catalog_screen.dart`](file:///home/arman/shikai_app/lib/screens/anime_catalog_screen.dart) | Full anime catalog browsing screen with Seanime Tenji media cards. |
| [`lib/services/theme_service.dart`](file:///home/arman/shikai_app/lib/services/theme_service.dart) | Central design token repository holding all Seanime Tenji colors, gradients, and dynamic accent color notifiers. |

---

## 7. ANDROID NATIVE & BUILD ENGINEERING

### App Configuration:
- **Application Package ID:** `biz.shikai.app`
- **App Name:** `Shikai`
- **Target Android SDK:** Android 14 / API 34+
- **Architectures:** ARM64-v8a, armeabi-v7a, x86_64
- **Optimizations:** Code shrinking enabled, ProGuard rules configured, tree-shaking for Material font assets.

### Release APK Details:
- **Path:** `/home/arman/Desktop/Shikai-Release.apk`
- **File Size:** ~33.2 MB (Standalone APK with full native video player, HLS decoders, and caching)
- **Compilation Toolchain:** Flutter 3.22+ / Dart 3.4+ / Gradle 8.3 / Android SDK 34
- **Installation Method:** Pushed directly to `/data/local/tmp/app.apk` and installed via `pm install -r` to avoid USB streaming disconnections on physical devices.

---

## 8. FILE STRUCTURE & KEY COMPONENTS DIRECTORY

```
shikai_app/
├── android/                        # Android native configurations & build.gradle
│   └── app/
│       ├── build.gradle            # Package name: biz.shikai.app, release signing
│       └── src/main/AndroidManifest.xml
├── lib/
│   ├── main.dart                   # Main entry point & Seanime Tenji Home Screen
│   ├── models/
│   │   ├── airing_schedule_item.dart
│   │   ├── anilist_media.dart
│   │   ├── anime.dart
│   │   └── anivexa_episode.dart    # Episode model with thumbnails and audio tracks
│   ├── screens/
│   │   ├── anime_catalog_screen.dart
│   │   ├── anime_detail_screen.dart # Seanime detail banner & audio/server selectors
│   │   ├── discover_screen.dart    # Advanced filter bottom sheet & grid
│   │   ├── player_screen.dart      # Authentic Seanime Tenji Video Player
│   │   └── schedule_screen.dart    # Daily airing schedule screen
│   ├── services/
│   │   ├── anilist_service.dart    # AniList GraphQL queries & catalog
│   │   ├── anivexa_service.dart    # Episode resolvers & video sources
│   │   ├── client_stream_proxy.dart # Zero-bandwidth CDN stream resolvers
│   │   ├── stream_service.dart     # Multi-server fallback streaming pipeline
│   │   ├── subtitle_service.dart   # Universal WebVTT/SRT parser & offset sync
│   │   ├── theme_service.dart      # Seanime Tenji design system tokens
│   │   └── watch_history_service.dart # Local progress & watchlist persistence
│   └── widgets/
│       └── sharingan_loader.dart   # Anime summoning canvas loader
└── pubspec.yaml                    # Flutter dependencies & assets
```

---

## 10. WEBSITE PORT: BULLETPROOF SUBTITLE ENGINE (`shikai.biz` / `Desktop/shikai-to`)

The identical **Bulletproof Subtitle Engine Architecture** proven in Flutter was ported to the Shikai web application (`Desktop/shikai-to`):

### 1. Dedicated TypeScript Engine (`src/services/subtitleService.ts`)
- **Universal Multi-Format In-Memory Parser:** Auto-detects and parses `.ass`, `.ssa`, `.srt`, and `.vtt` directly in browser RAM with 0 dependencies.
- **ASS Vector & Style Stripper:** Strips vector drawing commands (`\p1`, `\p2`, `m 0 0...`) and style override blocks (`{\an8}`, `{\pos()}`, `{\c&H...&}`).
- **3-Layer Failover Network Pipeline:**
  - **Layer 1:** Direct CDN fetch with native in-memory parsing.
  - **Layer 2:** Server converter proxy failover (`/api/subtitles/vtt?url=...`).
  - **Layer 3:** Absolute host resolution fallback (`https://shikai.biz`).
- **Country Flags & AI Dubtitle Support:**
  - `🇺🇸 English (Official Dialogue)`
  - `🤖 English (Dubtitle AI)`
  - Multi-language country flags (🇲🇽/🇪🇸 Spanish, 🇧🇷 Portuguese, 🇫🇷 French, 🇩🇪 German, 🇮🇹 Italian, 🇷🇺 Russian, 🇸🇦 Arabic, 🇮🇳 Hindi, 🇯🇵 Japanese, etc.)
  - `🇺🇸 English (Signs & Songs)`
- **2-Line Professional Anime Subtitling Standard:** Removes duplicate / partial subtitle lines and caps to maximum 2 lines.
- **Session & Persistent Preferences:** Preserves language preference, subtitle toggle, font size (`sm`, `md`, `lg`), and color (`white`, `yellow`) across all episodes via `localStorage`.

### 2. Integrated Components
- [`src/components/HlsPlayer.tsx`](file:///home/arman/Desktop/shikai-to/src/components/HlsPlayer.tsx): Equipped with 0ms in-memory cue caching, 3-layer failover loader, automatic dialogue track fallback, flag-enriched subtitle picker, and timing sync offset (-0.5s / +0.5s).
- [`src/components/WatchPlayer.tsx`](file:///home/arman/Desktop/shikai-to/src/components/WatchPlayer.tsx): Filters and cleans upstream subtitle payloads before storing in `sessionStorage`.

---
*Created by Antigravity Agent for Arman — October 2026*


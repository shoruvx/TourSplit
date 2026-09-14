# TourSplit Release & "What's New" Standard

Whenever preparing or cutting a new release of TourSplit, always follow these rules to ensure the **detailed yet minimalistic features** appear in What's New on GitHub releases, in-app update prompts, and push notifications every time.

## 1. Structure of What's New Features

Every release must present 4 to 7 key features or improvements in a **detailed yet minimalistic** bullet list:
- **Format**: `- <Emoji> **<Feature Title>**: <1-2 Sentence Crisp Description>`
- **Tone**: Professional, informative, focused on what the feature does and how it helps users. Avoid vague filler like "minor bug fixes and improvements".
- **Visuals**: Use a distinct, context-relevant emoji for every item (e.g., 👤 for profiles, ⚡ for instant/auto operations, 🎨 for design & themes, 📊 for metrics/analytics, 🧮 for math/calculator, 💳 for payments/accounts, 📬 for communication/feedback, 🚀 for OTA/performance).

### Example:
```markdown
### What's New in TourSplit v1.4.1 ✨

- 👤 **Member Profile Hub**: Tap any member avatar or name anywhere in the app to view their profile, role, contact info, and tour activity.
- ⚡ **Offline Auto-Settlement**: Settlements with offline companions now resolve automatically without requiring approval from the offline friend.
- 🎨 **3D Teal UI & System Theme**: Smooth 3D elevation cards with sleek teal borders, white-bordered buttons, and adaptive system default theme.
- 📊 **Your Spending Breakdown**: Tours and summary cards now display your exact personal spending share rather than a generic per-person average.
- 📬 **Contact Us & Suggestion Portal**: Send feature ideas, feedback, and bug reports directly to Constant Time Labs from the Profile screen.
- 🚀 **Over-The-Air Push Updates**: Stay up-to-date with background push alerts via Firebase Cloud Messaging and 1-tap seamless in-app APK installation.
```

## 2. Release Preparation Checklist

When bumping version for a new release:
1. **Update In-App What's New Dialog**:
   - In `lib/presentation/widgets/whats_new_dialog.dart`, update the `_features` list with the new version's icons, titles, and descriptions.
2. **Update Changelog**:
   - In `CHANGELOG.md`, add a new section `## [vX.Y.Z] - YYYY-MM-DD` with the formatted feature bullets.
3. **Bump Version**:
   - In `pubspec.yaml`, increment `version: X.Y.Z+<BUILD_NUMBER>`.
4. **Publish**:
   - Run `./scripts/release.sh <version>`. The script automatically parses the detailed yet minimalistic features via `scripts/generate_release_notes.py` and tags the commit.
   - GitHub Actions (`.github/workflows/release.yml`) builds the APK, publishes the GitHub Release with the formatted What's New body and rich title, and broadcasts the FCM push notification to all users.

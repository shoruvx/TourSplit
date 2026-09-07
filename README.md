# 🗺️ TourSplit

<div align="center">

[![Version](https://img.shields.io/badge/version-1.2.0-teal.svg?style=for-the-badge)](https://github.com/shoruvx/TourSplit/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B.svg?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore-FFCA28.svg?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84.svg?style=for-the-badge&logo=android&logoColor=white)](https://github.com/shoruvx/TourSplit/releases)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

**Split the costs, keep the memories.**

A smart, real-time travel expense tracker and debt settlement app built for real trips with real people.

[Download Latest APK (v1.2.0)](https://github.com/shoruvx/TourSplit/releases/latest) • [Privacy Policy](https://shoruvx.github.io/TourSplit/) • [Report Bug](https://github.com/shoruvx/TourSplit/issues)

</div>

---

## 💡 Why TourSplit?

Anyone who has traveled with a group knows the drill: multiple people pay for cabs, hotel bookings, groceries, and late-night snacks. By day three, you're stuck in a nightmare of napkins, notes apps, and spreadsheet formulas trying to figure out who owes who.

**TourSplit takes care of all that instantly.** Log bills as they happen, do quick math right inside the amount box, add friends even if they don't have the app yet, and let TourSplit calculate the minimum number of payments to settle up at the end.

---

## 📱 Screenshots (Live on Device)

<div align="center">

### Tour Experience & Expense Splitting

| Streamlined Home | Tour Dashboard | In-Line Math Split | Instant QR Invite |
|:---:|:---:|:---:|:---:|
| <img src="docs/TourSplit_home_new.png" width="220" alt="Home Screen"/> | <img src="docs/TourSplit_dashboard.png" width="220" alt="Dashboard Screen"/> | <img src="docs/TourSplit_math_preview.png" width="220" alt="Add Expense Math Evaluation"/> | <img src="docs/TourSplit_qr_code.png" width="220" alt="Tour QR Code Invite"/> |

<br/>

### Members, Migration & Profiles

| Offline Companions | Link Online Account | Avatar Customization | Create New Tour |
|:---:|:---:|:---:|:---:|
| <img src="docs/TourSplit_members_offline.png" width="220" alt="Members & Offline Friend"/> | <img src="docs/TourSplit_link_online_dialog.png" width="220" alt="Link Online Migration"/> | <img src="docs/TourSplit_profile_photo_sheet.png" width="220" alt="Profile Avatar Picker"/> | <img src="docs/TourSplit_create_tour.png" width="220" alt="Create Tour"/> |

</div>

---

## ✨ Features You'll Actually Love

### 🧮 In-Line Math Calculator
No need to switch back and forth to your calculator app. When splitting a bill, type formulas directly into the amount box:
- Enter expressions like `(500 * 2) + 350` or `1200 / 3 + 50`.
- See a live glowing evaluation preview chip (`= ৳1350`).
- Tap the preview chip or click anywhere to auto-convert the expression into the final sum.
- Includes a dedicated quick arithmetic keypad (+, -, *, /, parentheses) right above your keyboard.

### 👥 Offline Companions & Instant Online Migration
Traveling with friends who don't have the app installed or have poor network reception?
- **Add Offline Friends**: Add companions with just their name in two seconds—no account or device required.
- **Track Normally**: Split bills, assign payers, and track balances for offline friends just like any member.
- **Link When Ready**: When your friend installs TourSplit and joins the tour, tap **Link Online**. TourSplit migrates their entire transaction history, shared splits, and balance sheet to their real account with zero loss of data.

### 🤝 Greedy Debt Simplification
Instead of everyone transferring small amounts back and forth:
- TourSplit runs a **two-pointer greedy debt reduction algorithm** to collapse multi-party debts into the absolute minimum number of payments.
- Directly approve settlements, record payment channels (bKash, Nagad, Cash, Bank Transfer), and maintain an unalterable audit log.

### 📅 Collapsible Daily Ledger
- Group expenses chronologically by day (Day 1, Day 2, Day 3...).
- Keep days collapsed for a clean summary or expand any day to inspect individual line items.
- Supports multi-payer bills (e.g., Alice paid ৳2,000 and Bob paid ৳1,500 on the same hotel invoice).
- Split equally, split with selected companions, or enter custom exact share amounts.

### 📸 Real-Time Profile Avatars
- Express yourself on the group ledger with customizable profile photos.
- Pick pictures from your phone gallery, take a fresh selfie with your camera, or choose from travel-themed avatars.
- Updates broadcast instantly in real-time across all tour member screens.

### 📄 PDF Export & Reports
- Export professional, itemized accounting reports with a single tap.
- Download or print ready-to-share summaries of tour statistics, member contributions, and final balances.

### 🔄 Seamless Over-The-Air (OTA) Updates
- TourSplit connects directly with GitHub Releases to check for updates.
- Download and install newer versions directly inside the app with a friendly progress banner.

---

## ⚡ Quick Start

### 1. Grab the APK
Download the latest Android release from the **[Releases Page](https://github.com/shoruvx/TourSplit/releases/latest)** (`TourSplit-v1.2.0.apk`).

### 2. Sign In
Log in with your Google account or email.

### 3. Create or Join a Tour
- **Create Tour**: Give your trip a name, select dates, pick a cover theme, and start logging.
- **Join Tour**: Scan the tour QR code or enter the 6-digit invite code (e.g., `RCQYDM`).
- **Navigation Tip**: Tap the tour title at any time to browse all your trips, or tap Back to return to the clean home screen.

---

## 🛠️ Developer Setup

If you want to contribute, build from source, or customize TourSplit for your own trips:

### Prerequisites
- [Flutter SDK](https://flutter.dev) (v3.3.0 or higher)
- Android SDK (API 34+)
- A Firebase project with Authentication (Google Sign-In) and Cloud Firestore enabled

### Getting Started

```bash
# 1. Clone the repo
git clone https://github.com/shoruvx/TourSplit.git
cd TourSplit

# 2. Fetch packages
flutter pub get

# 3. Add your Firebase config
# Place your `google-services.json` inside android/app/

# 4. Launch on an Android device or emulator
flutter run
```

### Building Release APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## 🧱 Project Architecture

```
TourSplit/
├── android/                  # Native Android configuration & signing keystores
├── docs/                     # Live app screenshots & GitHub Pages assets
├── lib/
│   ├── core/                 # Theme tokens, route declarations, constants
│   ├── data/                 # Firestore repositories, data models & services
│   │   ├── models/           # TourModel, ExpenseModel, SettlementModel, UserModel
│   │   ├── repositories/     # Tour, Expense, Settlement, User repositories
│   │   └── services/         # AppUpdateService, AuthService, BalanceService
│   ├── presentation/         # Riverpod-powered UI screens & components
│   │   ├── auth/             # Login, Registration, Password Reset
│   │   ├── expense/          # Add/Edit Expense, Math amount input, Ledger views
│   │   ├── home/             # 3-Card Home, Tour Dashboard, Settlements
│   │   ├── profile/          # Profile screen, Avatar bottom sheet
│   │   ├── reports/          # PDF export & printable expense summaries
│   │   ├── tour/             # Create, Join (Code/QR), Settings, Member linking
│   │   └── widgets/          # Shared components, badges, dialogs
│   └── main.dart             # App entry point, Firebase & Hive initialization
├── pubspec.yaml              # App configuration & dependencies
└── README.md                 # Project documentation
```

---

## 📜 License

TourSplit is open source under the [MIT License](LICENSE). Feel free to use, modify, and distribute it!

<div align="center">

Crafted with ❤️ by [Shoruv](https://github.com/shoruvx)

</div>

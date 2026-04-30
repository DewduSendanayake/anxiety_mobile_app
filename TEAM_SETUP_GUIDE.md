# 🛠 Team Setup & Handover Guide
**Project: Anxiety Research Mobile App (Digital Phenotyping)**

This document provides step-by-step instructions for team members to set up the development environment and build the app.

---

## 1. System Dependencies (Pre-requisites)
Every team member must have the following installed:

*   **Flutter SDK (Stable)**: [Download here](https://docs.flutter.dev/get-started/install). 
    *   *Verification*: Run `flutter doctor` in your terminal.
*   **Java JDK 17**: Required for Android builds.
*   **Android SDK**: API Level 34 (Android 14) is required.
*   **Git**: To clone the project.

---

## 2. Project Initialization
1.  **Clone the project**:
    ```bash
    git clone <your-repository-url>
    cd anxiety_mobile_app
    ```
2.  **Install Flutter packages**:
    ```bash
    flutter pub get
    ```

---

## 3. Security Configuration (DO NOT SKIP)
For security, the API keys are not in the code. You must set them up locally:

1.  Create a file at `lib/config.dart`.
2.  Paste this code inside:
    ```dart
    class AppConfig {
      static const String googleScriptUrl = String.fromEnvironment('SCRIPT_URL');
      static const String authToken = String.fromEnvironment('AUTH_TOKEN');
    }
    ```
3.  **Note**: This file is ignored by Git. You must manually provide the keys when running the app.

---

## 4. How to Run & Build

### Option A: Using Android Studio (Recommended)
1.  Open the project in Android Studio.
2.  Go to **Run** -> **Edit Configurations...**
3.  In the **Additional run args** field, enter:
    `--dart-define=SCRIPT_URL="YOUR_URL" --dart-define=AUTH_TOKEN="YOUR_TOKEN"`
4.  Click **OK** and press the Green Run button.

### Option B: Using Only the SDK (Command Line)
If you don't use an IDE, use these commands:

*   **To Run**:
    ```bash
    flutter run --dart-define=SCRIPT_URL="YOUR_URL" --dart-define=AUTH_TOKEN="YOUR_TOKEN"
    ```
*   **To Build Release APK**:
    ```bash
    flutter build apk --obfuscate --split-debug-info=./debug-info \
      --dart-define=SCRIPT_URL="YOUR_URL" \
      --dart-define=AUTH_TOKEN="YOUR_TOKEN"
    ```

---

## 5. Troubleshooting
*   **"Timer not found"**: Ensure `import 'dart:async';` is at the top of the file.
*   **"Background Service not found"**: Run `flutter pub get` again.
*   **Data not appearing in Sheets**: Check that your `AUTH_TOKEN` exactly matches the one in your Google Apps Script.
*   **Background service stops**: Ensure the test phone has **"Battery Optimization" set to "Unrestricted"** for this app.

---
**Research Lead**: Dulhara KKaushalya
**Date**: April 2026

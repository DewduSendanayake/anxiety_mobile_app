# Anxiety Research Mobile App (Digital Phenotyping)

This is a Flutter-based research application designed to collect behavioral and physiological signals (digital phenotyping) to study anxiety patterns in participants.

## 🚀 Overview
The app collects data through two primary methods:
1.  **Passive Sensing**: Automatic background collection of location, motion, app usage, and social activity metrics.
2.  **Active Sensing**: Scheduled Ecological Momentary Assessments (EMAs) and weekly GAD-7 clinical questionnaires.

## 🛠 For Developers & Team Members
If you are setting up this project for the first time, please refer to the dedicated setup guide:
👉 **[TEAM_SETUP_GUIDE.md](./TEAM_SETUP_GUIDE.md)**

## ✨ Key Features
- **Persistent Background Service**: Runs 24/7 with auto-restart on device reboot.
- **Offline-First Storage**: Up to 10,000 data points can be stored locally if internet is lost.
- **Secure Data Sync**: Automated integration with Google Sheets via Google Apps Script.
- **Anxiety Pressure Sensor**: A unique dashboard feature that records touch pressure as a stress indicator.
- **Customizable Check-ins**: Users can pick their preferred times for daily anxiety ratings.

## 🔒 Privacy & Ethics
- **Data Obfuscation**: All release builds are obfuscated to protect server endpoints.
- **Location Fuzzing**: GPS data is generalized to protect participant residence privacy.
- **Ethical Collection**: No private message content, phone numbers, or identifiable audio is recorded.

## 👥 Research Team
- **Research Lead**: Dulhara KKaushalya
- **Affiliation**: SLIIT Anxiety Research Project 2026

---
*This project is for research purposes only.*

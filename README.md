# QuickKart 🛒⚡

10-minute grocery delivery app: Flutter hiring assignment.

👉 **Start with [ASSIGNMENT.md](ASSIGNMENT.md).**

## Setup

Requirements: Flutter **stable 3.27 or newer**, plus an Android emulator/device
or iOS simulator.

```bash
# 1. The repo contains only lib/ and test/. Generate the platform folders
#    (this does NOT overwrite existing files):
flutter create . --project-name quickkart --platforms=android,ios

# 2. Dependencies
flutter pub get

# 3. Make sure everything is green before you start
flutter analyze
flutter test

# 4. Run
flutter run
```

No backend, database or Firebase project is needed. Everything runs on the
device through the mock server in `lib/mock_server/`.

## Dev tools

Tap 🐞 on the home screen. From there you can:

- go **offline**, make the network **slow** or **flaky**;
- **lose the response** of the next order (the server processes it, the app
  never hears back);
- change prices, **create conflicts for your cart**, reset server data;
- **publish remote config** (close the store, force update, change the home
  layout…);
- pretend the installed **app version** is different;
- **advance** orders through their delivery statuses.

## Useful commands

```bash
flutter test                         # all tests
flutter test test/my_test.dart       # one file
flutter analyze
```

## Docs

- [ASSIGNMENT.md](ASSIGNMENT.md): what to do and how it's evaluated
- [docs/BUSINESS_RULES.md](docs/BUSINESS_RULES.md): product rules (source of truth)
- [docs/API_CONTRACT.md](docs/API_CONTRACT.md): backend API
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): code structure and public contract

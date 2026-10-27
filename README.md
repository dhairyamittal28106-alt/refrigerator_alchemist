# Refrigerator Alchemist

A Flutter app that turns ingredients on hand into recipe ideas. Users can add ingredients manually or scan them with the camera, review suggested recipes, and revisit saved history. The app uses image-recognition and recipe services, Firebase Authentication and Cloud Firestore, and supports Google sign-in.

## Configure services

Before running, configure the provider settings expected by the app in `.env` and add the Firebase platform configuration for your own Firebase project. Do not commit private service credentials.

## Run locally

Install Flutter and Dart 3.4 or newer, then run:

    flutter pub get
    flutter run

Camera-based scanning requires a supported device and camera permission. Authentication and saved data require Firebase configuration.

## Main implementation

- `lib/main.dart`: app shell, authentication, ingredient entry and scan flow, recipe results, and history
- `lib/assets/`: bundled app artwork
- `pubspec.yaml`: Flutter packages and asset configuration

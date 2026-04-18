# docmedrepo

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Configuration

To run on a real device or iOS simulator against a local backend, you must specify the `API_BASE_URL` using `--dart-define`:

```bash
flutter run --dart-define=API_BASE_URL=http://<YOUR_LOCAL_IP>:5000/api
```
If omitted, it defaults to `http://10.0.2.2:5000/api` (Android emulator only) or `http://localhost:5000/api` (Web).

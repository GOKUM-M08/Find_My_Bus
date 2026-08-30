/// Central place for environment-specific config.
///
/// Set the backend URL at run/build time — never hardcode it in a screen.
///
/// Local dev, same machine (Chrome, iOS simulator):
///   flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://localhost:8000
///
/// Local dev, Android emulator (10.0.2.2 = emulator's alias for host PC):
///   flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:8000
///
/// Local dev, physical device on same WiFi as your PC:
///   flutter run --dart-define=BACKEND_BASE_URL=http://<your-pc-lan-ip>:8000
///
/// Production build (once backend is deployed):
///   flutter build apk --dart-define=BACKEND_BASE_URL=https://your-backend.onrender.com
///
/// If no --dart-define is passed, this defaults to the Android emulator
/// alias — safe fallback for local development, but the demo/production
/// build MUST pass the real URL explicitly.
const String kBackendBaseUrl = String.fromEnvironment(
  'BACKEND_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
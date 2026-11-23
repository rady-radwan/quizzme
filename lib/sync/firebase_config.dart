/// Firebase project settings, supplied at build time with `--dart-define`
/// (GitHub repository secrets in CI), never hard-coded in the source.
/// Firebase web API keys only identify the project; access to data is
/// controlled by Firebase Authentication and the Firestore security rules
/// (`firebase/firestore.rules`).
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('QUIZME_FIREBASE_API_KEY');
  static const projectId = String.fromEnvironment('QUIZME_FIREBASE_PROJECT_ID');

  static bool get configured => apiKey.isNotEmpty && projectId.isNotEmpty;
}

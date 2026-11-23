/// Google OAuth client ids for Drive sync, supplied at build time
/// (`--dart-define`, from GitHub repository secrets in CI). Nothing is
/// hard-coded in the source. When they are missing, sync is shown as not
/// available in that build.
class SyncConfig {
  /// "Web application" OAuth client id (Android sign-in needs it as the
  /// server client id).
  static const webClientId = String.fromEnvironment('QUIZME_GOOGLE_WEB_CLIENT_ID');

  /// "Desktop app" OAuth client (Windows). Google treats desktop client
  /// secrets as non-confidential, but it is still kept out of the source.
  static const desktopClientId = String.fromEnvironment('QUIZME_GOOGLE_DESKTOP_CLIENT_ID');
  static const desktopClientSecret = String.fromEnvironment('QUIZME_GOOGLE_DESKTOP_CLIENT_SECRET');

  /// Only the app's own hidden folder in the user's Drive.
  static const driveScope = 'https://www.googleapis.com/auth/drive.appdata';
}

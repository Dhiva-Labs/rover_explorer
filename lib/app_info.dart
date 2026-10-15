/// Single source of truth for product identity and version metadata.
///
/// Keep [version] and [buildNumber] in sync with `pubspec.yaml`'s
/// `version: <version>+<buildNumber>` line and the packaging manifests under
/// `packaging/`.
class AppInfo {
  const AppInfo._();

  static const String name = 'Rover Explorer';
  static const String vendor = 'Dhiva Labs';
  static const String version = '1.0.1';
  static const String buildNumber = '2';
  static const String copyright = 'Copyright © 2026 Dhiva Labs';
  static const String tagline =
      'A Windows XP-style file explorer with the Rover search companion';
  static const String repository =
      'https://github.com/Dhiva-Labs/rover_explorer';
  static const String license = 'MIT License';

  /// Reverse-DNS application id used by the Linux runner and packaging.
  static const String applicationId = 'com.dhivalabs.rover_explorer';

  static String get fullVersion => '$version (build $buildNumber)';
}

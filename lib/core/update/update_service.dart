import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../network/api_client.dart';
import 'app_version.dart';

enum UpdateRequirement {
  /// The installed build is current enough. Also what every failure returns.
  none,

  /// Newer build available; the prompt is dismissible.
  optional,

  /// Below the server's minimum; the app must not be used until updated.
  required,
}

class UpdateStatus {
  const UpdateStatus({
    required this.requirement,
    this.latestVersion,
    this.storeUrl,
    this.message,
  });

  static const upToDate = UpdateStatus(requirement: UpdateRequirement.none);

  final UpdateRequirement requirement;
  final String? latestVersion;
  final String? storeUrl;
  final String? message;

  bool get isRequired => requirement == UpdateRequirement.required;
  bool get isOptional => requirement == UpdateRequirement.optional;
}

class UpdateService {
  UpdateService._();

  /// Set once per launch so a dismissed optional prompt stays dismissed until
  /// the app is restarted. A required update is never dismissible, so it is
  /// deliberately not covered by this.
  static bool optionalPromptDismissed = false;

  static Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// Asks the backend whether this build may keep running.
  ///
  /// Fails open on every error: an app that cannot reach the config endpoint
  /// must keep working, so anything unexpected reads as up to date.
  static Future<UpdateStatus> check() async {
    try {
      final platform = defaultTargetPlatform == TargetPlatform.android
          ? 'android'
          : 'ios';
      final res = await ApiClient.instance.get(
        '/app-version',
        // The business app shares this backend; without `app` the endpoint
        // would answer with its thresholds instead of ours.
        queryParameters: {'app': 'client', 'platform': platform},
      );
      final data = res.data as Map<String, dynamic>;

      final current = AppVersion.parse(await currentVersion());
      final minimum = AppVersion.parse(data['minVersion'] as String? ?? '0.0.0');
      final latest = AppVersion.parse(data['latestVersion'] as String? ?? '0.0.0');
      final storeUrl = data['storeUrl'] as String?;
      final message = data['updateMessage'] as String?;

      if (current < minimum) {
        return UpdateStatus(
          requirement: UpdateRequirement.required,
          latestVersion: latest.toString(),
          storeUrl: storeUrl,
          message: message,
        );
      }
      if (current < latest) {
        return UpdateStatus(
          requirement: UpdateRequirement.optional,
          latestVersion: latest.toString(),
          storeUrl: storeUrl,
          message: message,
        );
      }
      return UpdateStatus.upToDate;
    } catch (e) {
      debugPrint('[UpdateService] version check skipped: $e');
      return UpdateStatus.upToDate;
    }
  }
}

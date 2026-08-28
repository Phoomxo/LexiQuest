import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('notification dependencies are exact production pins', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final dependencies = pubspec['dependencies'] as YamlMap;

    expect(dependencies['flutter_local_notifications'], '22.3.0');
    expect(dependencies['timezone'], '0.11.1');
  });

  test(
    'Android notification delivery is reboot-safe and inexact by default',
    () {
      final settings = File('android/settings.gradle.kts').readAsStringSync();
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final scheduler = File(
        'lib/features/reminders/data/platform_reminder_scheduler.dart',
      ).readAsStringSync();

      final agp = RegExp(
        r'id\("com\.android\.application"\) version "([0-9.]+)"',
      ).firstMatch(settings);
      expect(agp, isNotNull);
      expect(_versionAtLeast(agp!.group(1)!, '8.11.1'), isTrue);
      expect(gradle, matches(RegExp(r'compileSdk\s*=\s*(3[5-9]|[4-9][0-9])')));
      expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
      expect(gradle, contains('multiDexEnabled = true'));
      expect(
        gradle,
        contains(
          'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
        ),
      );
      expect(
        gradle,
        contains('implementation("androidx.multidex:multidex:2.0.1")'),
      );
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
      expect(manifest, contains('ScheduledNotificationReceiver'));
      expect(manifest, contains('ScheduledNotificationBootReceiver'));
      expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
      expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(manifest, isNot(contains('USE_EXACT_ALARM')));
      expect(scheduler, contains('AndroidScheduleMode.inexactAllowWhileIdle'));
      expect(
        File(
          'android/app/src/main/res/drawable/ic_stat_lexiquest.xml',
        ).existsSync(),
        isTrue,
      );
      expect(
        File('android/app/src/main/res/raw/keep.xml').existsSync(),
        isTrue,
      );
    },
  );

  test('iOS notification integration is CocoaPods-backed at iOS 13', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final podfile = File('ios/Podfile').readAsStringSync();
    final lock = File('ios/Podfile.lock').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final debug = File('ios/Flutter/Debug.xcconfig').readAsStringSync();
    final release = File('ios/Flutter/Release.xcconfig').readAsStringSync();
    final workspace = File(
      'ios/Runner.xcworkspace/contents.xcworkspacedata',
    ).readAsStringSync();
    final scheduler = File(
      'lib/features/reminders/data/platform_reminder_scheduler.dart',
    ).readAsStringSync();

    for (final match in RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
    ).allMatches(project)) {
      expect(_versionAtLeast(match.group(1)!, '13.0'), isTrue);
    }
    expect(podfile, contains("platform :ios, '13.0'"));
    expect(lock, contains('flutter_local_notifications'));
    expect(debug, contains('Pods-Runner.debug.xcconfig'));
    expect(release, contains('Pods-Runner.release.xcconfig'));
    expect(workspace, contains('Pods/Pods.xcodeproj'));
    expect(
      delegate,
      contains('UNUserNotificationCenter.current().delegate = self'),
    );
    expect(scheduler, contains('maxPendingIosNotifications = 64'));
  });
}

bool _versionAtLeast(String actual, String minimum) {
  final left = actual.split('.').map(int.parse).toList();
  final right = minimum.split('.').map(int.parse).toList();
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index += 1) {
    final a = index < left.length ? left[index] : 0;
    final b = index < right.length ? right[index] : 0;
    if (a != b) return a > b;
  }
  return true;
}

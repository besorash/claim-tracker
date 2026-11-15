/// The About card's version labels must match pubspec.yaml: the build was
/// once left at 14 while the app had reached build 23.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/core/constants/app_constants.dart';

void main() {
  test('About version and build match pubspec.yaml', () {
    final RegExpMatch m = RegExp(
      r'^version:\s*(\d+)\.\d+\.\d+\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(AppConstants.appVersionLabel, m[1], reason: 'major version');
    expect(AppConstants.appBuildLabel, m[2], reason: 'build number');
  });
}

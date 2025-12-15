import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';

/// Centralized helper for ShowcaseView keys and triggers
class ShowcaseHelper {
  // Define commonly used targets
  static final GlobalKey joinCodeFieldKey = GlobalKey();
  static final GlobalKey joinButtonKey = GlobalKey();
  static final GlobalKey settingsIconKey = GlobalKey();
  static final GlobalKey sendFileButtonKey = GlobalKey();
  static final GlobalKey receivedListKey = GlobalKey();
  static final GlobalKey disconnectKey = GlobalKey();

  // Home screen keys
  static final GlobalKey qrScannerKey = GlobalKey();
  static final GlobalKey linkShareKey = GlobalKey();
  static final GlobalKey connectedDevicesKey = GlobalKey();
  static final GlobalKey settingsKey = GlobalKey();
  static final GlobalKey helpKey = GlobalKey();

  // File operation keys
  static final GlobalKey saveButtonKey = GlobalKey();
  static final GlobalKey downloadAllKey = GlobalKey();
  static final GlobalKey receivedFileCardKey = GlobalKey();

  /// Starts showcase for a standard flow depending on route
  static void startForWebEntry(BuildContext context) {
    ShowCaseWidget.of(
      context,
    ).startShowCase([settingsIconKey, joinCodeFieldKey, joinButtonKey]);
  }

  static void startForChat(BuildContext context) {
    ShowCaseWidget.of(
      context,
    ).startShowCase([sendFileButtonKey, receivedListKey, disconnectKey]);
  }

  static void startForWebRTCChat(BuildContext context) {
    ShowCaseWidget.of(
      context,
    ).startShowCase([sendFileButtonKey, receivedListKey]);
  }

  static void startForHome(BuildContext context) {
    ShowCaseWidget.of(context).startShowCase([
      connectedDevicesKey,
      qrScannerKey,
      linkShareKey,
      settingsKey,
    ]);
  }
}

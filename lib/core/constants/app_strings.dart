class AppStrings {
  static const String appName = 'Fylooo';

  // Welcome and setup strings
  static const String welcomePrefix = 'Welcome to';
  static String get welcomeMessage => '$welcomePrefix $appName';

  // User-facing strings
  static const String directShare = 'Direct Share';
  static const String webUser = 'Web User';

  // Common UI strings
  static const String continueText = 'Continue';
  static const String cancelText = 'Cancel';
  static const String confirmText = 'Confirm';
  static const String okText = 'OK';
  static const String yesText = 'Yes';
  static const String noText = 'No';

  // Action strings
  static const String closeText = 'Close';
  static const String backText = 'Back';
  static const String doneText = 'Done';
  static const String closeAndGoBackText = 'Close & Go Back';

  // Validation messages
  static const String pleaseEnterDeviceName = 'Please enter a device name';
  static const String deviceNameTooShort = 'Device name is too short';
  static const String failedToSaveDeviceName = 'Failed to save device name';
}

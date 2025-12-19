# App Update Configuration Guide

This guide explains how to configure the mandatory app update system using Firebase Remote Config.

## Overview

The app includes a mandatory update system that forces users to update when a new version is available. This ensures all users are on compatible versions for security and feature consistency.

## Firebase Remote Config Setup

### 1. Create Remote Config Parameters

In your Firebase Console, go to Remote Config and create the following parameters:

#### Required Parameters:
- `minimum_version`: The minimum app version that users must have (e.g., "0.1.2")
- `latest_version`: The latest available app version (e.g., "0.1.3")
- `update_required`: Boolean flag to enable/disable mandatory updates (true/false)
- `update_message`: The message shown to users when update is required
- `update_title`: The title of the update dialog
- `update_url_android`: URL to Google Play Store (e.g., "https://play.google.com/store/apps/details?id=com.example.cpft")
- `update_url_ios`: URL to Apple App Store (e.g., "https://apps.apple.com/app/cpft/id1234567890")

### 2. Default Values

The app includes sensible defaults:
- `minimum_version`: "0.1.0"
- `latest_version`: "0.1.2"
- `update_required`: false
- `update_message`: "A new version of the app is available. Please update to continue using the app."
- `update_title`: "Update Required"
- `update_url_android`: "https://play.google.com/store/apps/details?id=com.example.cpft"
- `update_url_ios`: "https://apps.apple.com/app/cpft/id1234567890"

## How It Works

### Update Types

1. **Mandatory Update**: When `current_version < minimum_version`
   - User cannot dismiss the dialog
   - Must update to continue using the app

2. **Optional Update**: When `current_version < latest_version`
   - User can dismiss the dialog with "Later"
   - Can still use the app

### Version Comparison

The system uses semantic versioning (e.g., "1.2.3") and compares versions numerically.

## Configuration Examples

### Force Update to Version 0.1.3
```
minimum_version: "0.1.3"
latest_version: "0.1.3"
update_required: true
update_message: "Critical security update available. Please update immediately."
```

### Optional Update Available
```
minimum_version: "0.1.0"
latest_version: "0.1.4"
update_required: false
update_message: "New features available! Update to enjoy the latest improvements."
```

## Testing

To test the update system:

1. Set `minimum_version` higher than your current app version
2. Set `update_required` to true
3. Publish the Remote Config changes
4. Restart the app - the update dialog should appear

## Deployment Checklist

- [ ] Update `pubspec.yaml` version before releasing
- [ ] Update Firebase Remote Config parameters
- [ ] Test update dialog on both Android and iOS
- [ ] Publish Remote Config changes
- [ ] Submit app update to stores
- [ ] Monitor update adoption rates
# Android App Bundle (AAB) Generation & Upload Guide

Follow these steps exactly to ensure your AAB is correctly signed and accepted by the Google Play Console.

## Step 1: Clean the project
Before generating a new bundle, always clean the previous build data to avoid conflicts.
Run this in your terminal:
```bash
flutter clean
flutter pub get
```

## Step 2: Update Version (Optional but Recommended)
Ensure your `pubspec.yaml` has a version higher than the one currently in production.
Example: `version: 1.1.0+4`

## Step 3: Generate the Signed AAB
Run the following command. The `--release` flag ensures the bundle uses the signing configuration defined in `android/app/build.gradle.kts`.
```bash
flutter build appbundle --release
```
*The resulting file will be located at:*
`build/app/outputs/bundle/release/app-release.aab`

## Step 4: Correct Upload to Play Console
To avoid the "You cannot remove all production APKs" error, handle the release track correctly:

1. **Production Track**: Go to **Release** > **Production**.
2. **Discard Drafts**: If there is any existing draft release, click the three dots and select **Discard**.
3. **Create New Release**: Click the button in the top right.
4. **Upload AAB**: Drag and drop the `app-release.aab` you just generated.
5. **Attach correctly**: Once uploaded, ensure the AAB appears in the **"App bundles"** list with the status **"Included"**.
6. **Review & Rollout**: 
   - Click **Next** / **Save**.
   - Click **Review release**.
   - Ensure the previous production bundle is in the **"Deactivated"** or **"Replaced"** section of the review screen.
   - Click **Start rollout to Production**.

### Troubleshooting the "Remove all" error:
If the error persists even with a new AAB:
- It usually means you didn't click **"Include"** on the new AAB or you tried to delete the old one manually before the new one was processed.
- The Play Console requires one version to always be "active". Adding a new one automatically replaces the old one; you don't need to (and shouldn't) delete the old one first.

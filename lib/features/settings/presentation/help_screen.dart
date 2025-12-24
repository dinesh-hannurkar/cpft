import 'package:flutter/material.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/core/constants/app_strings.dart';
import 'package:fylooo/shared/widgets/back_button_chip.dart';
import 'package:fylooo/shared/widgets/primary_app_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PrimaryAppBar(
        leading: BackButtonChip(onPressed: () => Navigator.pop(context)),
        title: 'Help & Support',
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE2F6FB), Color(0xFFFFFFFF)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSizes.md),
            children: [
              _buildSection(
                'Getting Started',
                [
                  _HelpItem(
                    icon: Icons.play_circle_outline,
                    title: 'Quick Start Guide',
                    subtitle: 'Learn how to connect and transfer files',
                    onTap: () => _showQuickStart(context),
                  ),
                  _HelpItem(
                    icon: Icons.connect_without_contact,
                    title: 'Connection Guide',
                    subtitle: 'Troubleshooting connection issues',
                    onTap: () => _showConnectionGuide(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.lg),
              _buildSection(
                'Troubleshooting',
                [
                  _HelpItem(
                    icon: Icons.wifi_off,
                    title: 'Connection Refused',
                    subtitle: 'Fix connection refused errors',
                    onTap: () => _showConnectionRefusedGuide(context),
                  ),
                  _HelpItem(
                    icon: Icons.bug_report,
                    title: 'Debug Guide',
                    subtitle: 'Advanced debugging tools and logs',
                    onTap: () => _showDebugGuide(context),
                  ),
                  _HelpItem(
                    icon: Icons.phone_android,
                    title: 'Platform Issues',
                    subtitle: 'Android and iOS specific fixes',
                    onTap: () => _showPlatformIssues(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.lg),
              _buildSection(
                'Features',
                [
                  _HelpItem(
                    icon: Icons.web,
                    title: 'Web Platform Support',
                    subtitle: 'Using ${AppStrings.appName} in web browsers',
                    onTap: () => _showWebPlatformGuide(context),
                  ),
                  _HelpItem(
                    icon: Icons.file_present,
                    title: 'File Transfer Features',
                    subtitle: 'Advanced file operations and management',
                    onTap: () => _showFileFeatures(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.lg),
              _buildSection(
                'Contact & Support',
                [
                  _HelpItem(
                    icon: Icons.email,
                    title: 'Send Feedback',
                    subtitle: 'Report bugs or suggest features',
                    onTap: () => _launchEmail(),
                  ),
                  _HelpItem(
                    icon: Icons.help_center,
                    title: 'FAQs',
                    subtitle: 'Frequently asked questions',
                    onTap: () => _showFAQs(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<_HelpItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSizes.sm, bottom: AppSizes.sm),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.darkPrimary,
            ),
          ),
        ),
        ...items,
      ],
    );
  }

  void _showQuickStart(BuildContext context) {
    final appName = AppStrings.appName;
    _showMarkdownContent(
      context,
      'Quick Start Guide',
      '''
**Quick Start Guide**

**Connecting Devices**

Follow these simple steps to connect your devices:

• Open $appName on both devices you want to connect
• Ensure both devices are connected to the same WiFi network
• Grant permissions when prompted (location, storage, camera, etc.)
• Wait for device discovery - devices will appear on the radar screen
• Tap a device on the radar to initiate connection
• Accept the connection on the receiving device when prompted

**Transferring Files**

Once connected, transferring files is easy:

• Connect to a device using the steps above
• Tap the chat icon to open the chat screen
• Tap the attachment icon to select files
• Choose files from your device storage
• Files will transfer automatically once selected

**Pro Tips**

• Keep both devices awake during transfer to prevent interruptions
• Large files may take time - be patient and maintain stable connection
• Check your WiFi signal strength for best performance
• Ensure firewall/antivirus isn't blocking the connection
• Use the same network - different subnets may cause issues

**Troubleshooting**

If devices don't appear:
• Restart both apps
• Check WiFi connection
• Verify permissions are granted
• Try different devices
''',
    );
  }

  void _showConnectionGuide(BuildContext context) {
    final appName = AppStrings.appName;
    _showMarkdownContent(
      context,
      'Connection Troubleshooting',
      '''
**Connection Troubleshooting Guide**

**Common Connection Problems**

**Devices Not Appearing on Radar**
Possible causes and solutions:

• WiFi Network Issues
  - Both devices must be on the same WiFi network
  - Check if devices are on different subnets
  - Try switching to a different WiFi network

• Permission Problems
  - Grant location permissions (required for network discovery)
  - Allow storage permissions for file access
  - Enable local network permissions (iOS)

• Security Software
  - Firewall may be blocking connections
  - Antivirus software interfering with network traffic
  - VPN connections can cause issues

**Connection Refused Errors**
When connection fails after device discovery:

• Restart Both Apps
  - Close $appName completely on both devices
  - Wait 10 seconds, then reopen

• Network Stability
  - Check WiFi signal strength
  - Avoid congested networks
  - Try moving closer to router

• Device Naming
  - Use unique device names
  - Avoid special characters in names

**Transfer Failures**
File transfer starts but fails:

• Storage Space
  - Check available space on receiving device
  - Clear space if needed

• File Size Issues
  - Very large files may timeout
  - Try smaller files first for testing

• Network Speed
  - Slow connections affect large transfers
  - Check upload/download speeds

**Advanced Troubleshooting**

**Network Diagnostics**
• Check IP addresses are in same subnet
• Verify multicast is enabled (Android)
• Test with different devices
• Check router settings and firewall

**Debug Information**
• Device Info: Model, OS version, $appName version
• Network Type: Home WiFi, office, public hotspot
• Error Messages: Exact error text shown
• Steps to Reproduce: Detailed sequence

**Platform-Specific Fixes**
• Android: Enable multicast in developer options
• iOS: Grant local network permissions
• Web: Check browser compatibility

**Still Having Issues?**

Contact Support with this information:
• Device models and OS versions
• Network environment details
• Exact error messages
• Steps to reproduce the issue
''',
    );
  }

  void _showConnectionRefusedGuide(BuildContext context) {
    final appName = AppStrings.appName;
    _showMarkdownContent(
      context,
      'Connection Refused Fix',
      '''
**Connection Refused Error - Quick Fix**

**Immediate Solution**

Try this first - it works 90% of the time:

• Restart both devices completely
• Reopen $appName app on both devices
• Try connecting again immediately

**If That Doesn't Work**

**Android-Specific Fixes**
• Disable Battery Optimization for $appName in Settings
• Check Do Not Disturb mode isn't blocking notifications
• Enable Multicast in Developer Options
• Grant Precise Location permission

**iOS-Specific Fixes**
• Disable Low Power Mode in Settings
• Enable Background App Refresh for $appName
• Keep app in foreground during connection attempts
• Check Local Network permissions in Privacy settings

**Network-Related Fixes**
• Change WiFi network (try different access point)
• Disable VPN if active
• Check firewall settings on router/computer
• Try mobile hotspot as alternative network
• Test on home network vs office/public WiFi

**Advanced Diagnostics**

**Network Testing**
• Check if both devices have IP addresses in same subnet
• Example: 192.168.1.xxx range
• Use device settings to view IP address

**Connection Testing**
• Test basic connectivity between devices
• Try pinging one device from the other
• Check if ports 8080 and 5353 are accessible

**Need More Help?**

Please provide this information when contacting support:

• Device Models: e.g., "Samsung Galaxy S23, iPhone 15 Pro"
• OS Versions: e.g., "Android 14, iOS 17.2"
• Network Type: Home WiFi, Office, Public Hotspot, Mobile Data
• Exact Error Message: Copy the full error text
• Reproduction Steps: Detailed steps that cause the error

Contact: support@cpft.app
''',
    );
  }

  void _showDebugGuide(BuildContext context) {
    final appName = AppStrings.appName;
    _showMarkdownContent(
      context,
      'Debug Guide',
      '''
**Debug & Troubleshooting Tools**

**Debug Commands & Testing**

**Network Testing Commands**
• Test basic connectivity: ping [device-ip]
• Check DNS resolution: nslookup [device-name].local
• Browse network services: dns-sd -B _http._tcp

**Connection Testing**
• Test HTTP connectivity: curl -I http://[device-ip]:8080/
• Test TCP connection: telnet [device-ip] 8080

**Log Analysis Guide**

**Finding Device Logs**

**Android:**
• Open Android Studio → Device File Explorer
• Navigate to /data/data/com.omnity.fylooo/logs/
• Look for cpft_debug.log files

**iOS:**
• Open Xcode → Devices and Simulators
• Select your device → View Device Logs
• Filter by "$appName" or process name

**Web Browser:**
• Press F12 to open Developer Tools
• Check Console tab for JavaScript errors
• Look for network requests in Network tab

**Common Error Patterns**

| Error Message | Likely Cause | Solution |
|---------------|-------------|----------|
| "Connection refused" | Network/firewall blocking | Check firewall, restart devices |
| "Timeout" | Network congestion or device sleep | Improve WiFi, keep devices awake |
| "Permission denied" | Missing app permissions | Grant all required permissions |
| "Multicast disabled" | Android multicast restriction | Enable in developer options |
| "Local network denied" | iOS local network permission | Grant in Settings → Privacy |

**Advanced Diagnostic Tools**

**Network Packet Analysis**
Using Wireshark or similar tools:
• Capture network traffic during connection attempts
• Look for UDP multicast packets on port 5353 (device discovery)
• Check TCP connections on port 8080 (file transfer)
• Verify packets are being sent/received by both devices

**Device Compatibility Testing**
• Test different device combinations (Android↔iOS, etc.)
• Try various network environments (home, office, public)
• Use network simulation tools to test edge cases
• Monitor network latency and packet loss

**System Resource Monitoring**
• CPU usage during transfers
• Memory consumption with large files
• Battery drain patterns
• WiFi signal strength stability

**Performance Optimization**

**Network Configuration**
• Router QoS settings for better prioritization
• TCP window scaling adjustments
• Connection timeout optimizations
• Packet retransmission settings

**Device Settings**
• Disable battery optimization for $appName
• Prevent device sleep during transfers
• Enable high-performance mode if available
• Clear app cache periodically

**When to Contact Support**

Gather this information before contacting:

• Detailed logs from both devices
• Network analysis results
• Performance metrics during failure
• Exact reproduction steps
• System configuration details
''',
    );
  }

  void _showPlatformIssues(BuildContext context) {
    final appName = AppStrings.appName;
    _showMarkdownContent(
      context,
      'Platform-Specific Issues',
      '''
**Platform-Specific Issues & Solutions**

**Android-Specific Issues**

**Multicast Discovery Problems**
Device discovery not working on Android:

• Enable Multicast in Developer Options
  - Go to Settings → Developer Options
  - Find "Wi-Fi multicast" or "Multicast"
  - Enable the setting

• Disable Battery Optimization
  - Settings → Apps → $appName → Battery
  - Set to "Don't optimize" or "Unrestricted"

• Check WiFi Settings
  - Ensure WiFi scanning is enabled
  - Try forgetting and reconnecting to WiFi
  - Check advanced WiFi settings

**Hotspot Connection Issues**
Problems connecting via mobile hotspot:

• Location Permission Required
  - Hotspot discovery needs precise location access
  - Grant "Allow all the time" location permission

• Android Version Restrictions
  - Some Android versions restrict hotspot API access
  - Alternative: Use regular WiFi instead of hotspot

• Device Compatibility
  - Older Android versions may have limitations
  - Check Android 8.0+ for best compatibility

**File Access Permissions**
Issues with file selection/storage:

• Storage Permission
  - Grant "All files access" on Android 11+
  - Or use scoped storage for media files

• Media Permissions
  - Separate permissions for photos, videos, audio
  - Grant all media permissions for full access

**iOS-Specific Issues**

**Local Network Permission**
"Local Network" permission required:

• Grant Permission
  - When prompted, tap "Allow" for local network access
  - Check Settings → Privacy & Security → Local Network
  - Ensure $appName has local network permission enabled

• Re-grant Permission
  - Delete and reinstall app to reset permissions
  - Or toggle the permission off/on in settings

**Background Execution**
App being suspended in background:

• Enable Background App Refresh
  - Settings → General → Background App Refresh
  - Ensure $appName is enabled

• Disable Low Power Mode
  - Settings → Battery → Low Power Mode
  - Turn off when using $appName

• Keep App Active
  - Avoid switching apps during transfers
  - Keep $appName in foreground for best performance

**Hotspot Limitations**
iOS hotspot discovery restrictions:

• iOS Restrictions
  - iOS heavily restricts personal hotspot discovery
  - Workaround: Use regular WiFi networks instead

• Alternative Solutions
  - Connect both devices to same WiFi network
  - Use WebRTC mode for browser connections
  - Try different network environments

**Web Platform Issues**

**Browser Compatibility**
Supported and limited browsers:

• Full Support (Recommended)
  - Chrome (v90+) - Complete feature support
  - Edge (Chromium-based) - All features available
  - Opera - Full compatibility

• Limited Support
  - Firefox (v85+) - Missing some advanced features
  - WebRTC data channels may be slower
  - File system access limited

• Basic Support Only
  - Safari (v14+) - Major limitations
  - WebRTC support incomplete
  - File system access not supported

**Camera & Permissions**
QR scanning and camera access:

• HTTPS Required
  - Camera access requires secure connection (HTTPS)
  - Local development needs valid SSL certificate

• Permission Grants
  - Allow camera permission when prompted
  - Check browser site settings if blocked

**File System Access**
File upload/download limitations:

• File System API
  - Modern browsers support File System Access API
  - Allows direct file system access

• Download Restrictions
  - Browser may block automatic downloads
  - User interaction required for downloads

**Performance Considerations**
Web platform limitations:

• Background Limitations
  - Transfers may pause when tab becomes inactive
  - Keep browser tab active during transfers

• Size Limitations
  - Browser-imposed file size limits
  - Memory constraints for large files

• Network Restrictions
  - CORS policies may limit connections
  - Mixed content warnings on HTTP sites
''',
    );
  }

  void _showWebPlatformGuide(BuildContext context) {
    final appName = AppStrings.appName;
    _showMarkdownContent(
      context,
      'Web Platform Support',
      '''
**Web Platform Features & Limitations**

**Supported Browsers**

**Full Support (Recommended)**
• Chrome (v90+) - Complete feature support
• Edge (Chromium-based) - All features available
• Opera - Full compatibility

**Limited Support**
• Firefox (v85+) - Missing some advanced features
  - WebRTC data channels may be slower
  - File system access limited

**Basic Support Only**
• Safari (v14+) - Major limitations
  - WebRTC support incomplete
  - File system access not supported

**Available Features**

**Device Discovery**
• WebRTC-based discovery for browser-to-browser
• QR code scanning for easy connection setup
• Room-based connections via shareable links

**File Transfer**
• Direct P2P transfer between browsers
• Real-time progress tracking
• Multiple file support in single transfer
• Resume capability for interrupted transfers

**Real-time Chat**
• Text messaging during file transfers
• Connection status updates
• Transfer notifications

**QR Code Integration**
• Camera access for QR scanning
• Automatic connection setup
• Fallback manual entry

**Current Limitations**

**Network Restrictions**
• Cannot discover local devices on same network
• No multicast discovery (UDP limitations)
• Browser security policies restrict local network access

**File System Access**
• Browser sandboxing limits direct file access
• User interaction required for downloads
• File size limits imposed by browser

**Performance Constraints**
• Background processing limited when tab inactive
• Memory limitations for large files
• Network throttling when browser tab hidden

**Getting Started with Web Version**

**Initial Setup**
1. Open $appName in supported web browser
2. Grant camera permission when prompted for QR scanning
3. Allow file access permissions for uploads
4. Use WebRTC mode for browser connections

**Connection Methods**
1. Mobile App Method:
  - Open $appName on mobile device
   - Generate WebRTC room link
   - Share link with browser or scan QR code

2. Browser-to-Browser:
  - Open $appName in two browser tabs/windows
   - Use same room ID in both instances
   - Automatic peer discovery

**Troubleshooting Web Issues**

**Camera Permission Issues**
• Enable HTTPS - Camera requires secure connection
• Check browser permissions in address bar
• Reset permissions in browser settings
• Try different browser if issues persist

**File Access Problems**
• Grant file system permissions when prompted
• Check download settings in browser
• Clear browser cache if files won't download
• Verify file size limits (usually 2GB max)

**Connection Failures**
• Ensure stable internet connection
• Try different browsers for compatibility
• Disable VPN/extensions that may interfere
• Check network latency and stability

**Performance Issues**
• Monitor browser memory usage
• Clear browser cache periodically
• Close other tabs to free resources
• Update browser to latest version

**Best Practices**

**For Optimal Performance**
• Use modern browsers (Chrome/Edge recommended)
• Maintain stable internet connection
• Keep browser tab active during transfers
• Clear cache regularly for best performance

**Security Considerations**
• Use HTTPS for secure connections
• Avoid public networks for sensitive transfers
• Verify connection before sending files
• Keep browser updated for security patches

**File Transfer Tips**
• Start with small files for testing
• Monitor transfer progress closely
• Ensure sufficient browser memory
• Resume interrupted transfers when possible
''',
    );
  }

  void _showFileFeatures(BuildContext context) {
    _showMarkdownContent(
      context,
      'File Transfer Features',
      '''
**File Transfer Features & Capabilities**

**Supported File Types**

**Universal Support**
• All file formats supported without restrictions
• Any file size (limited only by device storage)
• Multiple files in single transfer batch
• Folder structures preserved when possible

**Performance Capabilities**
• Large files: GB-sized files supported
• Resume transfers: Interrupted transfers can resume
• Parallel transfers: Multiple files simultaneously
• Real-time progress: Live transfer status updates

**Transfer Options & Controls**

**Auto-Accept Mode**
• Automatic file reception without user confirmation
• Configurable timeout for security
• Device-specific settings per connection

**Batch Operations**
• Save All: Download multiple received files at once
• Send Multiple: Select and send many files together
• Transfer queue: Manage pending transfers
• Retry failed: Automatically retry failed transfers

**File Preview & Management**
• File preview: View files before downloading
• File information: Size, type, date, source
• File organization: Sort by name, size, date
• Selective deletion: Remove unwanted files

**File Management System**

**Organized Storage**
• Date-based folders: Files organized by transfer date
• Device-based naming: Folders named by source device
• Custom categories: User-defined organization
• Quick search: Find files by name or type

**Automatic Cleanup**
• Time-based cleanup: Remove old files automatically
• Space monitoring: Alert when storage is low
• Usage statistics: Track storage consumption
• Manual cleanup: User-initiated file removal

**Storage Optimization**
• Compression options: Reduce file sizes when possible
• Temporary files: Automatic cleanup of temp files
• Duplicate handling: Smart duplicate file detection
• Storage analytics: Usage patterns and trends

**Performance Features**

**Speed Optimizations**
• Parallel streams: Multiple data streams for speed
• Dynamic chunking: Optimal packet sizes
• Adaptive transfer: Adjust to network conditions
• Memory management: Efficient RAM usage

**Network Adaptation**
• Auto-detection: Optimal settings per network type
• Bandwidth monitoring: Real-time speed adjustments
• Protocol optimization: Best transfer method selection
• Timeout management: Smart retry mechanisms

**Security & Privacy**

**Transfer Security**
• End-to-end encryption: Files encrypted in transit
• Device authentication: Verify connection partners
• Transfer logs: Complete audit trail
• Unauthorized access: Strict permission controls

**Privacy Protection**
• No cloud storage: Files never stored on servers
• Local network only: No internet exposure
• Automatic cleanup: No residual file traces
• File scanning: Optional security scans

**Data Integrity**
• Checksum verification: Ensure file integrity
• Transfer validation: Confirm complete transfers
• Corruption detection: Identify damaged files
• Backup protection: Prevent accidental overwrites

**Monitoring & Analytics**

**Transfer Statistics**
• Transfer speeds: Real-time and average speeds
• Success rates: Transfer completion statistics
• Time tracking: Transfer duration analytics
• Size metrics: File size distribution analysis

**Usage Insights**
• Device patterns: Most used device connections
• File type analysis: Popular file formats
• Network performance: Connection quality metrics
• Usage patterns: Peak usage times and days

**Advanced Features**

**Custom Configurations**
• Transfer settings: Customizable chunk sizes
• Retry policies: Configurable retry attempts
• Timeout settings: Adjustable connection timeouts
• Buffer sizes: Memory usage optimization

**Integration Options**
• System integration: Share menu integration
• Desktop sync: Cross-platform file sync
• Cloud bridging: Optional cloud storage links
• API access: Developer integration options

**Future Enhancements**

**Planned Features**
• Folder sync: Complete folder synchronization
• Differential transfer: Send only changed parts
• On-the-fly compression: Reduce transfer sizes
• Advanced encryption: Military-grade security options
''',
    );
  }

  void _launchEmail() async {
    final appName = AppStrings.appName;
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@cpft.app',
      queryParameters: {
        'subject': '$appName Support Request',
        'body': '''
Please describe your issue:

Device: [Android/iOS/Web]
OS Version: [e.g., Android 13, iOS 17]
$appName Version: [check in Settings → Version]
Network Type: [WiFi/Home/Office/Public]

Steps to reproduce:
1.
2.
3.

Additional details:
''',
      },
    );

    try {
      await launchUrl(emailUri);
    } catch (e) {
      // Fallback - could show a dialog with email address
      debugPrint('Could not launch email: $e');
    }
  }

  void _showFAQs(BuildContext context) {
    final appName = AppStrings.appName;
    _showMarkdownContent(
      context,
      'Frequently Asked Questions',
      '''
**Frequently Asked Questions**

**General Questions**

**What is $appName?**
$appName (Cross-Platform File Transfer) is a modern, peer-to-peer file sharing application that works seamlessly across Android, iOS, and Web platforms. Unlike cloud-based services, $appName transfers files directly between devices using your local WiFi network for maximum speed and privacy.

**Is $appName free?**
Yes, completely free! $appName is open-source and will always remain free to use. No hidden costs, subscriptions, or premium features. All functionality is available to everyone.

**Is my data secure?**
Absolutely secure. Files are transferred directly between devices using local network connections. No data passes through external servers, cloud storage, or third-party services. Your files remain private and secure.

**How does $appName work?**
$appName uses advanced networking technologies:
• Device Discovery: Multicast DNS (mDNS) for automatic device detection
• Direct Connections: Peer-to-peer TCP connections for file transfer
• WebRTC: Browser-to-device connections for web platform
• Local Network: All transfers happen within your WiFi network

**Connection Questions**

**Why don't devices appear on the radar?**
Common causes:
• Different Networks: Both devices must be on the same WiFi network
• Missing Permissions: Location and local network permissions required
• Firewall Blocks: Security software may block discovery
• Weak Signal: Poor WiFi connection affects discovery

**Why does connection get refused?**
Quick fixes:
• Restart Apps: Close and reopen $appName on both devices
• Check Network: Ensure stable WiFi connection
• Device Names: Use unique, simple device names
• Battery Settings: Disable battery optimization for $appName

**Can I use mobile data?**
No, WiFi only. $appName requires local network connectivity for device discovery and file transfer. Mobile data networks don't support the required multicast and peer-to-peer features.

**File Transfer Questions**

**How large files can I transfer?**
No strict limits! $appName supports files of any size, limited only by your device storage and network speed. Successfully tested with multi-gigabyte files.

**Can I transfer multiple files?**
Yes! Select multiple files at once or use the "Save All" feature for batch operations. $appName handles multiple simultaneous transfers efficiently.

**What file types are supported?**
All file types! $appName doesn't restrict file formats. Transfer documents, photos, videos, apps, archives, system files - anything your device can access.

**How fast are transfers?**
Transfer speed depends on:
• WiFi network speed (usually 50-300 Mbps)
• Device storage speed (SSD faster than HDD)
• Device processing power
• File size and type

**Platform-Specific Questions**

**Android Issues**
Multicast Problems:
• Enable "Wi-Fi multicast" in Developer Options
• Disable battery optimization for CPFT
• Grant precise location permission

Hotspot Issues:
• iOS devices have restrictions with personal hotspots
• Use regular WiFi networks when possible
• Check iOS local network permissions

**iOS Issues**
Local Network Permission:
• Grant "Local Network" permission when prompted
• Check Settings → Privacy → Local Network
• Reinstall app if permission doesn't appear

Background Restrictions:
• Enable Background App Refresh
• Disable Low Power Mode
• Keep app in foreground during transfers

**Web Platform Issues**
Browser Compatibility:
• Chrome/Edge: Full support
• Firefox: Limited features
• Safari: Basic support only

Camera Permission:
• HTTPS required for camera access
• Grant permission when prompted
• Check browser settings if blocked

**Troubleshooting Questions**

**Transfer keeps failing?**
Check these:
• Storage space on receiving device
• Network stability and speed
• Device battery and performance mode
• Security software interference

**App crashes or freezes?**
Solutions:
• Force restart the app
• Reboot devices completely
• Clear app cache and data
• Update app to latest version

**Web version not working?**
Try these:
• Use HTTPS (required for camera)
• Update browser to latest version
• Disable VPN and extensions
• Clear browser cache

**Support & Contact**

**How to get help?**
Contact support:
• Email: support@cpft.app
• Include details: Device info, error messages, steps to reproduce
• Check guides: Review troubleshooting sections above first

**Found a bug?**
Report bugs:
• Describe the issue clearly
• Include device information
• Steps to reproduce
• Error messages and logs

**Have a suggestion?**
Feature requests:
• Send to: support@cpft.app
• Describe the feature and use case
• Explain benefits for other users

**Pro Tip**: Most issues are resolved by restarting devices and ensuring both are on the same WiFi network. Try that first before contacting support!
''',
    );
  }

  TextSpan _parseBoldText(String text) {
    final List<TextSpan> spans = [];
    final RegExp boldRegex = RegExp(r'\*\*(.*?)\*\*');
    final matches = boldRegex.allMatches(text);

    int lastIndex = 0;
    for (final match in matches) {
      // Add text before the bold part
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Colors.black87,
          ),
        ));
      }

      // Add the bold text
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(
          fontSize: 14,
          height: 1.5,
          color: Colors.black87,
          fontWeight: FontWeight.bold,
        ),
      ));

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: const TextStyle(
          fontSize: 14,
          height: 1.5,
          color: Colors.black87,
        ),
      ));
    }

    return TextSpan(children: spans);
  }

  void _showMarkdownContent(BuildContext context, String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(AppSizes.md),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey, width: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSizes.md),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: RichText(
                      text: _parseBoldText(content),
                      textScaler: const TextScaler.linear(1.0),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HelpItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.cardRadiusSm),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.xs,
        ),
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(AppSizes.cardRadiusSm),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
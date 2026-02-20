import 'package:flutter/material.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/shared/widgets/primary_app_bar.dart';
import 'package:fylooo/shared/widgets/back_button_chip.dart';
import 'package:fylooo/features/home/presentation/widgets/tiles/device_list_tile.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:fylooo/features/chat/presentation/chat_screen.dart';
import 'package:fylooo/features/chat/services/connection_manager.dart';
import 'package:fylooo/services/database_service.dart';

class HistoryListScreen extends StatefulWidget {
  final ConnectionManager connectionManager;
  final String myDeviceName;

  final bool showAppBar;

  const HistoryListScreen({
    super.key,
    required this.connectionManager,
    required this.myDeviceName,
    this.showAppBar = true,
  });

  @override
  State<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends State<HistoryListScreen> {
  late Future<List<Map<String, dynamic>>> _devicesFuture;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[HistoryListScreen] 🟢 Initializing - fetching recent devices...',
    );
    _devicesFuture = DatabaseService().getRecentDevices();
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshHistory() async {
    setState(() {
      _devicesFuture = DatabaseService().getRecentDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: widget.showAppBar
          ? PrimaryAppBar(
              leading: BackButtonChip(onPressed: () => Navigator.pop(context)),
              title: 'Recent Chats (24h)',
              centerTitle: true,
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _devicesFuture,
        builder: (context, snapshot) {
          debugPrint(
            '[HistoryListScreen] 🔄 Builder Update: ${snapshot.connectionState}, hasData=${snapshot.hasData}, hasError=${snapshot.hasError}, dataLen=${snapshot.data?.length}',
          );
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final devices = snapshot.data ?? [];

          if (devices.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No recent history',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              // Ensure content starts below the AppBar (Status Bar + Toolbar)
              SliverSafeArea(
                bottom: false,
                sliver: SliverPadding(
                  padding: const EdgeInsets.only(top: 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final device = devices[index];
                      final deviceId = device['deviceId'] as String;
                      final lastTime = DateTime.fromMillisecondsSinceEpoch(
                        device['lastMessageTime'] as int,
                      );

                      // Add top padding to the first item for visual spacing (8px)
                      // Use Column to add spacing if it's the first item?
                      // Better: Use SliverPadding around the list.
                      return Column(
                        children: [
                          DeviceListTile(
                            deviceId: deviceId,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ShowCaseWidget(
                                    builder: (context) => ChatScreen(
                                      deviceName: deviceId,
                                      ipAddress: deviceId,
                                      port: 0,
                                      myDeviceName: widget.myDeviceName,
                                      connectionManager:
                                          widget.connectionManager,
                                      initialDeviceId: deviceId,
                                      isOffline: true,
                                    ),
                                  ),
                                ),
                              ).then((_) => _refreshHistory());
                            },
                            leadingOverride: CircleAvatar(
                              backgroundColor: AppColors.primary,
                              child: Text(
                                deviceId.isNotEmpty
                                    ? deviceId[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            subtitleOverride:
                                'Last active: ${_formatTime(lastTime)}',
                            subtitleColorOverride: Colors.grey,
                          ),
                          if (index < devices.length - 1)
                            const Divider(height: 1),
                          if (index == devices.length - 1)
                            const SizedBox(height: 16),
                        ],
                      );
                    }, childCount: devices.length),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

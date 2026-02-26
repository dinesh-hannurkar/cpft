import 'package:flutter/material.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/shared/widgets/primary_app_bar.dart';
import 'package:fylooo/shared/widgets/back_button_chip.dart';
import 'package:fylooo/features/home/presentation/widgets/tiles/device_list_tile.dart';
import 'package:fylooo/features/chat/presentation/chat_screen.dart';
import 'package:fylooo/features/chat/services/connection_manager.dart';
import 'package:fylooo/services/database_service.dart';
import 'package:fylooo/services/discovery_service.dart';

class HistoryListScreen extends StatefulWidget {
  final ConnectionManager connectionManager;
  final String myDeviceName;
  final DiscoveryService discoveryService;
  final bool showAppBar;

  const HistoryListScreen({
    super.key,
    required this.connectionManager,
    required this.myDeviceName,
    required this.discoveryService,
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
              backgroundColor: Colors.transparent,
              leading: BackButtonChip(onPressed: () => Navigator.pop(context)),
              title: 'Recent Chats (24h)',
              centerTitle: true,
            )
          : null,
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
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _devicesFuture,
            builder: (context, snapshot) {
              debugPrint(
                '[HistoryListScreen] 🔄 Builder Update: ${snapshot.connectionState}, hasData=${snapshot.hasData}, hasError=${snapshot.hasError}, dataLen=${snapshot.data?.length}',
              );
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return RefreshIndicator(
                  onRefresh: _refreshHistory,
                  backgroundColor: AppColors.white,
                  color: AppColors.primary,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Error: ${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final devices = snapshot.data ?? [];

              if (devices.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refreshHistory,
                  backgroundColor: AppColors.white,
                  color: AppColors.primary,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.history,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No recent history',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              // Add some bottom padding to compensate for the AppBar height
                              // if it's visible, to make it visually centered in the remaining space
                              if (widget.showAppBar) const SizedBox(height: 80),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refreshHistory,
                backgroundColor: AppColors.white,
                color: AppColors.primary,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final device = devices[index];
                          final deviceId = device['deviceId'] as String;
                          final lastTime = DateTime.fromMillisecondsSinceEpoch(
                            device['lastMessageTime'] as int,
                          );

                          return Column(
                            children: [
                              DeviceListTile(
                                deviceId: deviceId,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      settings: const RouteSettings(
                                        name: '/chat',
                                      ),
                                      builder: (_) => ChatScreen(
                                        deviceName: deviceId,
                                        ipAddress: deviceId,
                                        port: 0,
                                        myDeviceName: widget.myDeviceName,
                                        connectionManager:
                                            widget.connectionManager,
                                        discoveryService:
                                            widget.discoveryService,
                                        initialDeviceId: deviceId,
                                        isOffline: true,
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
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  indent: 16,
                                  endIndent: 16,
                                  color: AppColors.skyBlue.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                              if (index == devices.length - 1)
                                const SizedBox(height: 16),
                            ],
                          );
                        }, childCount: devices.length),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

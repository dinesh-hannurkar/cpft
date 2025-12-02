import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import '../../../../features/chat/services/connection_manager.dart';
import '../../../../services/discovery_service.dart';
import '../../../../features/chat/models/connection_state.dart';

class ConnectionFlowDialog extends StatefulWidget {
  final String myDeviceName;
  final String peerDeviceName;
  final String peerIp;
  final int p2pPort;
  final ConnectionManager connectionManager;
  final DiscoveryService discoveryService;

  const ConnectionFlowDialog({
    super.key,
    required this.myDeviceName,
    required this.peerDeviceName,
    required this.peerIp,
    required this.p2pPort,
    required this.connectionManager,
    required this.discoveryService,
  });

  @override
  State<ConnectionFlowDialog> createState() => _ConnectionFlowDialogState();
}

class _ConnectionFlowDialogState extends State<ConnectionFlowDialog> {
  ConnectionStatus _status = ConnectionStatus.connecting;
  String? _error;
  late final _service = widget.connectionManager.getOrCreateConnection(
    widget.peerDeviceName,
  );
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[ConnectionFlowDialog] Creating connection to ${widget.peerDeviceName}');
    _service.addStatusListener(_onStatus);
    _connect();
  }

  Future<void> _connect() async {
    // Don't attempt connection if already connecting or connected
    final currentStatus = _service.currentConnection?.status;
    if (currentStatus == ConnectionStatus.connected || 
        currentStatus == ConnectionStatus.connecting) {
      debugPrint('[ConnectionFlowDialog] Already $currentStatus, skipping connect()');
      setState(() {
        _status = currentStatus!; // safe: we checked it's not null above
      });
      if (currentStatus == ConnectionStatus.connected) {
        // Already connected, close dialog immediately
        if (mounted && !_completed) {
          _completed = true;
          Navigator.of(context).pop('connected');
        }
      }
      return;
    }
    
    try {
      await _service.connect(
        widget.peerDeviceName,
        widget.peerIp,
        widget.p2pPort,
      );
      // After TCP connect, we wait for handshake to flip to connected.
      setState(() {
        _status =
            ConnectionStatus.connecting; // remains connecting until handshake
      });
    } catch (e) {
      setState(() {
        _status = ConnectionStatus.failed;
        _error = e.toString();
      });
    }
  }

  void _onStatus(ConnectionInfo info) {
    if (!mounted) return;
    debugPrint('[ConnectionFlowDialog] Status update for ${widget.peerDeviceName}: ${info.status}');
    setState(() {
      _status = info.status;
      _error = info.error;
    });
    // When connected, close this dialog and let caller proceed
    if (info.status == ConnectionStatus.connected && !_completed) {
      _completed = true;
      debugPrint('[ConnectionFlowDialog] Connection established to ${widget.peerDeviceName}, closing dialog');
      // Pop with a result the caller can use to navigate
      Navigator.of(context).pop('connected');
    } else if ((info.status == ConnectionStatus.failed || info.status == ConnectionStatus.disconnected) && !_completed) {
      // Provide quick feedback to the initiator if rejected/disconnected
      final messenger = ScaffoldMessenger.maybeOf(context);
      final isRejected = (info.error ?? '').toLowerCase().contains('rejected');
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            isRejected
                ? 'Request rejected by ${widget.peerDeviceName}'
                : (info.status == ConnectionStatus.failed
                    ? 'Failed to connect to ${widget.peerDeviceName}'
                    : 'Disconnected from ${widget.peerDeviceName}'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      // If explicitly rejected, avoid full discovery restart (too noisy); just send a fresh announcement
      if (isRejected) {
        widget.discoveryService.announce();
      } else {
        // For genuine failures/disconnects, perform a lighter refresh first
        widget.discoveryService.announce();
        // Fallback: schedule full restart if device list stays stale
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            widget.discoveryService.checkDiscoveryHealth();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _service.removeStatusListener(_onStatus);
    // If not connected yet, cancel the attempt
    if (_status != ConnectionStatus.connected) {
      _service.disconnect();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialog = Dialog(
      insetPadding: const EdgeInsets.all(AppSizes.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitle(),
            const SizedBox(height: AppSizes.lg),
            _buildFacesRow(),
            const SizedBox(height: AppSizes.md),
            if (_status == ConnectionStatus.failed && _error != null)
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.red),
              ),
          ],
        ),
      ),
    );

    // Wrap the dialog and an external close button in a centered column.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          dialog,
          if (_status == ConnectionStatus.failed ||
              _status == ConnectionStatus.disconnected) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              elevation: 3,
              shape: const CircleBorder(),
              child: Semantics(
                button: true,
                label: 'Close dialog',
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTitle() {
      print("=== Connection Status: $_status ===");
    switch (_status) {
    
      case ConnectionStatus.connecting:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Establishing Connection ',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 4),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        );
      case ConnectionStatus.connected:
        return  Text(
          'Connected',
          style: Theme.of(  context).textTheme.titleMedium?.copyWith(
                color: AppColors.green,
                fontWeight: FontWeight.w600,
              ),
        );
      case ConnectionStatus.failed:
        return const Text(
          'Request Rejected',
          style: TextStyle(
            color: AppColors.red,
            fontWeight: FontWeight.w600,
          ),
        );
      case ConnectionStatus.disconnected:
        return const Text(
          'Disconnected',
          style: TextStyle(
            color: AppColors.red,
            fontWeight: FontWeight.w600,
          ),
        );
    }
  }

  Widget _buildFacesRow() {
    final left = _circle(widget.myDeviceName);
    final right = _circle(widget.peerDeviceName);

    Widget middle;
    if (_status == ConnectionStatus.connected) {
      middle = const Icon(Icons.handshake, color: AppColors.green, size: 32);
    } else if (_status == ConnectionStatus.failed) {
      middle = const Icon(Icons.block, color: AppColors.red, size: 32);
    } else if (_status == ConnectionStatus.disconnected) {
      middle = const Icon(Icons.link_off, color: AppColors.red, size: 32);
    } else {
      middle = const Icon(
        Icons.multiple_stop,
        color: AppColors.primary,
        size: 28,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [left, middle, right],
    );
  }

  Widget _circle(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.greyDark,
            ),
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        SizedBox(
          width: 100,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

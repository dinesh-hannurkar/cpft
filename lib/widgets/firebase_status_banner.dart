import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cpft/services/firebase_initializer.dart';

class FirebaseStatusBanner extends StatefulWidget {
  const FirebaseStatusBanner({super.key});

  @override
  State<FirebaseStatusBanner> createState() => _FirebaseStatusBannerState();
}

class _FirebaseStatusBannerState extends State<FirebaseStatusBanner> {
  @override
  void initState() {
    super.initState();
    FirebaseInitializer.isReady.addListener(_onChange);
  }

  @override
  void dispose() {
    FirebaseInitializer.isReady.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();

    final ready = (FirebaseInitializer.isReady as ValueListenable<bool>).value;
    final pid = FirebaseInitializer.projectId ?? '-';
    final apps = FirebaseInitializer.appCount;
    final hasError = FirebaseInitializer.lastError != null;

    final String text = hasError
        ? 'Firebase: Error (apps=$apps)'
        : (ready ? 'Firebase: OK ($pid)' : 'Firebase: Init…');

    final Color bg = hasError
        ? Colors.red.withOpacity(0.85)
        : (ready ? Colors.black.withOpacity(0.65) : Colors.orange.withOpacity(0.8));

    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.only(top: 8, right: 8),
        alignment: Alignment.topRight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              child: Text(text, textAlign: TextAlign.right),
            ),
          ),
        ),
      ),
    );
  }
}

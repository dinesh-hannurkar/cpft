import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';

class FileTaglineBar extends StatelessWidget {
  final VoidCallback onTapMain;
  final VoidCallback onTapFab;
  final AnimationController pulseController;
  final List<IconData> fileIcons;
  final int fileIconIndex;
  final bool slideFromLeft;
  const FileTaglineBar({
    super.key,
    required this.onTapMain,
    required this.onTapFab,
    required this.pulseController,
    required this.fileIcons,
    required this.fileIconIndex,
    required this.slideFromLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTapMain,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 62, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFEFF7FF), Color(0xFFDFF0FF)],
              ),
              border: Border(top: BorderSide(color: Color(0xFFCCE4F6))),
            ),
            child: LayoutBuilder(builder: (context, constraints) {
              return ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [AppColors.primary, AppColors.skyBlue],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(Rect.fromLTWH(0, 0, constraints.maxWidth, 20)),
                blendMode: BlendMode.srcIn,
                child: Text(
                  'Any file, any format—share it instantly.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              );
            }),
          ),
        ),
        Positioned(
          left: 16,
          top: -24,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTapFab,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB3E5FC), Color(0xFF81D4FA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: pulseController,
                      builder: (context, child) {
                        final scale = Tween<double>(begin: 0.96, end: 1.06)
                            .animate(CurvedAnimation(parent: pulseController, curve: Curves.easeInOut))
                            .value;
                        return Transform.scale(
                          scale: scale,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 380),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, anim) {
                              final isOutgoing = anim.status == AnimationStatus.reverse;
                              final offsetTween = isOutgoing
                                  ? Tween<Offset>(begin: Offset.zero, end: Offset(slideFromLeft ? 0.35 : -0.35, 0.0))
                                  : Tween<Offset>(begin: Offset(slideFromLeft ? -0.35 : 0.35, 0.0), end: Offset.zero);
                              final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
                              return FadeTransition(
                                opacity: curved,
                                child: SlideTransition(position: curved.drive(offsetTween), child: child),
                              );
                            },
                            child: ShaderMask(
                              key: ValueKey<int>(fileIconIndex),
                              shaderCallback: (rect) => const LinearGradient(
                                colors: [Color(0xFF2F80ED), Color(0xFF56CCF2)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(rect),
                              child: Icon(fileIcons[fileIconIndex], size: 24, color: Colors.white),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

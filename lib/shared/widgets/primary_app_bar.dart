import 'package:flutter/material.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';

class PrimaryAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? leading;
  final String? title;
  final Widget? titleWidget;
  final TextStyle? titleStyle;
  final List<Widget>? trailing;
  final bool centerTitle;
  final Color? backgroundColor;
  final Widget? logo;

  const PrimaryAppBar({
    super.key,
    this.leading,
    this.title,
    this.titleWidget,
    this.titleStyle,
    this.trailing,
    this.centerTitle = true,
    this.backgroundColor,
    this.logo,
  }) : assert(
         title == null || titleWidget == null,
         'Cannot provide both title and titleWidget',
       );

  @override
  Size get preferredSize => Size.fromHeight(AppSizes.appBarHeight);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(
            bottom: BorderSide(
              color: AppColors.skyBlue.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        height: AppSizes.appBarHeight,
        child: Stack(
          children: [
            if (title != null || titleWidget != null)
              Align(
                alignment: centerTitle
                    ? Alignment.center
                    : Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: centerTitle ? 0 : 60.0,
                    right: centerTitle ? 0 : 60.0,
                  ),
                  child:
                      titleWidget ??
                      Text(
                        title!,
                        style:
                            (titleStyle ??
                                    Theme.of(context).textTheme.headlineMedium)
                                ?.apply(color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                      ),
                ),
              ),
            if (leading != null)
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(child: leading!),
              ),
            if (trailing != null && trailing!.isNotEmpty)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [..._withSpacing(trailing!)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _withSpacing(List<Widget> children) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i != children.length - 1) {
        out.add(const SizedBox(width: AppSizes.sm));
      }
    }
    return out;
  }
}

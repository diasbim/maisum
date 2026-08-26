import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_layout.dart';

enum MaisUmAppBarDismissal { back, close, none }

class MaisUmAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MaisUmAppBar({
    super.key,
    required this.title,
    this.dismissal = MaisUmAppBarDismissal.back,
    this.fallbackLocation = '/dashboard',
    this.actions,
    this.backgroundColor = AppColors.offWhite,
  });

  final String title;
  final MaisUmAppBarDismissal dismissal;
  final String fallbackLocation;
  final List<Widget>? actions;
  final Color backgroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final foregroundColor =
        ThemeData.estimateBrightnessForColor(backgroundColor) == Brightness.dark
            ? AppColors.onPrimary
            : AppColors.onSurface;

    return AppBar(
      automaticallyImplyLeading: false,
      leading: dismissal == MaisUmAppBarDismissal.none
          ? null
          : IconButton(
              tooltip: dismissal == MaisUmAppBarDismissal.close
                  ? 'Fechar'
                  : 'Voltar',
              constraints: const BoxConstraints(
                minWidth: AppControlSize.iconButton,
                minHeight: AppControlSize.iconButton,
              ),
              icon: Icon(
                dismissal == MaisUmAppBarDismissal.close
                    ? Icons.close_rounded
                    : Icons.arrow_back_rounded,
              ),
              onPressed: () => _dismiss(context),
            ),
      title: Text(title),
      actions: actions,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: foregroundColor),
      actionsIconTheme: IconThemeData(color: foregroundColor),
      titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: foregroundColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
      systemOverlayStyle:
          ThemeData.estimateBrightnessForColor(backgroundColor) ==
                  Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
    );
  }

  void _dismiss(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go(fallbackLocation);
  }
}

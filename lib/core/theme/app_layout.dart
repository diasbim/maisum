import 'package:flutter/widgets.dart';

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double xxxxl = 40;
  static const double xxxxxl = 48;
  static const double xxxxxxl = 64;

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: xl,
  );
  static const EdgeInsets listPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}

class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double card = lg;
  static const double xl = 24;
  static const double xxl = 32;
  static const double pill = 999;
}

class AppControlSize {
  static const double iconButton = 48;
  static const double button = 56;
  static const double buttonLarge = 64;
}

class AppBreakpoints {
  static const double tablet = 600;
  static const double desktop = 1024;
}

class AppLayout {
  static const double formMaxWidth = 520;
  static const double contentMaxWidth = 720;
}

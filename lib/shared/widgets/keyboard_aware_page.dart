import 'package:flutter/material.dart';

class KeyboardAwarePage extends StatelessWidget {
  const KeyboardAwarePage({
    super.key,
    required this.builder,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
    this.useIntrinsicHeight = true,
  });

  final Widget Function(
    BuildContext context,
    bool isKeyboardVisible,
    BoxConstraints constraints,
  ) builder;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final bool useIntrinsicHeight;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mediaInset = MediaQuery.viewInsetsOf(context).bottom;
          final view = View.of(context);
          final viewInset = view.viewInsets.bottom / view.devicePixelRatio;
          final keyboardInset = mediaInset > viewInset ? mediaInset : viewInset;
          final isKeyboardVisible = keyboardInset > 0;
          final content = builder(context, isKeyboardVisible, constraints);

          return SingleChildScrollView(
            keyboardDismissBehavior: keyboardDismissBehavior,
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: useIntrinsicHeight
                  ? IntrinsicHeight(child: content)
                  : content,
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'validation_state.dart';

class MaisUmTextField extends StatelessWidget {
  const MaisUmTextField({
    super.key,
    this.fieldKey,
    this.label,
    this.hintText,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.prefix,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.autovalidateMode,
    this.validationState = ValidationState.neutral,
    this.showValidIcon = false,
  });

  final String? label;
  final Key? fieldKey;
  final String? hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? prefix;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final bool readOnly;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final AutovalidateMode? autovalidateMode;
  final ValidationState validationState;
  final bool showValidIcon;

  @override
  Widget build(BuildContext context) {
    final borderColor = _borderColor(validationState);
    final borderWidth = validationState == ValidationState.focused ? 2.0 : 1.0;
    final decoration = InputDecoration(
      hintText: hintText,
      prefix: prefix,
      prefixIcon: prefixIcon,
      suffixIcon: showValidIcon && validationState == ValidationState.valid
          ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
          : suffixIcon,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      constraints: const BoxConstraints(minHeight: 60, maxHeight: 60),
      border: _outline(borderColor, borderWidth),
      enabledBorder: _outline(borderColor, borderWidth),
      focusedBorder: _outline(borderColor, borderWidth),
      errorBorder: _outline(AppColors.error, 1.0),
      focusedErrorBorder: _outline(AppColors.error, 2.0),
    );

    final field = TextFormField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      enabled: enabled,
      readOnly: readOnly,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      autovalidateMode: autovalidateMode,
      decoration: decoration,
    );

    if (label == null) {
      return field;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label!,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        field,
      ],
    );
  }

  static OutlineInputBorder _outline(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static Color _borderColor(ValidationState state) {
    switch (state) {
      case ValidationState.neutral:
        return AppColors.g300;
      case ValidationState.focused:
        return AppColors.secondary;
      case ValidationState.valid:
        return AppColors.success;
      case ValidationState.invalid:
        return AppColors.error;
    }
  }
}

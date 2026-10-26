import 'package:flutter/material.dart';

/// The official "standard color" Google "G" mark, used to build a
/// custom "Continuar com Google" / "Sign in with Google" button that still
/// complies with Google's identity branding guidelines
/// (https://developers.google.com/identity/branding-guidelines): the logo
/// must keep its standard color gradient and must not be recolored,
/// stretched, or replaced with a generic icon.
///
/// Always place this on a white/light-neutral background, and keep the
/// button's aspect ratio so the mark isn't distorted.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/google_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Google',
    );
  }
}

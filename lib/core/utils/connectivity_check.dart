import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../widgets/app_feedback.dart';

class ConnectivityCheck {
  static Future<bool> isConnected() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  static void showNoConnectionSnackBar(BuildContext context) {
    AppFeedback.showMessage(
      context,
      message: 'Sem ligação à internet. Verifique e tente de novo.',
      isError: true,
    );
  }
}

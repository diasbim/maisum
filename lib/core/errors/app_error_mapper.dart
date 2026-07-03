import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../constants/app_strings.dart';
import 'app_exception.dart';

class AppErrorInfo {
  const AppErrorInfo({required this.title, required this.message});

  final String title;
  final String message;
}

class AppErrorMapper {
  static AppErrorInfo describe(Object error) {
    if (error is AppException) {
      return AppErrorInfo(title: 'Erro', message: error.message);
    }

    if (error is FirebaseAuthException) {
      final detail = _firebaseDetail(error);
      return AppErrorInfo(
        title: 'Sessao expirada',
        message: detail ?? AppStrings.erroAuth,
      );
    }

    if (error is FirebaseException) {
      final detail = _firebaseDetail(error);
      switch (error.code) {
        case 'failed-precondition':
          return AppErrorInfo(
            title: 'Sincronizacao pendente',
            message: detail ?? AppStrings.syncIndiceFaltando,
          );
        case 'permission-denied':
          return AppErrorInfo(
            title: 'Sem permissao',
            message: detail ?? 'Permissao negada no Firebase (${error.code}).',
          );
        case 'unavailable':
        case 'deadline-exceeded':
        case 'resource-exhausted':
          return AppErrorInfo(
            title: 'Sem ligacao',
            message: detail ?? AppStrings.erroRede,
          );
        default:
          return AppErrorInfo(
            title: 'Erro',
            message: detail ?? AppStrings.erroGenerico,
          );
      }
    }

    if (error is FormatException) {
      return const AppErrorInfo(
        title: 'Dados invalidos',
        message: AppStrings.erroGenerico,
      );
    }

    if (error is sqflite.DatabaseException) {
      final raw = error.toString().toLowerCase();
      if (raw.contains('customers.phone') ||
          raw.contains('idx_customers_merchant_phone') ||
          raw.contains('unique constraint failed')) {
        return const AppErrorInfo(
          title: 'Número já registado',
          message: AppStrings.customerPhoneDuplicate,
        );
      }
      return const AppErrorInfo(
        title: 'Erro de dados',
        message: AppStrings.erroGenericoAcao,
      );
    }

    return const AppErrorInfo(
      title: 'Erro',
      message: AppStrings.erroGenerico,
    );
  }

  static String? _firebaseDetail(FirebaseException error) {
    final message = error.message?.trim();
    if (message == null || message.isEmpty) {
      return 'Firebase ${error.plugin}/${error.code}';
    }
    return 'Firebase ${error.plugin}/${error.code}: $message';
  }
}

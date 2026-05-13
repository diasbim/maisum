import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

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
      return AppErrorInfo(
        title: 'Sessao expirada',
        message: AppStrings.erroAuth,
      );
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'failed-precondition':
          return const AppErrorInfo(
            title: 'Sincronizacao pendente',
            message: AppStrings.syncIndiceFaltando,
          );
        case 'permission-denied':
          return const AppErrorInfo(
            title: 'Sem permissao',
            message: AppStrings.syncPermissaoNegada,
          );
        case 'unavailable':
        case 'deadline-exceeded':
        case 'resource-exhausted':
          return const AppErrorInfo(
            title: 'Sem ligacao',
            message: AppStrings.erroRede,
          );
        default:
          return const AppErrorInfo(
            title: 'Erro',
            message: AppStrings.erroGenerico,
          );
      }
    }

    if (error is FormatException) {
      return const AppErrorInfo(
        title: 'Dados invalidos',
        message: AppStrings.erroGenerico,
      );
    }

    return const AppErrorInfo(
      title: 'Erro',
      message: AppStrings.erroGenerico,
    );
  }
}

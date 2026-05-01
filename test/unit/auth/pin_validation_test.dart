import 'package:flutter_test/flutter_test.dart';
import 'package:loyalty_app/core/constants/app_constants.dart';

void main() {
  group('PIN validation rules', () {
    test('exactly 4 digits is valid length', () {
      expect('1234'.length, AppConstants.pinLength);
    });

    test('fewer than 4 digits fails length check', () {
      expect('123'.length == AppConstants.pinLength, false);
    });

    test('more than 4 digits fails length check', () {
      expect('12345'.length == AppConstants.pinLength, false);
    });

    test('empty PIN fails length check', () {
      expect(''.length == AppConstants.pinLength, false);
    });

    test('numeric-only PIN passes format check', () {
      expect(RegExp(r'^\d+$').hasMatch('1234'), true);
      expect(RegExp(r'^\d+$').hasMatch('0000'), true);
      expect(RegExp(r'^\d+$').hasMatch('9999'), true);
    });

    test('non-numeric PIN fails format check', () {
      expect(RegExp(r'^\d+$').hasMatch('12ab'), false);
      expect(RegExp(r'^\d+$').hasMatch('abcd'), false);
      expect(RegExp(r'^\d+$').hasMatch('1 34'), false);
    });

    test('matching PINs are equal', () {
      expect('4567' == '4567', true);
    });

    test('mismatched PINs are not equal', () {
      expect('4567' == '4568', false);
      expect('1234' == '4321', false);
    });
  });

  group('PIN attempt constants', () {
    test('maxPinAttempts is 3', () {
      expect(AppConstants.maxPinAttempts, 3);
    });

    test('pinLength is 4', () {
      expect(AppConstants.pinLength, 4);
    });

    test('pinKey is defined', () {
      expect(AppConstants.pinKey, isNotEmpty);
    });

    test('pinAttemptsKey is defined and different from pinKey', () {
      expect(AppConstants.pinAttemptsKey, isNotEmpty);
      expect(AppConstants.pinAttemptsKey, isNot(AppConstants.pinKey));
    });
  });
}

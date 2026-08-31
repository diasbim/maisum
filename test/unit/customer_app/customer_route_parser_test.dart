import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/customer_app/presentation/customer_route_parser.dart';

void main() {
  group('customer deep links', () {
    test('accepts documented custom-scheme customer routes', () {
      expect(
        parseCustomerDeepLink(Uri.parse('maisum://app/customer/home')),
        '/customer/home',
      );
      expect(
        parseCustomerDeepLink(
          Uri.parse('maisum://app/customer/redeem/reward_123'),
        ),
        '/customer/redeem/reward_123',
      );
      expect(
        parseCustomerDeepLink(Uri.parse('maisum://app/customer/terms')),
        '/customer/terms',
      );
      expect(
        parseCustomerDeepLink(Uri.parse('maisum://app/customer/privacy')),
        '/customer/privacy',
      );
    });

    test('rejects unknown origins, query strings, and non-customer routes', () {
      for (final uri in [
        Uri.parse('https://app/customer/home'),
        Uri.parse('maisum://evil/customer/home'),
        Uri.parse('maisum://app/admin'),
        Uri.parse('maisum://app/merchant/customer-qr'),
        Uri.parse('maisum://app/customer/home?next=/dashboard'),
      ]) {
        expect(parseCustomerDeepLink(uri), isNull);
      }
    });
  });

  group('customer push routes', () {
    test('accepts only allow-listed customer route payloads', () {
      expect(
        parseCustomerPushRoute(
            {'customer_route': '/customer/business/store-1'}),
        '/customer/business/store-1',
      );
      expect(
        parseCustomerPushRoute({'customer_route': '/customer/rewards'}),
        '/customer/rewards',
      );
    });

    test('rejects arbitrary, external, and merchant/admin payload routes', () {
      for (final data in [
        <String, dynamic>{'route': '/customer/home'},
        <String, dynamic>{'customer_route': 'maisum://app/customer/home'},
        <String, dynamic>{'customer_route': '/dashboard'},
        <String, dynamic>{'customer_route': '/merchant/customer-qr'},
        <String, dynamic>{'customer_route': '/admin'},
        <String, dynamic>{'customer_route': '/customer/redeem/../../admin'},
      ]) {
        expect(parseCustomerPushRoute(data), isNull);
      }
    });
  });
}

import '../../features/customers/data/customer_dao.dart';
import '../../features/customers/domain/customer.dart';

class CustomerMatch {
  const CustomerMatch({required this.customer, required this.reason});

  final Customer? customer;
  final String reason;
}

class CustomerMatchEngine {
  CustomerMatchEngine(this._customerDao);

  final CustomerDao _customerDao;

  Future<CustomerMatch> match({String? phone}) async {
    if (phone != null && phone.isNotEmpty) {
      final exact = await _customerDao.findByPhone(phone);
      if (exact != null) {
        return CustomerMatch(customer: exact, reason: 'phone');
      }
    }

    final recent = await _customerDao.getRecent(limit: 1);
    if (recent.isNotEmpty) {
      return CustomerMatch(customer: recent.first, reason: 'recent');
    }

    return const CustomerMatch(customer: null, reason: 'none');
  }
}

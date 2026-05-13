import '../../../features/sales/data/sale_dao.dart';
import 'streak_calculator.dart';

class StreakService {
  StreakService(this._saleDao, {this.maxLookbackDays = 45});

  final SaleDao _saleDao;
  final int maxLookbackDays;
  final StreakCalculator _calculator = StreakCalculator();

  Future<StreakSummary> getCurrentStreak() async {
    final saleDays = await _saleDao.getSaleDays(days: maxLookbackDays);
    return _calculator.calculate(
      saleDays: saleDays,
      maxLookbackDays: maxLookbackDays,
    );
  }
}

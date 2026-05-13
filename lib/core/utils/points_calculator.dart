import '../constants/app_constants.dart';

class PointsCalculator {
  const PointsCalculator();

  int calculate(double amount) {
    if (amount <= 0) return 0;
    return (amount / AppConstants.pointsPerMzn).floor();
  }
}

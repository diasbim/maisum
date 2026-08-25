import '../constants/app_constants.dart';

class PointsCalculator {
  const PointsCalculator({
    this.pointsPerMzn = AppConstants.pointsPerMzn,
  }) : assert(pointsPerMzn > 0);

  final int pointsPerMzn;

  int calculate(double amount) {
    if (amount <= 0) return 0;
    return (amount / pointsPerMzn).floor();
  }
}

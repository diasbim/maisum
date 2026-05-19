import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../sync/sync_service.dart';
import '../domain/appointment.dart';

final appointmentsProvider = FutureProvider<List<Appointment>>((ref) {
  return ref.read(appointmentRepositoryProvider).getUpcomingAppointments(
        limit: 100,
      );
});

final upcomingAppointmentsProvider = FutureProvider<List<Appointment>>((ref) {
  return ref.read(appointmentRepositoryProvider).getUpcomingAppointments(
        limit: 20,
      );
});

class CreateAppointmentController extends AsyncNotifier<Appointment?> {
  @override
  Future<Appointment?> build() async => null;

  Future<Appointment> createAppointment({
    required String customerId,
    required DateTime scheduledDate,
    String source = 'post_sale_flow',
  }) async {
    state = const AsyncLoading();
    final appointment =
        await ref.read(appointmentRepositoryProvider).createAppointment(
              customerId: customerId,
              scheduledDate: scheduledDate,
              source: source,
            );

    ref.invalidate(appointmentsProvider);
    ref.invalidate(upcomingAppointmentsProvider);
    ref.read(syncServiceProvider).processQueue();

    state = AsyncData(appointment);
    return appointment;
  }

  void reset() {
    state = const AsyncData(null);
  }
}

final createAppointmentProvider =
    AsyncNotifierProvider<CreateAppointmentController, Appointment?>(
  CreateAppointmentController.new,
);

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:maisum/features/appointments/domain/appointment.dart';
import 'package:maisum/features/appointments/presentation/appointments_screen.dart';
import 'package:table_calendar/table_calendar.dart';

AppointmentWithCustomer _appointment({
  required String id,
  required String customerName,
  required DateTime scheduledDate,
}) {
  return AppointmentWithCustomer(
    appointment: Appointment(
      id: id,
      customerId: 'customer-$id',
      scheduledDate: scheduledDate,
      status: AppointmentStatus.scheduled,
      source: 'post_sale_flow',
      reminderSent: false,
      createdAt: scheduledDate,
      updatedAt: scheduledDate,
    ),
    customerName: customerName,
    customerPhone: '84100000$id',
  );
}

Widget _buildScreen(List<AppointmentWithCustomer> items) {
  final router = GoRouter(
    initialLocation: '/appointments',
    routes: [
      GoRoute(
        path: '/appointments',
        builder: (_, __) => const AppointmentsScreen(),
      ),
      GoRoute(
        path: '/customers/:id',
        builder: (_, state) =>
            Scaffold(body: Text('customer:${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appointmentsWithCustomerProvider.overrideWith((ref) async => items),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  testWidgets('shows an empty state with no upcoming appointments',
      (tester) async {
    await tester.pumpWidget(_buildScreen(const []));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum agendamento futuro'), findsOneWidget);
  });

  testWidgets('lists upcoming appointments with customer name and phone',
      (tester) async {
    final scheduled = DateTime.now().add(const Duration(days: 1));
    await tester.pumpWidget(
      _buildScreen([
        _appointment(id: '1', customerName: 'Ana Costa', scheduledDate: scheduled),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Costa'), findsOneWidget);
    expect(find.text('Nenhum agendamento futuro'), findsNothing);
  });

  testWidgets('tapping an appointment navigates to the customer detail',
      (tester) async {
    final scheduled = DateTime.now().add(const Duration(days: 1));
    await tester.pumpWidget(
      _buildScreen([
        _appointment(id: '7', customerName: 'Beatriz', scheduledDate: scheduled),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beatriz'));
    await tester.pumpAndSettle();

    expect(find.text('customer:customer-7'), findsOneWidget);
  });

  testWidgets('switches from list to calendar view', (tester) async {
    final scheduled = DateTime.now().add(const Duration(days: 1));
    await tester.pumpWidget(
      _buildScreen([
        _appointment(id: '1', customerName: 'Carla', scheduledDate: scheduled),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Carla'), findsOneWidget);
    expect(find.byType(TableCalendar<AppointmentWithCustomer>), findsNothing);

    await tester.tap(find.text('Calendário'));
    await tester.pumpAndSettle();

    expect(find.byType(TableCalendar<AppointmentWithCustomer>), findsOneWidget);
  });
}

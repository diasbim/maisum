import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/appointment.dart';
import '../providers/appointments_providers.dart';

enum _AppointmentsViewMode { list, calendar }

class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  _AppointmentsViewMode _viewMode = _AppointmentsViewMode.list;
  DateTime _selectedDay = _normalizeDay(DateTime.now());
  DateTime _focusedDay = _normalizeDay(DateTime.now());

  void _changeMode(_AppointmentsViewMode mode) {
    if (_viewMode == mode) {
      return;
    }
    setState(() => _viewMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final appointmentsAsync = ref.watch(appointmentsWithCustomerProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Agenda de cortes'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        color: AppColors.secondary,
        onRefresh: () async {
          ref.invalidate(appointmentsWithCustomerProvider);
          await ref.read(appointmentsWithCustomerProvider.future);
        },
        child: appointmentsAsync.when(
          data: (items) {
            if (_viewMode == _AppointmentsViewMode.list) {
              return _AppointmentsListView(
                items: items,
                mode: _viewMode,
                onModeChanged: _changeMode,
              );
            }

            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  _AppointmentsViewSwitcher(
                    mode: _viewMode,
                    onModeChanged: _changeMode,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.event_busy_rounded,
                          size: 46,
                          color: AppColors.g500,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nenhum agendamento futuro',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppColors.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Crie um agendamento após a próxima venda.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            final sortedDays = items
                .map((item) => _normalizeDay(item.appointment.scheduledDate))
                .toList()
              ..sort((a, b) => a.compareTo(b));

            final first = sortedDays.first;
            final last = sortedDays.last;
            final firstDate = DateTime(first.year, first.month, first.day)
                .subtract(const Duration(days: 365));
            final lastDate = DateTime(last.year, last.month, last.day)
                .add(const Duration(days: 365));
            final effectiveSelectedDay = _clampDay(
              _selectedDay,
              firstDate,
              lastDate,
            );
            final effectiveFocusedDay = _clampDay(
              _focusedDay,
              firstDate,
              lastDate,
            );

            final appointmentsByDay =
                <DateTime, List<AppointmentWithCustomer>>{};
            for (final item in items) {
              final dayKey = _normalizeDay(item.appointment.scheduledDate);
              appointmentsByDay
                  .putIfAbsent(dayKey, () => <AppointmentWithCustomer>[])
                  .add(item);
            }
            for (final dayItems in appointmentsByDay.values) {
              dayItems.sort(
                (a, b) => a.appointment.scheduledDate
                    .compareTo(b.appointment.scheduledDate),
              );
            }

            final selectedItems = appointmentsByDay[effectiveSelectedDay] ??
                const <AppointmentWithCustomer>[];

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              children: [
                _AppointmentsViewSwitcher(
                  mode: _viewMode,
                  onModeChanged: _changeMode,
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.g100),
                  ),
                  child: TableCalendar<AppointmentWithCustomer>(
                    locale: 'pt_PT',
                    firstDay: firstDate,
                    lastDay: lastDate,
                    focusedDay: effectiveFocusedDay,
                    selectedDayPredicate: (day) =>
                        _isSameCalendarDay(day, effectiveSelectedDay),
                    eventLoader: (day) =>
                        appointmentsByDay[_normalizeDay(day)] ??
                        const <AppointmentWithCustomer>[],
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = _normalizeDay(selectedDay);
                        _focusedDay = _normalizeDay(focusedDay);
                      });
                    },
                    onPageChanged: (focusedDay) {
                      setState(() => _focusedDay = _normalizeDay(focusedDay));
                    },
                    headerStyle: const HeaderStyle(
                      titleCentered: true,
                      formatButtonVisible: false,
                    ),
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: const BoxDecoration(
                        color: AppColors.secondary,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: const BoxDecoration(
                        color: AppColors.secondaryDark,
                        shape: BoxShape.circle,
                      ),
                      markersMaxCount: 3,
                      markerSize: 5,
                      outsideDaysVisible: false,
                    ),
                    calendarBuilders: CalendarBuilders<AppointmentWithCustomer>(
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        if (events.length <= 3) {
                          return Positioned(
                            bottom: 4,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                events.length,
                                (index) => Container(
                                  width: 5,
                                  height: 5,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: const BoxDecoration(
                                    color: AppColors.secondaryDark,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return Positioned(
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryDark,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${events.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Agendamentos em ${_formatDay(effectiveSelectedDay)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                ),
                const SizedBox(height: 8),
                if (selectedItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.g100),
                    ),
                    child: Text(
                      'Sem agendamentos para este dia.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                    ),
                  )
                else
                  ...selectedItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _AppointmentTile(item: item),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.secondary),
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 120),
              Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.red,
                      size: 40,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AppStrings.erroGenerico,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(appointmentsWithCustomerProvider),
                      child: const Text(AppStrings.tentar),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static DateTime _normalizeDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _isSameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _clampDay(DateTime value, DateTime min, DateTime max) {
    if (value.isBefore(min)) {
      return min;
    }
    if (value.isAfter(max)) {
      return max;
    }
    return value;
  }

  static String _formatDay(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class _AppointmentsListView extends StatelessWidget {
  const _AppointmentsListView({
    required this.items,
    required this.mode,
    required this.onModeChanged,
  });

  final List<AppointmentWithCustomer> items;
  final _AppointmentsViewMode mode;
  final ValueChanged<_AppointmentsViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        children: [
          _AppointmentsViewSwitcher(mode: mode, onModeChanged: onModeChanged),
          const SizedBox(height: 24),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.event_busy_rounded,
                  size: 46,
                  color: AppColors.g500,
                ),
                const SizedBox(height: 12),
                Text(
                  'Nenhum agendamento futuro',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Crie um agendamento após a próxima venda.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      itemCount: items.length + 1,
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 12 : 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _AppointmentsViewSwitcher(
            mode: mode,
            onModeChanged: onModeChanged,
          );
        }
        final item = items[index - 1];
        return _AppointmentTile(item: item);
      },
    );
  }
}

class _AppointmentsViewSwitcher extends StatelessWidget {
  const _AppointmentsViewSwitcher({
    required this.mode,
    required this.onModeChanged,
  });

  final _AppointmentsViewMode mode;
  final ValueChanged<_AppointmentsViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.g100),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SwitcherButton(
              label: 'Lista',
              icon: Icons.view_list_rounded,
              isActive: mode == _AppointmentsViewMode.list,
              onTap: () => onModeChanged(_AppointmentsViewMode.list),
            ),
          ),
          Expanded(
            child: _SwitcherButton(
              label: 'Calendario',
              icon: Icons.calendar_month_rounded,
              isActive: mode == _AppointmentsViewMode.calendar,
              onTap: () => onModeChanged(_AppointmentsViewMode.calendar),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitcherButton extends StatelessWidget {
  const _SwitcherButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.secondary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? AppColors.secondaryDark : AppColors.g500,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color:
                          isActive ? AppColors.secondaryDark : AppColors.g500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppointmentWithCustomer {
  const AppointmentWithCustomer({
    required this.appointment,
    required this.customerName,
    required this.customerPhone,
  });

  final Appointment appointment;
  final String customerName;
  final String customerPhone;
}

final appointmentsWithCustomerProvider =
    FutureProvider<List<AppointmentWithCustomer>>((ref) async {
  final appointments = await ref.read(appointmentsProvider.future);
  if (appointments.isEmpty) return const <AppointmentWithCustomer>[];

  final customerDao = ref.read(customerDaoProvider);
  final items = <AppointmentWithCustomer>[];

  for (final appointment in appointments) {
    final customer = await customerDao.getById(appointment.customerId);
    items.add(
      AppointmentWithCustomer(
        appointment: appointment,
        customerName: customer?.name ?? 'Cliente removido',
        customerPhone: customer?.phone ?? '-',
      ),
    );
  }

  return items;
});

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.item});

  final AppointmentWithCustomer item;

  @override
  Widget build(BuildContext context) {
    final date = item.appointment.scheduledDate;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return InkWell(
      onTap: () => context.push('/customers/${item.appointment.customerId}'),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.g100),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.secondaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.content_cut_rounded,
                color: AppColors.secondaryDark,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.customerPhone,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.event_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$day/$month/${date.year} - $hour:$minute',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.g500,
            ),
          ],
        ),
      ),
    );
  }
}

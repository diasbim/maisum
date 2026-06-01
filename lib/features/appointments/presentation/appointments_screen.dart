import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/appointment.dart';
import '../providers/appointments_providers.dart';

class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
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

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return _AppointmentTile(item: item);
              },
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

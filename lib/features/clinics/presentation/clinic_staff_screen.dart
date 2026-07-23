import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../auth/application/auth_controller.dart';
import '../../staff/data/staff_repository.dart';
import '../../staff/domain/staff_member.dart';
import '../../staff/presentation/staff_tile.dart';
import '../domain/clinic.dart';

/// Сотрудники ОДНОЙ клиники — открывается из экрана «Клиники» (действие
/// «Сотрудники» в меню плитки). Платформенный владелец видит здесь «какой
/// сотрудник из какой клиники» и управляет ими (роль/права/доступ) теми же
/// диалогами, что и на общем экране «Сотрудники» (через общий [StaffTile]).
///
/// Список берётся из общего `staffListProvider` (владелец получает всех) и
/// фильтруется по `clinic_id` этой клиники — отдельного запроса не нужно.
class ClinicStaffScreen extends ConsumerWidget {
  const ClinicStaffScreen({super.key, required this.clinic});

  final Clinic clinic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authControllerProvider).user?.id;
    final staff = ref.watch(staffListProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Сотрудники — ${clinic.name}'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(staffListProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: AsyncValueWidget<List<StaffMember>>(
          value: staff,
          onRetry: () => ref.invalidate(staffListProvider),
          builder: (all) {
            final items = all.where((s) => s.clinicId == clinic.id).toList();
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'В этой клинике пока нет сотрудников.',
                    style: TextStyle(color: AppColors.sub),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        for (final s in items)
                          StaffTile(staff: s, isSelf: s.uid == userId),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

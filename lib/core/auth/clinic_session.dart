import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/analyses/data/analyses_repository.dart';
import '../../features/analysis_types/data/analysis_types_repository.dart';
import '../../features/audit/data/audit_repository.dart';
import '../../features/clinics/data/clinics_repository.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/fibroscan/data/fibroscan_repository.dart';
import '../../features/fibroscan_refs/data/fibroscan_refs_repository.dart';
import '../../features/inventory/data/categories_repository.dart';
import '../../features/inventory/data/warehouse_repository.dart';
import '../../features/patients/presentation/patients_screen.dart';
import '../../features/payments/data/cash_repository.dart';
import '../../features/payments/data/payments_repository.dart';
import '../../features/payments/data/services_repository.dart';
import '../../features/staff/data/staff_repository.dart';
import '../../features/visits/data/visit_repository.dart';
import 'clinic_scope.dart';

/// Смена активной клиники платформенного владельца — ЕДИНАЯ точка ре-скоупа
/// сессии на другую клинику.
///
/// Владелец платформы (`isPlatformAdmin`) работает «изнутри» выбранной клиники:
/// её `clinic_id` — это [ClinicScope.current], по которому ВСЕ репозитории
/// фильтруют чтение и штампуют запись. Чтобы переключить клинику «на лету» (без
/// повторного входа), мы:
///   1. переставляем [ClinicScope.current] на новый `clinicId`;
///   2. инвалидируем документ активной клиники ([currentClinicProvider]) — чтобы
///      сайдбар/навигация/модульный гард пересчитались под новую клинику;
///   3. инвалидируем ВСЕ keep-alive списочные провайдеры (top-level, не
///      autoDispose) — они закешированы под старый `clinic_id`, поэтому без явной
///      инвалидции экраны показывали бы данные прежней клиники. autoDispose-
///      провайдеры (напр. [patientsListProvider]) перечитаются сами при заходе
///      на экран, но инвалидция их тоже безопасна (no-op, если не активны).
///
/// После инвалидции дожидаемся перезагрузки документа новой клиники, чтобы
/// вызывающий код навигировал уже по её модулям (домашний экран/гард).
///
/// [ClinicScope.isPlatformAdmin] НЕ трогаем — смена рабочей клиники не меняет
/// того, что пользователь остаётся владельцем платформы.
Future<void> switchActiveClinic(WidgetRef ref, String clinicId) async {
  if (clinicId.isEmpty || ClinicScope.current == clinicId) return;

  // (1) Ре-скоуп сессии на новую клинику.
  ClinicScope.current = clinicId;

  // (2) Идентичность/навигация активной клиники.
  ref.invalidate(currentClinicProvider);

  // (3) Все keep-alive списочные провайдеры — данные перезагрузятся под новый
  // clinic_id (порядок не важен, инвалидция ленивая).
  ref.invalidate(todayVisitsProvider);
  ref.invalidate(todayPaymentsProvider);
  ref.invalidate(todayRefundsProvider);
  ref.invalidate(currentShiftProvider);
  ref.invalidate(todayWithdrawalsProvider);
  ref.invalidate(activeServicesProvider);
  ref.invalidate(allServicesProvider);
  ref.invalidate(analysesListProvider);
  ref.invalidate(fibroscanListProvider);
  ref.invalidate(warehouseStockProvider);
  ref.invalidate(warehouseMovementsProvider);
  ref.invalidate(productCategoriesProvider);
  ref.invalidate(analysisTypesProvider);
  ref.invalidate(activeAnalysisTypesProvider);
  ref.invalidate(fibroRefsProvider);
  ref.invalidate(staffListProvider);
  ref.invalidate(auditLogProvider);
  ref.invalidate(dashboardProvider);
  ref.invalidate(patientsListProvider);

  // Дожидаемся документа новой клиники, чтобы навигация после переключения шла
  // уже по её модулям. Ошибку глушим — навигация всё равно продолжится, а
  // модульный гард применится, как только документ подтянется.
  try {
    await ref.read(currentClinicProvider.future);
  } catch (_) {
    // Клиника не загрузилась — не блокируем переключение/навигацию.
  }
}

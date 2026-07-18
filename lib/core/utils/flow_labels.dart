/// Human RU labels for the automatic visit workflow statuses.
/// The status is read-only on the client — the backend flow engine owns it.
String flowStatusLabel(String flowStatus) => switch (flowStatus) {
      'registered' => 'зарегистрирован',
      'awaiting_assignment' => 'ожидает назначения',
      'waiting_diagnostic' => 'ждёт диагностику',
      'in_diagnostic' => 'на диагностике',
      'waiting_doctor' => 'ждёт врача',
      'in_doctor' => 'у врача',
      'treatment_assigned' => 'назначено лечение',
      'surgery_assigned' => 'назначена операция',
      'surgery_scheduled' => 'операция запланирована',
      'surgery_completed' => 'операция выполнена',
      'follow_up' => 'контрольное наблюдение',
      'completed' => 'завершён',
      'cancelled' => 'отменён',
      _ => flowStatus,
    };

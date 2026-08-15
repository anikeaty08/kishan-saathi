import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/krishi_api.dart';

class ReminderRepository {
  const ReminderRepository(this._api);

  final KrishiApi _api;

  Future<List<FarmReminder>> loadReminders() async {
    final payload = await _api.listReminders(
      filters: {'include_finished': 'true'},
    );
    return _list(
      payload,
      'reminders',
    ).map((item) => _reminder(_map(item, 'reminder'))).toList(growable: false);
  }

  Future<List<ReminderProposalModel>> loadProposals() async {
    final payload = await _api.listReminderProposals();
    return _list(payload, 'reminder proposals')
        .map((item) => _proposal(_map(item, 'reminder proposal')))
        .toList(growable: false);
  }

  Future<void> complete(String reminderId) async {
    await _api.actOnReminder(reminderId, {'action': 'done'});
  }

  Future<void> act(
    String reminderId, {
    required String action,
    DateTime? dueAt,
  }) async {
    await _api.actOnReminder(reminderId, {
      'action': action,
      if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
    });
  }

  Future<void> decide(String proposalId, {required bool accepted}) async {
    await _api.decideReminderProposal(proposalId, {'accepted': accepted});
  }

  Future<void> create({
    required String title,
    required DateTime dueAt,
    String? notes,
    String? plotId,
    int? recurrenceDays,
  }) async {
    await _api.createReminder({
      'title': title.trim(),
      'due_at': dueAt.toUtc().toIso8601String(),
      'notes': _text(notes),
      'plot_id': plotId,
      'recurrence_days': recurrenceDays,
    });
  }
}

String? _text(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

FarmReminder _reminder(Map<String, dynamic> row) => FarmReminder(
  id: row['id'] as String,
  title: row['title'] as String? ?? 'Farm reminder',
  dueAt: DateTime.tryParse(row['due_at'] as String? ?? '') ?? DateTime.now(),
  plotName: 'Farm task',
  plotId: row['plot_id'] as String?,
  notes: row['notes'] as String?,
  recurrenceDays: (row['recurrence_days'] as num?)?.toInt(),
  status: switch (row['status']) {
    'done' => ReminderStatus.done,
    'skipped' => ReminderStatus.skipped,
    'cancelled' => ReminderStatus.cancelled,
    _ => ReminderStatus.pending,
  },
);

ReminderProposalModel _proposal(Map<String, dynamic> row) =>
    ReminderProposalModel(
      id: row['id'] as String,
      title: row['title'] as String? ?? 'Suggested reminder',
      dueAt:
          DateTime.tryParse(row['due_at'] as String? ?? '') ?? DateTime.now(),
      status: row['status'] as String? ?? 'pending',
      chatId: row['chat_id'] as String?,
      plotId: row['plot_id'] as String?,
      recurrenceDays: (row['recurrence_days'] as num?)?.toInt(),
    );

Map<String, dynamic> _map(Object? value, String contract) {
  if (value is Map<String, dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

List<dynamic> _list(Object? value, String contract) {
  if (value is List<dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

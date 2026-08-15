import '../../../core/models/app_models.dart';

abstract final class ChatScopePolicy {
  static bool belongsToPlot(
    ChatThreadModel chat,
    String plotId, {
    required Set<String> diagnosisIds,
  }) {
    if (chat.effectivePlotId == plotId || chat.plotId == plotId) return true;
    final diagnosisId = chat.diagnosisCaseId;
    return diagnosisId != null && diagnosisIds.contains(diagnosisId);
  }
}

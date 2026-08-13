import 'api_client.dart';
import 'api_endpoints.dart';

/// Thin, stateless service surface matching every current FastAPI operation.
/// Repositories parse these raw contracts into feature models and own caching.
class KrishiApi {
  const KrishiApi(this.client);

  final ApiClient client;

  Future<Object?> live() => client.get(ApiEndpoints.live, auth: false);
  Future<Object?> ready() => client.get(ApiEndpoints.ready, auth: false);

  Future<Object?> getProfile() => client.get(ApiEndpoints.me);
  Future<Object?> updateProfile(Map<String, Object?> body) =>
      client.patch(ApiEndpoints.me, body: body);

  Future<Object?> listFarms() => client.get(ApiEndpoints.farms);
  Future<Object?> createFarm(Map<String, Object?> body) =>
      client.post(ApiEndpoints.farms, body: body);
  Future<Object?> getFarm(String id) => client.get(ApiEndpoints.farm(id));
  Future<Object?> updateFarm(String id, Map<String, Object?> body) =>
      client.put(ApiEndpoints.farm(id), body: body);
  Future<void> deleteFarm(String id) => client.delete(ApiEndpoints.farm(id));
  Future<Object?> farmDeletionImpact(String id) =>
      client.get(ApiEndpoints.farmDeletionImpact(id));

  Future<Object?> listPlots({String? farmId}) => client.get(
    ApiEndpoints.plots,
    query: farmId == null ? null : {'farm_id': farmId},
  );
  Future<Object?> createPlot(Map<String, Object?> body) =>
      client.post(ApiEndpoints.plots, body: body);
  Future<Object?> getPlot(String id) => client.get(ApiEndpoints.plot(id));
  Future<Object?> updatePlot(String id, Map<String, Object?> body) =>
      client.patch(ApiEndpoints.plot(id), body: body);
  Future<void> deletePlot(String id) => client.delete(ApiEndpoints.plot(id));
  Future<Object?> plotDeletionImpact(String id) =>
      client.get(ApiEndpoints.plotDeletionImpact(id));

  Future<Object?> createCrop(String plotId, Map<String, Object?> body) =>
      client.post(ApiEndpoints.plotCrops(plotId), body: body);
  Future<Object?> updateCrop(String id, Map<String, Object?> body) =>
      client.patch(ApiEndpoints.crop(id), body: body);
  Future<Object?> updateCropStage(String id, Map<String, Object?> body) =>
      client.patch(ApiEndpoints.cropStage(id), body: body);
  Future<Object?> closeCropCycle(String id, Map<String, Object?> body) =>
      client.post(ApiEndpoints.cropCloseCycle(id), body: body);
  Future<void> deleteCrop(String id, {bool confirmHistoryLoss = false}) =>
      client.delete(
        ApiEndpoints.crop(id),
        query: {'confirm_history_loss': '$confirmHistoryLoss'},
      );
  Future<Object?> cropDeletionImpact(String id) =>
      client.get(ApiEndpoints.cropDeletionImpact(id));

  Future<Object?> createActivity(String plotId, Map<String, Object?> body) =>
      client.post(ApiEndpoints.plotActivities(plotId), body: body);
  Future<Object?> listActivities(String plotId) =>
      client.get(ApiEndpoints.plotActivities(plotId));
  Future<Object?> getActivity(String id) =>
      client.get(ApiEndpoints.activity(id));
  Future<Object?> updateActivity(String id, Map<String, Object?> body) =>
      client.patch(ApiEndpoints.activity(id), body: body);
  Future<void> deleteActivity(String id) =>
      client.delete(ApiEndpoints.activity(id));
  Future<Object?> addActivityPhoto(String id, String filePath) =>
      client.multipart(
        ApiEndpoints.activityPhotos(id),
        fields: const {},
        filePaths: [filePath],
        fileField: 'photo',
      );
  Future<Object?> listActivityPhotos(String id) =>
      client.get(ApiEndpoints.activityPhotos(id));
  Future<List<int>> getActivityPhoto(String activityId, String photoId) =>
      client.getBytes(ApiEndpoints.activityPhoto(activityId, photoId));
  Future<void> deleteActivityPhoto(String activityId, String photoId) =>
      client.delete(ApiEndpoints.activityPhoto(activityId, photoId));
  Future<Object?> plotTimeline(
    String plotId, {
    Map<String, Object?>? filters,
  }) => client.get(ApiEndpoints.plotTimeline(plotId), query: filters);

  Future<Object?> createDiagnosis({
    required List<String> imagePaths,
    Map<String, String> fields = const {},
  }) => client.multipart(
    ApiEndpoints.diagnoses,
    fields: fields,
    filePaths: imagePaths,
  );
  Future<Object?> listDiagnoses({Map<String, String>? filters}) =>
      client.get(ApiEndpoints.diagnoses, query: filters);
  Future<Object?> getDiagnosis(String id) =>
      client.get(ApiEndpoints.diagnosis(id));
  Future<void> deleteDiagnosis(String id) =>
      client.delete(ApiEndpoints.diagnosis(id));
  Future<Object?> createRetake(
    String id, {
    required List<String> imagePaths,
    Map<String, String> fields = const {},
  }) => client.multipart(
    ApiEndpoints.diagnosisRetakes(id),
    fields: fields,
    filePaths: imagePaths,
  );
  Future<Object?> diagnosisAssessments(String id) =>
      client.get(ApiEndpoints.diagnosisAssessments(id));
  Future<Object?> compareDiagnosisProgression(
    String id, {
    required String responseLanguage,
  }) => client.post(
    ApiEndpoints.diagnosisProgression(id),
    body: {'response_language': responseLanguage},
  );
  Future<Object?> diagnosisImages(String id) =>
      client.get(ApiEndpoints.diagnosisImages(id));
  Future<List<int>> diagnosisImage(String id, String imageId) =>
      client.getBytes(ApiEndpoints.diagnosisImage(id, imageId));
  Future<Object?> diagnosisImagePredictions(String id) =>
      client.get(ApiEndpoints.diagnosisImagePredictions(id));
  Future<Object?> linkDiagnosis(String id, Map<String, Object?> body) =>
      client.patch(ApiEndpoints.diagnosisLink(id), body: body);
  Future<Object?> getDiagnosisFeedback(String id) =>
      client.get(ApiEndpoints.diagnosisFeedback(id));
  Future<Object?> upsertDiagnosisFeedback(
    String id,
    Map<String, Object?> body,
  ) => client.put(ApiEndpoints.diagnosisFeedback(id), body: body);

  Future<Object?> createChat(Map<String, Object?> body) =>
      client.post(ApiEndpoints.chats, body: body);
  Future<Object?> listChats({Map<String, String>? filters}) =>
      client.get(ApiEndpoints.chats, query: filters);
  Future<Object?> getChat(String id) => client.get(ApiEndpoints.chat(id));
  Future<Object?> updateChat(String id, Map<String, Object?> body) =>
      client.patch(ApiEndpoints.chat(id), body: body);
  Future<void> deleteChat(String id) => client.delete(ApiEndpoints.chat(id));
  Future<Object?> listChatMessages(String id, {Map<String, String>? paging}) =>
      client.get(ApiEndpoints.chatMessages(id), query: paging);
  Future<Object?> sendChatMessage(
    String id,
    Map<String, Object?> body, {
    required String idempotencyKey,
  }) => client.post(
    ApiEndpoints.chatMessages(id),
    body: body,
    headers: {'Idempotency-Key': idempotencyKey},
  );
  Future<Object?> listChatTurns(String id, {bool activeOnly = true}) => client
      .get(ApiEndpoints.chatTurns(id), query: {'active_only': '$activeOnly'});
  Future<Object?> getChatTurn(String chatId, String turnId) =>
      client.get(ApiEndpoints.chatTurn(chatId, turnId));
  Future<Object?> retryChatTurn(String chatId, String turnId) =>
      client.post(ApiEndpoints.chatTurnRetry(chatId, turnId));

  Future<Object?> transcribeChatAudio(String chatId, String filePath) =>
      client.multipart(
        ApiEndpoints.voiceTranscription(chatId),
        fields: const {},
        filePaths: [filePath],
        fileField: 'audio',
      );

  Future<List<int>> assistantSpeech(String chatId, String messageId) =>
      client.postBytes(
        ApiEndpoints.assistantSpeech(chatId, messageId),
        headers: const {'Accept': 'audio/mpeg'},
      );

  Future<Object?> connectChatMemory(String id, Map<String, Object?> body) =>
      client.post(ApiEndpoints.chatMemoryConnection(id), body: body);
  Future<void> disconnectChatMemory(String id) =>
      client.delete(ApiEndpoints.chatMemoryConnection(id));
  Future<Object?> listFarmMemories(String id, {Map<String, String>? paging}) =>
      client.get(ApiEndpoints.farmMemories(id), query: paging);
  Future<Object?> listPlotMemories(String id, {Map<String, String>? paging}) =>
      client.get(ApiEndpoints.plotMemories(id), query: paging);
  Future<void> deleteMemory(String id) =>
      client.delete(ApiEndpoints.memory(id));
  Future<Object?> retryMemory(String id) =>
      client.post(ApiEndpoints.memoryRetry(id));

  Future<Object?> listReminderProposals() =>
      client.get(ApiEndpoints.reminderProposals);
  Future<Object?> decideReminderProposal(
    String id,
    Map<String, Object?> body,
  ) => client.post(ApiEndpoints.reminderProposalDecision(id), body: body);
  Future<Object?> createReminder(Map<String, Object?> body) =>
      client.post(ApiEndpoints.reminders, body: body);
  Future<Object?> listReminders({Map<String, String>? filters}) =>
      client.get(ApiEndpoints.reminders, query: filters);
  Future<Object?> actOnReminder(String id, Map<String, Object?> body) =>
      client.post(ApiEndpoints.reminderActions(id), body: body);
  Future<Object?> reminderEvents(String id) =>
      client.get(ApiEndpoints.reminderEvents(id));

  Future<Object?> currentWeather(Map<String, Object?> coordinates) =>
      client.post(ApiEndpoints.weatherCurrent, body: coordinates);
  Future<Object?> currentPlotWeather(String id) =>
      client.get(ApiEndpoints.plotCurrentWeather(id));
  Future<Object?> plotForecast(String id) =>
      client.get(ApiEndpoints.plotForecast(id));
  Future<Object?> searchLocations(
    String query, {
    required String language,
    int limit = 8,
  }) => client.get(
    ApiEndpoints.locationsSearch,
    query: {'query': query, 'language': language, 'limit': '$limit'},
  );

  Future<Object?> createDiagnosisReport(
    String caseId,
    Map<String, Object?> approval,
  ) => client.post(ApiEndpoints.diagnosisReports(caseId), body: approval);
  Future<Object?> listDiagnosisReports(String caseId) =>
      client.get(ApiEndpoints.diagnosisReports(caseId));
  Future<Object?> revokeDiagnosisReport(String reportId) =>
      client.post(ApiEndpoints.diagnosisReportRevoke(reportId));
  Future<List<int>> ownerReportImage(String reportId, String imageId) =>
      client.getBytes(ApiEndpoints.diagnosisReportImage(reportId, imageId));
  Future<Object?> publicDiagnosisReport(String reportId, String token) =>
      client.get(
        ApiEndpoints.publicDiagnosisReport(reportId),
        auth: false,
        headers: {'X-Report-Token': token},
      );
  Future<List<int>> publicDiagnosisReportImage(
    String reportId,
    String imageId,
    String token,
  ) => client.getBytes(
    ApiEndpoints.publicDiagnosisReportImage(reportId, imageId),
    auth: false,
    headers: {'X-Report-Token': token},
  );

  Future<Object?> retryObjectDeletions() =>
      client.post(ApiEndpoints.retryObjectDeletions);
}

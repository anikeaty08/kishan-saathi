abstract final class ApiEndpoints {
  static const authSignUp = '/api/v1/auth/sign-up';
  static const authConfirm = '/api/v1/auth/confirm';
  static const authResend = '/api/v1/auth/resend';
  static const authSignIn = '/api/v1/auth/sign-in';
  static const authRefresh = '/api/v1/auth/refresh';
  static const authPasswordReset = '/api/v1/auth/password-reset';
  static const authPasswordResetConfirm = '/api/v1/auth/password-reset/confirm';
  static const live = '/health/live';
  static const ready = '/health/ready';
  static const me = '/api/v1/me';
  static const farms = '/api/v1/farms';
  static String farm(String id) => '$farms/$id';
  static String farmDeletionImpact(String id) => '${farm(id)}/deletion-impact';
  static const plots = '/api/v1/plots';
  static String plot(String id) => '$plots/$id';
  static String plotDeletionImpact(String id) => '${plot(id)}/deletion-impact';
  static String plotCrops(String id) => '${plot(id)}/crops';
  static String plotActivities(String id) => '${plot(id)}/activities';
  static String plotTimeline(String id) => '${plot(id)}/timeline';
  static String crop(String id) => '/api/v1/crops/$id';
  static String cropStage(String id) => '${crop(id)}/stage';
  static String cropCloseCycle(String id) => '${crop(id)}/close-cycle';
  static String cropDeletionImpact(String id) => '${crop(id)}/deletion-impact';
  static String activity(String id) => '/api/v1/activities/$id';
  static String activityPhotos(String id) => '${activity(id)}/photos';
  static String activityPhoto(String activityId, String photoId) =>
      '${activityPhotos(activityId)}/$photoId';
  static const diagnoses = '/api/v1/diagnoses';
  static String diagnosis(String id) => '$diagnoses/$id';
  static String diagnosisRetakes(String id) => '${diagnosis(id)}/retakes';
  static String diagnosisAssessments(String id) =>
      '${diagnosis(id)}/assessments';
  static String diagnosisProgression(String id) =>
      '${diagnosis(id)}/progression';
  static String diagnosisImages(String id) => '${diagnosis(id)}/images';
  static String diagnosisImage(String id, String imageId) =>
      '${diagnosisImages(id)}/$imageId';
  static String diagnosisImagePredictions(String id) =>
      '${diagnosis(id)}/image-predictions';
  static String diagnosisLink(String id) => '${diagnosis(id)}/link';
  static String diagnosisFeedback(String id) => '${diagnosis(id)}/feedback';
  static const chats = '/api/v1/chats';
  static String chat(String id) => '$chats/$id';
  static String chatMessages(String id) => '${chat(id)}/messages';
  static String chatTurns(String id) => '${chat(id)}/turns';
  static String chatTurn(String chatId, String turnId) =>
      '${chatTurns(chatId)}/$turnId';
  static String chatTurnRetry(String chatId, String turnId) =>
      '${chatTurn(chatId, turnId)}/retry';
  static String voiceTranscription(String chatId) =>
      '/api/v1/voice/chats/$chatId/transcriptions';
  static String assistantSpeech(String chatId, String messageId) =>
      '/api/v1/voice/chats/$chatId/messages/$messageId/speech';
  static String farmMemories(String id) => '${farm(id)}/memories';
  static String plotMemories(String id) => '${plot(id)}/memories';
  static String memory(String id) => '/api/v1/memories/$id';
  static String memoryRetry(String id) => '${memory(id)}/retry';
  static String chatMemoryConnection(String id) =>
      '${chat(id)}/memory-connection';
  static const reminderProposals = '/api/v1/reminder-proposals';
  static String reminderProposalDecision(String id) =>
      '$reminderProposals/$id/decision';
  static const reminders = '/api/v1/reminders';
  static String reminderActions(String id) => '$reminders/$id/actions';
  static String reminderEvents(String id) => '$reminders/$id/events';
  static const weatherCurrent = '/api/v1/weather/current';
  static String plotCurrentWeather(String id) =>
      '/api/v1/weather/plots/$id/current';
  static String plotForecast(String id) => '/api/v1/weather/plots/$id/forecast';
  static const locationsSearch = '/api/v1/locations/search';
  static String diagnosisReports(String caseId) =>
      '${diagnosis(caseId)}/reports';
  static String diagnosisReportRevoke(String id) =>
      '/api/v1/diagnosis-reports/$id/revoke';
  static String diagnosisReportImage(String id, String imageId) =>
      '/api/v1/diagnosis-reports/$id/images/$imageId';
  static String publicDiagnosisReport(String id) =>
      '/api/v1/shared/diagnosis-reports/$id';
  static String publicDiagnosisReportImage(String id, String imageId) =>
      '${publicDiagnosisReport(id)}/images/$imageId';
  static const retryObjectDeletions = '/api/v1/privacy/object-deletions/retry';
}

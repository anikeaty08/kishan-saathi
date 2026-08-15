import '../../../core/models/app_models.dart';

abstract final class ScanStatePolicy {
  static String? previousDiagnosisId(List<DiagnosisCaseModel> diagnoses) =>
      diagnoses.isEmpty ? null : diagnoses.first.id;
}

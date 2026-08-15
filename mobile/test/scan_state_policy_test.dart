import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/models/app_models.dart';
import 'package:krishisathi/features/scan/data/scan_state_policy.dart';

void main() {
  test('failed first scan exposes no invalid previous-result target', () {
    expect(ScanStatePolicy.previousDiagnosisId(const []), isNull);
  });

  test('existing diagnosis can be opened as a previous result', () {
    final diagnosis = DemoData.diagnoses.first;
    expect(ScanStatePolicy.previousDiagnosisId([diagnosis]), diagnosis.id);
  });
}

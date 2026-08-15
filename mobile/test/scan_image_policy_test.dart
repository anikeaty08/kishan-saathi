import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:krishisathi/features/scan/data/scan_image_policy.dart';

void main() {
  test('gallery and recovered images cannot exceed one case limit', () {
    final files = List.generate(20, (index) => XFile('leaf_$index.jpg'));

    expect(ScanImagePolicy.remaining(5), 7);
    expect(ScanImagePolicy.remaining(12), 0);
    expect(ScanImagePolicy.acceptRecovered(files, 5), hasLength(7));
    expect(ScanImagePolicy.acceptRecovered(files, 12), isEmpty);
  });
}

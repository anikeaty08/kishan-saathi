import 'package:image_picker/image_picker.dart';

abstract final class ScanImagePolicy {
  static const maxImagesPerCase = 12;

  static int remaining(int currentCount) =>
      (maxImagesPerCase - currentCount).clamp(0, maxImagesPerCase);

  static List<XFile> acceptRecovered(List<XFile> files, int currentCount) =>
      files.take(remaining(currentCount)).toList(growable: false);
}

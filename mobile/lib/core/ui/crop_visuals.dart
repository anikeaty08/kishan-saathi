abstract final class CropVisuals {
  static String forCrop(String? cropName) {
    final name = cropName?.trim().toLowerCase() ?? '';
    if (name.contains('tomato')) return 'assets/images/crop_tomato.jpg';
    if (name.contains('rice') || name.contains('paddy')) {
      return 'assets/images/crop_rice.webp';
    }
    if (name.contains('wheat')) return 'assets/images/crop_wheat.webp';
    if (name.contains('cotton')) return 'assets/images/crop_cotton.webp';
    if (name.contains('banana')) return 'assets/images/crop_banana.webp';
    if (name.contains('millet') || name.contains('ragi')) {
      return 'assets/images/crop_ragi.jpg';
    }
    return 'assets/images/crop_maize.jpg';
  }

  static String forFarm(Iterable<String> cropNames) {
    final first = cropNames.firstOrNull;
    return first == null ? 'assets/images/hero_farm_bg.jpg' : forCrop(first);
  }
}

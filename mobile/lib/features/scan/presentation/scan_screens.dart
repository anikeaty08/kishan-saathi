import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../data/diagnosis_repository.dart';
import '../data/scan_image_policy.dart';
import '../data/scan_state_policy.dart';
import '../../shared/presentation/app_controller.dart';
import 'leaf_camera_screen.dart';

enum _ScanStep { capture, review, processing, unavailable, saved }

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    this.initialPlotId,
    this.retakeCaseId,
    this.initialImageSource,
  });
  final String? initialPlotId;
  final String? retakeCaseId;
  final String? initialImageSource;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  final _cropController = TextEditingController();
  final List<XFile> _images = [];
  _ScanStep _step = _ScanStep.capture;
  String? _plotId;
  String? _historyPlotId;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _plotId = widget.initialPlotId;
    unawaited(_initializePicker());
  }

  @override
  void dispose() {
    _cropController.dispose();
    super.dispose();
  }

  Future<void> _recoverLostData() async {
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty || !mounted) return;
      final files = response.files;
      if (files != null) {
        final accepted = ScanImagePolicy.acceptRecovered(files, _images.length);
        setState(() {
          _images.addAll(accepted);
          if (_images.isNotEmpty) _step = _ScanStep.review;
        });
        if (files.length > accepted.length && mounted) {
          _showImageLimit();
        }
      }
    } on PlatformException catch (error) {
      if (mounted) _showPickerError(error);
    }
  }

  Future<void> _initializePicker() async {
    await _recoverLostData();
    if (!mounted || _images.isNotEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialImageSource == 'camera') {
        unawaited(_takePhoto());
      } else if (widget.initialImageSource == 'gallery') {
        unawaited(_choosePhotos());
      }
    });
  }

  Future<void> _takePhoto() async {
    if (ScanImagePolicy.remaining(_images.length) == 0) {
      _showImageLimit();
      return;
    }
    final controller = context.read<AppController>();
    if (!controller.cameraEnabled) {
      final status = await controller.setCameraEnabled(true);
      if (!mounted || !status.isAllowed) {
        if (mounted) {
          showAppSnackBar(
            context,
            'Camera permission is required to take a leaf photo.',
          );
        }
        return;
      }
    }
    try {
      final image = await Navigator.of(context).push<XFile>(
        MaterialPageRoute<XFile>(
          fullscreenDialog: true,
          builder: (_) => const LeafCameraScreen(),
        ),
      );
      if (image == null || !mounted) return;
      setState(() {
        _images.add(image);
        _step = _ScanStep.review;
      });
    } on PlatformException catch (error) {
      if (mounted) _showPickerError(error);
    }
  }

  Future<void> _choosePhotos() async {
    final remaining = ScanImagePolicy.remaining(_images.length);
    if (remaining <= 0) {
      _showImageLimit();
      return;
    }
    try {
      final images = await _picker.pickMultiImage(
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
        limit: remaining,
      );
      if (images.isEmpty || !mounted) return;
      setState(() {
        _images.addAll(images);
        _step = _ScanStep.review;
      });
    } on PlatformException catch (error) {
      if (mounted) _showPickerError(error);
    }
  }

  void _showImageLimit() {
    showAppSnackBar(
      context,
      'You can add up to ${ScanImagePolicy.maxImagesPerCase} leaf photos to one scan.',
    );
  }

  void _showPickerError(PlatformException error) {
    showAppSnackBar(
      context,
      error.code.toLowerCase().contains('permission')
          ? 'Allow camera and photo access in phone settings to add leaf images.'
          : 'The phone could not open the camera or gallery. Please try again.',
    );
  }

  Future<void> _analyse() async {
    if (_images.isEmpty || _step == _ScanStep.processing) return;
    setState(() {
      _step = _ScanStep.processing;
      _error = null;
    });
    try {
      final controller = context.read<AppController>();
      final paths = _images.map((item) => item.path).toList();
      final diagnosis = widget.retakeCaseId == null
          ? await controller.submitDiagnosis(
              imagePaths: paths,
              cropName: _cropController.text,
              plotId: _plotId,
            )
          : await controller.addDiagnosisRetake(
              caseId: widget.retakeCaseId!,
              imagePaths: paths,
            );
      if (!mounted) return;
      context.push('/scan/result/${diagnosis.id}');
      setState(_reset);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _step = _ScanStep.unavailable;
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'scan',
          context: ErrorDescription('while submitting a leaf diagnosis'),
        ),
      );
      if (!mounted) return;
      setState(() {
        _error = const ApiException(
          code: 'SCAN_FAILED',
          message: 'Leaf analysis could not be completed',
        );
        _step = _ScanStep.unavailable;
      });
    }
  }

  void _reset() {
    _images.clear();
    _cropController.clear();
    _step = _ScanStep.capture;
    _error = null;
  }

  Future<void> _queue() async {
    try {
      await context.read<AppController>().queueScan(
        _images.map((item) => item.path).toList(),
        cropName: _cropController.text,
        plotId: _plotId,
      );
      if (mounted) setState(() => _step = _ScanStep.saved);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final plots = controller.farms.expand((farm) => farm.plots).toList();
    final visibleDiagnoses = _historyPlotId == null
        ? controller.diagnoses
        : controller.diagnoses
              .where((diagnosis) => diagnosis.plotId == _historyPlotId)
              .toList(growable: false);
    final isProcessing = _step == _ScanStep.processing;
    return PopScope<void>(
      canPop: !isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isProcessing) {
          showAppSnackBar(
            context,
            'Leaf analysis is still running. Please keep this screen open.',
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('scanTitle')),
          actions: [
            if (!isProcessing && controller.queuedScans.isNotEmpty)
              IconButton(
                tooltip: 'Saved leaf checks',
                onPressed: () => context.push('/scan/queue'),
                icon: Badge(
                  label: Text('${controller.queuedScans.length}'),
                  child: const Icon(LucideIcons.cloudUpload, size: 22),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: AppContent(
            maxWidth: 900,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: switch (_step) {
                _ScanStep.capture => _CaptureStep(
                  key: const ValueKey('capture'),
                  onCamera: _takePhoto,
                  onGallery: _choosePhotos,
                  diagnoses: visibleDiagnoses,
                  plots: plots,
                  selectedHistoryPlotId: _historyPlotId,
                  onHistoryPlotChanged: (value) =>
                      setState(() => _historyPlotId = value),
                ),
                _ScanStep.review => _ReviewStep(
                  key: const ValueKey('review'),
                  images: _images,
                  cropController: _cropController,
                  plots: plots,
                  selectedPlotId: _plotId,
                  onPlotChanged: (value) => setState(() => _plotId = value),
                  onCamera: _takePhoto,
                  onGallery: _choosePhotos,
                  onRemove: (index) {
                    setState(() {
                      _images.removeAt(index);
                      if (_images.isEmpty) _step = _ScanStep.capture;
                    });
                  },
                  onAnalyse: _analyse,
                ),
                _ScanStep.processing => const _ProcessingStep(
                  key: ValueKey('processing'),
                ),
                _ScanStep.unavailable => _UnavailableStep(
                  key: const ValueKey('unavailable'),
                  error: _error,
                  onRetry: _analyse,
                  onQueue: _queue,
                  onSample:
                      ScanStatePolicy.previousDiagnosisId(
                            controller.diagnoses,
                          ) ==
                          null
                      ? null
                      : () => context.push(
                          '/scan/result/${ScanStatePolicy.previousDiagnosisId(controller.diagnoses)}',
                        ),
                ),
                _ScanStep.saved => _SavedStep(
                  key: const ValueKey('saved'),
                  onDone: () => setState(_reset),
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureStep extends StatelessWidget {
  const _CaptureStep({
    super.key,
    required this.onCamera,
    required this.onGallery,
    required this.diagnoses,
    required this.plots,
    required this.selectedHistoryPlotId,
    required this.onHistoryPlotChanged,
  });
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final List<DiagnosisCaseModel> diagnoses;
  final List<PlotModel> plots;
  final String? selectedHistoryPlotId;
  final ValueChanged<String?> onHistoryPlotChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('scan-capture'),
      padding: const EdgeInsets.only(top: 8, bottom: 110),
      children: [
        Text('Check a leaf', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 5),
        Text(
          context.tr('scanBody'),
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: AppColors.mutedInk),
        ),
        const SizedBox(height: 18),
        _PulsingScanCard(
          onCamera: onCamera,
          onGallery: onGallery,
          photoGuide: context.tr('photoGuide'),
          takePhoto: context.tr('takePhoto'),
          choosePhotos: context.tr('choosePhotos'),
        ),
        const SizedBox(height: 22),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: const Icon(LucideIcons.history, color: AppColors.forest),
          title: Text(context.tr('scanHistory')),
          subtitle: Text(
            diagnoses.isEmpty
                ? 'No completed checks yet'
                : '${diagnoses.length} saved ${diagnoses.length == 1 ? 'check' : 'checks'}',
          ),
          children: [
            if (plots.isNotEmpty) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All plots'),
                      selected: selectedHistoryPlotId == null,
                      onSelected: (_) => onHistoryPlotChanged(null),
                    ),
                    const SizedBox(width: 7),
                    for (final plot in plots) ...[
                      ChoiceChip(
                        label: Text(plot.name),
                        selected: selectedHistoryPlotId == plot.id,
                        onSelected: (_) => onHistoryPlotChanged(plot.id),
                      ),
                      const SizedBox(width: 7),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (diagnoses.isEmpty)
              AppStateView(
                kind: AppStateKind.empty,
                title: selectedHistoryPlotId == null
                    ? context.tr('emptyTitle')
                    : 'No leaf checks for this plot',
                message: selectedHistoryPlotId == null
                    ? 'Completed leaf checks will appear here.'
                    : 'Choose another plot or start a new check linked to this field.',
                compact: true,
              )
            else
              ...diagnoses.map(
                (diagnosis) => _HistoryRow(diagnosis: diagnosis),
              ),
          ],
        ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    super.key,
    required this.images,
    required this.cropController,
    required this.plots,
    required this.selectedPlotId,
    required this.onPlotChanged,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
    required this.onAnalyse,
  });
  final List<XFile> images;
  final TextEditingController cropController;
  final List<PlotModel> plots;
  final String? selectedPlotId;
  final ValueChanged<String?> onPlotChanged;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ValueChanged<int> onRemove;
  final VoidCallback onAnalyse;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 110),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('photosSelected', {'count': images.length}),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              tooltip: context.tr('takePhoto'),
              onPressed: images.length >= 12 ? null : onCamera,
              icon: const Icon(LucideIcons.camera),
            ),
            IconButton(
              tooltip: context.tr('choosePhotos'),
              onPressed: images.length >= 12 ? null : onGallery,
              icon: const Icon(LucideIcons.images),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) => Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: Image.file(File(images[index].path), fit: BoxFit.cover),
              ),
              PositionedDirectional(
                top: 6,
                end: 6,
                child: IconButton.filled(
                  tooltip: 'Remove photo',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xC7111A14),
                  ),
                  onPressed: () => onRemove(index),
                  icon: const Icon(
                    LucideIcons.x,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: const Icon(LucideIcons.listPlus, color: AppColors.forest),
          title: const Text('Add crop or plot context'),
          subtitle: const Text('Optional, but it can improve the result'),
          children: [
            TextField(
              controller: cropController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr('optionalCrop'),
                prefixIcon: const Icon(LucideIcons.sprout, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: selectedPlotId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('linkToPlot'),
                prefixIcon: const Icon(LucideIcons.map, size: 20),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No plot selected'),
                ),
                ...plots.map(
                  (plot) => DropdownMenuItem<String?>(
                    value: plot.id,
                    child: Text(plot.name),
                  ),
                ),
              ],
              onChanged: onPlotChanged,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.circleCheck,
              size: 18,
              color: AppColors.leaf,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                context.tr('photoGuide'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.mutedInk),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onAnalyse,
          icon: const Icon(LucideIcons.scanLine, size: 19),
          label: Text(context.tr('analyseLeaf')),
        ),
      ],
    );
  }
}

class _ProcessingStep extends StatefulWidget {
  const _ProcessingStep({super.key});

  @override
  State<_ProcessingStep> createState() => _ProcessingStepState();
}

class _ProcessingStepState extends State<_ProcessingStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fillController;
  int _tipIndex = 0;
  Timer? _tipTimer;
  bool? _reduceMotion;

  static const _tips = [
    'Checking image quality and leaf visibility…',
    'Reviewing compatible PlantWild classes…',
    'Combining evidence from the submitted leaf photos…',
    'Preparing possible matches and retake guidance…',
  ];

  @override
  void initState() {
    super.initState();
    _fillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _tipTimer?.cancel();
    if (reduceMotion) {
      _fillController
        ..stop()
        ..value = 0.55;
      return;
    }
    _fillController.repeat(reverse: true);
    _tipTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) {
        setState(() => _tipIndex = (_tipIndex + 1) % _tips.length);
      }
    });
  }

  @override
  void dispose() {
    _fillController.dispose();
    _tipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Leaf fill loader
            Semantics(
              label: 'Leaf analysis in progress',
              child: RepaintBoundary(
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: AnimatedBuilder(
                    animation: _fillController,
                    builder: (context, _) => CustomPaint(
                      painter: _LeafFillPainter(
                        progress: _fillController.value,
                        dark: dark,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              context.tr('processingScan'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: _reduceMotion == true
                  ? Duration.zero
                  : const Duration(milliseconds: 400),
              child: Text(
                _tips[_tipIndex],
                key: ValueKey(_tipIndex),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedInk, height: 1.5),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'This usually takes about 20–30 seconds. Keep this screen open.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.mutedInk, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeafFillPainter extends CustomPainter {
  const _LeafFillPainter({required this.progress, required this.dark});
  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.42;

    // Leaf outline path
    final leaf = Path()
      ..moveTo(cx, cy - r)
      ..cubicTo(
        cx + r * 0.9,
        cy - r * 0.5,
        cx + r * 0.9,
        cy + r * 0.5,
        cx,
        cy + r,
      )
      ..cubicTo(
        cx - r * 0.9,
        cy + r * 0.5,
        cx - r * 0.9,
        cy - r * 0.5,
        cx,
        cy - r,
      );

    // Background leaf
    canvas.drawPath(
      leaf,
      Paint()
        ..color = dark
            ? AppColors.leaf.withValues(alpha: 0.12)
            : AppColors.divider,
    );

    // Fill clip from bottom
    final fillHeight = size.height * progress;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, size.height - fillHeight, size.width, fillHeight),
    );
    canvas.drawPath(
      leaf,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [AppColors.forest, AppColors.leaf, AppColors.youngLeaf],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.restore();

    // Leaf vein
    final vein = Path()
      ..moveTo(cx, cy + r * 0.9)
      ..lineTo(cx, cy - r * 0.9);
    canvas.drawPath(
      vein,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LeafFillPainter old) =>
      old.progress != progress || old.dark != dark;
}

class _UnavailableStep extends StatelessWidget {
  const _UnavailableStep({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onQueue,
    required this.onSample,
  });
  final ApiException? error;
  final VoidCallback onRetry;
  final VoidCallback onQueue;
  final VoidCallback? onSample;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 36, bottom: 80),
      children: [
        AppStateView(
          kind: AppStateKind.error,
          title: context.tr('modelUnavailable'),
          message: context.tr('modelUnavailableBody'),
        ),
        if (error?.requestId != null)
          Center(
            child: Text(context.tr('requestId', {'id': error!.requestId})),
          ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: onQueue,
          icon: const Icon(LucideIcons.cloudUpload, size: 19),
          label: Text(context.tr('queueOffline')),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(LucideIcons.refreshCw, size: 19),
          label: Text(context.tr('retry')),
        ),
        if (onSample != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: onSample,
            child: const Text('Open previous result'),
          ),
        ],
      ],
    );
  }
}

class _SavedStep extends StatelessWidget {
  const _SavedStep({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 50, bottom: 80),
      children: [
        AppStateView(
          kind: AppStateKind.success,
          title: context.tr('savedForLater'),
          message: 'KrishiSathi will ask before uploading these photos when live diagnosis becomes available.',
        ),
        FilledButton(onPressed: onDone, child: Text(context.tr('done'))),
      ],
    );
  }
}

class _PulsingScanCard extends StatefulWidget {
  const _PulsingScanCard({
    required this.onCamera,
    required this.onGallery,
    required this.photoGuide,
    required this.takePhoto,
    required this.choosePhotos,
  });
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final String photoGuide;
  final String takePhoto;
  final String choosePhotos;

  @override
  State<_PulsingScanCard> createState() => _PulsingScanCardState();
}

class _PulsingScanCardState extends State<_PulsingScanCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(
      begin: 1.0,
      end: 1.18,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _pulseOpacity = Tween<double>(
      begin: 0.25,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E3828), Color(0xFF0F2018)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.large),
          boxShadow: [
            BoxShadow(
              color: AppColors.forest.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Soft glow top right
            PositionedDirectional(
              top: -30,
              end: -30,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.youngLeaf.withValues(alpha: 0.18),
                      AppColors.youngLeaf.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // Center pulsing icon
            Center(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) => Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pulse ring
                    Opacity(
                      opacity: _pulseOpacity.value,
                      child: Transform.scale(
                        scale: _pulseScale.value,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFE1A82B),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Inner icon circle
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: const Color(0xFFDCE8D5).withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        LucideIcons.scanSearch,
                        color: Color(0xFFF1C85B),
                        size: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Badge top left
            PositionedDirectional(
              top: 14,
              start: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Text(
                  'One clear photo works great',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFF6F1E5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            // Buttons at bottom
            PositionedDirectional(
              start: 14,
              end: 14,
              bottom: 14,
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onCamera,
                      icon: const Icon(LucideIcons.camera, size: 17),
                      label: Text(widget.takePhoto),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.forest,
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onGallery,
                      icon: const Icon(LucideIcons.images, size: 17),
                      label: Text(widget.choosePhotos),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(
                          color: Color(0xFFDCE8D5),
                          width: 1.2,
                        ),
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QueuedScansScreen extends StatelessWidget {
  const QueuedScansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final scans = controller.queuedScans;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved leaf checks')),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 760,
          child: scans.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.cloudOff,
                        size: 48,
                        color: AppColors.mutedInk,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No offline scans',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'When you scan without internet, they will be saved here to upload later.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.mutedInk),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(top: 8, bottom: 36),
                  itemCount: scans.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final scan = scans[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: AppColors.leaf.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.small,
                                ),
                              ),
                              child: const Icon(
                                LucideIcons.shieldCheck,
                                color: AppColors.forest,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    scan.cropName ?? 'Crop not specified',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${scan.imagePaths.length} ${scan.imagePaths.length == 1 ? 'photo' : 'photos'} - ${context.tr('date.saved', {'date': context.strings.formatDateTime(scan.createdAt)})}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: AppColors.mutedInk),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      OutlinedButton(
                                        onPressed: controller.busy
                                            ? null
                                            : () => _remove(context, scan),
                                        child: Text(context.tr('delete')),
                                      ),
                                      FilledButton.icon(
                                        onPressed:
                                            controller.canUseLiveServices &&
                                                !controller.busy
                                            ? () => _analyse(context, scan)
                                            : null,
                                        icon: const Icon(
                                          LucideIcons.scanLine,
                                          size: 17,
                                        ),
                                        label: const Text('Analyse now'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _analyse(BuildContext context, QueuedScanModel scan) async {
    try {
      final diagnosis = await context.read<AppController>().submitQueuedScan(
        scan,
      );
      if (context.mounted) {
        context.push('/scan/result/${diagnosis.id}');
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }

  Future<void> _remove(BuildContext context, QueuedScanModel scan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove saved photos?'),
        content: const Text(
          'These local copies will be deleted from KrishiSathi. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await context.read<AppController>().removeQueuedScan(scan.id);
      } on ApiException catch (error) {
        if (context.mounted) {
          showAppSnackBar(context, context.localizedError(error));
        }
      }
    }
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.diagnosis});
  final DiagnosisCaseModel diagnosis;
  @override
  Widget build(BuildContext context) {
    final prediction = diagnosis.predictions.firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/scan/result/${diagnosis.id}'),
          child: Row(
            children: [
              _DiagnosisImage(diagnosis: diagnosis, width: 84, height: 84),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prediction?.name ?? 'Processing',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${diagnosis.cropName} · ${context.strings.formatShortDate(diagnosis.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppColors.mutedInk),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _confidenceColor(diagnosis.confidenceLabel)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.small),
                        ),
                        child: Text(
                          _confidenceText(diagnosis.confidenceLabel),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _confidenceColor(
                                  diagnosis.confidenceLabel,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsetsDirectional.only(end: 12),
                child: Icon(
                  LucideIcons.chevronRight,
                  size: 20,
                  color: AppColors.mutedInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DiagnosisResultScreen extends StatefulWidget {
  const DiagnosisResultScreen({super.key, required this.diagnosisId});
  final String diagnosisId;

  @override
  State<DiagnosisResultScreen> createState() => _DiagnosisResultScreenState();
}

class _DiagnosisResultScreenState extends State<DiagnosisResultScreen> {
  List<DiagnosisAssessmentModel> _history = const [];
  List<ProgressionComparisonModel> _comparisonHistory = const [];
  bool _loadingHistory = true;
  bool _comparing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final controller = context.read<AppController>();
        await controller.loadDiagnosis(widget.diagnosisId);
        _history = await controller.loadDiagnosisHistory(widget.diagnosisId);
        _comparisonHistory = await controller.loadProgressionHistory(
          widget.diagnosisId,
        );
      } on ApiException catch (error) {
        if (mounted) showAppSnackBar(context, context.localizedError(error));
      } finally {
        if (mounted) setState(() => _loadingHistory = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final diagnosis = controller.diagnoses
        .cast<DiagnosisCaseModel?>()
        .firstWhere(
          (item) => item?.id == widget.diagnosisId,
          orElse: () => null,
        );
    if (diagnosis == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const AppStateView(
          kind: AppStateKind.error,
          title: 'Leaf check not found',
          message: 'It may have been deleted or is still being processed.',
        ),
      );
    }
    final primary = diagnosis.predictions.firstOrNull;
    final existingChat = controller.chats
        .where((chat) => chat.diagnosisCaseId == diagnosis.id && !chat.archived)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('possibleMatch')),
        actions: [
          IconButton(
            tooltip: context.tr('share'),
            onPressed: () => _showReportSheet(context, diagnosis),
            icon: const Icon(LucideIcons.share2),
          ),
          PopupMenuButton<String>(
            tooltip: 'Leaf check options',
            onSelected: (action) => _handleOption(context, diagnosis, action),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'link',
                child: Text('Link to plot and crop'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: Text('Delete leaf check')),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 780,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: _DiagnosisImage(diagnosis: diagnosis),
                ),
              ),
              if (diagnosis.imageIds.length > 1) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: diagnosis.imageIds.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      child: SizedBox.square(
                        dimension: 86,
                        child: _DiagnosisServerImage(
                          caseId: diagnosis.id,
                          imageId: diagnosis.imageIds[index],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          primary?.name ?? 'No clear match',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${diagnosis.cropName}${diagnosis.plotName == null ? '' : ' - ${diagnosis.plotName}'}',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: AppColors.mutedInk),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _confidenceColor(diagnosis.confidenceLabel)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                    ),
                    child: Text(
                      _confidenceText(diagnosis.confidenceLabel),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                primary?.summary ??
                    'The model did not return a reliable match.',
              ),
              if (diagnosis.retakeRecommended ||
                  diagnosis.qualityFlags.isNotEmpty) ...[
                const SizedBox(height: 18),
                InlineNotice(
                  title: context.tr('retakeRecommended'),
                  message: 'Take one closer photo in daylight and one photo of the full plant before acting.',
                  icon: LucideIcons.camera,
                  color: AppColors.amber,
                ),
              ],
              const SizedBox(height: 26),
              SectionHeader(title: context.tr('whatToDo')),
              const SizedBox(height: 10),
              const _ActionStep(
                number: '1',
                title: 'Remove badly affected leaves',
                body: 'Keep removed leaves away from the plot. Do not compost them near the crop.',
              ),
              const _ActionStep(
                number: '2',
                title: 'Keep foliage dry',
                body: 'Water near the root and improve airflow where plants are crowded.',
              ),
              const _ActionStep(
                number: '3',
                title: 'Confirm before treatment',
                body: 'Ask a local expert before using any pesticide or fungicide.',
              ),
              if (diagnosis.predictions.length > 1) ...[
                const SizedBox(height: 24),
                SectionHeader(title: 'Other possibilities'),
                const SizedBox(height: 10),
                ...diagnosis.predictions
                    .skip(1)
                    .map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          LucideIcons.leaf,
                          color: AppColors.leaf,
                        ),
                        title: Text(item.name),
                        subtitle: Text(item.summary),
                      ),
                    ),
              ],
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Case history',
                subtitle: 'Original checks and retakes stay linked.',
              ),
              const SizedBox(height: 10),
              if (_loadingHistory)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_history.isEmpty)
                const AppStateView(
                  kind: AppStateKind.empty,
                  title: 'No earlier assessments',
                  message: 'Retake results will appear here without replacing the original record.',
                  compact: true,
                )
              else
                ..._history.map(
                  (assessment) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      assessment.isActive
                          ? LucideIcons.circleCheck
                          : LucideIcons.history,
                      color: assessment.isActive
                          ? AppColors.leaf
                          : AppColors.mutedInk,
                    ),
                    title: Text(assessment.diseaseName),
                    subtitle: Text(
                      '${assessment.cropName} · ${_confidenceText(assessment.confidenceLabel)} · ${context.strings.formatDateTime(assessment.createdAt.toLocal())}',
                    ),
                    trailing: assessment.isActive
                        ? const Text('Current')
                        : null,
                  ),
                ),
              if (_history.length >= 2) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('compare-leaf-progress'),
                    onPressed: _comparing
                        ? null
                        : () => _compareProgression(context, diagnosis),
                    icon: _comparing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.chartNoAxesCombined, size: 18),
                    label: Text(
                      _comparing
                          ? 'Comparing visible change…'
                          : 'Compare earlier and recent photos',
                    ),
                  ),
                ),
                if (_comparisonHistory.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const SectionHeader(
                    title: 'Earlier visual comparisons',
                    subtitle: 'Saved analyses can be reopened here.',
                  ),
                  const SizedBox(height: 8),
                  ..._comparisonHistory.map(
                    (comparison) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _ProgressionComparisonSheet._trendIcon(
                          comparison.trend,
                        ),
                        color: AppColors.leaf,
                      ),
                      title: Text(
                        _ProgressionComparisonSheet._trendLabel(
                          comparison.trend,
                        ),
                      ),
                      subtitle: Text(
                        context.strings.formatDateTime(
                          comparison.generatedAt.toLocal(),
                        ),
                      ),
                      trailing: const Icon(LucideIcons.chevronRight, size: 18),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        showDragHandle: true,
                        builder: (_) => _ProgressionComparisonSheet(
                          caseId: diagnosis.id,
                          comparison: comparison,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.go(
                        '/scan?retake=${Uri.encodeQueryComponent(diagnosis.id)}',
                      ),
                      icon: const Icon(LucideIcons.camera, size: 18),
                      label: Text(context.tr('takePhoto')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _showFeedbackSheet(context, diagnosis),
                      icon: const Icon(LucideIcons.messageSquareMore, size: 18),
                      label: Text(context.tr('giveFeedback')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => existingChat == null
                      ? context.push(
                          Uri(
                            path: '/saathi/new',
                            queryParameters: {
                              'scope': 'scan',
                              'context': diagnosis.id,
                              'prompt': 'Explain this leaf-check result and what I should observe next.',
                            },
                          ).toString(),
                        )
                      : context.push('/saathi/chat/${existingChat.id}'),
                  icon: const Icon(LucideIcons.messagesSquare, size: 18),
                  label: Text(
                    existingChat == null
                        ? 'Ask Saathi about this result'
                        : 'Continue linked Saathi conversation',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFeedbackSheet(BuildContext context, DiagnosisCaseModel diagnosis) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DiagnosisFeedbackSheet(diagnosis: diagnosis),
    );
  }

  Future<void> _compareProgression(
    BuildContext context,
    DiagnosisCaseModel diagnosis,
  ) async {
    setState(() => _comparing = true);
    try {
      final comparison = await context
          .read<AppController>()
          .compareDiagnosisProgression(
            diagnosis.id,
            responseLanguage: Localizations.localeOf(context).languageCode,
          );
      if (!context.mounted) return;
      setState(() {
        _comparisonHistory = [
          comparison,
          ..._comparisonHistory.where((item) => item.id != comparison.id),
        ];
      });
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _ProgressionComparisonSheet(
          caseId: diagnosis.id,
          comparison: comparison,
        ),
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  void _showReportSheet(BuildContext context, DiagnosisCaseModel diagnosis) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ReportApprovalSheet(diagnosis: diagnosis),
    );
  }

  Future<void> _handleOption(
    BuildContext context,
    DiagnosisCaseModel diagnosis,
    String action,
  ) async {
    if (action == 'link') {
      await _showLinkSheet(context, diagnosis);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this leaf check?'),
        content: const Text(
          'Its images, diagnosis history, linked scan conversation, and saved scan context will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: diagnosis.isSample
                ? null
                : () => Navigator.pop(context, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    try {
      await context.read<AppController>().deleteDiagnosis(diagnosis.id);
      if (context.mounted) context.go('/scan');
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }

  Future<void> _showLinkSheet(
    BuildContext context,
    DiagnosisCaseModel diagnosis,
  ) async {
    final controller = context.read<AppController>();
    final plots = controller.farms.expand((farm) => farm.plots).toList();
    var plotId = diagnosis.plotId;
    var cropId = diagnosis.cropId;
    final result = await showModalBottomSheet<(String?, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedPlot = plotId == null
              ? null
              : plots.cast<PlotModel?>().firstWhere(
                  (plot) => plot?.id == plotId,
                  orElse: () => null,
                );
          final activeCrops =
              selectedPlot?.crops.where((crop) => crop.isActive).toList() ??
              const <CropModel>[];
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                4,
                24,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Link this leaf check',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose the field record that should contain this result. Leave it standalone when you are unsure.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppColors.mutedInk),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String?>(
                    initialValue: plotId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Plot'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Keep as standalone scan'),
                      ),
                      ...plots.map(
                        (plot) => DropdownMenuItem(
                          value: plot.id,
                          child: Text(plot.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setSheetState(() {
                      plotId = value;
                      cropId = null;
                    }),
                  ),
                  if (selectedPlot != null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: activeCrops.any((crop) => crop.id == cropId)
                          ? cropId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Crop in this plot (optional)',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Not sure yet'),
                        ),
                        ...activeCrops.map(
                          (crop) => DropdownMenuItem(
                            value: crop.id,
                            child: Text('${crop.name} · ${crop.stage}'),
                          ),
                        ),
                      ],
                      onChanged: (value) => setSheetState(() => cropId = value),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, (plotId, cropId)),
                    child: Text(context.tr('save')),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await controller.linkDiagnosis(
        diagnosis: diagnosis,
        plotId: result.$1,
        cropId: result.$2,
      );
      if (context.mounted) {
        showAppSnackBar(context, 'Leaf check link updated.', success: true);
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }
}

class _ProgressionComparisonSheet extends StatelessWidget {
  const _ProgressionComparisonSheet({
    required this.caseId,
    required this.comparison,
  });

  final String caseId;
  final ProgressionComparisonModel comparison;

  @override
  Widget build(BuildContext context) {
    final trendColor = switch (comparison.trend) {
      'improving' => AppColors.leaf,
      'worsening' => AppColors.amber,
      _ => AppColors.sky,
    };
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            'Visible leaf change',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'This compares the two photo groups. It does not replace or change the trained leaf-model diagnosis.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.mutedInk),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack =
                  constraints.maxWidth < 500 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final earlier = _ProgressionTimepoint(
                label: 'Earlier',
                capturedAt: comparison.earlierCapturedAt,
                caseId: caseId,
                imageIds: comparison.earlierImageIds,
              );
              final later = _ProgressionTimepoint(
                label: 'Recent',
                capturedAt: comparison.laterCapturedAt,
                caseId: caseId,
                imageIds: comparison.laterImageIds,
              );
              if (stack) {
                return Column(
                  children: [earlier, const SizedBox(height: 12), later],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: earlier),
                  const SizedBox(width: 12),
                  Expanded(child: later),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(color: trendColor.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_trendIcon(comparison.trend), color: trendColor),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _trendLabel(comparison.trend),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text('${(comparison.confidence * 100).round()}%'),
                  ],
                ),
              ],
            ),
          ),
          if (comparison.evidence.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeader(title: 'Visible evidence'),
            const SizedBox(height: 8),
            ...comparison.evidence.map(
              (code) => _ComparisonBullet(_progressionCodeLabel(code)),
            ),
          ],
          if (comparison.recommendations.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionHeader(title: 'What to observe next'),
            const SizedBox(height: 8),
            ...comparison.recommendations.map(
              (code) => _ComparisonBullet(_progressionCodeLabel(code)),
            ),
          ],
          if (comparison.limitations.isNotEmpty) ...[
            const SizedBox(height: 18),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Comparison limitations'),
              children: comparison.limitations
                  .map((code) => _ComparisonBullet(_progressionCodeLabel(code)))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _trendIcon(String trend) => switch (trend) {
    'improving' => LucideIcons.trendingUp,
    'worsening' => LucideIcons.trendingDown,
    'unchanged' => LucideIcons.moveRight,
    _ => LucideIcons.circleHelp,
  };

  static String _trendLabel(String trend) => switch (trend) {
    'improving' => 'Visible symptoms look reduced',
    'worsening' => 'Visible symptoms may be increasing',
    'unchanged' => 'No clear visible change',
    _ => 'Change is unclear',
  };

  static String _progressionCodeLabel(String code) => switch (code) {
    'affected_area_reduced' => 'The visibly affected area appears smaller.',
    'affected_area_increased' => 'The visibly affected area appears larger.',
    'affected_area_similar' => 'The visibly affected area appears similar.',
    'yellowing_reduced' => 'Visible yellowing appears reduced.',
    'yellowing_increased' => 'Visible yellowing appears increased.',
    'browning_reduced' => 'Visible browning appears reduced.',
    'browning_increased' => 'Visible browning appears increased.',
    'curling_reduced' => 'Visible leaf curling appears reduced.',
    'curling_increased' => 'Visible leaf curling appears increased.',
    'wilting_reduced' => 'Visible wilting appears reduced.',
    'wilting_increased' => 'Visible wilting appears increased.',
    'no_reliable_visible_difference' =>
      'No reliable visible difference was found.',
    'different_lighting' => 'Lighting differs between the photo groups.',
    'different_viewpoint' => 'The viewing angle differs.',
    'different_zoom' => 'The photo distance or zoom differs.',
    'different_leaf' => 'The photos may show different leaves.',
    'different_background' => 'The background differs.',
    'earlier_image_quality' => 'The earlier photo quality limits comparison.',
    'later_image_quality' => 'The recent photo quality limits comparison.',
    'too_little_visible_evidence' =>
      'There is too little visible evidence to compare.',
    'monitor_same_leaf' => 'Keep monitoring the same leaf when possible.',
    'retake_same_angle' => 'Retake from the same angle.',
    'retake_same_lighting' => 'Retake in similar daylight.',
    'retake_full_plant_and_close_leaf' =>
      'Take one full-plant and one close leaf photo.',
    'keep_foliage_dry' => 'Keep foliage dry while monitoring.',
    'use_clean_hands_and_tools' =>
      'Use clean hands and tools around affected leaves.',
    'consult_local_expert_if_worsening' =>
      'Consult a local expert if visible symptoms continue to increase.',
    _ => code.replaceAll('_', ' '),
  };
}

class _ProgressionTimepoint extends StatelessWidget {
  const _ProgressionTimepoint({
    required this.label,
    required this.capturedAt,
    required this.caseId,
    required this.imageIds,
  });

  final String label;
  final DateTime capturedAt;
  final String caseId;
  final List<String> imageIds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageIds.isEmpty)
          const AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: AppColors.divider,
              child: Icon(LucideIcons.imageOff),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: imageIds.length == 1 ? 1 : 2,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 4 / 3,
            ),
            itemCount: imageIds.length,
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: _DiagnosisServerImage(
                caseId: caseId,
                imageId: imageIds[index],
              ),
            ),
          ),
        const SizedBox(height: 7),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        Text(
          context.strings.formatDateTime(capturedAt.toLocal()),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.mutedInk),
        ),
      ],
    );
  }
}

class _ComparisonBullet extends StatelessWidget {
  const _ComparisonBullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(LucideIcons.dot, size: 14, color: AppColors.leaf),
        ),
        const SizedBox(width: 5),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ActionStep extends StatelessWidget {
  const _ActionStep({
    required this.number,
    required this.title,
    required this.body,
  });
  final String number;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.forest,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedInk),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReportApprovalSheet extends StatefulWidget {
  const _ReportApprovalSheet({required this.diagnosis});
  final DiagnosisCaseModel diagnosis;

  @override
  State<_ReportApprovalSheet> createState() => _ReportApprovalSheetState();
}

class _ReportApprovalSheetState extends State<_ReportApprovalSheet> {
  bool includeImage = true;
  bool includePlot = false;
  bool includePlotLocation = false;
  bool includeFeedback = false;
  bool includeAlternatives = true;
  bool _creating = false;

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final report = await context.read<AppController>().createDiagnosisReport(
        diagnosis: widget.diagnosis,
        includeImage: includeImage,
        includeAlternatives: includeAlternatives,
        includeFeedback: includeFeedback,
        includePlotName: includePlot,
        includePlotLocation: includePlot && includePlotLocation,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      if (!mounted) return;
      Navigator.pop(context);
      await SharePlus.instance.share(
        ShareParams(
          subject: 'KrishiSathi leaf report',
          text:
              'KrishiSathi leaf report\n'
              'Report ID: ${report.id}\n'
              'Private access code: ${report.token}\n'
              '${context.tr('date.expires', {'date': context.strings.formatDateTime(report.expiresAt.toLocal())})}\n\n'
              'Share this only with the person you want to review the report.',
        ),
      );
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('createReport'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose exactly what the temporary report may reveal. Reports can be revoked at any time.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.mutedInk),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Selected leaf image'),
              value: includeImage,
              onChanged: (value) => setState(() => includeImage = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Plot name'),
              value: includePlot,
              onChanged: (value) => setState(() {
                includePlot = value;
                if (!value) includePlotLocation = false;
              }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Plot location'),
              subtitle: const Text('Share only when the reviewer needs it.'),
              value: includePlotLocation,
              onChanged: includePlot
                  ? (value) => setState(() => includePlotLocation = value)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Other possible diagnoses'),
              value: includeAlternatives,
              onChanged: (value) => setState(() => includeAlternatives = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Your feedback'),
              value: includeFeedback,
              onChanged: (value) => setState(() => includeFeedback = value),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.diagnosis.isSample || _creating
                    ? null
                    : _create,
                icon: const Icon(LucideIcons.link, size: 18),
                label: Text(
                  widget.diagnosis.isSample
                      ? 'Unavailable for sample results'
                      : _creating
                      ? 'Creating private report...'
                      : context.tr('createReport'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosisFeedbackSheet extends StatefulWidget {
  const _DiagnosisFeedbackSheet({required this.diagnosis});

  final DiagnosisCaseModel diagnosis;

  @override
  State<_DiagnosisFeedbackSheet> createState() =>
      _DiagnosisFeedbackSheetState();
}

class _DiagnosisFeedbackSheetState extends State<_DiagnosisFeedbackSheet> {
  final _crop = TextEditingController();
  final _disease = TextEditingController();
  final _notes = TextEditingController();
  bool _isIncorrect = false;
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final feedback = await context
          .read<AppController>()
          .loadDiagnosisFeedback(widget.diagnosis.id);
      if (feedback != null && mounted) {
        setState(() {
          _isIncorrect = feedback.isIncorrect;
          _crop.text = feedback.correctedCrop ?? '';
          _disease.text = feedback.correctedDisease ?? '';
          _notes.text = feedback.notes ?? '';
        });
      }
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _crop.dispose();
    _disease.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppController>().saveDiagnosisFeedback(
        caseId: widget.diagnosis.id,
        isIncorrect: _isIncorrect,
        correctedCrop: _isIncorrect ? _crop.text : null,
        correctedDisease: _isIncorrect ? _disease.text : null,
        notes: _notes.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      showAppSnackBar(context, 'Feedback saved.', success: true);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('giveFeedback'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Your correction helps improve future leaf checks. It never changes another farmer\'s result automatically.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.mutedInk),
            ),
            const SizedBox(height: 18),
            if (_loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Looks correct')),
                ButtonSegment(value: true, label: Text('Needs correction')),
              ],
              selected: {_isIncorrect},
              onSelectionChanged: (value) =>
                  setState(() => _isIncorrect = value.first),
            ),
            if (_isIncorrect) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _crop,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Correct crop or plant (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _disease,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Correct condition (optional)',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What did you observe? (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving || _loading ? null : _save,
                child: Text(_saving ? 'Saving...' : 'Save feedback'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosisImage extends StatelessWidget {
  const _DiagnosisImage({required this.diagnosis, this.width, this.height});

  final DiagnosisCaseModel diagnosis;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final localPath = diagnosis.imagePath;
    if (localPath != null && File(localPath).existsSync()) {
      return Image.file(
        File(localPath),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    if (!diagnosis.isSample && diagnosis.imageIds.isNotEmpty) {
      return FutureBuilder<List<int>>(
        future: context.read<AppController>().loadDiagnosisImage(
          diagnosis.id,
          diagnosis.imageIds.first,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              Uint8List.fromList(snapshot.data!),
              width: width,
              height: height,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _fallback(),
            );
          }
          if (snapshot.hasError) return _fallback();
          return SizedBox(
            width: width,
            height: height,
            child: const ColoredBox(
              color: AppColors.mineral,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        },
      );
    }
    return _fallback();
  }

  Widget _fallback() => Image.asset(
    diagnosis.imageAsset,
    width: width,
    height: height,
    fit: BoxFit.cover,
  );
}

class _DiagnosisServerImage extends StatelessWidget {
  const _DiagnosisServerImage({required this.caseId, required this.imageId});

  final String caseId;
  final String imageId;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<int>>(
    future: context.read<AppController>().loadDiagnosisImage(caseId, imageId),
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return Image.memory(
          Uint8List.fromList(snapshot.data!),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          semanticLabel: 'Leaf image in this diagnosis case',
        );
      }
      if (snapshot.hasError) {
        return const ColoredBox(
          color: AppColors.divider,
          child: Icon(LucideIcons.imageOff),
        );
      }
      return const ColoredBox(
        color: AppColors.mineral,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    },
  );
}

String _confidenceText(String value) => switch (value.toLowerCase()) {
  'high' => 'High confidence',
  'medium' => 'Medium confidence',
  _ => 'Low confidence',
};

Color _confidenceColor(String value) => switch (value.toLowerCase()) {
  'high' => AppColors.leaf,
  'medium' => AppColors.amber,
  _ => AppColors.danger,
};

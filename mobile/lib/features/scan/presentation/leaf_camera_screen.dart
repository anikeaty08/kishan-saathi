import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';

class LeafCameraScreen extends StatefulWidget {
  const LeafCameraScreen({super.key});

  @override
  State<LeafCameraScreen> createState() => _LeafCameraScreenState();
}

class _LeafCameraScreenState extends State<LeafCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  late final AnimationController _scanController;
  bool _initializing = true;
  bool _capturing = false;
  bool _torchEnabled = false;
  String? _errorMessage;
  int _cameraIndex = 0;
  int _initializationEpoch = 0;
  bool _appIsActive = true;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    unawaited(_initializeCameras());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _scanController
        ..stop()
        ..value = 0.5;
    } else {
      _scanController.repeat(reverse: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _appIsActive = false;
      _initializationEpoch += 1;
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed &&
        _cameraController == null &&
        _cameras.isNotEmpty) {
      _appIsActive = true;
      unawaited(_initializeController(_cameras[_cameraIndex]));
    }
  }

  Future<void> _initializeCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _errorMessage = 'No camera was found on this device.';
        });
        return;
      }
      _cameras = cameras;
      final backIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = backIndex < 0 ? 0 : backIndex;
      if (!_appIsActive) return;
      await _initializeController(cameras[_cameraIndex]);
    } on CameraException catch (error) {
      _showCameraError(error);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorMessage = 'The camera could not be opened. Please try again.';
      });
    }
  }

  Future<void> _initializeController(CameraDescription description) async {
    final epoch = ++_initializationEpoch;
    if (mounted) {
      setState(() {
        _initializing = true;
        _errorMessage = null;
      });
    }
    final previous = _cameraController;
    _cameraController = null;
    await previous?.dispose();

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      if (!mounted || !_appIsActive || epoch != _initializationEpoch) {
        await controller.dispose();
        return;
      }
      _cameraController = controller;
      setState(() => _initializing = false);
    } on CameraException catch (error) {
      await controller.dispose();
      _showCameraError(error);
    }
  }

  void _showCameraError(CameraException error) {
    if (!mounted) return;
    final denied =
        error.code.toLowerCase().contains('access') ||
        error.code.toLowerCase().contains('permission');
    setState(() {
      _initializing = false;
      _errorMessage = denied
          ? 'Allow camera access in phone settings to photograph a leaf.'
          : 'The camera could not be opened. Please try again.';
    });
  }

  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    await controller?.dispose();
  }

  Future<void> _capture() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final image = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(image);
    } on CameraException catch (error) {
      _showCameraError(error);
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null) return;
    final next = !_torchEnabled;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchEnabled = next);
    } on CameraException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torch is unavailable on this camera.')),
      );
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _capturing) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _torchEnabled = false;
    await _initializeController(_cameras[_cameraIndex]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanController.dispose();
    unawaited(_cameraController?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    return Scaffold(
      backgroundColor: const Color(0xFF07110B),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              _CameraViewport(controller: controller)
            else
              const ColoredBox(color: Color(0xFF07110B)),
            if (controller != null && controller.value.isInitialized)
              AnimatedBuilder(
                animation: _scanController,
                builder: (context, _) => LeafScannerOverlay(
                  progress: _scanController.value,
                  reducedMotion: _reduceMotion ?? false,
                ),
              ),
            _CameraChrome(
              initializing: _initializing,
              capturing: _capturing,
              errorMessage: _errorMessage,
              torchEnabled: _torchEnabled,
              canSwitch: _cameras.length > 1,
              onClose: () => Navigator.of(context).pop(),
              onRetry: _initializeCameras,
              onTorch: _toggleTorch,
              onSwitch: _switchCamera,
              onCapture: _capture,
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraViewport extends StatelessWidget {
  const _CameraViewport({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class LeafScannerOverlay extends StatelessWidget {
  const LeafScannerOverlay({
    super.key,
    required this.progress,
    required this.reducedMotion,
  });

  final double progress;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final pulse = reducedMotion
        ? 0.82
        : 0.7 + (math.sin(progress * math.pi) * 0.3);
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('live-leaf-scanner-overlay'),
        painter: _LeafScannerPainter(progress: progress, pulse: pulse),
      ),
    );
  }
}

class _LeafScannerPainter extends CustomPainter {
  const _LeafScannerPainter({required this.progress, required this.pulse});

  final double progress;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalMargin = math.max(28.0, size.width * 0.075);
    final top = size.height * 0.18;
    final bottom = size.height * 0.72;
    final frame = Rect.fromLTRB(
      horizontalMargin,
      top,
      size.width - horizontalMargin,
      bottom,
    );
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.28);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(26)));
    canvas.drawPath(path, shade);

    final cornerPaint = Paint()
      ..color = const Color(0xFFD9F09D).withValues(alpha: pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const corner = 38.0;
    final radius = const Radius.circular(18);
    final rounded = RRect.fromRectAndRadius(frame, radius);
    final cornerPath = Path()
      ..moveTo(rounded.left, rounded.top + corner)
      ..lineTo(rounded.left, rounded.top + radius.y)
      ..quadraticBezierTo(
        rounded.left,
        rounded.top,
        rounded.left + radius.x,
        rounded.top,
      )
      ..lineTo(rounded.left + corner, rounded.top)
      ..moveTo(rounded.right - corner, rounded.top)
      ..lineTo(rounded.right - radius.x, rounded.top)
      ..quadraticBezierTo(
        rounded.right,
        rounded.top,
        rounded.right,
        rounded.top + radius.y,
      )
      ..lineTo(rounded.right, rounded.top + corner)
      ..moveTo(rounded.left, rounded.bottom - corner)
      ..lineTo(rounded.left, rounded.bottom - radius.y)
      ..quadraticBezierTo(
        rounded.left,
        rounded.bottom,
        rounded.left + radius.x,
        rounded.bottom,
      )
      ..lineTo(rounded.left + corner, rounded.bottom)
      ..moveTo(rounded.right - corner, rounded.bottom)
      ..lineTo(rounded.right - radius.x, rounded.bottom)
      ..quadraticBezierTo(
        rounded.right,
        rounded.bottom,
        rounded.right,
        rounded.bottom - radius.y,
      )
      ..lineTo(rounded.right, rounded.bottom - corner);
    canvas.drawPath(cornerPath, cornerPaint);

    final lineY = frame.top + 22 + ((frame.height - 44) * progress);
    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x00D9F09D), Color(0xFFD9F09D), Color(0x00D9F09D)],
      ).createShader(Rect.fromLTWH(frame.left, lineY - 2, frame.width, 4))
      ..strokeWidth = 2.2;
    canvas.drawLine(
      Offset(frame.left + 18, lineY),
      Offset(frame.right - 18, lineY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_LeafScannerPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.pulse != pulse;
}

class _CameraChrome extends StatelessWidget {
  const _CameraChrome({
    required this.initializing,
    required this.capturing,
    required this.errorMessage,
    required this.torchEnabled,
    required this.canSwitch,
    required this.onClose,
    required this.onRetry,
    required this.onTorch,
    required this.onSwitch,
    required this.onCapture,
  });

  final bool initializing;
  final bool capturing;
  final String? errorMessage;
  final bool torchEnabled;
  final bool canSwitch;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final VoidCallback onTorch;
  final VoidCallback onSwitch;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Row(
            children: [
              _CameraIconButton(
                tooltip: 'Close camera',
                onPressed: onClose,
                icon: LucideIcons.x,
              ),
              const Spacer(),
              _CameraIconButton(
                tooltip: torchEnabled ? 'Turn torch off' : 'Turn torch on',
                onPressed: errorMessage == null ? onTorch : null,
                icon: torchEnabled ? LucideIcons.zap : LucideIcons.zapOff,
              ),
              if (canSwitch) ...[
                const SizedBox(width: 8),
                _CameraIconButton(
                  tooltip: 'Switch camera',
                  onPressed: errorMessage == null ? onSwitch : null,
                  icon: LucideIcons.switchCamera,
                ),
              ],
            ],
          ),
        ),
        const Spacer(),
        if (errorMessage != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xED13241A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(
                  LucideIcons.cameraOff,
                  color: Colors.white,
                  size: 30,
                ),
                const SizedBox(height: 10),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, height: 1.4),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ),
          )
        else if (initializing)
          const CircularProgressIndicator(color: Color(0xFFD9F09D))
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              'Place one leaf inside the corners. Keep it sharp and well lit.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.35,
                shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
              ),
            ),
          ),
        const SizedBox(height: 22),
        Semantics(
          button: true,
          label: 'Take leaf photo',
          child: GestureDetector(
            onTap: !initializing && errorMessage == null && !capturing
                ? onCapture
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                color: Colors.black12,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: capturing ? Colors.white54 : const Color(0xFFF6F1E5),
                ),
                child: capturing
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.forest,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

class _CameraIconButton extends StatelessWidget {
  const _CameraIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.38),
      ),
      icon: Icon(icon, size: 21),
    );
  }
}

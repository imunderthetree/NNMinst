import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'link_launcher.dart';

void main() {
  runApp(const NnminstApp());
}

class NnminstApp extends StatefulWidget {
  const NnminstApp({super.key, this.loadModel = true});

  final bool loadModel;

  @override
  State<NnminstApp> createState() => _NnminstAppState();
}

class _NnminstAppState extends State<NnminstApp> {
  bool _useDarkMode = false;

  ThemeData _buildTheme(ColorScheme colorScheme, {required bool isDark}) {
    final scaffoldColor =
        isDark ? const Color(0xFF0F1514) : const Color(0xFFF5F7F6);
    final cardColor = isDark ? const Color(0xFF151B1A) : Colors.white;
    final outlineColor =
        isDark ? const Color(0xFF22302D) : const Color(0xFFE1E8E5);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffoldColor,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scaffoldColor,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: outlineColor,
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: outlineColor),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );
    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NNMINST',
      theme: _buildTheme(colorScheme, isDark: false),
      darkTheme: _buildTheme(darkColorScheme, isDark: true),
      themeMode: _useDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: DigitHomePage(
        loadModel: widget.loadModel,
        isDarkMode: _useDarkMode,
        onThemeModeChanged: (value) {
          setState(() {
            _useDarkMode = value;
          });
        },
      ),
    );
  }
}

enum InputMode { photo, draw }

class DigitHomePage extends StatefulWidget {
  const DigitHomePage({
    required this.loadModel,
    required this.isDarkMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final bool loadModel;
  final bool isDarkMode;
  final ValueChanged<bool> onThemeModeChanged;

  @override
  State<DigitHomePage> createState() => _DigitHomePageState();
}

class _DigitHomePageState extends State<DigitHomePage> {
  final _classifier = DigitClassifier();
  final _imagePicker = ImagePicker();
  final _drawingKey = GlobalKey();
  final List<Stroke> _strokes = [];

  DetectionResult? _detectionResult;
  Uint8List? _pickedImageBytes;
  InputMode _inputMode = InputMode.photo;
  InputMode? _resultMode;
  bool _isModelLoading = true;
  bool _isModelReady = false;
  bool _isBusy = false;
  bool _isDrawing = false;
  int _pageIndex = 0;
  String? _error;
  String? _lastSourceLabel;

  @override
  void initState() {
    super.initState();
    if (widget.loadModel) {
      _loadModel();
    } else {
      _isModelLoading = false;
    }
  }

  @override
  void dispose() {
    _classifier.close();
    super.dispose();
  }

  Future<void> _loadModel() async {
    try {
      await _classifier.load();
      if (!mounted) return;
      setState(() {
        _isModelLoading = false;
        _isModelReady = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isModelLoading = false;
        _isModelReady = false;
        _error = 'Model failed to load: $error';
      });
    }
  }

  Future<void> _pickAndClassify(ImageSource source) async {
    if (!_canPredict) return;

    setState(() {
      _isBusy = true;
      _error = null;
      _inputMode = InputMode.photo;
      _isDrawing = false;
    });

    try {
      final imageFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 1800,
        maxHeight: 1800,
      );

      if (imageFile == null) {
        if (!mounted) return;
        setState(() {
          _isBusy = false;
        });
        return;
      }

      final imageResult = await _classifier.detectImageBytes(
        await imageFile.readAsBytes(),
        invert: false,
        preferPaperCrop: source == ImageSource.camera,
      );

      if (!mounted) return;
      setState(() {
        _pickedImageBytes = imageResult.displayBytes;
        _detectionResult = imageResult.result;
        _resultMode = InputMode.photo;
        _lastSourceLabel = source == ImageSource.camera ? 'Camera' : 'Gallery';
        _isBusy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Image prediction failed: $error';
        _isBusy = false;
      });
    }
  }

  void _startStroke(Offset point) {
    setState(() {
      _inputMode = InputMode.draw;
      _isDrawing = true;
      _strokes.add(Stroke(points: [point]));
      _detectionResult = null;
      _resultMode = null;
      _error = null;
    });
  }

  void _appendStrokePoint(Offset point) {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.last.points.add(point);
    });
  }

  void _endStroke(DragEndDetails details) {
    if (!_isDrawing) return;
    setState(() {
      _isDrawing = false;
    });
  }

  void _cancelStroke() {
    if (!_isDrawing) return;
    setState(() {
      _isDrawing = false;
    });
  }

  void _clearDrawing() {
    setState(() {
      _strokes.clear();
      _detectionResult = null;
      _resultMode = null;
      _error = null;
      _isDrawing = false;
    });
  }

  void _clearSession() {
    setState(() {
      _strokes.clear();
      _pickedImageBytes = null;
      _detectionResult = null;
      _resultMode = null;
      _lastSourceLabel = null;
      _error = null;
      _isDrawing = false;
    });
  }

  void _classifyDrawing() async {
    if (!_canPredict || _strokes.isEmpty) return;

    final renderBox =
        _drawingKey.currentContext?.findRenderObject() as RenderBox?;
    final canvasSize = renderBox?.size ?? const Size(320, 320);

    setState(() {
      _isBusy = true;
      _error = null;
      _inputMode = InputMode.draw;
      _isDrawing = false;
    });

    try {
      final result = await _classifier.detectStrokes(_strokes, canvasSize);
      setState(() {
        _detectionResult = result;
        _resultMode = InputMode.draw;
        _isBusy = false;
      });
    } catch (error) {
      setState(() {
        _error = 'Drawing prediction failed: $error';
        _isBusy = false;
      });
    }
  }

  bool get _canPredict => _isModelReady && !_isModelLoading && !_isBusy;

  String get _pageTitle {
    return switch (_pageIndex) {
      0 => 'NNMINST',
      1 => 'Settings',
      _ => 'About',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 420;
    final pages = [
      PredictView(
        detectionResult: _detectionResult,
        imageBytes: _pickedImageBytes,
        inputMode: _inputMode,
        resultMode: _resultMode,
        strokes: _strokes,
        drawingKey: _drawingKey,
        isModelLoading: _isModelLoading,
        isModelReady: _isModelReady,
        isBusy: _isBusy,
        error: _error,
        lastSourceLabel: _lastSourceLabel,
        onInputModeChanged: (mode) {
          setState(() {
            _inputMode = mode;
            _error = null;
            _isDrawing = false;
          });
        },
        onCamera: () => _pickAndClassify(ImageSource.camera),
        onGallery: () => _pickAndClassify(ImageSource.gallery),
        onPanDown: _startStroke,
        onPanUpdate: _appendStrokePoint,
        onPanEnd: _endStroke,
        onPanCancel: _cancelStroke,
        onClearDrawing: _clearDrawing,
        onPredictDrawing: _classifyDrawing,
        isDrawingActive: _isDrawing && _inputMode == InputMode.draw,
      ),
      SettingsView(
        isDarkMode: widget.isDarkMode,
        isModelLoading: _isModelLoading,
        isModelReady: _isModelReady,
        onThemeModeChanged: widget.onThemeModeChanged,
        onClearSession: _clearSession,
      ),
      const AboutView(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const AppMark(size: 34),
            const SizedBox(width: 10),
            Text(_pageTitle),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: _clearSession,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: IndexedStack(index: _pageIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex,
        labelBehavior:
            isCompact
                ? NavigationDestinationLabelBehavior.onlyShowSelected
                : NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          setState(() {
            _pageIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.center_focus_strong_outlined),
            selectedIcon: Icon(Icons.center_focus_strong),
            label: 'Predict',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'About',
          ),
        ],
      ),
    );
  }
}

class PredictView extends StatelessWidget {
  const PredictView({
    required this.detectionResult,
    required this.imageBytes,
    required this.inputMode,
    required this.resultMode,
    required this.strokes,
    required this.drawingKey,
    required this.isModelLoading,
    required this.isModelReady,
    required this.isBusy,
    required this.error,
    required this.lastSourceLabel,
    required this.onInputModeChanged,
    required this.onCamera,
    required this.onGallery,
    required this.onPanDown,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
    required this.onClearDrawing,
    required this.onPredictDrawing,
    required this.isDrawingActive,
    super.key,
  });

  final DetectionResult? detectionResult;
  final Uint8List? imageBytes;
  final InputMode inputMode;
  final InputMode? resultMode;
  final List<Stroke> strokes;
  final GlobalKey drawingKey;
  final bool isModelLoading;
  final bool isModelReady;
  final bool isBusy;
  final String? error;
  final String? lastSourceLabel;
  final ValueChanged<InputMode> onInputModeChanged;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ValueChanged<Offset> onPanDown;
  final ValueChanged<Offset> onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final VoidCallback onPanCancel;
  final VoidCallback onClearDrawing;
  final VoidCallback onPredictDrawing;
  final bool isDrawingActive;

  @override
  Widget build(BuildContext context) {
    final sidePadding = responsiveSidePadding(context);
    final canPredict = isModelReady && !isModelLoading && !isBusy;
    final disableScroll = inputMode == InputMode.draw && isDrawingActive;

    return SafeArea(
      child: ListView(
        physics: disableScroll ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 24),
        children: [
          ResultCard(
            detectionResult: detectionResult,
            isModelLoading: isModelLoading,
            isModelReady: isModelReady,
            isBusy: isBusy,
            error: error,
          ),
          const SizedBox(height: 12),
          InputModeCard(inputMode: inputMode, onChanged: onInputModeChanged),
          const SizedBox(height: 12),
          if (inputMode == InputMode.photo)
            PhotoInputCard(
              imageBytes: imageBytes,
              detectionResult:
                  resultMode == InputMode.photo ? detectionResult : null,
              lastSourceLabel: lastSourceLabel,
              canPredict: canPredict,
              isBusy: isBusy,
              onCamera: onCamera,
              onGallery: onGallery,
            )
          else
            DrawingInputCard(
              drawingKey: drawingKey,
              strokes: strokes,
              detectionResult:
                  resultMode == InputMode.draw ? detectionResult : null,
              canPredict: canPredict && strokes.isNotEmpty,
              onPanDown: onPanDown,
              onPanUpdate: onPanUpdate,
              onPanEnd: onPanEnd,
              onPanCancel: onPanCancel,
              onClear: onClearDrawing,
              onPredict: onPredictDrawing,
            ),
        ],
      ),
    );
  }
}

class ResultCard extends StatelessWidget {
  const ResultCard({
    required this.detectionResult,
    required this.isModelLoading,
    required this.isModelReady,
    required this.isBusy,
    required this.error,
    super.key,
  });

  final DetectionResult? detectionResult;
  final bool isModelLoading;
  final bool isModelReady;
  final bool isBusy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = _statusText;
    final primaryPrediction = detectionResult?.primaryPrediction;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DigitResultBadge(text: detectionResult?.badgeText),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detectionResult == null
                            ? 'On-device digit recognition'
                            : '${detectionResult!.detections.length} detected digit${detectionResult!.detections.length == 1 ? '' : 's'}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isModelLoading || isBusy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(minHeight: 6),
            ],
            if (error != null) ...[
              const SizedBox(height: 14),
              ErrorStrip(message: error!),
            ],
            if (detectionResult != null) ...[
              const SizedBox(height: 16),
              DetectionOutputBox(result: detectionResult!),
              if (primaryPrediction != null) ...[
                const SizedBox(height: 14),
                TopGuessRow(prediction: primaryPrediction),
                const SizedBox(height: 14),
                ProbabilityBars(probabilities: primaryPrediction.probabilities),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String get _statusText {
    if (isModelLoading) return 'Loading model';
    if (isBusy) return 'Running prediction';
    if (!isModelReady) return 'Model unavailable';
    if (detectionResult == null) return 'Ready to detect';
    if (detectionResult!.detections.isEmpty) return 'No digits found';
    return 'Detected ${detectionResult!.sequence}';
  }
}

class DigitResultBadge extends StatelessWidget {
  const DigitResultBadge({required this.text, super.key});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final label = text ?? '-';
    final colorScheme = Theme.of(context).colorScheme;
    final badgeColor = colorScheme.primary;

    return Container(
      width: 86,
      height: 86,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class DetectionOutputBox extends StatelessWidget {
  const DetectionOutputBox({required this.result, super.key});

  final DetectionResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sequence = result.sequence.isEmpty ? '-' : result.sequence;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Output',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sequence,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          if (result.detections.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < result.detections.length; i++)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${i + 1}: ${result.detections[i].prediction.digit}  '
                      '${(result.detections[i].prediction.confidence * 100).toStringAsFixed(0)}%',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class TopGuessRow extends StatelessWidget {
  const TopGuessRow({required this.prediction, super.key});

  final Prediction prediction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final guesses = prediction.topGuesses.take(3).toList(growable: false);

    return Row(
      children: [
        for (final guess in guesses) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  Text(
                    '${guess.digit}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(guess.score * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (guess != guesses.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class ProbabilityBars extends StatelessWidget {
  const ProbabilityBars({required this.probabilities, super.key});

  final List<double> probabilities;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (var digit = 0; digit < probabilities.length; digit++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '$digit',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 9,
                      value: probabilities[digit].clamp(0.0, 1.0),
                      color: colorScheme.primary,
                      backgroundColor: colorScheme.surfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(probabilities[digit] * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class InputModeCard extends StatelessWidget {
  const InputModeCard({
    required this.inputMode,
    required this.onChanged,
    super.key,
  });

  final InputMode inputMode;
  final ValueChanged<InputMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 420;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<InputMode>(
          segments: const [
            ButtonSegment(
              value: InputMode.photo,
              icon: Icon(Icons.photo_camera_outlined),
              label: Text('Image'),
            ),
            ButtonSegment(
              value: InputMode.draw,
              icon: Icon(Icons.draw_outlined),
              label: Text('Draw'),
            ),
          ],
          selected: {inputMode},
          showSelectedIcon: false,
          onSelectionChanged: (values) => onChanged(values.first),
        ),
      ),
    );
  }
}

class PhotoInputCard extends StatelessWidget {
  const PhotoInputCard({
    required this.imageBytes,
    required this.detectionResult,
    required this.lastSourceLabel,
    required this.canPredict,
    required this.isBusy,
    required this.onCamera,
    required this.onGallery,
    super.key,
  });

  final Uint8List? imageBytes;
  final DetectionResult? detectionResult;
  final String? lastSourceLabel;
  final bool canPredict;
  final bool isBusy;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 420;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SectionTitle(
                  icon: Icons.image_search_outlined,
                  title: 'Photo input',
                ),
                const Spacer(),
                if (lastSourceLabel != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(lastSourceLabel!),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child:
                    imageBytes == null
                        ? const EmptyInputState(
                          icon: Icons.add_photo_alternate_outlined,
                          label: 'No image selected',
                        )
                        : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(imageBytes!, fit: BoxFit.contain),
                            if (detectionResult != null)
                              CustomPaint(
                                painter: DetectionOverlayPainter(
                                  detectionResult!,
                                ),
                              ),
                          ],
                        ),
              ),
            ),
            const SizedBox(height: 14),
            if (isCompact)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: canPredict ? onGallery : null,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canPredict ? onCamera : null,
                      icon:
                          isBusy
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canPredict ? onGallery : null,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canPredict ? onCamera : null,
                      icon:
                          isBusy
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class DrawingInputCard extends StatelessWidget {
  const DrawingInputCard({
    required this.drawingKey,
    required this.strokes,
    required this.detectionResult,
    required this.canPredict,
    required this.onPanDown,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
    required this.onClear,
    required this.onPredict,
    super.key,
  });

  final GlobalKey drawingKey;
  final List<Stroke> strokes;
  final DetectionResult? detectionResult;
  final bool canPredict;
  final ValueChanged<Offset> onPanDown;
  final ValueChanged<Offset> onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final VoidCallback onPanCancel;
  final VoidCallback onClear;
  final VoidCallback onPredict;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 420;
    final colorScheme = Theme.of(context).colorScheme;
    final guideColor = colorScheme.outlineVariant;
    final strokeColor = colorScheme.onSurface;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              icon: Icons.draw_outlined,
              title: 'Drawing input',
            ),
            const SizedBox(height: 14),
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    key: drawingKey,
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (details) => onPanDown(details.localPosition),
                    onPanUpdate:
                        (details) => onPanUpdate(details.localPosition),
                    onPanEnd: onPanEnd,
                    onPanCancel: onPanCancel,
                    child: CustomPaint(
                      painter: DrawingPainter(
                        strokes,
                        detectionResult: detectionResult,
                        guideColor: guideColor,
                        strokeColor: strokeColor,
                      ),
                      child:
                          strokes.isEmpty
                              ? const EmptyInputState(
                                icon: Icons.gesture_outlined,
                                label: 'Draw a digit',
                              )
                              : const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (isCompact)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: strokes.isEmpty ? null : onClear,
                      icon: const Icon(Icons.backspace_outlined),
                      label: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canPredict ? onPredict : null,
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Predict'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: strokes.isEmpty ? null : onClear,
                      icon: const Icon(Icons.backspace_outlined),
                      label: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canPredict ? onPredict : null,
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Predict'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({
    required this.isDarkMode,
    required this.isModelLoading,
    required this.isModelReady,
    required this.onThemeModeChanged,
    required this.onClearSession,
    super.key,
  });

  final bool isDarkMode;
  final bool isModelLoading;
  final bool isModelReady;
  final ValueChanged<bool> onThemeModeChanged;
  final VoidCallback onClearSession;

  @override
  Widget build(BuildContext context) {
    final sidePadding = responsiveSidePadding(context);

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 24),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: isDarkMode,
                  onChanged: onThemeModeChanged,
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Dark mode'),
                  subtitle: const Text('Use the darker interface style.'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.memory_outlined),
                  title: const Text('Model status'),
                  subtitle: Text(_modelStatus),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                const ListTile(
                  leading: Icon(Icons.grid_on_outlined),
                  title: Text('Model input'),
                  subtitle: Text('64 x 64 grayscale digit image'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Made by imunderthetree (Yusuf Mohammad)'),
                  subtitle: Text('NNMINST bonus project build'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onClearSession,
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('Clear current session'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _modelStatus {
    if (isModelLoading) return 'Loading bundled TFLite model';
    if (isModelReady) return 'Loaded and ready';
    return 'Unavailable';
  }
}

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  Future<void> _handleLink(
    BuildContext context,
    String url, {
    bool newTab = false,
  }) async {
    final ok = await openExternalLink(url, newTab: newTab);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open $url')),
      );
    }
  }

  Widget _linkButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required String url,
    bool filled = false,
    bool newTab = false,
  }) {
    final onPressed = () => _handleLink(context, url, newTab: newTab);
    return filled
        ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        )
        : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
  }

  @override
  Widget build(BuildContext context) {
    final sidePadding = responsiveSidePadding(context);
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const AppMark(size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NNMINST',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Handwritten digit recognizer',
                          style: textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    icon: Icons.info_outline,
                    title: 'About the app',
                  ),
                  SizedBox(height: 12),
                  Text(
                    'NNMINST detects digit regions from a camera photo, gallery image, or drawing canvas, draws a box around each region, and runs the bundled TensorFlow Lite classifier on every crop. The output box shows the detected number sequence.',
                  ),
                  SizedBox(height: 14),
                  InfoStrip(
                    icon: Icons.offline_bolt_outlined,
                    message:
                        'Prediction runs locally after the APK is installed.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.code_outlined),
                  title: Text('Made by imunderthetree (Yusuf Mohammad)'),
                  subtitle: Text('Built with Flutter and TensorFlow Lite'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _linkButton(
                        context: context,
                        label: 'LinkedIn',
                        icon: Icons.work_outline,
                        url: 'https://linkedin.com/in/yusufmohammaddsai/',
                        filled: true,
                        newTab: true,
                      ),
                      _linkButton(
                        context: context,
                        label: 'GitHub',
                        icon: Icons.code_outlined,
                        url: 'https://github.com/imunderthetree',
                        newTab: true,
                      ),
                      _linkButton(
                        context: context,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        url: 'mailto:yusufalazhar7@gmail.com',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppMark extends StatelessWidget {
  const AppMark({required this.size, super.key});

  final double size;
  static const String _logoAsset = 'assets/logo.png';

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);

    return ClipRRect(
      borderRadius: radius,
      child: Image.asset(
        _logoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => _fallbackMark(radius),
      ),
    );
  }

  Widget _fallbackMark(BorderRadius radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF073B3A),
        borderRadius: radius,
      ),
      child: Center(
        child: Container(
          width: size * 0.56,
          height: size * 0.56,
          decoration: BoxDecoration(
            color: const Color(0xFFFFD166),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.numbers_outlined,
            color: const Color(0xFF073B3A),
            size: size * 0.38,
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.icon, required this.title, super.key});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class EmptyInputState extends StatelessWidget {
  const EmptyInputState({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 56,
            color: colorScheme.onSurfaceVariant.withOpacity(0.8),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class InfoStrip extends StatelessWidget {
  const InfoStrip({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surface = colorScheme.tertiaryContainer;
    final outline = colorScheme.tertiary;
    final contentColor = colorScheme.onTertiaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: outline),
      ),
      child: Row(
        children: [
          Icon(icon, color: outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: contentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ErrorStrip extends StatelessWidget {
  const ErrorStrip({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surface = colorScheme.errorContainer;
    final outline = colorScheme.error;
    final contentColor = colorScheme.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: contentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  DrawingPainter(
    this.strokes, {
    required this.detectionResult,
    required this.guideColor,
    required this.strokeColor,
  });

  final List<Stroke> strokes;
  final DetectionResult? detectionResult;
  final Color guideColor;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint =
        Paint()
          ..color = guideColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;

    final strokePaint =
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..strokeWidth = drawingStrokeWidth(size);

    final inset = size.shortestSide / 3;
    canvas.drawLine(Offset(inset, 0), Offset(inset, size.height), guidePaint);
    canvas.drawLine(
      Offset(inset * 2, 0),
      Offset(inset * 2, size.height),
      guidePaint,
    );
    canvas.drawLine(Offset(0, inset), Offset(size.width, inset), guidePaint);
    canvas.drawLine(
      Offset(0, inset * 2),
      Offset(size.width, inset * 2),
      guidePaint,
    );

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first,
          strokePaint.strokeWidth / 2,
          strokePaint,
        );
        continue;
      }

      final path = _buildSmoothPath(stroke.points);
      canvas.drawPath(path, strokePaint);
    }

    final result = detectionResult;
    if (result != null) {
      paintDetectionBoxes(
        canvas,
        Rect.fromLTWH(0, 0, size.width, size.height),
        result.detections,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    return true;
  }

  Path _buildSmoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
      return path;
    }

    for (var i = 1; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }

    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }
}

class DetectionOverlayPainter extends CustomPainter {
  DetectionOverlayPainter(this.result);

  final DetectionResult result;

  @override
  void paint(Canvas canvas, Size size) {
    final sourceSize = result.sourceSize;
    if (sourceSize.width <= 0 || sourceSize.height <= 0) return;

    final sourceAspect = sourceSize.width / sourceSize.height;
    final viewAspect = size.width / size.height;
    late final Rect contentRect;

    if (sourceAspect > viewAspect) {
      final height = size.width / sourceAspect;
      contentRect = Rect.fromLTWH(
        0,
        (size.height - height) / 2,
        size.width,
        height,
      );
    } else {
      final width = size.height * sourceAspect;
      contentRect = Rect.fromLTWH(
        (size.width - width) / 2,
        0,
        width,
        size.height,
      );
    }

    paintDetectionBoxes(canvas, contentRect, result.detections);
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.result != result;
  }
}

void paintDetectionBoxes(
  Canvas canvas,
  Rect contentRect,
  List<DetectedDigit> detections,
) {
  final boxPaint =
      Paint()
        ..color = const Color(0xFFFFD166)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
  final labelPaint =
      Paint()
        ..color = const Color(0xFF073B3A)
        ..style = PaintingStyle.fill;

  for (var i = 0; i < detections.length; i++) {
    final detection = detections[i];
    final rect = Rect.fromLTRB(
      contentRect.left + detection.box.left * contentRect.width,
      contentRect.top + detection.box.top * contentRect.height,
      contentRect.left + detection.box.right * contentRect.width,
      contentRect.top + detection.box.bottom * contentRect.height,
    );

    canvas.drawRect(rect, boxPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '${detection.prediction.digit}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelRect = Rect.fromLTWH(
      rect.left,
      math.max(contentRect.top, rect.top - textPainter.height - 6),
      textPainter.width + 12,
      textPainter.height + 6,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      labelPaint,
    );
    textPainter.paint(canvas, Offset(labelRect.left + 6, labelRect.top + 3));
  }
}

class DigitClassifier {
  static const imageSize = 64;
  Interpreter? _interpreter;

  Future<void> load() async {
    final interpreter = await Interpreter.fromAsset('assets/model.tflite');
    interpreter.allocateTensors();
    _interpreter = interpreter;
  }

  Future<ImageDetectionResult> detectImageBytes(
    Uint8List bytes, {
    required bool invert,
    bool preferPaperCrop = false,
  }) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Unsupported image format');
    }

    final oriented = img.bakeOrientation(decoded);
    final smoothed = img.gaussianBlur(oriented, radius: 1);
    final candidate = _detectBestPhotoCandidate(
      smoothed,
      invert: invert,
      preferPaperCrop: preferPaperCrop,
    );
    // Run inference on all non-blank crops first, collect raw results
    final rawDetections = <({DetectedDigit digit, double confidence})>[];
    for (final box in candidate.boxes) {
      if (_isBlankCrop(candidate.image, box, invert: invert)) continue;
      final prediction = _run(
        _imageBoxToTensor(candidate.image, box, invert: invert),
      );
      rawDetections.add((
        digit: DetectedDigit(
          box: box.toNormalizedRect(
            candidate.image.width,
            candidate.image.height,
          ),
          prediction: prediction,
        ),
        confidence: prediction.confidence,
      ));
    }

    // Dynamic threshold: reject anything below 60% of the best confidence.
    // This adapts to the photo's lighting/contrast — in a dark shadowy photo
    // the best score might be 0.65, so threshold becomes 0.39 (keeps real digits).
    // In a clean bright photo the best might be 0.98, threshold becomes 0.59.
    // Hard floor of 0.35 so we never accept clearly random outputs.
    final bestConfidence = rawDetections.isEmpty
        ? 0.0
        : rawDetections
            .map((e) => e.confidence)
            .reduce((a, b) => a > b ? a : b);
    final dynamicThreshold = math.max(0.35, bestConfidence * 0.60);

    final detections = rawDetections
        .where((e) => e.confidence >= dynamicThreshold)
        .map((e) => e.digit)
        .toList();

    return ImageDetectionResult(
      displayBytes: Uint8List.fromList(
        img.encodeJpg(candidate.image, quality: 95),
      ),
      result: DetectionResult(
        detections: detections,
        sourceSize: Size(
          candidate.image.width.toDouble(),
          candidate.image.height.toDouble(),
        ),
      ),
    );
  }

  Future<Prediction> predictImageBytes(
    Uint8List bytes, {
    required bool invert,
  }) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Unsupported image format');
    }

    final input = _imageToTensor(decoded, invert: invert);
    return _run(input);
  }

  Future<Prediction> predictStrokes(
    List<Stroke> strokes,
    Size canvasSize,
  ) async {
    final result = await detectStrokes(strokes, canvasSize);
    final primaryPrediction = result.primaryPrediction;
    if (primaryPrediction == null) {
      throw StateError('No digit strokes found');
    }
    return primaryPrediction;
  }

  Future<DetectionResult> detectStrokes(
    List<Stroke> strokes,
    Size canvasSize,
  ) async {
    final regions = _detectStrokeRegions(strokes, canvasSize);

    // Run inference on all regions first
    final rawDetections = <({DetectedDigit digit, double confidence})>[];
    for (final region in regions) {
      final prediction = _run(_strokeRegionToTensor(region));
      rawDetections.add((
        digit: DetectedDigit(
          box: region.box.toNormalizedRect(canvasSize),
          prediction: prediction,
        ),
        confidence: prediction.confidence,
      ));
    }

    // Same dynamic threshold as photo mode
    final bestConfidence = rawDetections.isEmpty
        ? 0.0
        : rawDetections
            .map((e) => e.confidence)
            .reduce((a, b) => a > b ? a : b);
    final dynamicThreshold = math.max(0.35, bestConfidence * 0.60);

    final detections = rawDetections
        .where((e) => e.confidence >= dynamicThreshold)
        .map((e) => e.digit)
        .toList();

    return DetectionResult(detections: detections, sourceSize: canvasSize);
  }

  void close() {
    _interpreter?.close();
  }

  // Returns true if the crop contains too little ink to be a real digit.
  // Binarizes a small downscaled version of the crop and checks ink pixel ratio.
  bool _isBlankCrop(img.Image source, PixelBox box, {required bool invert}) {
    final squareBox = box.expandedSquare(
      imageWidth: source.width,
      imageHeight: source.height,
      paddingFactor: 0.10,
    );
    final cropped = img.copyCrop(
      source,
      x: squareBox.left,
      y: squareBox.top,
      width: squareBox.width,
      height: squareBox.height,
    );
    // Downsample to 16x16 for a fast ink-ratio check
    final small = img.copyResize(cropped, width: 16, height: 16);
    final total = 16 * 16;
    final histogram = List<int>.filled(256, 0);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final p = small.getPixel(x, y);
        var lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b)
            .round()
            .clamp(0, 255)
            .toInt();
        if (invert) lum = 255 - lum;
        histogram[lum]++;
      }
    }
    final threshold = _otsuThreshold(histogram, total);
    var inkPixels = 0;
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final p = small.getPixel(x, y);
        var lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b)
            .round()
            .clamp(0, 255)
            .toInt();
        if (invert) lum = 255 - lum;
        if (lum < threshold) inkPixels++;
      }
    }
    final inkRatio = inkPixels / total;
    // Fewer than 3% ink pixels → almost certainly blank space or a line artifact
    return inkRatio < 0.03;
  }

  Prediction _run(List<List<List<List<double>>>> input) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('Interpreter is not loaded');
    }

    final output = List.generate(1, (_) => List<double>.filled(10, 0));
    interpreter.run(input, output);
    return Prediction.fromScores(output.first);
  }

  _PhotoCandidate _detectBestPhotoCandidate(
    img.Image source, {
    required bool invert,
    required bool preferPaperCrop,
  }) {
    final candidates = <img.Image>[
      if (preferPaperCrop) ..._cameraPhotoCandidates(source),
      source,
    ];

    _PhotoCandidate? best;
    for (final image in candidates) {
      final boxes = _detectInkBoxes(image, invert: invert);
      final candidate = _PhotoCandidate(
        image: image,
        boxes: boxes,
        score: _scoreDetectedBoxes(boxes, image),
      );
      if (best == null || candidate.score > best.score) {
        best = candidate;
      }
    }

    return best ?? _PhotoCandidate(image: source, boxes: const [], score: -1);
  }

  List<img.Image> _cameraPhotoCandidates(img.Image source) {
    final candidates = <img.Image>[];
    final paperBox = _findLikelyPaperBox(source);
    if (paperBox != null) {
      candidates.add(
        img.copyCrop(
          source,
          x: paperBox.left,
          y: paperBox.top,
          width: paperBox.width,
          height: paperBox.height,
        ),
      );
    }

    final centerCrop = _largeCenterCrop(source);
    if (centerCrop != null) {
      candidates.add(centerCrop);
    }
    return candidates;
  }

  double _scoreDetectedBoxes(List<PixelBox> boxes, img.Image image) {
    if (boxes.isEmpty) return -1;

    final imageArea = (image.width * image.height).toDouble();
    var score = math.min(boxes.length, 20) * 100.0;
    if (boxes.length > 20) {
      score -= (boxes.length - 20) * 120.0;
    }
    for (final box in boxes) {
      final areaRatio = box.area / imageArea;
      if (areaRatio > 0.20) score -= 80;
      if (areaRatio < 0.00002) score -= 20;
      if (box.left <= 1 ||
          box.top <= 1 ||
          box.right >= image.width - 2 ||
          box.bottom >= image.height - 2) {
        score -= 12;
      }
    }
    return score;
  }

  PixelBox? _findLikelyPaperBox(img.Image source) {
    final width = source.width;
    final height = source.height;
    final totalPixels = width * height;
    if (totalPixels == 0) return null;

    final histogram = List<int>.filled(256, 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = source.getPixel(x, y);
        final luminance =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
                .round()
                .clamp(0, 255)
                .toInt();
        histogram[luminance]++;
      }
    }

    final brightThreshold = math.max(
      145,
      _histogramPercentile(histogram, totalPixels, 0.62),
    );
    var paperPixels = 0;
    var minX = width;
    var maxX = 0;
    var minY = height;
    var maxY = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = source.getPixel(x, y);
        final red = pixel.r.toInt();
        final green = pixel.g.toInt();
        final blue = pixel.b.toInt();
        final maxChannel = math.max(red, math.max(green, blue));
        final minChannel = math.min(red, math.min(green, blue));
        final luminance =
            (0.299 * red + 0.587 * green + 0.114 * blue)
                .round()
                .clamp(0, 255)
                .toInt();
        final saturation =
            maxChannel == 0 ? 0.0 : (maxChannel - minChannel) / maxChannel;

        if (luminance < brightThreshold || saturation > 0.38) continue;

        paperPixels++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    final paperRatio = paperPixels / totalPixels;
    if (paperRatio < 0.10 || paperRatio > 0.96) return null;

    var paperBox = PixelBox(left: minX, top: minY, right: maxX, bottom: maxY);
    if (paperBox.width < width * 0.20 || paperBox.height < height * 0.20) {
      return null;
    }

    paperBox = paperBox.expand(
      imageWidth: width,
      imageHeight: height,
      padding: math.max(8, (math.min(width, height) * 0.025).round()),
    );
    return paperBox;
  }

  img.Image? _largeCenterCrop(img.Image source) {
    final side = (math.min(source.width, source.height) * 0.86).round();
    if (side <= 0 || side >= math.min(source.width, source.height)) {
      return null;
    }
    return img.copyCrop(
      source,
      x: ((source.width - side) / 2).round(),
      y: ((source.height - side) / 2).round(),
      width: side,
      height: side,
    );
  }

  List<List<List<List<double>>>> _imageToTensor(
    img.Image source, {
    required bool invert,
  }) {
    final oriented = img.bakeOrientation(source);
    final boxes = _detectInkBoxes(oriented, invert: invert);
    if (boxes.isNotEmpty) {
      final largestBox = boxes.reduce(
        (best, box) => box.area > best.area ? box : best,
      );
      return _imageBoxToTensor(oriented, largestBox, invert: invert);
    }

    final side = math.min(oriented.width, oriented.height);
    final cropped = img.copyCrop(
      oriented,
      x: (oriented.width - side) ~/ 2,
      y: (oriented.height - side) ~/ 2,
      width: side,
      height: side,
    );

    return _cropToModelTensor(cropped, invert: invert);
  }

  List<List<List<List<double>>>> _imageBoxToTensor(
    img.Image source,
    PixelBox box, {
    required bool invert,
  }) {
    final squareBox = box.expandedSquare(
      imageWidth: source.width,
      imageHeight: source.height,
      paddingFactor: 0.28,
    );
    final cropped = img.copyCrop(
      source,
      x: squareBox.left,
      y: squareBox.top,
      width: squareBox.width,
      height: squareBox.height,
    );

    return _cropToModelTensor(cropped, invert: invert);
  }

  List<List<List<List<double>>>> _cropToModelTensor(
    img.Image crop, {
    required bool invert,
  }) {
    final hasClearBg = _cropHasClearBackground(crop, invert: invert);
    final foregroundBox =
        hasClearBg ? _foregroundBoxForModel(crop, invert: invert) : null;
    final normalizedSource =
        hasClearBg && (foregroundBox != null)
            ? _copyExpandedForeground(crop, foregroundBox)
            : crop;
    final modelImage = _normalizeModelImage(normalizedSource, invert: invert);
    final resized = img.copyResize(
      modelImage,
      width: imageSize,
      height: imageSize,
      interpolation: img.Interpolation.average,
    );

    return _pixelsToTensor(resized);
  }

  bool _cropHasClearBackground(img.Image crop, {required bool invert}) {
    var sum = 0.0;
    final total = crop.width * crop.height;
    for (var y = 0; y < crop.height; y++) {
      for (var x = 0; x < crop.width; x++) {
        final lum = _modelLuminance(crop.getPixel(x, y), invert: invert);
        sum += lum;
      }
    }
    final meanLum = sum / (total * 255.0);
    return invert ? meanLum < 0.45 : meanLum > 0.55;
  }

  img.Image _copyExpandedForeground(img.Image crop, PixelBox foregroundBox) {
    final modelBox = foregroundBox.expandedSquare(
      imageWidth: crop.width,
      imageHeight: crop.height,
      paddingFactor: 0.24,
    );
    return img.copyCrop(
      crop,
      x: modelBox.left,
      y: modelBox.top,
      width: modelBox.width,
      height: modelBox.height,
    );
  }

  List<List<List<List<double>>>> _pixelsToTensor(img.Image image) {
    return [
      List.generate(imageSize, (y) {
        return List.generate(imageSize, (x) {
          final pixel = image.getPixel(x, y);
          final luminance =
              (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
          return [luminance.clamp(0.0, 1.0).toDouble()];
        });
      }),
    ];
  }

  PixelBox? _foregroundBoxForModel(img.Image image, {required bool invert}) {
    final width = image.width;
    final height = image.height;
    final totalPixels = width * height;
    if (totalPixels == 0) return null;

    final luminances = Uint8List(totalPixels);
    final histogram = List<int>.filled(256, 0);
    var index = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final luminance = _modelLuminance(image.getPixel(x, y), invert: invert);
        luminances[index++] = luminance;
        histogram[luminance]++;
      }
    }

    final threshold = _otsuThreshold(histogram, totalPixels);
    var inkPixels = 0;
    var minX = width;
    var maxX = 0;
    var minY = height;
    var maxY = 0;

    for (var i = 0; i < totalPixels; i++) {
      if (luminances[i] >= threshold) continue;

      final x = i % width;
      final y = i ~/ width;
      inkPixels++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    final minInkPixels = math.max(4, (totalPixels * 0.002).round());
    if (inkPixels < minInkPixels || inkPixels > totalPixels * 0.70) {
      return null;
    }

    return PixelBox(left: minX, top: minY, right: maxX, bottom: maxY);
  }

  img.Image _normalizeModelImage(img.Image image, {required bool invert}) {
    // MAHDBase training format: white background (255), dark ink (0).
    // Binarize with Otsu — do NOT contrast-stretch, it distorts model input.
    final width = image.width;
    final height = image.height;
    final totalPixels = width * height;
    final luminances = Uint8List(totalPixels);
    final histogram = List<int>.filled(256, 0);
    var index = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = image.getPixel(x, y);
        var lum =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b)
                .round()
                .clamp(0, 255)
                .toInt();
        if (invert) lum = 255 - lum;
        luminances[index++] = lum;
        histogram[lum]++;
      }
    }

    final threshold = _otsuThreshold(histogram, totalPixels);
    final normalized = img.Image(width: width, height: height);

    index = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // ink → 0 (black), background → 255 (white) — matches MAHDBase
        final value = luminances[index++] < threshold ? 0 : 255;
        normalized.setPixelRgb(x, y, value, value, value);
      }
    }

    return normalized;
  }

  int _modelLuminance(img.Pixel pixel, {required bool invert}) {
    final luminance =
        (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            .round()
            .clamp(0, 255)
            .toInt();
    return invert ? 255 - luminance : luminance;
  }

  List<List<List<List<double>>>> _strokeRegionToTensor(StrokeRegion region) {
    final grid = List.generate(
      imageSize,
      (_) => List<double>.filled(imageSize, 1.0),
    );

    final squareBox = region.box.expandedSquare(
      bounds: Offset.zero & region.canvasSize,
      paddingFactor: 0.28,
    );

    if (squareBox.width <= 0 || squareBox.height <= 0) {
      throw StateError('Invalid drawing area');
    }

    final brushRadius = _modelBrushRadius(region.canvasSize, squareBox);

    Offset toModelPoint(Offset point) {
      final x =
          ((point.dx - squareBox.left) / squareBox.width).clamp(0.0, 1.0) *
          (imageSize - 1);
      final y =
          ((point.dy - squareBox.top) / squareBox.height).clamp(0.0, 1.0) *
          (imageSize - 1);
      return Offset(x, y);
    }

    for (final stroke in region.strokes) {
      final points = stroke.points.map(toModelPoint).toList(growable: false);
      if (points.isEmpty) continue;
      if (points.length == 1) {
        _stamp(grid, points.first, brushRadius);
        continue;
      }

      for (var i = 1; i < points.length; i++) {
        _drawSoftLine(grid, points[i - 1], points[i], brushRadius);
      }
    }

    return [
      List.generate(imageSize, (y) {
        return List.generate(imageSize, (x) => [grid[y][x]]);
      }),
    ];
  }

  double _modelBrushRadius(Size canvasSize, Rect modelSourceBox) {
    final visualRadius = drawingStrokeWidth(canvasSize) / 2;
    final sourceSide = math.min(modelSourceBox.width, modelSourceBox.height);
    final modelScale = (imageSize - 1) / sourceSide;
    return (visualRadius * modelScale).clamp(2.2, 5.4).toDouble();
  }

  // ── Adaptive local thresholding ──────────────────────────────────────────
  // Divides the image into tiles and computes a local Otsu threshold per tile,
  // then bilinearly interpolates to get a per-pixel threshold. This handles
  // uneven lighting, shadows, and paper creases robustly.
  Uint8List _adaptiveThreshold(
    Uint8List luminances,
    int width,
    int height, {
    required bool invert,
    int tileCount = 8,
    int localC = 6,
  }) {
    final tileW = (width / tileCount).ceil();
    final tileH = (height / tileCount).ceil();

    // Compute local thresholds on a grid
    final gridW = tileCount + 1;
    final gridH = tileCount + 1;
    final thresholds = List<double>.filled(gridW * gridH, 128);

    for (var ty = 0; ty < tileCount; ty++) {
      for (var tx = 0; tx < tileCount; tx++) {
        final x0 = tx * tileW;
        final y0 = ty * tileH;
        final x1 = math.min(x0 + tileW, width);
        final y1 = math.min(y0 + tileH, height);

        final hist = List<int>.filled(256, 0);
        var count = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) {
            hist[luminances[y * width + x]]++;
            count++;
          }
        }
        final t = count > 0 ? _otsuThreshold(hist, count).toDouble() : 128.0;
        // Store at grid center
        thresholds[ty * gridW + tx] = t;
      }
    }

    // Fill right/bottom border by copying nearest
    for (var ty = 0; ty < tileCount; ty++) {
      thresholds[ty * gridW + tileCount] =
          thresholds[ty * gridW + (tileCount - 1)];
    }
    for (var tx = 0; tx <= tileCount; tx++) {
      thresholds[tileCount * gridW + tx] =
          thresholds[(tileCount - 1) * gridW + tx];
    }

    // Apply per-pixel with bilinear interpolation
    final foreground = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final tx = (x / tileW).clamp(0, tileCount - 1).toInt();
        final ty = (y / tileH).clamp(0, tileCount - 1).toInt();
        final fx = (x / tileW) - tx;
        final fy = (y / tileH) - ty;

        final t00 = thresholds[ty * gridW + tx];
        final t10 = thresholds[ty * gridW + tx + 1];
        final t01 = thresholds[(ty + 1) * gridW + tx];
        final t11 = thresholds[(ty + 1) * gridW + tx + 1];
        final localThreshold =
            t00 * (1 - fx) * (1 - fy) +
            t10 * fx * (1 - fy) +
            t01 * (1 - fx) * fy +
            t11 * fx * fy;

        final lum = luminances[y * width + x];
        final adjustedThreshold = (localThreshold - localC).clamp(30, 220);
        final isInk =
            invert ? lum > adjustedThreshold : lum < adjustedThreshold;
        foreground[y * width + x] = isInk ? 1 : 0;
      }
    }

    return foreground;
  }

  // ── Ink density check ────────────────────────────────────────────────────
  // Shadows and creases have very sparse ink pixels relative to bounding box.
  // Real digits have a higher fill ratio.
  double _inkDensity(
    Uint8List foreground,
    int width,
    PixelBox box,
  ) {
    var inkCount = 0;
    for (var y = box.top; y <= box.bottom; y++) {
      for (var x = box.left; x <= box.right; x++) {
        if (foreground[y * width + x] == 1) inkCount++;
      }
    }
    return inkCount / math.max(1, box.area);
  }

  List<PixelBox> _detectInkBoxes(img.Image image, {required bool invert}) {
    final width = image.width;
    final height = image.height;
    final totalPixels = width * height;
    if (totalPixels == 0) return [];

    // Step 1: Extract luminances
    final luminances = Uint8List(totalPixels);
    final histogram = List<int>.filled(256, 0);
    var index = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
                .round()
                .clamp(0, 255)
                .toInt();
        luminances[index++] = luminance;
        histogram[luminance]++;
      }
    }

    // Step 2: Global Otsu sanity check — if image is nearly uniform, bail out
    final otsuThreshold = _otsuThreshold(histogram, totalPixels);
    final inkCount = luminances
        .where(invert ? (l) => l > otsuThreshold : (l) => l < otsuThreshold)
        .length;
    if (otsuThreshold < 50 || otsuThreshold > 210 || inkCount < totalPixels * 0.003) {
      return [PixelBox(left: 0, top: 0, right: width - 1, bottom: height - 1)];
    }

    // Step 3: Adaptive local threshold — handles shadows/uneven lighting
    final foreground = _adaptiveThreshold(
      luminances,
      width,
      height,
      invert: invert,
      tileCount: 8,
      localC: 7,
    );

    // Step 4: Connected components (BFS flood fill)
    final visited = Uint8List(totalPixels);
    final queue = Int32List(totalPixels);
    final boxes = <PixelBox>[];
    final minImageSide = math.min(width, height);
    final minSide = math.max(4, (minImageSide * 0.010).round());
    final minArea = math.max(
      36,
      (minImageSide * 0.015 * minImageSide * 0.015).round(),
    );
    final maxArea = (totalPixels * 0.40).round();

    for (var start = 0; start < totalPixels; start++) {
      if (foreground[start] == 0 || visited[start] == 1) continue;

      var head = 0;
      var tail = 0;
      queue[tail++] = start;
      visited[start] = 1;

      var area = 0;
      var minX = width;
      var maxX = 0;
      var minY = height;
      var maxY = 0;

      while (head < tail) {
        final current = queue[head++];
        final x = current % width;
        final y = current ~/ width;
        area++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;

        for (var ny = math.max(0, y - 1); ny <= math.min(height - 1, y + 1); ny++) {
          for (var nx = math.max(0, x - 1); nx <= math.min(width - 1, x + 1); nx++) {
            final neighbor = ny * width + nx;
            if (visited[neighbor] == 1 || foreground[neighbor] == 0) continue;
            visited[neighbor] = 1;
            queue[tail++] = neighbor;
          }
        }
      }

      final box = PixelBox(left: minX, top: minY, right: maxX, bottom: maxY);
      final ratio = box.width / math.max(1, box.height);

      // Step 5: Filter by size, aspect, and ink density
      if (area < minArea || area > maxArea) continue;
      if (box.width < minSide || box.height < minSide) continue;

      // Reject notebook lines: very wide and thin (ratio >> 1)
      // Real Arabic digits are roughly square (0.15–4.0 ratio)
      if (ratio < 0.12 || ratio > 4.5) continue;

      // Reject boxes that are too tall relative to width (paper edge shadows)
      // and too wide relative to the image
      if (box.width > width * 0.55) continue;
      if (box.height > height * 0.55) continue;

      // Reject blobs with very low ink density (notebook lines are thin)
      final density = _inkDensity(foreground, width, box);
      if (density < 0.06 || density > 0.90) continue;

      boxes.add(box);
    }

    // Step 6: Merge nearby boxes (handles fragmented digits like ٠ and ٢)
    // Use tight merge — only merge boxes very close to each other
    final merged = _mergePixelBoxes(boxes, width, height);

    // Step 7: After merge, reject boxes that are too large
    // (merging gone wrong — a merged box shouldn't cover >15% of image)
    final maxMergedArea = totalPixels * 0.15;
    final filtered = merged.where((box) {
      if (box.area > maxMergedArea) return false;
      if (box.width > width * 0.55) return false;
      final ratio = box.width / math.max(1, box.height);
      if (ratio < 0.10 || ratio > 5.0) return false;
      final density = _inkDensity(foreground, width, box);
      return density >= 0.05;
    }).toList();

    // Cap at 20 — prefer largest by area if too many
    if (filtered.length > 20) {
      filtered.sort((a, b) => b.area.compareTo(a.area));
      filtered.removeRange(20, filtered.length);
    }

    return _sortPixelBoxes(filtered);
  }

  int _otsuThreshold(List<int> histogram, int totalPixels) {
    var sum = 0.0;
    for (var i = 0; i < histogram.length; i++) {
      sum += i * histogram[i];
    }

    var backgroundWeight = 0;
    var backgroundSum = 0.0;
    var bestVariance = -1.0;
    var threshold = 127;

    for (var i = 0; i < histogram.length; i++) {
      backgroundWeight += histogram[i];
      if (backgroundWeight == 0) continue;

      final foregroundWeight = totalPixels - backgroundWeight;
      if (foregroundWeight == 0) break;

      backgroundSum += i * histogram[i];
      final backgroundMean = backgroundSum / backgroundWeight;
      final foregroundMean = (sum - backgroundSum) / foregroundWeight;
      final variance =
          backgroundWeight *
          foregroundWeight *
          math.pow(backgroundMean - foregroundMean, 2);

      if (variance > bestVariance) {
        bestVariance = variance.toDouble();
        threshold = i;
      }
    }

    return threshold.clamp(40, 220).toInt();
  }

  int _histogramPercentile(
    List<int> histogram,
    int totalPixels,
    double percentile,
  ) {
    if (totalPixels <= 0) return 127;

    final target = (totalPixels * percentile.clamp(0.0, 1.0)).round();
    var cumulative = 0;
    for (var i = 0; i < histogram.length; i++) {
      cumulative += histogram[i];
      if (cumulative >= target) return i;
    }
    return histogram.length - 1;
  }

  List<PixelBox> _mergePixelBoxes(
    List<PixelBox> boxes,
    int imageWidth,
    int imageHeight,
  ) {
    // Use median digit height as merge padding — adapts to actual digit size
    // rather than image size, preventing merging of far-apart digits.
    double mergePadding;
    if (boxes.isEmpty) {
      mergePadding = math.max(2.0, math.min(imageWidth, imageHeight) * 0.020);
    } else {
      final heights = boxes.map((b) => b.height).toList()..sort();
      final medianHeight = heights[heights.length ~/ 2].toDouble();
      // 15% of median digit height — tight enough to catch fragments
      // but won't merge digits that are clearly separate
      mergePadding = (medianHeight * 0.15).clamp(
        3.0,
        math.min(imageWidth, imageHeight) * 0.018,
      );
    }
    final merged = [...boxes];
    var changed = true;

    while (changed) {
      changed = false;
      for (var i = 0; i < merged.length; i++) {
        for (var j = i + 1; j < merged.length; j++) {
          if (!merged[i]
              .toRect()
              .inflate(mergePadding)
              .overlaps(merged[j].toRect())) {
            continue;
          }
          merged[i] = merged[i].merge(merged[j]);
          merged.removeAt(j);
          changed = true;
          break;
        }
        if (changed) break;
      }
    }

    return merged;
  }

  List<PixelBox> _sortPixelBoxes(List<PixelBox> boxes) {
    boxes.sort((a, b) {
      final rowTolerance = math.max(a.height, b.height) * 0.6;
      if ((a.centerY - b.centerY).abs() > rowTolerance) {
        return a.top.compareTo(b.top);
      }
      return a.left.compareTo(b.left);
    });
    return boxes;
  }

  List<StrokeRegion> _detectStrokeRegions(
    List<Stroke> strokes,
    Size canvasSize,
  ) {
    final regions = <StrokeRegion>[];
    final strokePadding = math.max(
      drawingStrokeWidth(canvasSize) * 0.75,
      canvasSize.shortestSide * 0.045,
    );
    final bounds = Offset.zero & canvasSize;

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      var minX = double.infinity;
      var maxX = double.negativeInfinity;
      var minY = double.infinity;
      var maxY = double.negativeInfinity;

      for (final point in stroke.points) {
        if (point.dx < minX) minX = point.dx;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dy > maxY) maxY = point.dy;
      }

      final strokeBox = Rect.fromLTRB(
        minX,
        minY,
        maxX,
        maxY,
      ).inflate(strokePadding).intersect(bounds);
      if (strokeBox.isEmpty) continue;

      var merged = false;
      for (var i = 0; i < regions.length; i++) {
        if (_shouldMergeStrokeBoxes(regions[i].box, strokeBox, canvasSize)) {
          regions[i] = regions[i].merge(stroke, strokeBox);
          merged = true;
          break;
        }
      }

      if (!merged) {
        regions.add(
          StrokeRegion(
            box: strokeBox,
            strokes: [stroke],
            canvasSize: canvasSize,
          ),
        );
      }
    }

    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < regions.length; i++) {
        for (var j = i + 1; j < regions.length; j++) {
          if (!_shouldMergeStrokeBoxes(
            regions[i].box,
            regions[j].box,
            canvasSize,
          )) {
            continue;
          }
          regions[i] = regions[i].mergeRegion(regions[j]);
          regions.removeAt(j);
          changed = true;
          break;
        }
        if (changed) break;
      }
    }

    regions.sort((a, b) {
      final rowTolerance = math.max(a.box.height, b.box.height) * 0.6;
      if ((a.box.center.dy - b.box.center.dy).abs() > rowTolerance) {
        return a.box.top.compareTo(b.box.top);
      }
      return a.box.left.compareTo(b.box.left);
    });
    return regions;
  }

  bool _shouldMergeStrokeBoxes(Rect a, Rect b, Size canvasSize) {
    final padding = math.max(
      drawingStrokeWidth(canvasSize) * 0.65,
      canvasSize.shortestSide * 0.045,
    );
    if (a.inflate(padding).overlaps(b)) return true;

    final verticalOverlap =
        math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    final minHeight = math.min(a.height, b.height);
    final horizontalGap =
        a.right < b.left
            ? b.left - a.right
            : a.left > b.right
            ? a.left - b.right
            : 0.0;

    final verticalGap =
        a.bottom < b.top
            ? b.top - a.bottom
            : b.bottom < a.top
            ? a.top - b.bottom
            : 0.0;
    final closeSeparateStrokes =
        horizontalGap < canvasSize.shortestSide * 0.065 &&
        verticalGap < canvasSize.shortestSide * 0.065;

    return closeSeparateStrokes ||
        (verticalOverlap > minHeight * 0.35 &&
            horizontalGap < canvasSize.shortestSide * 0.055);
  }

  void _drawSoftLine(
    List<List<double>> grid,
    Offset start,
    Offset end,
    double radius,
  ) {
    final distance = (end - start).distance;
    final steps = math.max(1, (distance / 0.35).ceil());

    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final point = Offset(
        start.dx + (end.dx - start.dx) * t,
        start.dy + (end.dy - start.dy) * t,
      );
      _stamp(grid, point, radius);
    }
  }

  void _stamp(List<List<double>> grid, Offset center, double radius) {
    final minX = math.max(0, (center.dx - radius - 1).floor());
    final maxX = math.min(imageSize - 1, (center.dx + radius + 1).ceil());
    final minY = math.max(0, (center.dy - radius - 1).floor());
    final maxY = math.min(imageSize - 1, (center.dy + radius + 1).ceil());

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final distance = math.sqrt(
          math.pow(x - center.dx, 2) + math.pow(y - center.dy, 2),
        );
        if (distance <= radius) {
          grid[y][x] = 0.0;
        } else if (distance <= radius + 1) {
          final edge = distance - radius;
          grid[y][x] = math.min(grid[y][x], edge.clamp(0.0, 1.0).toDouble());
        }
      }
    }
  }
}

class _PhotoCandidate {
  const _PhotoCandidate({
    required this.image,
    required this.boxes,
    required this.score,
  });

  final img.Image image;
  final List<PixelBox> boxes;
  final double score;
}

class ImageDetectionResult {
  const ImageDetectionResult({
    required this.displayBytes,
    required this.result,
  });

  final Uint8List displayBytes;
  final DetectionResult result;
}

class DetectionResult {
  const DetectionResult({required this.detections, required this.sourceSize});

  final List<DetectedDigit> detections;
  final Size sourceSize;

  String get sequence {
    return detections
        .map((detection) => detection.prediction.digit.toString())
        .join();
  }

  String? get badgeText {
    if (detections.isEmpty) return null;
    return sequence;
  }

  Prediction? get primaryPrediction {
    if (detections.length != 1) return null;
    return detections.first.prediction;
  }
}

class DetectedDigit {
  const DetectedDigit({required this.box, required this.prediction});

  final Rect box;
  final Prediction prediction;
}

class PixelBox {
  const PixelBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left + 1;
  int get height => bottom - top + 1;
  int get area => width * height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  Rect toRect() {
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      (right + 1).toDouble(),
      (bottom + 1).toDouble(),
    );
  }

  Rect toNormalizedRect(int imageWidth, int imageHeight) {
    return Rect.fromLTRB(
      (left / imageWidth).clamp(0.0, 1.0).toDouble(),
      (top / imageHeight).clamp(0.0, 1.0).toDouble(),
      ((right + 1) / imageWidth).clamp(0.0, 1.0).toDouble(),
      ((bottom + 1) / imageHeight).clamp(0.0, 1.0).toDouble(),
    );
  }

  PixelBox merge(PixelBox other) {
    return PixelBox(
      left: math.min(left, other.left),
      top: math.min(top, other.top),
      right: math.max(right, other.right),
      bottom: math.max(bottom, other.bottom),
    );
  }

  PixelBox expand({
    required int imageWidth,
    required int imageHeight,
    required int padding,
  }) {
    return PixelBox(
      left: math.max(0, left - padding),
      top: math.max(0, top - padding),
      right: math.min(imageWidth - 1, right + padding),
      bottom: math.min(imageHeight - 1, bottom + padding),
    );
  }

  PixelBox expandedSquare({
    required int imageWidth,
    required int imageHeight,
    required double paddingFactor,
  }) {
    final maxSide = math.min(imageWidth, imageHeight);
    var side = (math.max(width, height) * (1 + paddingFactor * 2)).round();
    side = side.clamp(1, maxSide).toInt();

    final centerX = this.centerX;
    final centerY = this.centerY;
    var squareLeft = (centerX - side / 2).round();
    var squareTop = (centerY - side / 2).round();
    squareLeft = squareLeft.clamp(0, imageWidth - side).toInt();
    squareTop = squareTop.clamp(0, imageHeight - side).toInt();

    return PixelBox(
      left: squareLeft,
      top: squareTop,
      right: squareLeft + side - 1,
      bottom: squareTop + side - 1,
    );
  }
}

class StrokeRegion {
  const StrokeRegion({
    required this.box,
    required this.strokes,
    required this.canvasSize,
  });

  final Rect box;
  final List<Stroke> strokes;
  final Size canvasSize;

  StrokeRegion merge(Stroke stroke, Rect strokeBox) {
    return StrokeRegion(
      box: box.expandToInclude(strokeBox),
      strokes: [...strokes, stroke],
      canvasSize: canvasSize,
    );
  }

  StrokeRegion mergeRegion(StrokeRegion other) {
    return StrokeRegion(
      box: box.expandToInclude(other.box),
      strokes: [...strokes, ...other.strokes],
      canvasSize: canvasSize,
    );
  }
}

extension DigitRectX on Rect {
  Rect toNormalizedRect(Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return Rect.zero;
    }
    return Rect.fromLTRB(
      (left / size.width).clamp(0.0, 1.0).toDouble(),
      (top / size.height).clamp(0.0, 1.0).toDouble(),
      (right / size.width).clamp(0.0, 1.0).toDouble(),
      (bottom / size.height).clamp(0.0, 1.0).toDouble(),
    );
  }

  Rect expandToInclude(Rect other) {
    return Rect.fromLTRB(
      math.min(left, other.left),
      math.min(top, other.top),
      math.max(right, other.right),
      math.max(bottom, other.bottom),
    );
  }

  Rect expandedSquare({required Rect bounds, required double paddingFactor}) {
    final maxSide = math.min(bounds.width, bounds.height);
    final center = this.center;
    var side = math.max(width, height) * (1 + paddingFactor * 2);
    side = side.clamp(1.0, maxSide).toDouble();

    var squareLeft = center.dx - side / 2;
    var squareTop = center.dy - side / 2;
    squareLeft = squareLeft.clamp(bounds.left, bounds.right - side).toDouble();
    squareTop = squareTop.clamp(bounds.top, bounds.bottom - side).toDouble();

    return Rect.fromLTWH(squareLeft, squareTop, side, side);
  }
}

class Stroke {
  Stroke({required this.points});

  final List<Offset> points;
}

class Prediction {
  const Prediction({
    required this.digit,
    required this.confidence,
    required this.probabilities,
  });

  factory Prediction.fromScores(List<double> scores) {
    final probabilities = _normalizeScores(scores);
    var bestIndex = 0;
    var bestScore = probabilities.first;

    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > bestScore) {
        bestScore = probabilities[i];
        bestIndex = i;
      }
    }

    return Prediction(
      digit: bestIndex,
      confidence: bestScore,
      probabilities: probabilities,
    );
  }

  final int digit;
  final double confidence;
  final List<double> probabilities;

  List<DigitGuess> get topGuesses {
    final guesses = [
      for (var i = 0; i < probabilities.length; i++)
        DigitGuess(digit: i, score: probabilities[i]),
    ];
    guesses.sort((a, b) => b.score.compareTo(a.score));
    return guesses;
  }

  static List<double> _normalizeScores(List<double> scores) {
    final sum = scores.fold<double>(0, (total, score) => total + score);
    final alreadyProbabilities =
        sum > 0.9 && sum < 1.1 && scores.every((score) => score >= 0);

    if (alreadyProbabilities) {
      return scores.map((score) => score.clamp(0.0, 1.0).toDouble()).toList();
    }

    final maxScore = scores.reduce(math.max);
    final expScores =
        scores.map((score) => math.exp(score - maxScore)).toList();
    final expSum = expScores.fold<double>(0, (total, score) => total + score);
    return expScores.map((score) => score / expSum).toList();
  }
}

class DigitGuess {
  const DigitGuess({required this.digit, required this.score});

  final int digit;
  final double score;
}

double responsiveSidePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width <= 420) return 12;
  if (width <= 760) return 16;
  return math.max(24, (width - 720) / 2);
}

double drawingStrokeWidth(Size size) {
  final base = size.shortestSide * 0.06;
  return base.clamp(14.0, 24.0).toDouble();
}
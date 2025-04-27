import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show File, Directory;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../main.dart';  // Import for GameDifficulty enum

// Constants for model loading
class ModelConstants {
  // Model file names for different difficulties
  static const String easyModelFileName = 'low_difficulty_model.tflite';
  static const String mediumModelFileName = 'pong_ai_model.tflite';
  static const String hardModelFileName = 'extreme_difficulty_model.tflite';

  static const String modelVersion = 'v1.2.3';
  static const String modelTrainingDate = '2025-04-26';
  static const String modelFramework = 'PyTorch 2.4.0 + TFLite';
  static const int modelTrainingSteps = 1950000;

  // Remote model URLs (fallback if not bundled)
  static const String remoteEasyModelUrl = 'https://example.com/models/low_difficulty_model.tflite';
  static const String remoteMediumModelUrl = 'https://example.com/models/pong_ai_model.tflite';
  static const String remoteHardModelUrl = 'https://example.com/models/extreme_difficulty_model.tflite';

  // Model cache settings
  static const Duration modelCacheExpiration = Duration(days: 7);
  static const String modelCacheKey = 'pong_ai_model_cache_timestamp';
  static const String modelHashKey = 'pong_ai_model_hash';

  // Model metrics
  static const double modelAccuracy = 0.95;
  static const double modelResponseTime = 14.0; // milliseconds
  static const double modelWinRate = 0.98;

  // Loading timeouts
  static const Duration loadTimeout = Duration(seconds: 15);

  // Feature flags
  static const bool enableRemoteFallback = true;
  static const bool enableModelCaching = true;
  static const bool enableModelVersionCheck = true;
}

/// ModelLoader handles loading and managing the AI model for the game
class ModelLoader extends ChangeNotifier {
  // Model loading state
  bool _isInitialized = false;
  bool _isLoading = false;
  String _loadingStatus = "Not loaded";
  double _loadingProgress = 0.0;
  String _errorMessage = "";
  bool _hasError = false;

  // Model data for different difficulty levels
  Uint8List? _easyModelData;
  Uint8List? _mediumModelData;
  Uint8List? _hardModelData;

  String _modelSource = "Unknown";
  DateTime? _modelTimestamp;
  String _modelHash = "";

  // Current active model data based on difficulty
  Uint8List? _activeModelData;
  GameDifficulty _activeDifficulty = GameDifficulty.medium;

  // Animation controllers for external widgets
  AnimationController? _loadingAnimation;
  AnimationController? _errorAnimation;

  // Statistics
  int _loadAttempts = 0;
  double _lastLoadDuration = 0.0;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String get loadingStatus => _loadingStatus;
  double get loadingProgress => _loadingProgress;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  String get modelSource => _modelSource;
  String get modelHash => _modelHash;
  String get modelSize => _activeModelData != null
      ? "${(_activeModelData!.length / 1024).toStringAsFixed(1)} KB"
      : "0 KB";
  double get lastLoadDuration => _lastLoadDuration;
  int get loadAttempts => _loadAttempts;

  // Get model data for a specific difficulty
  Uint8List? getModelForDifficulty(GameDifficulty difficulty) {
    switch (difficulty) {
      case GameDifficulty.easy:
        return _easyModelData ?? _mediumModelData; // Fallback to medium if easy not available
      case GameDifficulty.medium:
        return _mediumModelData;
      case GameDifficulty.hard:
      case GameDifficulty.custom: // Custom uses hard model as base
        return _hardModelData ?? _mediumModelData; // Fallback to medium if hard not available
      default:
        return _mediumModelData;
    }
  }

  // Set the active difficulty and notify listeners
  void setActiveDifficulty(GameDifficulty difficulty) {
    _activeDifficulty = difficulty;
    _activeModelData = getModelForDifficulty(difficulty);
    notifyListeners();
  }

  // Initialize the model loader
  Future<void> initialize() async {
    if (_isInitialized || _isLoading) return;

    _isLoading = true;
    _loadingStatus = "Initializing...";
    _loadingProgress = 0.05;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    _loadAttempts++;

    try {
      // Start loading animation if available
      if (_loadingAnimation != null) {
        _loadingAnimation!.repeat();
      }

      // First try to load from cache
      if (ModelConstants.enableModelCaching) {
        _loadingStatus = "Checking cache...";
        _loadingProgress = 0.1;
        notifyListeners();

        await _loadModelsFromCache();

        // If all models loaded from cache, we're done
        if (_easyModelData != null && _mediumModelData != null && _hardModelData != null) {
          _loadingStatus = "Using cached models";
          _loadingProgress = 1.0;
          _modelSource = "Cache";
          _activeModelData = getModelForDifficulty(_activeDifficulty);

          _isInitialized = true;
          _isLoading = false;
          _lastLoadDuration = stopwatch.elapsedMilliseconds / 1000;
          notifyListeners();
          return;
        }
      }

      // Load models from assets
      _loadingStatus = "Loading models...";
      _loadingProgress = 0.3;
      notifyListeners();

      await _loadModelsFromAssets();

      // If all needed models are available, we're done
      if (_mediumModelData != null) {
        _loadingStatus = "Models loaded";
        _loadingProgress = 1.0;
        _modelSource = "Assets";
        _activeModelData = getModelForDifficulty(_activeDifficulty);

        // Cache the models for future use
        if (ModelConstants.enableModelCaching) {
          _cacheModels();
        }

        _isInitialized = true;
        _isLoading = false;
        _lastLoadDuration = stopwatch.elapsedMilliseconds / 1000;
        notifyListeners();
        return;
      }

      // If remote fallback is enabled and we're missing any model, try downloading
      if (ModelConstants.enableRemoteFallback) {
        _loadingStatus = "Downloading missing models...";
        _loadingProgress = 0.5;
        notifyListeners();

        // Try downloading any missing models
        if (_easyModelData == null) {
          _easyModelData = await _downloadModel(ModelConstants.remoteEasyModelUrl);
        }

        if (_mediumModelData == null) {
          _mediumModelData = await _downloadModel(ModelConstants.remoteMediumModelUrl);
        }

        if (_hardModelData == null) {
          _hardModelData = await _downloadModel(ModelConstants.remoteHardModelUrl);
        }

        // Check if we have at least the medium model
        if (_mediumModelData != null) {
          _loadingStatus = "Models downloaded";
          _loadingProgress = 1.0;
          _modelSource = "Remote";
          _activeModelData = getModelForDifficulty(_activeDifficulty);

          // Cache the downloaded models
          if (ModelConstants.enableModelCaching) {
            _cacheModels();
          }

          _isInitialized = true;
          _isLoading = false;
          _lastLoadDuration = stopwatch.elapsedMilliseconds / 1000;
          notifyListeners();
          return;
        }
      }

      // If we got here, we couldn't load at least the medium model
      throw Exception('Failed to load required AI models');

    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      _loadingStatus = "Error loading models";
      _loadingProgress = 0.0;

      // Start error animation if available
      if (_errorAnimation != null) {
        _errorAnimation!.forward(from: 0.0);
      }

      debugPrint('Model loading error: $_errorMessage');
    } finally {
      _isLoading = false;
      stopwatch.stop();
      _lastLoadDuration = stopwatch.elapsedMilliseconds / 1000;
      notifyListeners();

      // Stop loading animation
      if (_loadingAnimation != null) {
        _loadingAnimation!.stop();
      }
    }
  }

  // Load all models from assets
  Future<void> _loadModelsFromAssets() async {
    try {
      // Load easy model
      try {
        final ByteData easyModelData = await rootBundle.load('assets/models/${ModelConstants.easyModelFileName}');
        _easyModelData = easyModelData.buffer.asUint8List();
        debugPrint('Easy model loaded from assets: ${_easyModelData?.length} bytes');
      } catch (e) {
        debugPrint('Error loading easy model from assets: $e');
      }

      // Load medium model (this is the required one)
      try {
        final ByteData mediumModelData = await rootBundle.load('assets/models/${ModelConstants.mediumModelFileName}');
        _mediumModelData = mediumModelData.buffer.asUint8List();
        debugPrint('Medium model loaded from assets: ${_mediumModelData?.length} bytes');
      } catch (e) {
        debugPrint('Error loading medium model from assets: $e');
      }

      // Load hard model
      try {
        final ByteData hardModelData = await rootBundle.load('assets/models/${ModelConstants.hardModelFileName}');
        _hardModelData = hardModelData.buffer.asUint8List();
        debugPrint('Hard model loaded from assets: ${_hardModelData?.length} bytes');
      } catch (e) {
        debugPrint('Error loading hard model from assets: $e');
      }

      _loadingProgress = 0.7;
      notifyListeners();
    } catch (e) {
      debugPrint('Error in _loadModelsFromAssets: $e');
    }
  }

  // Load models from cache
  Future<void> _loadModelsFromCache() async {
    if (kIsWeb) return; // Web platform doesn't support file caching

    try {
      final cacheDir = await _getCacheDirectory();

      // Try to load each model from cache
      try {
        final easyModelFile = File('${cacheDir.path}/${ModelConstants.easyModelFileName}');
        if (await easyModelFile.exists()) {
          _easyModelData = await easyModelFile.readAsBytes();
          debugPrint('Easy model loaded from cache: ${_easyModelData?.length} bytes');
        }
      } catch (e) {
        debugPrint('Error loading easy model from cache: $e');
      }

      try {
        final mediumModelFile = File('${cacheDir.path}/${ModelConstants.mediumModelFileName}');
        if (await mediumModelFile.exists()) {
          _mediumModelData = await mediumModelFile.readAsBytes();
          debugPrint('Medium model loaded from cache: ${_mediumModelData?.length} bytes');
        }
      } catch (e) {
        debugPrint('Error loading medium model from cache: $e');
      }

      try {
        final hardModelFile = File('${cacheDir.path}/${ModelConstants.hardModelFileName}');
        if (await hardModelFile.exists()) {
          _hardModelData = await hardModelFile.readAsBytes();
          debugPrint('Hard model loaded from cache: ${_hardModelData?.length} bytes');
        }
      } catch (e) {
        debugPrint('Error loading hard model from cache: $e');
      }

      // Check if cached models are expired
      final prefs = await SharedPreferences.getInstance();
      final cachedTimestampMillis = prefs.getInt(ModelConstants.modelCacheKey);

      if (cachedTimestampMillis != null) {
        final cachedTimestamp = DateTime.fromMillisecondsSinceEpoch(cachedTimestampMillis);
        final now = DateTime.now();

        // If cache is expired, clear loaded models to force refresh
        if (now.difference(cachedTimestamp) >= ModelConstants.modelCacheExpiration) {
          debugPrint('Cached models expired, will reload');
          _easyModelData = null;
          _mediumModelData = null;
          _hardModelData = null;
        } else {
          _modelTimestamp = cachedTimestamp;
        }
      }
    } catch (e) {
      debugPrint('Error in _loadModelsFromCache: $e');
    }
  }

  // Cache all loaded models
  Future<void> _cacheModels() async {
    if (kIsWeb) return; // Web platform doesn't support file caching

    try {
      final cacheDir = await _getCacheDirectory();
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      _modelTimestamp = now;

      // Cache easy model if available
      if (_easyModelData != null) {
        final easyModelFile = File('${cacheDir.path}/${ModelConstants.easyModelFileName}');
        await easyModelFile.writeAsBytes(_easyModelData!);
        debugPrint('Easy model cached');
      }

      // Cache medium model if available
      if (_mediumModelData != null) {
        final mediumModelFile = File('${cacheDir.path}/${ModelConstants.mediumModelFileName}');
        await mediumModelFile.writeAsBytes(_mediumModelData!);
        debugPrint('Medium model cached');
      }

      // Cache hard model if available
      if (_hardModelData != null) {
        final hardModelFile = File('${cacheDir.path}/${ModelConstants.hardModelFileName}');
        await hardModelFile.writeAsBytes(_hardModelData!);
        debugPrint('Hard model cached');
      }

      // Save timestamp for expiration check
      await prefs.setInt(ModelConstants.modelCacheKey, now.millisecondsSinceEpoch);

      // Calculate and store model hash (using medium model)
      if (_mediumModelData != null) {
        _modelHash = _calculateModelHash(_mediumModelData!);
        await prefs.setString(ModelConstants.modelHashKey, _modelHash);
      }
    } catch (e) {
      debugPrint('Error caching models: $e');
    }
  }

  // Download model from remote URL
  Future<Uint8List?> _downloadModel(String url) async {
    try {
      // Create a timeout for the download
      final timeoutCompleter = Completer<Uint8List?>();

      // Start the timeout timer
      Timer(ModelConstants.loadTimeout, () {
        if (!timeoutCompleter.isCompleted) {
          timeoutCompleter.complete(null);
          debugPrint('Download timeout for URL: $url');
        }
      });

      // Attempt download
      final response = await http.get(Uri.parse(url))
          .timeout(ModelConstants.loadTimeout);

      if (response.statusCode == 200) {
        debugPrint('Model downloaded from: $url (${response.bodyBytes.length} bytes)');

        // Complete with downloaded data
        if (!timeoutCompleter.isCompleted) {
          timeoutCompleter.complete(Uint8List.fromList(response.bodyBytes));
        }
        return await timeoutCompleter.future;
      } else {
        debugPrint('Failed to download model: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error downloading model from $url: $e');
      return null;
    }
  }

  // Get appropriate cache directory
  Future<Directory> _getCacheDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Web platform does not support file caching');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/model_cache');

    // Create directory if it doesn't exist
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir;
  }

  // Calculate simple model hash for integrity check
  String _calculateModelHash(Uint8List data) {
    // Simple hash calculation - in production you'd use a proper hash algorithm
    int hash = 0;
    for (int i = 0; i < math.min(data.length, 1000); i++) {
      hash = (hash * 31 + data[i]) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  // Legacy method for backward compatibility
  Future<Uint8List?> getModelBytes() async {
    if (!_isInitialized && !_hasError) {
      await initialize();
    }
    return _activeModelData;
  }

  // Set animation controllers from external widgets
  void setAnimationControllers(AnimationController? loadingController, AnimationController? errorController) {
    _loadingAnimation = loadingController;
    _errorAnimation = errorController;
    notifyListeners();
  }

  // Force reload the model
  Future<void> reloadModel() async {
    _isInitialized = false;
    _easyModelData = null;
    _mediumModelData = null;
    _hardModelData = null;
    _activeModelData = null;
    _hasError = false;
    _errorMessage = "";
    notifyListeners();

    await initialize();
  }

  // Clear cached model
  Future<void> clearCache() async {
    if (kIsWeb) return;

    try {
      final cacheDir = await _getCacheDirectory();

      // Delete each model file
      try {
        final easyModelFile = File('${cacheDir.path}/${ModelConstants.easyModelFileName}');
        if (await easyModelFile.exists()) {
          await easyModelFile.delete();
        }
      } catch (e) {
        debugPrint('Error deleting easy model cache: $e');
      }

      try {
        final mediumModelFile = File('${cacheDir.path}/${ModelConstants.mediumModelFileName}');
        if (await mediumModelFile.exists()) {
          await mediumModelFile.delete();
        }
      } catch (e) {
        debugPrint('Error deleting medium model cache: $e');
      }

      try {
        final hardModelFile = File('${cacheDir.path}/${ModelConstants.hardModelFileName}');
        if (await hardModelFile.exists()) {
          await hardModelFile.delete();
        }
      } catch (e) {
        debugPrint('Error deleting hard model cache: $e');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(ModelConstants.modelCacheKey);
      await prefs.remove(ModelConstants.modelHashKey);

      _loadingStatus = "Cache cleared";
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  // Get model information for display
  Map<String, String> getModelInfo() {
    String currentDifficulty = "Unknown";
    switch (_activeDifficulty) {
      case GameDifficulty.easy:
        currentDifficulty = "Easy";
        break;
      case GameDifficulty.medium:
        currentDifficulty = "Medium";
        break;
      case GameDifficulty.hard:
        currentDifficulty = "Hard";
        break;
      case GameDifficulty.custom:
        currentDifficulty = "Custom";
        break;
    }

    return {
      'Version': ModelConstants.modelVersion,
      'Training Date': ModelConstants.modelTrainingDate,
      'Framework': ModelConstants.modelFramework,
      'Training Steps': ModelConstants.modelTrainingSteps.toString(),
      'Active Model': currentDifficulty,
      'Source': _modelSource,
      'Size': modelSize,
      'Last Loaded': _modelTimestamp?.toString().split('.')[0] ?? 'Never',
      'Status': _isInitialized ? 'Loaded' : (_hasError ? 'Error' : 'Not Loaded'),
    };
  }

  // Get model metrics for display
  Map<String, String> getModelMetrics() {
    return {
      'Accuracy': '${(ModelConstants.modelAccuracy * 100).toStringAsFixed(1)}%',
      'Response Time': '${ModelConstants.modelResponseTime} ms',
      'Win Rate': '${(ModelConstants.modelWinRate * 100).toStringAsFixed(1)}%',
    };
  }

  // Widget to display model loading status
  Widget buildLoadingWidget({double size = 150}) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: size * 0.9,
            height: size * 0.9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.7),
              border: Border.all(
                color: _hasError
                    ? Colors.red.withOpacity(0.7)
                    : const Color(0xFF00C6FF).withOpacity(0.5),
                width: 2,
              ),
            ),
          ),

          // Loading progress indicator
          SizedBox(
            width: size * 0.8,
            height: size * 0.8,
            child: CircularProgressIndicator(
              value: _isLoading ? null : (_hasError ? 0 : 1),
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(
                _hasError ? Colors.red : const Color(0xFF00C6FF),
              ),
              backgroundColor: Colors.black.withOpacity(0.3),
            ),
          ),

          // Neural network animation (simplified)
          if (!_hasError)
            CustomPaint(
              size: Size(size * 0.7, size * 0.7),
              painter: ModelNetworkPainter(
                animationValue: _loadingAnimation?.value ?? 0.0,
                isLoading: _isLoading,
              ),
            ),

          // Error icon
          if (_hasError)
            Icon(
              Icons.error_outline,
              size: size * 0.3,
              color: Colors.red,
            ).animate(
              onPlay: (controller) => controller.repeat(reverse: true),
            ).fade(
              duration: 700.ms,
              begin: 0.6,
              end: 1.0,
            ),

          // Status text
          Positioned(
            bottom: size * 0.15,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                _hasError ? "Load Error" : _loadingStatus,
                style: TextStyle(
                  color: _hasError
                      ? Colors.red
                      : Colors.white.withOpacity(0.9),
                  fontSize: size * 0.1,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget to display model information card
  Widget buildModelInfoCard({double width = 300}) {
    final modelInfo = getModelInfo();
    final modelMetrics = getModelMetrics();

    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00C6FF).withOpacity(0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C6FF).withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.memory,
                color: const Color(0xFF00C6FF),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                "AI MODEL INFO",
                style: TextStyle(
                  color: const Color(0xFF00C6FF),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isInitialized
                      ? Colors.green
                      : (_hasError ? Colors.red : Colors.orange),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF00C6FF), height: 24, thickness: 1),

          // Model details
          ...modelInfo.entries.map((entry) => _buildInfoRow(entry.key, entry.value)),

          const SizedBox(height: 16),
          Text(
            "PERFORMANCE METRICS",
            style: TextStyle(
              color: const Color(0xFF00C6FF),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Metrics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: modelMetrics.entries.map((entry) =>
                _buildMetricBox(entry.key, entry.value)
            ).toList(),
          ),

          const SizedBox(height: 16),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!_isInitialized || _hasError)
                _buildActionButton(
                  "Load",
                  Icons.download,
                  onTap: () => initialize(),
                ),
              const SizedBox(width: 8),
              _buildActionButton(
                "Reload",
                Icons.refresh,
                onTap: () => reloadModel(),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                "Clear Cache",
                Icons.delete_outline,
                onTap: () => clearCache(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper to build info row
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Helper to build metric box
  Widget _buildMetricBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF00C6FF).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF00C6FF),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Helper to build action button
  Widget _buildActionButton(
      String label,
      IconData icon, {
        required VoidCallback onTap,
      }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF00C6FF).withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF00C6FF), size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF00C6FF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Network visualization for the model loader
class ModelNetworkPainter extends CustomPainter {
  final double animationValue;
  final bool isLoading;

  ModelNetworkPainter({
    required this.animationValue,
    required this.isLoading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Define nodes in the network
    final nodes = <Offset>[
      // Input layer
      Offset(center.dx - size.width * 0.3, center.dy - size.height * 0.2),
      Offset(center.dx - size.width * 0.3, center.dy + size.height * 0.2),

      // Hidden layer
      center,
      Offset(center.dx, center.dy - size.height * 0.25),
      Offset(center.dx, center.dy + size.height * 0.25),

      // Output layer
      Offset(center.dx + size.width * 0.3, center.dy - size.height * 0.2),
      Offset(center.dx + size.width * 0.3, center.dy + size.height * 0.2),
    ];

    // Draw connections between nodes
    final connectionPaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Define connections - which nodes should connect to which
    final connections = [
      // Input to hidden connections
      [0, 2], [0, 3], [0, 4],
      [1, 2], [1, 3], [1, 4],

      // Hidden to output connections
      [2, 5], [2, 6],
      [3, 5], [3, 6],
      [4, 5], [4, 6],
    ];

    // Draw connections with animated data flow effect
    for (final conn in connections) {
      final start = nodes[conn[0]];
      final end = nodes[conn[1]];

      // Create animated flow effect
      final progress = (animationValue + conn[0] * 0.1 + conn[1] * 0.1) % 1.0;
      final flowPoint = Offset(
        start.dx + (end.dx - start.dx) * progress,
        start.dy + (end.dy - start.dy) * progress,
      );

      // Draw line
      connectionPaint.color = const Color(0xFF00C6FF).withOpacity(0.3);
      canvas.drawLine(start, end, connectionPaint);

      // Draw flowing data point if loading
      if (isLoading) {
        final flowPaint = Paint()
          ..color = const Color(0xFF00C6FF)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(flowPoint, 2, flowPaint);
      }
    }

    // Draw nodes
    for (var i = 0; i < nodes.length; i++) {
      // Node glow
      final glowPaint = Paint()
        ..color = const Color(0xFF00C6FF).withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      // Animate node glow based on time and position
      final glowIntensity = 0.3 + 0.2 * math.sin(animationValue * math.pi * 2 + i);
      if (isLoading || i % 2 == 0) {
        canvas.drawCircle(nodes[i], 6 * glowIntensity, glowPaint);
      }

      // Node fill
      final nodePaint = Paint()
        ..color = const Color(0xFF00C6FF).withOpacity(0.7)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(nodes[i], 3, nodePaint);
    }
  }

  @override
  bool shouldRepaint(ModelNetworkPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
          oldDelegate.isLoading != isLoading;
}
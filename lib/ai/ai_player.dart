import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:provider/provider.dart';

import '../game/physics.dart';
import '../main.dart';
import 'model_loader.dart';

// Enum for AI difficulty levels
enum AILevel {
  beginner,    // Makes obvious mistakes, slow reactions
  intermediate, // Balanced AI with occasional mistakes
  expert,      // Fast reactions, good prediction, few mistakes
  unbeatable,  // Nearly perfect prediction and reactions
  adaptive     // Adapts to player skill level
}

// AI player behavior constants
class AIConstants {
  // Reaction time in seconds (how quickly AI responds to ball direction changes)
  static const double beginnerReactionTime = 0.5;
  static const double intermediateReactionTime = 0.3;
  static const double expertReactionTime = 0.15;
  static const double unbeatableReactionTime = 0.08;

  // Prediction error scales (higher = more mistakes in predicting ball position)
  static const double beginnerPredictionError = 0.4;    // 40% error
  static const double intermediatePredictionError = 0.2; // 20% error
  static const double expertPredictionError = 0.08;      // 8% error
  static const double unbeatablePredictionError = 0.02;  // 2% error

  // Movement speed scaling factors
  static const double beginnerSpeedScale = 0.7;
  static const double intermediateSpeedScale = 0.9;
  static const double expertSpeedScale = 1.0;
  static const double unbeatableSpeedScale = 1.1;

  // Paddle positioning biases (where on the paddle the AI tries to hit the ball)
  static const double centerBias = 0.5;  // Center of paddle
  static const double topBias = 0.25;    // Upper quarter
  static const double bottomBias = 0.75; // Lower quarter

  // How many frames to look ahead in prediction
  static const int predictionFrames = 60;

  // Adaptation constants
  static const int adaptiveWindowSize = 20;  // Number of points to consider
  static const double adaptiveAdjustRate = 0.05; // How quickly to adjust difficulty

  // Neural net input normalization constants
  static const double gameWidthNorm = 800.0;
  static const double gameHeightNorm = 600.0;
  static const double velocityNorm = 15.0;
}

/// AIPlayer class that handles the AI opponent logic in the game
class AIPlayer extends ChangeNotifier {
  // The difficulty level of the AI
  AILevel _difficultyLevel = AILevel.intermediate;

  // Settings-related properties
  double _ballSpeedMultiplier = 1.0;
  GameDifficulty _currentGameDifficulty = GameDifficulty.medium;

  // Current parameters
  double _reactionTime = AIConstants.intermediateReactionTime;
  double _predictionError = AIConstants.intermediatePredictionError;
  double _speedScale = AIConstants.intermediateSpeedScale;
  double _positionBias = AIConstants.centerBias;

  // AI state
  double _targetY = 0.0;
  double _lastPredictedY = 0.0;
  double _lastBallDirectionX = 0.0;
  double _lastReactionTime = 0.0;
  double _adaptiveDifficulty = 0.5; // 0.0 = easiest, 1.0 = hardest

  // Debug visualization properties
  bool _showDebug = false;
  final List<Offset> _predictedPath = [];
  double _predictionConfidence = 1.0;

  // For adaptive AI
  final List<bool> _recentPoints = [];
  int _playerWins = 0;
  int _aiWins = 0;

  // Neural network model
  tfl.Interpreter? _interpreter;
  bool _isModelLoaded = false;

  // Game dimensions - will be updated based on screen size
  double _gameWidth = AIConstants.gameWidthNorm;
  double _gameHeight = AIConstants.gameHeightNorm;

  // Animation controller for visualizing AI "thinking"
  AnimationController? _thinkingAnimation;

  // Model loader reference
  final ModelLoader _modelLoader;

  // Constructor
  AIPlayer(
      this._modelLoader, {
        GameDifficulty difficulty = GameDifficulty.medium,
      }) {
    // Set initial difficulty based on the game's difficulty setting
    _currentGameDifficulty = difficulty;
    _setDifficultyFromGameSetting(difficulty);

    // Load the AI model
    _loadModelForDifficulty(difficulty);
  }

  // Set the animation controller from external widgets
  void setAnimationController(AnimationController controller) {
    _thinkingAnimation = controller;
    notifyListeners();
  }

  // Method to handle settings updates
  void updateFromSettings(GameSettings settings) {
    // Update difficulty if it changed
    if (_currentGameDifficulty != settings.difficulty) {
      _currentGameDifficulty = settings.difficulty;
      _setDifficultyFromGameSetting(settings.difficulty);

      // Load the appropriate model for the new difficulty
      _loadModelForDifficulty(settings.difficulty);
    }

    // Update ball speed multiplier
    _ballSpeedMultiplier = 0.7 + (settings.ballSpeed * 0.6); // Map 0-1 to 0.7-1.3

    // Update visualization debug setting
    _showDebug = settings.showAIDebug;

    debugPrint('AI settings updated: difficulty=${settings.difficulty}, ball speed=${_ballSpeedMultiplier}, debug=${_showDebug}');
    notifyListeners();
  }

  // Load the appropriate model for the given difficulty
  Future<void> _loadModelForDifficulty(GameDifficulty difficulty) async {
    try {
      // Get model bytes for the current difficulty from ModelLoader
      final modelBytes = _modelLoader.getModelForDifficulty(difficulty);

      if (modelBytes != null) {
        // Close previous interpreter if it exists
        _interpreter?.close();

        // Load interpreter from bytes
        _interpreter = await tfl.Interpreter.fromBuffer(modelBytes);
        _isModelLoaded = true;
        debugPrint('AI model loaded successfully for difficulty: $difficulty');
      } else {
        debugPrint('No AI model available for $difficulty, using rule-based AI');
        _isModelLoaded = false;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading AI model for $difficulty: $e');
      _isModelLoaded = false;
      notifyListeners();
    }
  }

  // Legacy method for backward compatibility
  Future<void> _loadModel() async {
    await _loadModelForDifficulty(_currentGameDifficulty);
  }

  // Clean up resources
  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }

  // Update the game dimensions when screen size changes
  void updateGameDimensions(double width, double height) {
    _gameWidth = width;
    _gameHeight = height;
  }

  // Set the difficulty level
  void setDifficulty(AILevel level) {
    _difficultyLevel = level;

    // Update AI parameters based on difficulty
    switch (level) {
      case AILevel.beginner:
        _reactionTime = AIConstants.beginnerReactionTime;
        _predictionError = AIConstants.beginnerPredictionError;
        _speedScale = AIConstants.beginnerSpeedScale;
        break;

      case AILevel.intermediate:
        _reactionTime = AIConstants.intermediateReactionTime;
        _predictionError = AIConstants.intermediatePredictionError;
        _speedScale = AIConstants.intermediateSpeedScale;
        break;

      case AILevel.expert:
        _reactionTime = AIConstants.expertReactionTime;
        _predictionError = AIConstants.expertPredictionError;
        _speedScale = AIConstants.expertSpeedScale;
        break;

      case AILevel.unbeatable:
        _reactionTime = AIConstants.unbeatableReactionTime;
        _predictionError = AIConstants.unbeatablePredictionError;
        _speedScale = AIConstants.unbeatableSpeedScale;
        break;

      case AILevel.adaptive:
      // Start with intermediate settings for adaptive
        _reactionTime = AIConstants.intermediateReactionTime;
        _predictionError = AIConstants.intermediatePredictionError;
        _speedScale = AIConstants.intermediateSpeedScale;
        break;
    }

    notifyListeners();
  }

  // Map GameDifficulty enum to AILevel
  void _setDifficultyFromGameSetting(GameDifficulty difficulty) {
    switch (difficulty) {
      case GameDifficulty.easy:
        setDifficulty(AILevel.beginner);
        break;
      case GameDifficulty.medium:
        setDifficulty(AILevel.intermediate);
        break;
      case GameDifficulty.hard:
        setDifficulty(AILevel.expert);
        break;
      case GameDifficulty.custom:
        setDifficulty(AILevel.adaptive);
        break;
    }
  }

  // Toggle debug visualization
  void toggleDebug() {
    _showDebug = !_showDebug;
    notifyListeners();
  }

  // Get the current show debug state
  bool get showDebug => _showDebug;

  // Record point outcome for adaptive AI
  void recordPoint(bool playerWon) {
    if (_difficultyLevel == AILevel.adaptive) {
      // Keep track of recent points
      _recentPoints.add(playerWon);
      if (_recentPoints.length > AIConstants.adaptiveWindowSize) {
        _recentPoints.removeAt(0);
      }

      // Update win counters
      if (playerWon) {
        _playerWins++;
      } else {
        _aiWins++;
      }

      // Calculate win rate over the recent window
      int playerWins = _recentPoints.where((won) => won).length;
      double playerWinRate = playerWins / _recentPoints.length;

      // Adjust difficulty based on player performance
      if (playerWinRate > 0.6) {
        // Player is winning too much, increase difficulty
        _adaptiveDifficulty = math.min(1.0, _adaptiveDifficulty + AIConstants.adaptiveAdjustRate);
      } else if (playerWinRate < 0.4) {
        // AI is winning too much, decrease difficulty
        _adaptiveDifficulty = math.max(0.0, _adaptiveDifficulty - AIConstants.adaptiveAdjustRate);
      }

      // Update AI parameters based on adaptive difficulty
      _updateAdaptiveParameters();
    }
  }

  // Update AI parameters for adaptive difficulty
  void _updateAdaptiveParameters() {
    // Interpolate between beginner and expert settings
    _reactionTime = _lerp(
        AIConstants.beginnerReactionTime,
        AIConstants.expertReactionTime,
        _adaptiveDifficulty
    );

    _predictionError = _lerp(
        AIConstants.beginnerPredictionError,
        AIConstants.expertPredictionError,
        _adaptiveDifficulty
    );

    _speedScale = _lerp(
        AIConstants.beginnerSpeedScale,
        AIConstants.expertSpeedScale,
        _adaptiveDifficulty
    );
  }

  // Linear interpolation helper
  double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  // Calculate the next move for the AI paddle
  double calculateMove(
      double ballX,
      double ballY,
      double ballVelocityX,
      double ballVelocityY,
      double paddleY,
      double paddleHeight,
      double opponentPaddleY,
      int aiScore,
      int playerScore,
      double deltaTime
      ) {
    // Start thinking animation if available
    if (_thinkingAnimation != null && ballVelocityX < 0) {
      _thinkingAnimation!.repeat(reverse: true);
    } else if (_thinkingAnimation != null) {
      _thinkingAnimation!.stop();
    }

    // Calculate target position using different methods depending on configuration
    double targetY;

    // Reset prediction path if ball direction changes
    if ((ballVelocityX < 0 && _lastBallDirectionX >= 0) ||
        (ballVelocityX > 0 && _lastBallDirectionX <= 0)) {
      _predictedPath.clear();
      _lastReactionTime = _reactionTime;
    }

    // Store ball direction for next frame
    _lastBallDirectionX = ballVelocityX;

    // Apply ball speed multiplier to predictions
    // This helps the AI account for different ball speeds from settings
    double adjustedBallVelocityX = ballVelocityX;
    double adjustedBallVelocityY = ballVelocityY;

    // If ball is moving toward AI paddle (negative X velocity)
    if (ballVelocityX < 0) {
      if (_isModelLoaded) {
        // Use neural network for prediction
        targetY = _getPredictionFromModel(
            ballX,
            ballY,
            adjustedBallVelocityX,
            adjustedBallVelocityY,
            paddleY,
            opponentPaddleY,
            aiScore,
            playerScore
        );
      } else {
        // Use physics-based prediction
        targetY = _predictBallPosition(
            ballX,
            ballY,
            adjustedBallVelocityX,
            adjustedBallVelocityY,
            paddleHeight
        );
      }

      // Apply reaction time simulation
      _lastReactionTime -= deltaTime;
      if (_lastReactionTime <= 0) {
        _lastPredictedY = targetY;
        _lastReactionTime = _reactionTime;
      } else {
        // Smoothly interpolate to new prediction
        targetY = _lerp(_lastPredictedY, targetY, 1 - (_lastReactionTime / _reactionTime));
      }
    } else {
      // Ball moving away - default to a neutral defensive position
      targetY = _getDefensivePosition(paddleHeight);
    }

    // Apply difficulty-based error to target
    targetY = _applyPredictionError(targetY, paddleHeight);

    // Store target for external visualization
    _targetY = targetY;

    // Return the adjusted paddle position (centered on target)
    return targetY - (paddleHeight / 2);
  }

  // Get prediction using neural network
  double _getPredictionFromModel(
      double ballX,
      double ballY,
      double ballVelocityX,
      double ballVelocityY,
      double paddleY,
      double opponentPaddleY,
      int aiScore,
      int playerScore
      ) {
    // Check if model is available
    if (_interpreter == null) {
      return _predictBallPosition(ballX, ballY, ballVelocityX, ballVelocityY, 100);
    }

    try {
      // Prepare input tensor (normalize values)
      var input = [
        ballX / _gameWidth,
        ballY / _gameHeight,
        ballVelocityX / AIConstants.velocityNorm,
        ballVelocityY / AIConstants.velocityNorm,
        paddleY / _gameHeight,
        opponentPaddleY / _gameHeight,
        aiScore / 10.0, // Normalize score
        playerScore / 10.0 // Normalize score
      ];

      // Reshape for model input
      var inputData = Float32List.fromList(input);
      var inputShape = [1, input.length];
      var inputBuffer = [inputData];

      // Prepare output tensor
      var outputShape = [1, 3]; // [up, stay, down] probabilities
      var outputBuffer = List.filled(1 * 3, 0.0).reshape(outputShape);

      // Run inference
      _interpreter!.run(inputBuffer, outputBuffer);

      // Get results
      var output = outputBuffer[0];

      // Find the highest probability action
      int actionIndex = 0;
      double maxProb = output[0];
      for (int i = 1; i < output.length; i++) {
        if (output[i] > maxProb) {
          maxProb = output[i];
          actionIndex = i;
        }
      }

      // Set confidence for visualization
      _predictionConfidence = maxProb;

      // Convert action to paddle movement
      // 0 = up, 1 = stay, 2 = down
      double currentY = paddleY;
      switch (actionIndex) {
        case 0: // Move up
          return math.max(0, currentY - 50);
        case 2: // Move down
          return math.min(_gameHeight - 100, currentY + 50);
        case 1: // Stay
        default:
          return currentY;
      }
    } catch (e) {
      debugPrint('Error running AI model: $e');
      // Fallback to physics-based prediction
      return _predictBallPosition(ballX, ballY, ballVelocityX, ballVelocityY, 100);
    }
  }

  // Physics-based ball position prediction
  double _predictBallPosition(
      double ballX,
      double ballY,
      double ballVelocityX,
      double ballVelocityY,
      double paddleHeight
      ) {
    // Clear previous prediction path
    if (_predictedPath.isEmpty) {
      _predictedPath.clear();

      // Store current position as first point
      _predictedPath.add(Offset(ballX, ballY));

      // Calculate time until ball reaches paddle
      double paddleX = 20 + 15; // Left paddle x position + width
      double timeToReach = ballVelocityX != 0 ? (paddleX - ballX) / ballVelocityX : 0;

      if (timeToReach > 0) {
        // Simulate ball path, accounting for bounces
        double simX = ballX;
        double simY = ballY;
        double simVelocityX = ballVelocityX;
        double simVelocityY = ballVelocityY;
        double simTimeStep = timeToReach / 10; // Divide into 10 simulation steps

        for (int i = 0; i < AIConstants.predictionFrames && simX > paddleX; i++) {
          // Update position
          simX += simVelocityX * simTimeStep;
          simY += simVelocityY * simTimeStep;

          // Bounce off top and bottom walls
          if (simY < 0) {
            simY = -simY;
            simVelocityY = -simVelocityY;
          } else if (simY > _gameHeight) {
            simY = 2 * _gameHeight - simY;
            simVelocityY = -simVelocityY;
          }

          // Store prediction point
          _predictedPath.add(Offset(simX, simY));

          // Stop if we've reached the paddle
          if (simX <= paddleX) {
            break;
          }
        }
      }
    }

    // If we have a prediction path, use the final point
    if (_predictedPath.isNotEmpty && _predictedPath.last.dx <= 35) {
      // Apply position bias (aim for specific part of paddle)
      double targetY = _predictedPath.last.dy - (paddleHeight * _positionBias);
      return targetY;
    }

    // Fallback if prediction fails - aim at the ball directly
    return ballY - (paddleHeight * _positionBias);
  }

  // Get a defensive position when ball is moving away
  double _getDefensivePosition(double paddleHeight) {
    // Return to vertical center, with slight bias based on difficulty
    return (_gameHeight - paddleHeight) / 2 +
        (math.Random().nextDouble() * 2 - 1) * _gameHeight * 0.1 * _predictionError;
  }

  // Apply prediction error based on difficulty
  double _applyPredictionError(double targetY, double paddleHeight) {
    // Add random error proportional to difficulty
    double maxError = _gameHeight * _predictionError;
    double error = (math.Random().nextDouble() * 2 - 1) * maxError;

    // Apply error and clamp to game bounds
    double resultY = targetY + error;

    // Ensure paddle stays within game bounds
    resultY = math.max(0, math.min(_gameHeight - paddleHeight, resultY));

    return resultY;
  }

  // Get current AI stats for display/debugging
  Map<String, dynamic> getStats() {
    return {
      'difficulty': _difficultyLevel.toString().split('.').last,
      'game_difficulty': _currentGameDifficulty.toString().split('.').last,
      'reaction_time': _reactionTime.toStringAsFixed(3),
      'prediction_error': (_predictionError * 100).toStringAsFixed(1) + '%',
      'ball_speed_mult': _ballSpeedMultiplier.toStringAsFixed(2),
      'adaptive_level': _difficultyLevel == AILevel.adaptive
          ? (_adaptiveDifficulty * 100).toStringAsFixed(1) + '%'
          : 'N/A',
      'model_active': _isModelLoaded,
      'prediction_confidence': (_predictionConfidence * 100).toStringAsFixed(1) + '%',
      'win_ratio': _aiWins + _playerWins > 0
          ? (_aiWins / (_aiWins + _playerWins) * 100).toStringAsFixed(1) + '%'
          : 'N/A',
    };
  }

  // Draw debug visualization
  void drawDebug(Canvas canvas, Size size) {
    if (!_showDebug) return;

    // Draw predicted path
    final pathPaint = Paint()
      ..color = Colors.blue.withOpacity(0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final targetPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Draw prediction path
    if (_predictedPath.length > 1) {
      final path = Path();
      path.moveTo(_predictedPath[0].dx, _predictedPath[0].dy);

      for (int i = 1; i < _predictedPath.length; i++) {
        path.lineTo(_predictedPath[i].dx, _predictedPath[i].dy);
      }

      canvas.drawPath(path, pathPaint);

      // Draw target point
      canvas.drawCircle(_predictedPath.last, 5, targetPaint);
    }

    // Draw target Y position
    canvas.drawLine(
      Offset(0, _targetY),
      Offset(30, _targetY),
      Paint()
        ..color = Colors.yellow
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Draw confidence meter
    final confPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.red, Colors.yellow, Colors.green],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, 100 * _predictionConfidence, 10));

    canvas.drawRect(
      Rect.fromLTWH(10, size.height - 20, 100 * _predictionConfidence, 10),
      confPaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(10, size.height - 20, 100, 10),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    // Draw game settings info
    TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: 'Model: ${_isModelLoaded ? _currentGameDifficulty.toString().split('.').last : "None"}\n'
            'Ball Speed: ${_ballSpeedMultiplier.toStringAsFixed(2)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(10, size.height - 50));
  }

  // AI "brain" visualization for UI
  Widget buildAIBrainVisualization() {
    return Builder(
        builder: (context) {
          return Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.7),
              border: Border.all(
                color: _getAIColor(),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: _getAIColor().withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Neural network visualization
                CustomPaint(
                  painter: NeuralNetworkPainter(
                    animationValue: _thinkingAnimation?.value ?? 0.0,
                    color: _getAIColor(),
                    intensity: _predictionConfidence,
                  ),
                ),

                // AI icon
                Center(
                  child: Icon(
                    Icons.psychology,
                    color: _getAIColor(),
                    size: 48,
                  ),
                ),

                // Difficulty indicator
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black.withOpacity(0.7),
                    ),
                    child: Text(
                      _getDifficultyText(),
                      style: TextStyle(
                        color: _getAIColor(),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Model status indicator
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isModelLoaded ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
    );
  }

  // Get AI color based on difficulty
  Color _getAIColor() {
    switch (_difficultyLevel) {
      case AILevel.beginner:
        return Colors.green;
      case AILevel.intermediate:
        return Colors.yellow;
      case AILevel.expert:
        return Colors.orange;
      case AILevel.unbeatable:
        return Colors.red;
      case AILevel.adaptive:
      // Gradient from green to red based on adaptive difficulty
        if (_adaptiveDifficulty < 0.3) return Colors.green;
        if (_adaptiveDifficulty < 0.7) return Colors.yellow;
        return Colors.orange;
    }
  }

  // Get difficulty text
  String _getDifficultyText() {
    switch (_difficultyLevel) {
      case AILevel.beginner:
        return 'BEGINNER';
      case AILevel.intermediate:
        return 'INTERMEDIATE';
      case AILevel.expert:
        return 'EXPERT';
      case AILevel.unbeatable:
        return 'UNBEATABLE';
      case AILevel.adaptive:
      // Show percentage for adaptive
        return 'ADAPTIVE ${(_adaptiveDifficulty * 100).toStringAsFixed(0)}%';
    }
  }
}

// Neural network visualization painter
class NeuralNetworkPainter extends CustomPainter {
  final double animationValue;
  final Color color;
  final double intensity;

  NeuralNetworkPainter({
    required this.animationValue,
    required this.color,
    this.intensity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Define layers of neurons
    const layers = 3;
    const neuronsPerLayer = [4, 6, 3];
    final List<List<Offset>> neuronPositions = [];

    // Calculate neuron positions for each layer
    for (int layer = 0; layer < layers; layer++) {
      final layerNeurons = <Offset>[];
      final layerOffset = (layer / (layers - 1)) * size.width * 0.8 - size.width * 0.4;

      for (int n = 0; n < neuronsPerLayer[layer]; n++) {
        final heightOffset = (n / (neuronsPerLayer[layer] - 1)) * size.height * 0.6 - size.height * 0.3;
        layerNeurons.add(Offset(
          center.dx + layerOffset,
          center.dy + heightOffset,
        ));
      }

      neuronPositions.add(layerNeurons);
    }

    // Draw connections between neurons
    final linePaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw connections between layers
    for (int layer = 0; layer < layers - 1; layer++) {
      for (final startNeuron in neuronPositions[layer]) {
        for (final endNeuron in neuronPositions[layer + 1]) {
          // Use animation value to create pulsing/flowing effect
          final pulseOffset = (math.sin(animationValue * math.pi * 2 +
              startNeuron.dy / 10 +
              endNeuron.dy / 20) + 1) / 2;

          // Calculate color with gradient and animation
          final gradientPosition = (startNeuron.distance - endNeuron.distance).abs() / 100;
          final animatedColor = Color.lerp(
            color.withOpacity(0.1),
            color.withOpacity(0.7 * intensity),
            (pulseOffset + gradientPosition) / 2,
          )!;

          linePaint.color = animatedColor;

          canvas.drawLine(startNeuron, endNeuron, linePaint);
        }
      }
    }

    // Draw neurons
    for (int layer = 0; layer < layers; layer++) {
      for (int n = 0; n < neuronsPerLayer[layer]; n++) {
        final pos = neuronPositions[layer][n];

        // Create pulsing effect with animation
        final pulse = 0.8 + 0.4 * math.sin(
            animationValue * math.pi * 2 + layer + n / neuronsPerLayer[layer]
        );

        // Neuron glow
        final glowPaint = Paint()
          ..color = color.withOpacity(0.3 * intensity * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

        canvas.drawCircle(pos, 4 * pulse, glowPaint);

        // Neuron core
        final neuronPaint = Paint()
          ..color = Color.lerp(
              Colors.white.withOpacity(0.5),
              color.withOpacity(0.9),
              intensity * pulse
          )!
          ..style = PaintingStyle.fill;

        canvas.drawCircle(pos, 3 * pulse, neuronPaint);
      }
    }
  }

  @override
  bool shouldRepaint(NeuralNetworkPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
          oldDelegate.color != color ||
          oldDelegate.intensity != intensity;
}

// game/pong_game.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../main.dart';
import 'physics.dart';
import '../ai/ai_player.dart';

// Game colors
const Color kBallColor = Colors.white;
const Color kPlayerPaddleColor = Color(0xFF4CAF50);
const Color kAIPaddleColor = Color(0xFFFFEB3B);
const Color kAccentColor = Color(0xFF00C6FF);
const Color kNeonGlow = Color(0xFF00FFFF);
const Color kBackgroundColor = Color(0xFF121212);

// Game UI constants
const double kScoreTextSize = 48.0;
const double kGameInfoTextSize = 16.0;
const double kHitEffectDuration = 250; // milliseconds

class PongGame extends StatefulWidget {
  final GameDifficulty difficulty;
  final bool showDebug;
  final Function(int, int)? onScoreUpdate;
  final Function(bool)? onGameOver;

  const PongGame({
    Key? key,
    this.difficulty = GameDifficulty.medium,
    this.showDebug = false,
    this.onScoreUpdate,
    this.onGameOver,
  }) : super(key: key);

  @override
  State<PongGame> createState() => _PongGameState();
}

class _PongGameState extends State<PongGame> with TickerProviderStateMixin {
  // Game state
  late GameState _gameState;
  bool _isPaused = false;
  bool _isGameOver = false;
  bool _isCountingDown = false;
  int _countdown = 3;
  int _playerScore = 0;
  int _aiScore = 0;
  int _winningScore = 10;
  int _rallyCount = 0;
  int _maxRally = 0;
  String? _scoreMessage;

  // Physics and rendering
  late PhysicsEngine _physicsEngine;
  late PhysicsRenderer _physicsRenderer;

  // Screen dimensions
  double _gameWidth = 800;
  double _gameHeight = 600;
  Size? _lastSize;

  // Animation controllers
  late AnimationController _gameLoopController;
  late AnimationController _countdownController;
  late AnimationController _hitEffectController;
  late AnimationController _scoreEffectController;
  late AnimationController _powerUpController;
  late AnimationController _ambientController;

  // Game effects
  final List<ScoreEffect> _scoreEffects = [];
  final List<PowerUp> _powerUps = [];
  PowerUpType? _activePowerUp;
  double _powerUpTimeRemaining = 0;
  bool _ballSpeedBoost = false;
  bool _paddleSizeBoost = false;
  bool _reverseControls = false;

  // Audio players
  final AudioPlayer _sfxPlayer = AudioPlayer();
  final AudioPlayer _musicPlayer = AudioPlayer();
  bool _soundEnabled = true;

  // Debug info
  int _fps = 0;
  int _frameCount = 0;
  int _lastSecond = 0;

  // Input handling
  double? _touchYPosition;
  bool _isMouseDown = false;
  FocusNode _gameFocusNode = FocusNode();

  // AI difficulty
  double _aiDifficultyLevel = 0.5; // 0.0 = easiest, 1.0 = hardest
  double _aiReactionSpeed = 0.1;

  // Statistics
  int _aiHits = 0;
  int _aiMisses = 0;
  int _playerHits = 0;
  int _playerMisses = 0;

  // Frame timing
  int _lastFrameTime = 0;
  double _deltaTime = 0;

  // Special effects
  final GlobalKey _gameKey = GlobalKey();
  final List<Rect> _screenShakeRects = [];
  double _screenShakeIntensity = 0;

  @override
  void initState() {
    super.initState();

    // Initialize game state
    _gameState = GameState.ready;

    // Set up physics engine
    _physicsEngine = PhysicsEngine.standard();
    _physicsRenderer = PhysicsRenderer(_physicsEngine, showDebug: widget.showDebug);

    // Set AI difficulty
    _setDifficultyLevel(widget.difficulty);

    // Initialize animations
    _initializeAnimations();

    // Set up physics callbacks
    _setupPhysicsCallbacks();

    // Load audio assets
    _preloadAudio();

    // Focus handling for keyboard
    _gameFocusNode.requestFocus();

    // Start ambient animations
    _ambientController.repeat();

    // Start with countdown
    _startCountdown();
  }

  @override
  void didUpdateWidget(PongGame oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update debug setting if it changed
    _physicsRenderer = PhysicsRenderer(_physicsEngine, showDebug: widget.showDebug);

    // Update difficulty if it changed
    if (widget.difficulty != oldWidget.difficulty) {
      _setDifficultyLevel(widget.difficulty);
    }
  }

  @override
  void dispose() {
    // Dispose animation controllers
    _gameLoopController.dispose();
    _countdownController.dispose();
    _hitEffectController.dispose();
    _scoreEffectController.dispose();
    _powerUpController.dispose();
    _ambientController.dispose();

    // Dispose audio players
    _sfxPlayer.dispose();
    _musicPlayer.dispose();

    // Dispose focus node
    _gameFocusNode.dispose();

    super.dispose();
  }

  void _initializeAnimations() {
    // Main game loop animation
    _gameLoopController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_gameLoop);

    // Countdown animation
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(_updateCountdown);

    // Hit effect animation
    _hitEffectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Score effect animation
    _scoreEffectController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Power-up animation
    _powerUpController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    // Ambient background animation
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
  }

  void _setupPhysicsCallbacks() {
    // Handle paddle hits
    _physicsEngine.onPaddleHit = (isLeftPaddle) {
      _hitEffectController.forward(from: 0);

      // Play hit sound
      if (_soundEnabled) {
        _sfxPlayer.play(AssetSource('audio/paddle_hit.mp3'), volume: 0.7);
      }

      // Update statistics
      if (isLeftPaddle) {
        _aiHits++;
      } else {
        _playerHits++;
      }

      // Increment rally count
      _rallyCount++;
      if (_rallyCount > _maxRally) {
        _maxRally = _rallyCount;
      }

      // Trigger screen shake based on velocity
      _triggerScreenShake(0.3);
    };

    // Handle wall hits
    _physicsEngine.onWallHit = () {
      // Play wall hit sound
      if (_soundEnabled) {
        _sfxPlayer.play(AssetSource('audio/wall_hit.mp3'), volume: 0.5);
      }

      // Small screen shake
      _triggerScreenShake(0.1);
    };

    // Handle special hits (sweet spots, edges)
    _physicsEngine.onSpecialHit = (isLeftPaddle, hitZone) {
      // Play special hit sound based on hit zone
      if (_soundEnabled) {
        switch (hitZone) {
          case HitZone.sweetSpot:
            _sfxPlayer.play(AssetSource('audio/sweet_spot.mp3'), volume: 0.8);
            _triggerScreenShake(0.5);
            break;
          case HitZone.topEdge:
          case HitZone.bottomEdge:
            _sfxPlayer.play(AssetSource('audio/edge_hit.mp3'), volume: 0.7);
            _triggerScreenShake(0.4);
            break;
          default:
            break;
        }
      }

      // Spawn power-up randomly on special hits (15% chance)
      if (!isLeftPaddle && math.Random().nextDouble() < 0.15 && _powerUps.isEmpty) {
        _spawnPowerUp();
      }
    };

    // Handle scoring
    _physicsEngine.onScore = (isLeftPoint) {
      // Update score
      if (isLeftPoint) {
        _aiScore++;
        _aiMisses++;
        _showScoreMessage("AI SCORES");
      } else {
        _playerScore++;
        _playerMisses++;
        _showScoreMessage("YOU SCORE");
      }

      // Reset rally count
      _rallyCount = 0;

      // Play score sound
      if (_soundEnabled) {
        _sfxPlayer.play(AssetSource('audio/score.mp3'));
      }

      // Create score effect
      _createScoreEffect(isLeftPoint);

      // Trigger screen shake
      _triggerScreenShake(0.6);

      // Notify parent widget about score update
      if (widget.onScoreUpdate != null) {
        widget.onScoreUpdate!(_playerScore, _aiScore);
      }

      // Check for game over
      if (_playerScore >= _winningScore || _aiScore >= _winningScore) {
        _endGame();
      }
    };
  }

  void _preloadAudio() {
    // Preload sound effects
    AudioCache.instance.loadAll([
      'audio/paddle_hit.mp3',
      'audio/wall_hit.mp3',
      'audio/score.mp3',
      'audio/sweet_spot.mp3',
      'audio/edge_hit.mp3',
      'audio/power_up.mp3',
      'audio/game_start.mp3',
      'audio/game_over.mp3',
    ]);

    // Load and play background music
    _musicPlayer.setReleaseMode(ReleaseMode.loop);
    _musicPlayer.play(AssetSource('audio/background_music.mp3'), volume: 0.3);
  }

  void _setDifficultyLevel(GameDifficulty difficulty) {
    switch (difficulty) {
      case GameDifficulty.easy:
        _aiDifficultyLevel = 0.3;
        _aiReactionSpeed = 0.05;
        PhysicsDifficulty.setEasyMode();
        break;
      case GameDifficulty.medium:
        _aiDifficultyLevel = 0.6;
        _aiReactionSpeed = 0.1;
        PhysicsDifficulty.setMediumMode();
        break;
      case GameDifficulty.hard:
        _aiDifficultyLevel = 0.85;
        _aiReactionSpeed = 0.15;
        PhysicsDifficulty.setHardMode();
        break;
      case GameDifficulty.custom:
      // Custom settings would be loaded from preferences
        _aiDifficultyLevel = 0.5;
        _aiReactionSpeed = 0.1;
        break;
    }
  }

  // Main game loop
  void _gameLoop() {
    if (_isPaused || _isGameOver || _isCountingDown) return;

    // Calculate delta time
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    if (_lastFrameTime > 0) {
      _deltaTime = (currentTime - _lastFrameTime) / 1000.0; // Convert to seconds
    } else {
      _deltaTime = 1.0 / 60.0; // First frame assumption
    }
    _lastFrameTime = currentTime;

    // Cap delta time to avoid large jumps
    _deltaTime = math.min(_deltaTime, 0.05);

    // Update physics
    _physicsEngine.update(_deltaTime);

    // Update AI paddle target with calculated difficulty
    if (_gameState == GameState.playing) {
      final targetY = _physicsEngine.getAIPaddleTarget(_aiDifficultyLevel);
      _physicsEngine.leftPaddle.lerpFactor = _aiReactionSpeed;
      _physicsEngine.leftPaddle.setTarget(targetY);
    }

    // Handle power-ups
    _updatePowerUps();

    // Update FPS counter
    _updateFPS(currentTime);

    // Reduce screen shake intensity
    if (_screenShakeIntensity > 0) {
      _screenShakeIntensity *= 0.9;
      if (_screenShakeIntensity < 0.01) {
        _screenShakeIntensity = 0;
      }
    }

    // Force redraw
    setState(() {});
  }

  void _updateFPS(int currentTime) {
    final now = currentTime ~/ 1000; // Current second

    if (_lastSecond != now) {
      _fps = _frameCount;
      _frameCount = 0;
      _lastSecond = now;
    }

    _frameCount++;
  }

  void _startCountdown() {
    // Reset game state for countdown
    _isCountingDown = true;
    _countdown = 3;
    _resetPositions();

    // Play game start sound
    if (_soundEnabled) {
      _sfxPlayer.play(AssetSource('audio/game_start.mp3'));
    }

    // Start countdown animation
    _countdownController.reset();
    _countdownController.forward();
  }

  void _updateCountdown() {
    final progress = _countdownController.value;
    final newCountdown = 3 - (progress * 3).floor();

    if (newCountdown != _countdown) {
      setState(() {
        _countdown = newCountdown;
      });

      if (_countdown <= 0) {
        _startGame();
      } else if (_soundEnabled) {
        // Play countdown beep
        _sfxPlayer.play(AssetSource('audio/beep.mp3'), volume: 0.3);
      }
    }
  }

  void _startGame() {
    setState(() {
      _isCountingDown = false;
      _gameState = GameState.playing;
      _isPaused = false;
    });

    // Reset game data
    _resetPositions();
    _powerUpTimeRemaining = 0;
    _activePowerUp = null;
    _powerUps.clear();
    _rallyCount = 0;

    // Start the game loop
    _gameLoopController.repeat(min: 0, max: 1, period: const Duration(seconds: 1));
  }

  void _resetPositions() {
    // Reset ball and paddles
    _physicsEngine.reset(serveToRight: math.Random().nextBool());
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
      if (_isPaused) {
        _gameLoopController.stop();

        // Pause music
        _musicPlayer.pause();
      } else {
        _gameLoopController.repeat(min: 0, max: 1, period: const Duration(seconds: 1));

        // Resume music
        _musicPlayer.resume();
      }
    });
  }

  void _endGame() {
    setState(() {
      _isGameOver = true;
      _gameState = GameState.gameOver;
    });

    _gameLoopController.stop();

    // Play game over sound
    if (_soundEnabled) {
      _sfxPlayer.play(AssetSource('audio/game_over.mp3'));
    }

    // Notify parent
    if (widget.onGameOver != null) {
      widget.onGameOver!(_playerScore > _aiScore);
    }
  }

  void _resetGame() {
    setState(() {
      _playerScore = 0;
      _aiScore = 0;
      _aiHits = 0;
      _aiMisses = 0;
      _playerHits = 0;
      _playerMisses = 0;
      _rallyCount = 0;
      _maxRally = 0;
      _isGameOver = false;
      _gameState = GameState.ready;
    });

    // Reset power-ups
    _powerUps.clear();
    _activePowerUp = null;
    _powerUpTimeRemaining = 0;
    _ballSpeedBoost = false;
    _paddleSizeBoost = false;
    _reverseControls = false;

    // Reset physics engine
    _resetPositions();

    // Start new game with countdown
    _startCountdown();
  }

  void _showScoreMessage(String message) {
    setState(() {
      _scoreMessage = message;
    });

    // Clear message after delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _scoreMessage = null;
        });
      }
    });
  }

  void _createScoreEffect(bool isLeftPoint) {
    final effect = ScoreEffect(
      x: isLeftPoint ? _gameWidth * 0.25 : _gameWidth * 0.75,
      y: _gameHeight * 0.25,
      text: "+1",
      color: isLeftPoint ? kAIPaddleColor : kPlayerPaddleColor,
      lifetime: 90,
    );

    setState(() {
      _scoreEffects.add(effect);
    });

    _scoreEffectController.forward(from: 0);
  }

  void _updatePowerUps() {
    // Update active power-up time
    if (_activePowerUp != null) {
      _powerUpTimeRemaining -= _deltaTime;
      if (_powerUpTimeRemaining <= 0) {
        _deactivatePowerUp();
      }
    }

    // Update visual power-up objects
    for (int i = _powerUps.length - 1; i >= 0; i--) {
      _powerUps[i].update(_deltaTime);

      // Check for collision with ball
      if (_physicsEngine.ball.bounds.overlaps(_powerUps[i].bounds)) {
        _activatePowerUp(_powerUps[i].type);
        _powerUps.removeAt(i);

        // Play power-up sound
        if (_soundEnabled) {
          _sfxPlayer.play(AssetSource('audio/power_up.mp3'));
        }
      }
    }

    // Update score effects
    for (int i = _scoreEffects.length - 1; i >= 0; i--) {
      _scoreEffects[i].update();
      if (_scoreEffects[i].isDead) {
        _scoreEffects.removeAt(i);
      }
    }
  }

  void _spawnPowerUp() {
    // Choose random power-up type
    final powerUpType = PowerUpType.values[math.Random().nextInt(PowerUpType.values.length)];

    // Choose random position (away from paddles)
    final x = _gameWidth * 0.3 + math.Random().nextDouble() * _gameWidth * 0.4;
    final y = math.Random().nextDouble() * (_gameHeight - 50);

    setState(() {
      _powerUps.add(PowerUp(
        type: powerUpType,
        x: x,
        y: y,
        size: 30,
      ));
    });
  }

  void _activatePowerUp(PowerUpType type) {
    setState(() {
      _activePowerUp = type;
      _powerUpTimeRemaining = 10.0; // 10 seconds duration

      switch (type) {
        case PowerUpType.speedBoost:
          _ballSpeedBoost = true;
          PhysicsConstants.ballSpeedMultiplier = 1.5;
          _physicsEngine.ball.speedMultiplier = 1.5;
          _showScoreMessage("SPEED BOOST!");
          break;

        case PowerUpType.paddleSize:
          _paddleSizeBoost = true;
          _physicsEngine.rightPaddle.height = PhysicsConstants.defaultPaddleHeight * 1.5;
          _showScoreMessage("BIGGER PADDLE!");
          break;

        case PowerUpType.slowAI:
          _aiReactionSpeed = 0.05;
          _physicsEngine.leftPaddle.lerpFactor = 0.05;
          _physicsEngine.leftPaddle.moveSpeed *= 0.7;
          _showScoreMessage("AI SLOWED!");
          break;

        case PowerUpType.reverseControls:
          _reverseControls = true;
          _showScoreMessage("REVERSE CONTROLS!");
          break;
      }

      // Start power-up animation
      _powerUpController.forward(from: 0);
    });
  }

  void _deactivatePowerUp() {
    setState(() {
      // Reset effects based on active power-up
      switch (_activePowerUp) {
        case PowerUpType.speedBoost:
          _ballSpeedBoost = false;
          PhysicsConstants.ballSpeedMultiplier =
          widget.difficulty == GameDifficulty.hard ? 1.3 :
          widget.difficulty == GameDifficulty.medium ? 1.0 : 0.7;
          _physicsEngine.ball.speedMultiplier = 1.0;
          break;

        case PowerUpType.paddleSize:
          _paddleSizeBoost = false;
          _physicsEngine.rightPaddle.height = PhysicsConstants.defaultPaddleHeight;
          break;

        case PowerUpType.slowAI:
          _aiReactionSpeed = widget.difficulty == GameDifficulty.hard ? 0.15 :
          widget.difficulty == GameDifficulty.medium ? 0.1 : 0.05;
          _physicsEngine.leftPaddle.lerpFactor = _aiReactionSpeed;
          _physicsEngine.leftPaddle.moveSpeed = 10.0;
          break;

        case PowerUpType.reverseControls:
          _reverseControls = false;
          break;

        default:
          break;
      }

      _activePowerUp = null;
      _powerUpTimeRemaining = 0;
    });
  }

  void _triggerScreenShake(double intensity) {
    setState(() {
      _screenShakeIntensity = intensity;
    });
  }

  // Update player paddle based on user input
  void _updatePlayerPaddle(double? inputY) {
    if (inputY == null || _isPaused || _isGameOver || _isCountingDown) return;

    setState(() {
      // Apply reverse controls if active
      final direction = _reverseControls ? -1 : 1;

      // Calculate paddle target - center paddle on input position
      final targetY = (inputY - (_physicsEngine.rightPaddle.height / 2)) * direction;

      // Clamp to game boundaries
      final clampedY = targetY.clamp(
          0,
          _gameHeight - _physicsEngine.rightPaddle.height
      );

      // Update paddle position
      _physicsEngine.rightPaddle.position.y = clampedY as double;
    });
  }

  // Handle keyboard input
  void _handleKeyEvent(RawKeyEvent event) {
    if (_isPaused || _isGameOver || _isCountingDown) return;

    if (event is RawKeyDownEvent) {
      final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.keyW;
      final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.keyS;

      if (isUp || isDown) {
        setState(() {
          // Get current position
          double currentY = _physicsEngine.rightPaddle.position.y;

          // Calculate direction, accounting for possible power-up reversal
          final direction = _reverseControls ? -1 : 1;

          // Apply movement
          if (isUp) {
            currentY -= 15 * direction;
          } else {
            currentY += 15 * direction;
          }

          // Clamp to game boundaries
          currentY = currentY.clamp(
              0,
              _gameHeight - _physicsEngine.rightPaddle.height
          );

          // Update paddle position
          _physicsEngine.rightPaddle.position.y = currentY;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate game dimensions based on available space
        // Maintain a 4:3 aspect ratio
        final aspectRatio = 4/3;

        if (constraints.maxWidth / constraints.maxHeight > aspectRatio) {
          // Wide screen - constrain by height
          _gameHeight = constraints.maxHeight;
          _gameWidth = _gameHeight * aspectRatio;
        } else {
          // Tall or square screen - constrain by width
          _gameWidth = constraints.maxWidth;
          _gameHeight = _gameWidth / aspectRatio;
        }

        // Update physics constants if size changed
        if (_lastSize == null || _lastSize!.width != _gameWidth || _lastSize!.height != _gameHeight) {
          _lastSize = Size(_gameWidth, _gameHeight);
          PhysicsConstants.updateGameDimensions(_gameWidth, _gameHeight);
          _physicsEngine.adaptToScreenSize(_gameWidth, _gameHeight);
        }

        return RawKeyboardListener(
          focusNode: _gameFocusNode,
          onKey: _handleKeyEvent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              _touchYPosition = details.localPosition.dy;
              _updatePlayerPaddle(_touchYPosition);
            },
            onPanStart: (details) {
              _touchYPosition = details.localPosition.dy;
              _updatePlayerPaddle(_touchYPosition);
            },
            onPanEnd: (details) {
              _touchYPosition = null;
            },
            onTap: () {
              if (_gameState == GameState.ready) {
                _startCountdown();
              } else if (_gameState == GameState.gameOver) {
                _resetGame();
              }
            },
            onDoubleTap: () {
              if (_gameState == GameState.playing) {
                _togglePause();
              }
            },
            child: Center(
              child: Container(
                key: _gameKey,
                width: _gameWidth,
                height: _gameHeight,
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(
                    color: kAccentColor.withOpacity(0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kAccentColor.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRect(
                  child: Stack(
                    children: [
                      // Game background with ambient effects
                      CustomPaint(
                        size: Size(_gameWidth, _gameHeight),
                        painter: GameBackgroundPainter(_ambientController.value),
                      ),

                      // Main game content with screen shake effect
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _gameLoopController,
                          _hitEffectController,
                        ]),
                        builder: (context, child) {
                          // Apply screen shake effect
                          final dx = _screenShakeIntensity > 0
                              ? math.Random().nextDouble() * _screenShakeIntensity * 10 - 5 * _screenShakeIntensity
                              : 0.0;
                          final dy = _screenShakeIntensity > 0
                              ? math.Random().nextDouble() * _screenShakeIntensity * 10 - 5 * _screenShakeIntensity
                              : 0.0;

                          return Transform.translate(
                            offset: Offset(dx, dy),
                            child: CustomPaint(
                              size: Size(_gameWidth, _gameHeight),
                              painter: GamePainter(
                                _physicsEngine,
                                _physicsRenderer,
                                hitEffectValue: _hitEffectController.value,
                                ballTrailEnabled: true,
                                scoreEffects: _scoreEffects,
                                powerUps: _powerUps,
                                activePowerUp: _activePowerUp,
                                powerUpTimeRemaining: _powerUpTimeRemaining,
                                paddleSizeBoost: _paddleSizeBoost,
                                ballSpeedBoost: _ballSpeedBoost,
                              ),
                            ),
                          );
                        },
                      ),

                      // Score display
                      Positioned(
                        top: 20,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // AI Score
                            Column(
                              children: [
                                Text(
                                  "AI",
                                  style: TextStyle(
                                    color: kAIPaddleColor,
                                    fontSize: kGameInfoTextSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$_aiScore",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: kScoreTextSize,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(
                                        color: kAIPaddleColor.withOpacity(0.7),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Score divider
                            SizedBox(width: _gameWidth * 0.15),

                            // Player score
                            Column(
                              children: [
                                Text(
                                  "YOU",
                                  style: TextStyle(
                                    color: kPlayerPaddleColor,
                                    fontSize: kGameInfoTextSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$_playerScore",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: kScoreTextSize,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(
                                        color: kPlayerPaddleColor.withOpacity(0.7),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Rally counter
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: kAccentColor.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.swap_horiz,
                                color: kAccentColor,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Rally: $_rallyCount",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Debug info overlay
                      if (widget.showDebug)
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: kAccentColor.withOpacity(0.4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "FPS: $_fps",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  "AI Hit Rate: ${_aiHits > 0 ? (_aiHits / (_aiHits + _aiMisses) * 100).toStringAsFixed(1) : '0.0'}%",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  "Max Rally: $_maxRally",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Active power-up indicator
                      if (_activePowerUp != null)
                        Positioned(
                          top: 80,
                          right: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _getPowerUpColor(_activePowerUp!),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _getPowerUpColor(_activePowerUp!).withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getPowerUpIcon(_activePowerUp!),
                                  color: _getPowerUpColor(_activePowerUp!),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getPowerUpName(_activePowerUp!),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  "${_powerUpTimeRemaining.toStringAsFixed(1)}s",
                                  style: TextStyle(
                                    color: _getPowerUpColor(_activePowerUp!),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ).animate(target: 1)
                              .shimmer(duration: 1500.ms, delay: 500.ms)
                              .then()
                              .shimmer(duration: 1500.ms, delay: 500.ms)
                              .then()
                              .shimmer(duration: 1500.ms, delay: 500.ms),
                        ),

                      // Score message
                      if (_scoreMessage != null)
                        Positioned.fill(
                          child: Center(
                            child: Text(
                              _scoreMessage!,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: kAccentColor.withOpacity(0.8),
                                    blurRadius: 15,
                                  ),
                                ],
                              ),
                            ).animate()
                                .fade(duration: 200.ms)
                                .scale(duration: 400.ms, curve: Curves.elasticOut)
                                .then(delay: 800.ms)
                                .fadeOut(duration: 600.ms),
                          ),
                        ),

                      // Countdown overlay
                      if (_isCountingDown)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.7),
                            child: Center(
                              child: AnimatedBuilder(
                                animation: _countdownController,
                                builder: (context, _) {
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _countdown > 0 ? "$_countdown" : "GO!",
                                        style: TextStyle(
                                          fontSize: 72,
                                          fontWeight: FontWeight.bold,
                                          color: _countdown > 0
                                              ? Colors.white
                                              : kPlayerPaddleColor,
                                          shadows: [
                                            Shadow(
                                              color: kAccentColor.withOpacity(0.8),
                                              blurRadius: 20,
                                            ),
                                          ],
                                        ),
                                      ).animate(
                                        onComplete: (controller) {
                                          controller.repeat(reverse: true);
                                        },
                                      ).scale(
                                        begin: const Offset(0.5, 0.5),
                                        end: const Offset(1.0, 1.0),
                                        curve: Curves.elasticOut,
                                        duration: 800.ms,
                                      ),
                                      if (_countdown <= 0)
                                        const SizedBox(height: 20),
                                      if (_countdown <= 0)
                                        Text(
                                          "Get ready!",
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.9),
                                            fontSize: 24,
                                          ),
                                        ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),

                      // Pause overlay
                      if (_isPaused && !_isGameOver && !_isCountingDown)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.8),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "PAUSED",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          color: kAccentColor.withOpacity(0.8),
                                          blurRadius: 15,
                                        ),
                                      ],
                                    ),
                                  ).animate().fade(duration: 300.ms).scale(),
                                  const SizedBox(height: 30),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text("RESUME"),
                                    onPressed: _togglePause,
                                    style: ElevatedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: kAccentColor,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 30,
                                        vertical: 15,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ).animate(delay: 200.ms)
                                      .fade(duration: 400.ms)
                                      .slideY(begin: 0.2, end: 0),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Game over overlay
                      if (_isGameOver)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.8),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _playerScore > _aiScore ? "YOU WIN!" : "AI WINS!",
                                    style: TextStyle(
                                      color: _playerScore > _aiScore
                                          ? kPlayerPaddleColor
                                          : kAIPaddleColor,
                                      fontSize: 64,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          color: (_playerScore > _aiScore
                                              ? kPlayerPaddleColor
                                              : kAIPaddleColor).withOpacity(0.8),
                                          blurRadius: 20,
                                        ),
                                      ],
                                    ),
                                  ).animate()
                                      .fade(duration: 500.ms)
                                      .scale(begin: const Offset(0.5, 0.5), duration: 700.ms, curve: Curves.elasticOut)
                                      .then()
                                      .shimmer(duration: 1200.ms, color: Colors.white.withOpacity(0.8)),

                                  const SizedBox(height: 30),

                                  // Display final score
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(color: kAccentColor.withOpacity(0.6), width: 2),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          "FINAL SCORE",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                          ),
                                        ),
                                        const SizedBox(height: 15),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Column(
                                              children: [
                                                Text(
                                                  "AI",
                                                  style: TextStyle(
                                                    color: kAIPaddleColor,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                Text(
                                                  "$_aiScore",
                                                  style: TextStyle(
                                                    color: kAIPaddleColor,
                                                    fontSize: 48,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 60),
                                            Column(
                                              children: [
                                                Text(
                                                  "YOU",
                                                  style: TextStyle(
                                                    color: kPlayerPaddleColor,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                Text(
                                                  "$_playerScore",
                                                  style: TextStyle(
                                                    color: kPlayerPaddleColor,
                                                    fontSize: 48,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 15),
                                        Text(
                                          "Max Rally: $_maxRally",
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.8),
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          "AI Hit Rate: ${_aiHits > 0 ? (_aiHits / (_aiHits + _aiMisses) * 100).toStringAsFixed(1) : '0.0'}%",
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.8),
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ).animate(delay: 400.ms).fade(duration: 600.ms),

                                  const SizedBox(height: 40),

                                  // Action buttons
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.refresh),
                                        label: const Text("PLAY AGAIN"),
                                        onPressed: _resetGame,
                                        style: ElevatedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor: kAccentColor,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 15,
                                          ),
                                        ),
                                      ).animate(delay: 800.ms).fade(duration: 400.ms),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getPowerUpColor(PowerUpType type) {
    switch (type) {
      case PowerUpType.speedBoost:
        return Colors.orange;
      case PowerUpType.paddleSize:
        return Colors.green;
      case PowerUpType.slowAI:
        return Colors.blue;
      case PowerUpType.reverseControls:
        return Colors.purple;
    }
  }

  IconData _getPowerUpIcon(PowerUpType type) {
    switch (type) {
      case PowerUpType.speedBoost:
        return Icons.speed;
      case PowerUpType.paddleSize:
        return Icons.expand;
      case PowerUpType.slowAI:
        return Icons.hourglass_bottom;
      case PowerUpType.reverseControls:
        return Icons.swap_vert;
    }
  }

  String _getPowerUpName(PowerUpType type) {
    switch (type) {
      case PowerUpType.speedBoost:
        return "Speed Boost";
      case PowerUpType.paddleSize:
        return "Bigger Paddle";
      case PowerUpType.slowAI:
        return "Slow AI";
      case PowerUpType.reverseControls:
        return "Reverse Controls";
    }
  }
}

// Game state enum
enum GameState {
  ready,
  playing,
  paused,
  gameOver,
}

// Power-up types
enum PowerUpType {
  speedBoost,
  paddleSize,
  slowAI,
  reverseControls,
}

// Power-up visual object
class PowerUp {
  final PowerUpType type;
  double x;
  double y;
  double size;
  double rotation = 0;
  late final Rect bounds;

  PowerUp({
    required this.type,
    required this.x,
    required this.y,
    required this.size,
  }) : bounds = Rect.fromCircle(center: Offset(x, y), radius: size / 2);

  void update(double deltaTime) {
    // Add floating animation
    y += math.sin(rotation * 2) * 0.3;
    rotation += deltaTime * 2;

    // Update bounds with new center
    bounds = Rect.fromCenter(
      center: Offset(x, y),
      width: bounds.width,
      height: bounds.height,
    );
  }


  Color get color {
    switch (type) {
      case PowerUpType.speedBoost:
        return Colors.orange;
      case PowerUpType.paddleSize:
        return Colors.green;
      case PowerUpType.slowAI:
        return Colors.blue;
      case PowerUpType.reverseControls:
        return Colors.purple;
    }
  }

  IconData get icon {
    switch (type) {
      case PowerUpType.speedBoost:
        return Icons.speed;
      case PowerUpType.paddleSize:
        return Icons.expand;
      case PowerUpType.slowAI:
        return Icons.hourglass_bottom;
      case PowerUpType.reverseControls:
        return Icons.swap_vert;
    }
  }
}

// Score effect animation
class ScoreEffect {
  double x;
  double y;
  String text;
  Color color;
  int lifetime;
  int age = 0;

  ScoreEffect({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    required this.lifetime,
  });

  void update() {
    y -= 0.8; // Move upward
    age++;
  }

  bool get isDead => age >= lifetime;

  double get opacity => 1.0 - (age / lifetime);

  double get scale => 1.0 + math.sin(math.pi * age / lifetime) * 0.5;
}

// Game background painter
class GameBackgroundPainter extends CustomPainter {
  final double animationValue;

  GameBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    // Background gradient
    final Rect rect = Offset.zero & size;
    const gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF1A1A2E),
        Color(0xFF16213E),
        Color(0xFF0F3460),
      ],
    );

    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    // Draw horizontal grid lines
    for (int i = 0; i <= 20; i++) {
      final y = size.height * i / 20;

      final path = Path();
      path.moveTo(0, y);

      for (double x = 0; x < size.width; x += 10) {
        final wave = math.sin(x / 200 + animationValue + i * 0.1) * 3;
        path.lineTo(x, y + wave);
      }

      canvas.drawPath(path, gridPaint);
    }

    // Draw vertical grid lines
    for (int i = 0; i <= 30; i++) {
      final x = size.width * i / 30;

      final path = Path();
      path.moveTo(x, 0);

      for (double y = 0; y < size.height; y += 10) {
        final wave = math.sin(y / 200 + animationValue + i * 0.1) * 3;
        path.lineTo(x + wave, y);
      }

      canvas.drawPath(path, gridPaint);
    }

    // Draw center line
    final centerLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw dashed line
    double dashHeight = 10;
    double dashSpace = 10;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        centerLinePaint,
      );
      startY += dashHeight + dashSpace;
    }

    // Draw subtle ambient particles
    final particlePaint = Paint()
      ..color = kAccentColor.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 15; i++) {
      final seed = i * 123.456;
      final x = ((math.sin(seed + animationValue) + 1) / 2) * size.width;
      final y = ((math.cos(seed * 2 + animationValue * 1.5) + 1) / 2) * size.height;
      final particleSize = (math.sin(animationValue + seed * 3) + 1) * 2 + 1;

      canvas.drawCircle(Offset(x, y), particleSize, particlePaint);
    }
  }

  @override
  bool shouldRepaint(GameBackgroundPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

// Game painter for rendering the actual game
class GamePainter extends CustomPainter {
  final PhysicsEngine engine;
  final PhysicsRenderer renderer;
  final double hitEffectValue;
  final bool ballTrailEnabled;
  final List<ScoreEffect> scoreEffects;
  final List<PowerUp> powerUps;
  final PowerUpType? activePowerUp;
  final double powerUpTimeRemaining;
  final bool paddleSizeBoost;
  final bool ballSpeedBoost;

  GamePainter(
      this.engine,
      this.renderer, {
        this.hitEffectValue = 0.0,
        this.ballTrailEnabled = true,
        this.scoreEffects = const [],
        this.powerUps = const [],
        this.activePowerUp,
        this.powerUpTimeRemaining = 0,
        this.paddleSizeBoost = false,
        this.ballSpeedBoost = false,
      });

  @override
  void paint(Canvas canvas, Size size) {
    // Let physics renderer draw the game objects
    renderer.render(canvas, size);

    // Draw power-ups
    for (final powerUp in powerUps) {
      _drawPowerUp(canvas, powerUp);
    }

    // Draw score effects
    _drawScoreEffects(canvas);

    // Draw hit effect flash overlay
    if (hitEffectValue > 0) {
      final flashPaint = Paint()
        ..color = Colors.white.withOpacity(hitEffectValue * 0.2)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        flashPaint,
      );
    }
  }

  void _drawPowerUp(Canvas canvas, PowerUp powerUp) {
    // Draw glow
    final glowPaint = Paint()
      ..color = powerUp.color.withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

    canvas.drawCircle(
      Offset(powerUp.x, powerUp.y),
      powerUp.size * 0.7,
      glowPaint,
    );

    // Draw background circle
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(powerUp.x, powerUp.y),
      powerUp.size * 0.5,
      bgPaint,
    );

    // Draw border
    final borderPaint = Paint()
      ..color = powerUp.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(
      Offset(powerUp.x, powerUp.y),
      powerUp.size * 0.5,
      borderPaint,
    );

    // Draw icon - use TextPainter for icon
    final iconData = powerUp.icon.codePoint;
    final iconFont = powerUp.icon.fontFamily ?? '';
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData),
        style: TextStyle(
          fontSize: powerUp.size * 0.5,
          color: powerUp.color,
          fontFamily: iconFont,
          package: 'material_design_icons',
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    iconPainter.layout();
    iconPainter.paint(
      canvas,
      Offset(
        powerUp.x - iconPainter.width / 2,
        powerUp.y - iconPainter.height / 2,
      ),
    );
  }

  void _drawScoreEffects(Canvas canvas) {
    for (final effect in scoreEffects) {
      final textStyle = TextStyle( // <-- this one from Flutter
        color: effect.color.withOpacity(effect.opacity),
        fontSize: 36 * effect.scale,
        fontWeight: FontWeight.bold,
      );

      final textSpan = TextSpan(
        text: effect.text,
        style: textStyle,
      );

      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(effect.x - textPainter.width / 2, effect.y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(GamePainter oldDelegate) => true;
}
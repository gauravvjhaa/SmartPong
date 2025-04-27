import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:audioplayers/audioplayers.dart';

// Import GameStateProvider and enums from main.dart
import '../main.dart';

import '../game/pong_game.dart';
import '../ai/ai_player.dart';

// Game colors
const Color kBallColor = Colors.white;
const Color kPlayerPaddleColor = Color(0xFF4CAF50);
const Color kAIPaddleColor = Color(0xFFFFEB3B);
const Color kAccentColor = Color(0xFF00C6FF);
const Color kSecondaryColor = Color(0xFFFF5252);
const Color kNeonGlow = Color(0xFF00FFFF);

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  // Game dimensions with default values
  double gameWidth = 800.0; // Default until calculated in build
  double gameHeight = 450.0; // Default until calculated in build
  final double paddleWidth = 15;
  final double paddleHeight = 100;
  final double ballSize = 15;

  // Game elements positions with default values
  double playerPaddleY = 175.0; // Default middle position
  double aiPaddleY = 175.0; // Default middle position
  double ballX = 392.5; // Default center (800/2 - 15/2)
  double ballY = 217.5; // Default center (450/2 - 15/2)
  double ballSpeedX = 0;
  double ballSpeedY = 0;

  // Game state
  int playerScore = 0;
  int aiScore = 0;
  bool isGameActive = false;
  bool isPaused = false;
  bool isCountingDown = true;
  int countdown = 3;
  bool justScored = false;
  String scoreMessage = '';

  // Animation controllers
  late AnimationController _gameLoopController;
  late AnimationController _ballHitController;
  late AnimationController _scoreAnimationController;
  late AnimationController _countdownController;
  late AnimationController _pauseOverlayController;

  // AI tracking
  int aiHits = 0;
  int aiMisses = 0;

  // Tracking for touch input
  double? touchYPosition;
  bool isMouseDown = false;
  bool maintainPaddleControl = true; // New flag to maintain paddle control

  // Game effects
  List<ParticleEffect> hitEffects = [];
  List<ScoreEffect> scoreEffects = [];

  // FPS calculation
  int _frameCount = 0;
  int _fps = 0;
  int _lastSecond = 0;

  // User settings
  double _paddleSensitivity = 1.0; // Default multiplier
  double _ballSpeedMultiplier = 1.0; // Default multiplier

  // Audio players
  final AudioPlayer _musicPlayer = AudioPlayer();
  final Map<String, AudioPlayer> _soundPlayers = {};
  bool _audioInitialized = false;

  @override
  void initState() {
    super.initState();

    // Initialize controllers
    _gameLoopController = AnimationController(
      vsync: this,
      duration: const Duration(days: 1), // Runs indefinitely
    )..addListener(_gameLoop);

    _ballHitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scoreAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(_updateCountdown);

    _pauseOverlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Setup keyboard focus
    FocusManager.instance.primaryFocus?.unfocus();

    // Initialize audio system
    _initializeAudio();

    // Load user settings
    _applyGameSettings();

    // Start countdown sequence
    _startCountdown();
  }

  // Initialize the audio players
  Future<void> _initializeAudio() async {
    final gameState = Provider.of<GameStateProvider>(context, listen: false);

    if (!gameState.soundEnabled) {
      print("Sound is disabled in settings");
      return;
    }

    try {
      // Create sound effect players
      final sounds = [
        'paddle_hit',
        'wall_hit',
        'score',
        'sweet_spot',
        'edge_hit',
        'power_up',
        'game_start',
        'game_over',
        'beep'
      ];

      for (var sound in sounds) {
        final player = AudioPlayer();
        await player.setSource(AssetSource('audio/$sound.mp3'));
        await player.setVolume(gameState.settings.sfxVolume * gameState.settings.masterVolume);
        _soundPlayers[sound] = player;
      }

      // Setup music player
      // await _musicPlayer.setSource(AssetSource('audio/background_music.mp3'));
      await _musicPlayer.setVolume(gameState.settings.musicVolume * gameState.settings.masterVolume);
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);

      // Start background music
      await _musicPlayer.resume();

      _audioInitialized = true;
      print("Audio initialized successfully");
    } catch (e) {
      print("Error initializing audio: $e");
    }
  }

  // Play a sound effect
  void _playSound(String soundName) {
    final gameState = Provider.of<GameStateProvider>(context, listen: false);
    if (!gameState.soundEnabled || !_audioInitialized) return;

    try {
      final player = _soundPlayers[soundName];
      if (player != null) {
        player.setVolume(gameState.settings.sfxVolume * gameState.settings.masterVolume);
        player.seek(Duration.zero);
        player.resume();
        print("Playing sound: $soundName");
      } else {
        print("Sound not found: $soundName");
      }
    } catch (e) {
      print("Error playing sound $soundName: $e");
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Apply settings in case they've changed
    _applyGameSettings();
  }

  // Apply game settings from GameStateProvider
  void _applyGameSettings() {
    final gameState = Provider.of<GameStateProvider>(context, listen: false);
    final settings = gameState.settings;

    // Convert 0-1 range to more useful gameplay values
    _paddleSensitivity = 0.5 + (settings.paddleSensitivity * 1.5); // Range: 0.5-2.0
    _ballSpeedMultiplier = 0.7 + (settings.ballSpeed * 0.6); // Range: 0.7-1.3

    // Update audio volumes if initialized
    if (_audioInitialized) {
      _musicPlayer.setVolume(settings.musicVolume * settings.masterVolume);

      for (var player in _soundPlayers.values) {
        player.setVolume(settings.sfxVolume * settings.masterVolume);
      }

      if (settings.soundEnabled) {
        _musicPlayer.resume();
      } else {
        _musicPlayer.pause();
      }
    }

    print("Applied game settings - paddle sensitivity: $_paddleSensitivity, ball speed: $_ballSpeedMultiplier");
  }

  @override
  void dispose() {
    // Dispose all audio players
    _musicPlayer.dispose();
    for (var player in _soundPlayers.values) {
      player.dispose();
    }

    _gameLoopController.dispose();
    _ballHitController.dispose();
    _scoreAnimationController.dispose();
    _countdownController.dispose();
    _pauseOverlayController.dispose();
    super.dispose();
  }

  void _gameLoop() {
    if (!isGameActive || isPaused) return;

    // Calculate time since last frame for smooth movement
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastSecond == 0) _lastSecond = now;

    // FPS calculation
    _frameCount++;
    if (now - _lastSecond >= 1000) {
      _fps = _frameCount;
      _frameCount = 0;
      _lastSecond = now;
    }

    // Move the ball - apply speed multiplier
    setState(() {
      ballX += ballSpeedX;
      ballY += ballSpeedY;

      // Handle AI paddle movement - make it smooth and slightly imperfect
      _moveAIPaddle();

      // Ball collision with top and bottom walls
      if (ballY <= 0 || ballY >= gameHeight - ballSize) {
        ballSpeedY = -ballSpeedY;
        ballY = ballY <= 0 ? 0 : gameHeight - ballSize;
        _playHitEffect(ballX, ballY, isWall: true);
        _playSound('wall_hit');
      }

      // Ball collision with player paddle (right)
      if (ballX + ballSize >= gameWidth - paddleWidth - 20 &&
          ballX <= gameWidth - 20 &&
          ballY + ballSize >= playerPaddleY &&
          ballY <= playerPaddleY + paddleHeight) {

        _handlePaddleHit(playerPaddleY, isPlayer: true);
        _playSound('paddle_hit');
      }

      // Ball collision with AI paddle (left)
      if (ballX <= 20 + paddleWidth &&
          ballX + ballSize >= 20 &&
          ballY + ballSize >= aiPaddleY &&
          ballY <= aiPaddleY + paddleHeight) {

        _handlePaddleHit(aiPaddleY, isPlayer: false);
        _playSound('paddle_hit');
        aiHits++;
        _updateAIStats();
      }

      // Ball out of bounds - scoring
      if (ballX <= -ballSize) {
        // Player scores
        playerScore++;
        _showScoreMessage("You scored!");
        _playScoreEffect(true);
        _playSound('score');
        _resetBall(servingToAI: false);
        aiMisses++;
        _updateAIStats();
        _updateGameState();
      } else if (ballX >= gameWidth) {
        // AI scores
        aiScore++;
        _showScoreMessage("AI scored!");
        _playScoreEffect(false);
        _playSound('score');
        _resetBall(servingToAI: true);
        _updateGameState();
      }

      // Update effects
      _updateEffects();
    });
  }

  void _moveAIPaddle() {
    // Get the current game state
    final gameState = Provider.of<GameStateProvider>(context, listen: false);

    // Get target position - depends on ball direction
    double targetY = aiPaddleY;

    // If ball is moving toward AI
    if (ballSpeedX < 0) {
      // Predict where ball will be when it reaches the AI paddle
      double timeToReachPaddle = (20 + paddleWidth - ballX) / -ballSpeedX;
      double predictedY = ballY + (ballSpeedY * timeToReachPaddle);

      // Handle bounces for prediction
      while (predictedY < 0 || predictedY > gameHeight - ballSize) {
        if (predictedY < 0) {
          predictedY = -predictedY;
        } else if (predictedY > gameHeight - ballSize) {
          predictedY = 2 * (gameHeight - ballSize) - predictedY;
        }
      }

      // Add some error based on difficulty
      double errorFactor = 0;
      switch(gameState.difficulty) {
        case GameDifficulty.easy:
          errorFactor = 0.3;
          break;
        case GameDifficulty.medium:
          errorFactor = 0.15;
          break;
        case GameDifficulty.hard:
          errorFactor = 0.05;
          break;
        case GameDifficulty.custom:
          errorFactor = 0.1;
          break;
      }

      // Apply error to prediction
      predictedY += (math.Random().nextDouble() * 2 - 1) * errorFactor * gameHeight;

      // Clamp the prediction to valid range
      predictedY = math.max(0, math.min(gameHeight - paddleHeight, predictedY));

      // Set target position based on prediction
      targetY = predictedY - (paddleHeight / 2) + (ballSize / 2);
    }

    // Move AI paddle toward target position with smooth interpolation
    double speed = 0;
    switch(gameState.difficulty) {
      case GameDifficulty.easy:
        speed = 5;
        break;
      case GameDifficulty.medium:
        speed = 8;
        break;
      case GameDifficulty.hard:
        speed = 12;
        break;
      case GameDifficulty.custom:
        speed = 10;
        break;
    }

    if (aiPaddleY < targetY) {
      aiPaddleY += math.min(speed, targetY - aiPaddleY);
    } else if (aiPaddleY > targetY) {
      aiPaddleY -= math.min(speed, aiPaddleY - targetY);
    }

    // Keep paddle within bounds
    aiPaddleY = math.max(0, math.min(gameHeight - paddleHeight, aiPaddleY));
  }

  void _handlePaddleHit(double paddleY, {required bool isPlayer}) {
    // Reverse x direction with speed multiplier applied
    ballSpeedX = -ballSpeedX * 1.05 * _ballSpeedMultiplier;

    // Adjust y speed based on where the ball hit the paddle
    double relativeIntersectY = (paddleY + (paddleHeight / 2)) - (ballY + (ballSize / 2));
    double normalizedRelativeIntersectionY = relativeIntersectY / (paddleHeight / 2);

    // Check if it's a "sweet spot" hit (near center of paddle)
    bool sweetSpot = normalizedRelativeIntersectionY.abs() < 0.2;
    // Check if it's an edge hit (near edge of paddle)
    bool edgeHit = normalizedRelativeIntersectionY.abs() > 0.8;

    if (sweetSpot) {
      _playSound('sweet_spot');
    } else if (edgeHit) {
      _playSound('edge_hit');
    }

    double bounceAngle = normalizedRelativeIntersectionY * (math.pi / 4); // Max 45 degree angle

    // Update ball speed based on bounce angle and apply multiplier
    ballSpeedY = -math.sin(bounceAngle) *
        math.sqrt(ballSpeedX * ballSpeedX + ballSpeedY * ballSpeedY);

    // Constrain to reasonable speeds, adjusted by multiplier
    double maxSpeed = 10.0 * _ballSpeedMultiplier;
    ballSpeedY = math.max(-maxSpeed, math.min(maxSpeed, ballSpeedY));
    ballSpeedX = math.max(-maxSpeed, math.min(maxSpeed, ballSpeedX));

    // Keep ball outside the paddle to prevent multiple collisions
    if (isPlayer) {
      ballX = gameWidth - paddleWidth - 20 - ballSize;
    } else {
      ballX = 20 + paddleWidth;
    }

    // Play hit animation
    _ballHitController.forward(from: 0);

    // Create hit effect particles
    _playHitEffect(isPlayer ? gameWidth - paddleWidth - 20 : 20 + paddleWidth, ballY);
  }

  void _playHitEffect(double x, double y, {bool isWall = false}) {
    final particles = List.generate(
      isWall ? 10 : 20,
          (index) => ParticleEffect(
        x: x + ballSize / 2,
        y: y + ballSize / 2,
        color: isWall ? kAccentColor : (x < gameWidth / 2 ? kAIPaddleColor : kPlayerPaddleColor),
        velocity: math.Point<double>(
          (math.Random().nextDouble() * 6 - 3) * (isWall ? 1 : 2),
          (math.Random().nextDouble() * 6 - 3) * (isWall ? 1 : 2),
        ),
        size: math.Random().nextDouble() * 4 + 2,
        lifetime: math.Random().nextInt(30) + 20,
      ),
    );

    setState(() {
      hitEffects.addAll(particles);
    });
  }

  void _handleQuit() {
    print("QUIT button pressed - returning to menu");

    // 1. Stop all game processes
    _gameLoopController.stop();
    _ballHitController.stop();
    _scoreAnimationController.stop();
    _countdownController.stop();
    _pauseOverlayController.stop();

    // 2. Set game as inactive
    setState(() {
      isGameActive = false;
      isPaused = false;
    });

    // Play game over sound
    _playSound('game_over');

    // 3. Just navigate directly to menu screen
    final gameState = Provider.of<GameStateProvider>(context, listen: false);
    gameState.navigateTo(GameScreenEnum.menu);
  }

  void _playScoreEffect(bool isPlayerScore) {
    final effect = ScoreEffect(
      x: isPlayerScore ? gameWidth * 0.75 : gameWidth * 0.25,
      y: gameHeight * 0.3,
      text: "+1",
      color: isPlayerScore ? kPlayerPaddleColor : kAIPaddleColor,
      lifetime: 90,
    );

    setState(() {
      scoreEffects.add(effect);
    });

    _scoreAnimationController.forward(from: 0);
  }

  void _updateEffects() {
    // Update particle effects
    for (int i = hitEffects.length - 1; i >= 0; i--) {
      hitEffects[i].update();
      if (hitEffects[i].isDead) {
        hitEffects.removeAt(i);
      }
    }

    // Update score effects
    for (int i = scoreEffects.length - 1; i >= 0; i--) {
      scoreEffects[i].update();
      if (scoreEffects[i].isDead) {
        scoreEffects.removeAt(i);
      }
    }
  }

  void _resetBall({required bool servingToAI}) {
    ballX = gameWidth / 2 - ballSize / 2;
    ballY = gameHeight / 2 - ballSize / 2;

    // Use ball speed multiplier
    double baseSpeed = 4.0;
    ballSpeedX = (servingToAI ? -baseSpeed : baseSpeed) * _ballSpeedMultiplier;
    ballSpeedY = (math.Random().nextDouble() * 6 - 3) * _ballSpeedMultiplier;

    print("Reset ball with speed multiplier: $_ballSpeedMultiplier → X: $ballSpeedX, Y: $ballSpeedY");

    justScored = true;
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          justScored = false;
        });
      }
    });

    // Important: don't reset the touch position here, which allows
    // the user to maintain control of the paddle after scoring
  }

  void _showScoreMessage(String message) {
    setState(() {
      scoreMessage = message;
    });

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          scoreMessage = '';
        });
      }
    });
  }

  void _updateAIStats() {
    final gameState = Provider.of<GameStateProvider>(context, listen: false);
    final hitRate = aiHits / math.max(1, aiHits + aiMisses);
    gameState.updateAIStats(hitRate);
  }

  void _updateGameState() {
    final gameState = Provider.of<GameStateProvider>(context, listen: false);
    gameState.updateScores(playerScore, aiScore);

    // Check for game over
    if (playerScore >= 3 || aiScore >= 3) {
      _endGame();
    }
  }

  void _startCountdown() {
    isCountingDown = true;
    countdown = 3;
    _countdownController.reset();
    _countdownController.forward();

    // Play countdown beep
    _playSound('beep');
  }

  void _updateCountdown() {
    final progress = _countdownController.value;
    final newCountdown = 3 - (progress * 3).floor();

    if (newCountdown != countdown) {
      setState(() {
        countdown = newCountdown;
      });

      if (countdown > 0) {
        // Play countdown beep for each number
        _playSound('beep');
      } else {
        // Play game start sound
        _playSound('game_start');
        _startGame();
      }
    }
  }

  void _startGame() {
    // Initialize game state
    setState(() {
      isCountingDown = false;
      isGameActive = true;
      isPaused = false;
      aiHits = 0;
      aiMisses = 0;
      playerScore = 0;
      aiScore = 0;

      // Start the game with a random direction
      _resetBall(servingToAI: math.Random().nextBool());
    });

    // Start game loop
    _gameLoopController.repeat();

    // Update game state provider
    final gameState = Provider.of<GameStateProvider>(context, listen: false);
    gameState.resetGame();
  }

  void _togglePause() {
    setState(() {
      isPaused = !isPaused;
      if (isPaused) {
        _pauseOverlayController.forward();
      } else {
        _pauseOverlayController.reverse();
      }
    });
  }

  void _endGame() {
    // Stop game loop
    _gameLoopController.stop();

    // Set game inactive
    setState(() {
      isGameActive = false;
    });

    // Play game over sound
    _playSound('game_over');

    // Navigate to game over screen
    final gameState = Provider.of<GameStateProvider>(context, listen: false);
    gameState.navigateTo(GameScreenEnum.gameOver);
  }

  // Update player paddle based on touch/mouse input with sensitivity
  void _handlePaddleInput(double? inputY) {
    if (inputY == null || !isGameActive || isPaused) return;

    final targetY = inputY - paddleHeight / 2;

    setState(() {
      // Apply smoothing with sensitivity adjustment
      // Higher sensitivity means quicker response (higher smoothFactor)
      final double smoothFactor = math.min(0.9, 0.3 * _paddleSensitivity);

      playerPaddleY = playerPaddleY * (1 - smoothFactor) + targetY * smoothFactor;
      playerPaddleY = math.max(0, math.min(gameHeight - paddleHeight, playerPaddleY));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size for responsive layout
    final size = MediaQuery.of(context).size;
    final gameState = Provider.of<GameStateProvider>(context);

    // Calculate game field dimensions based on screen size
    // 16:9 aspect ratio is ideal for the game field
    final aspectRatio = 16 / 9;

    if (size.width / size.height > aspectRatio) {
      // Wide screen - constrain by height
      gameHeight = size.height * 0.9; // 90% of screen height
      gameWidth = gameHeight * aspectRatio;
    } else {
      // Tall or square screen - constrain by width
      gameWidth = size.width * 0.9; // 90% of screen width
      gameHeight = gameWidth / aspectRatio;
    }

    // Update positions if needed based on new dimensions
    if (!isGameActive && !isPaused && !isCountingDown) {
      playerPaddleY = (gameHeight - paddleHeight) / 2;
      aiPaddleY = (gameHeight - paddleHeight) / 2;
      ballX = (gameWidth - ballSize) / 2;
      ballY = (gameHeight - ballSize) / 2;
      ballSpeedX = 0;
      ballSpeedY = 0;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RawKeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKey: (event) {
          if (event is RawKeyDownEvent) {
            // Handle keyboard input with sensitivity adjustment
            if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.keyW) {
              setState(() {
                // Apply sensitivity to movement amount
                double moveAmount = 15.0 * _paddleSensitivity;
                playerPaddleY = math.max(0, playerPaddleY - moveAmount);
              });
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.keyS) {
              setState(() {
                // Apply sensitivity to movement amount
                double moveAmount = 15.0 * _paddleSensitivity;
                playerPaddleY = math.min(gameHeight - paddleHeight, playerPaddleY + moveAmount);
              });
            } else if (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.keyP) {
              if (isGameActive) _togglePause();
            }
          }
        },
        child: Center(
          child: SizedBox(
            width: gameWidth,
            height: gameHeight,
            child: Stack(
              children: [
                // Game field
                Positioned.fill(
                  child: DecoratedBox(
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
                  ),
                ),

                // Center line
                Positioned(
                  left: gameWidth / 2 - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight;
                      // Each dash takes 30 pixels of space (10 height + 20 for margins)
                      final itemCount = (height / 30).floor();

                      return Column(
                        children: List.generate(
                          itemCount,
                              (index) => Container(
                            height: 10,
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // AI paddle (left)
                Positioned(
                  left: 20,
                  top: aiPaddleY,
                  width: paddleWidth,
                  height: paddleHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: kAIPaddleColor,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: kAIPaddleColor.withOpacity(0.6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),

                // Player paddle (right)
                Positioned(
                  right: 20,
                  top: playerPaddleY,
                  width: paddleWidth,
                  height: paddleHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: kPlayerPaddleColor,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: kPlayerPaddleColor.withOpacity(0.6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),

                // Ball
                AnimatedBuilder(
                    animation: _ballHitController,
                    builder: (context, child) {
                      // Apply a pulse effect when the ball hits a paddle
                      final scale = 1.0 + _ballHitController.value * 0.5;
                      return Positioned(
                        left: ballX,
                        top: ballY,
                        width: ballSize,
                        height: ballSize,
                        child: Transform.scale(
                          scale: scale,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: kBallColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: kNeonGlow.withOpacity(0.6),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                ),

                // Particle effects layer
                CustomPaint(
                  size: Size(gameWidth, gameHeight),
                  painter: EffectsPainter(hitEffects, scoreEffects),
                ),

                // Score display
                Positioned(
                  left: 0,
                  right: 0,
                  top: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ScoreDisplay(
                        score: aiScore,
                        color: kAIPaddleColor,
                        label: "AI",
                      ),
                      const SizedBox(width: 60),
                      ScoreDisplay(
                        score: playerScore,
                        color: kPlayerPaddleColor,
                        label: "YOU",
                      ),
                    ],
                  ),
                ),

                // Score message
                if (scoreMessage.isNotEmpty)
                  Positioned(
                    top: gameHeight * 0.4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        scoreMessage,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: kAccentColor.withOpacity(0.7),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .scale(duration: 300.ms, curve: Curves.easeOutBack)
                          .then()
                          .fadeOut(delay: 1200.ms, duration: 300.ms),
                    ),
                  ),

                // Touch input detector for the player paddle
                // Only active when game is not paused
                if (!isPaused)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      // Changed from onPanStart to onPanDown for better responsiveness
                      onPanDown: (details) {
                        if (isGameActive) {
                          touchYPosition = details.localPosition.dy;
                          _handlePaddleInput(touchYPosition);

                          // Start game if it was in initial state
                          if (ballSpeedX == 0 && ballSpeedY == 0) {
                            _startCountdown();
                          }
                        }
                      },
                      onPanStart: (details) {
                        if (isGameActive) {
                          touchYPosition = details.localPosition.dy;
                          _handlePaddleInput(touchYPosition);
                        }
                      },
                      onPanUpdate: (details) {
                        if (isGameActive) {
                          touchYPosition = details.localPosition.dy;
                          _handlePaddleInput(touchYPosition);
                        }
                      },
                      onPanEnd: (details) {
                        // We don't null the touchYPosition anymore to maintain paddle control
                        // This allows the player to continue controlling after a point is scored
                      },
                      onTap: () {
                        if (!isGameActive && !isCountingDown) {
                          _startCountdown();
                        }
                      },
                      onDoubleTap: () {
                        // Double tap to pause
                        if (isGameActive) {
                          _togglePause();
                        }
                      },
                    ),
                  ),

                // Countdown overlay
                if (isCountingDown)
                  AnimatedBuilder(
                    animation: _countdownController,
                    builder: (context, child) {
                      return Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.7),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  countdown > 0 ? "$countdown" : "GO!",
                                  style: TextStyle(
                                    fontSize: 80,
                                    fontWeight: FontWeight.bold,
                                    color: countdown > 0
                                        ? Colors.white
                                        : kPlayerPaddleColor,
                                  ),
                                ).animate().scale(
                                  duration: 700.ms,
                                  curve: Curves.elasticOut,
                                ),

                                if (countdown <= 0)
                                  Text(
                                    "Use arrow keys or touch to move paddle",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ).animate().fade(delay: 300.ms),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                // Pause overlay - keep this above the GestureDetector
                // to ensure pause buttons work correctly
                if (isPaused)
                  AnimatedBuilder(
                    animation: _pauseOverlayController,
                    builder: (context, child) {
                      final opacity = _pauseOverlayController.value;

                      return Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.7 * opacity),
                          child: Opacity(
                            opacity: opacity,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    "PAUSED",
                                    style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 40),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildPauseButton(
                                        Icons.play_arrow,
                                        "RESUME",
                                        kAccentColor,
                                            () {
                                          print('RESUME button pressed');
                                          _togglePause();
                                        },
                                      ),
                                      const SizedBox(width: 20),
                                      _buildPauseButton(
                                        Icons.exit_to_app,
                                        "QUIT",
                                        kSecondaryColor,
                                            () {
                                          print('QUIT button pressed');
                                          _handleQuit();
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                // Debug info overlay
                if (gameState.showAIDebug)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.all(10),
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
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                          Text(
                            "Ball: (${ballX.toStringAsFixed(1)}, ${ballY.toStringAsFixed(1)})",
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                          Text(
                            "Velocity: (${ballSpeedX.toStringAsFixed(1)}, ${ballSpeedY.toStringAsFixed(1)})",
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                          Text(
                            "AI Hit Rate: ${(aiHits / math.max(1, aiHits + aiMisses) * 100).toStringAsFixed(1)}%",
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                          Text(
                            "Settings: Speed ${_ballSpeedMultiplier.toStringAsFixed(1)}x, Sens ${_paddleSensitivity.toStringAsFixed(1)}x",
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                          Text(
                            "Difficulty: ${gameState.difficulty.toString().split('.').last}",
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                          Text(
                            "Audio: ${_audioInitialized ? 'Working' : 'Not Initialized'}",
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Control buttons - always visible
                Positioned(
                  right: 20,
                  top: 5,
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () {
                          if (isGameActive && !isPaused) {
                            _togglePause();
                          }
                        },
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.3),
                            border: Border.all(color: kAccentColor.withOpacity(0.6)),
                          ),
                          child: const Icon(
                            Icons.pause,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Current Time and User display in bottom right corner
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Text(
                    "",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPauseButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
            color: Colors.black.withOpacity(0.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
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

// Helper class for particle effects
class ParticleEffect {
  double x;
  double y;
  Color color;
  math.Point<double> velocity;
  double size;
  int lifetime;
  int age = 0;

  ParticleEffect({
    required this.x,
    required this.y,
    required this.color,
    required this.velocity,
    required this.size,
    required this.lifetime,
  });

  void update() {
    x += velocity.x;
    y += velocity.y;
    velocity = math.Point(velocity.x * 0.94, velocity.y * 0.94); // Apply drag
    age++;
  }

  bool get isDead => age >= lifetime;

  double get opacity => 1.0 - (age / lifetime);
}

// Helper class for score effects
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

// Custom painter for particle effects
class EffectsPainter extends CustomPainter {
  final List<ParticleEffect> particles;
  final List<ScoreEffect> scoreEffects;

  EffectsPainter(this.particles, this.scoreEffects);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw particles
    for (final particle in particles) {
      final paint = Paint()
        ..color = particle.color.withOpacity(particle.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size,
        paint,
      );
    }

    // Draw score effects
    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 36,
      fontWeight: FontWeight.bold,
    );


    for (final effect in scoreEffects) {
      // Set up text painting
      final textSpan = TextSpan(
        text: effect.text,
        style: textStyle.copyWith(
          color: effect.color.withOpacity(effect.opacity),
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Apply scaling and draw
      canvas.save();
      canvas.translate(effect.x, effect.y);
      canvas.scale(effect.scale, effect.scale);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(EffectsPainter oldDelegate) => true;
}

// Score display widget
class ScoreDisplay extends StatelessWidget {
  final int score;
  final Color color;
  final String label;

  const ScoreDisplay({
    super.key,
    required this.score,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        AnimatedScale(
          scale: score > 0 ? 1.0 : 0.8,
          duration: const Duration(milliseconds: 300),
          child: Text(
            score.toString(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: color.withOpacity(0.7),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


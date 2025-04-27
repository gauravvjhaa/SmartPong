import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:rive/rive.dart' hide LinearGradient;

import 'game/pong_game.dart';
import 'ui/game_screen.dart';
import 'ui/settings_screen.dart';
import 'ai/ai_player.dart';
import 'ai/model_loader.dart';

// Game theme colors
const Color kBackgroundColor = Color(0xFF121212);
const Color kAccentColor = Color(0xFF00C6FF);
const Color kSecondaryColor = Color(0xFFFF5252);
const Color kPlayerColor = Color(0xFF4CAF50);
const Color kAIColor = Color(0xFFFFEB3B);
const Color kNeonGlow = Color(0xFF00FFFF);

// Game state management
enum GameScreenEnum { splash, menu, play, settings, gameOver }
enum GameDifficulty { easy, medium, hard, custom }

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Use system overlay style for immersive experience
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Load user preferences and AI model
  final prefs = await SharedPreferences.getInstance();
  final modelLoader = ModelLoader();
  await modelLoader.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameStateProvider()),
        ChangeNotifierProvider.value(value: modelLoader),
        Provider.value(value: prefs),
      ],
      child: const PongAIApp(),
    ),
  );
}

class GameStateProvider extends ChangeNotifier {
  GameScreenEnum _currentScreen = GameScreenEnum.splash;
  GameDifficulty _difficulty = GameDifficulty.medium;
  bool _soundEnabled = true;
  bool _showAIDebug = false;
  int _playerScore = 0;
  int _aiScore = 0;
  double _aiHitRate = 0.0;

  // Add this property to store all settings
  GameSettings _settings = GameSettings(
    difficulty: GameDifficulty.medium,
    paddleSensitivity: 0.5,  // Default values
    ballSpeed: 0.5,          // Default values
    soundEnabled: true,
    masterVolume: 0.7,
    sfxVolume: 0.8,
    musicVolume: 0.5,
    showAIDebug: false,
  );

  // Getters
  GameScreenEnum get currentScreen => _currentScreen;
  GameDifficulty get difficulty => _difficulty;
  bool get soundEnabled => _soundEnabled;
  bool get showAIDebug => _showAIDebug;
  int get playerScore => _playerScore;
  int get aiScore => _aiScore;
  double get aiHitRate => _aiHitRate;

  // New getter for the settings object
  GameSettings get settings => _settings;

  // Navigation methods
  void navigateTo(GameScreenEnum screen) {
    print("Navigating to screen: $screen");
    _currentScreen = screen;
    notifyListeners();
  }

  // Update the difficulty method
  void setDifficulty(GameDifficulty difficulty) {
    _settings = _settings.copyWith(difficulty: difficulty);
    notifyListeners();
  }

  // Update the sound toggle method
  void toggleSound() {
    _settings = _settings.copyWith(soundEnabled: !_settings.soundEnabled);
    notifyListeners();
  }

  // Update the AI debug toggle method
  void toggleAIDebug() {
    _settings = _settings.copyWith(showAIDebug: !_settings.showAIDebug);
    notifyListeners();
  }

  // Method to save settings to SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('difficulty', _settings.difficulty.toString());
      prefs.setDouble('paddleSensitivity', _settings.paddleSensitivity);
      prefs.setDouble('ballSpeed', _settings.ballSpeed);
      prefs.setBool('soundEnabled', _settings.soundEnabled);
      prefs.setDouble('masterVolume', _settings.masterVolume);
      prefs.setDouble('sfxVolume', _settings.sfxVolume);
      prefs.setDouble('musicVolume', _settings.musicVolume);
      prefs.setBool('showAIDebug', _settings.showAIDebug);
    } catch (e) {
      print('Error saving settings: $e');
    }
  }

  // Method to update all settings at once
  void updateSettings(GameSettings newSettings) {
    _settings = newSettings;
    notifyListeners();

    // Save settings to SharedPreferences
    _saveSettings();
  }

  // Method to update specific settings
  void updateGameplaySettings({
    double? paddleSensitivity,
    double? ballSpeed,
  }) {
    _settings = _settings.copyWith(
      paddleSensitivity: paddleSensitivity,
      ballSpeed: ballSpeed,
    );
    notifyListeners();

    // Save settings to SharedPreferences
    _saveSettings();
  }

  // Game state updates
  void updateScores(int playerScore, int aiScore) {
    _playerScore = playerScore;
    _aiScore = aiScore;
    notifyListeners();
  }

  // Method to load settings from SharedPreferences
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load difficulty
      final difficultyStr = prefs.getString('difficulty');
      GameDifficulty loadedDifficulty = GameDifficulty.medium;
      if (difficultyStr != null) {
        loadedDifficulty = GameDifficulty.values.firstWhere(
              (e) => e.toString() == difficultyStr,
          orElse: () => GameDifficulty.medium,
        );
      }

      // Load other settings
      _settings = GameSettings(
        difficulty: loadedDifficulty,
        paddleSensitivity: prefs.getDouble('paddleSensitivity') ?? 0.5,
        ballSpeed: prefs.getDouble('ballSpeed') ?? 0.5,
        soundEnabled: prefs.getBool('soundEnabled') ?? true,
        masterVolume: prefs.getDouble('masterVolume') ?? 0.7,
        sfxVolume: prefs.getDouble('sfxVolume') ?? 0.8,
        musicVolume: prefs.getDouble('musicVolume') ?? 0.5,
        showAIDebug: prefs.getBool('showAIDebug') ?? false,
      );

      notifyListeners();
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  void updateAIStats(double hitRate) {
    _aiHitRate = hitRate;
    notifyListeners();
  }

  void resetGame() {
    _playerScore = 0;
    _aiScore = 0;
    _aiHitRate = 0.0;
    notifyListeners();
  }
}

class PongAIApp extends StatelessWidget {
  const PongAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pong AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: kAccentColor,
        scaffoldBackgroundColor: kBackgroundColor,
        textTheme: GoogleFonts.pressStart2pTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccentColor,
          brightness: Brightness.dark,
          secondary: kSecondaryColor,
        ),
      ),
      home: const GameContainer(),
    );
  }
}

class GameContainer extends StatefulWidget {
  const GameContainer({super.key});

  @override
  State<GameContainer> createState() => _GameContainerState();
}

class _GameContainerState extends State<GameContainer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _backgroundAnimation;
  late AIPlayer _aiPlayer;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Create background animation
    _backgroundAnimation = Tween<double>(begin: 0, end: 2 * math.pi)
        .animate(_controller);

    // Initialize AI player
    _aiPlayer = AIPlayer(
      Provider.of<ModelLoader>(context, listen: false),
      difficulty: GameDifficulty.medium,
    );

    // Show splash screen, then navigate to menu after delay
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Provider.of<GameStateProvider>(context, listen: false)
            .navigateTo(GameScreenEnum.menu);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use listen: true to ensure the widget rebuilds when state changes
    final gameState = Provider.of<GameStateProvider>(context, listen: true);

    // Debug print to track screen changes
    print("GameContainer rebuilding with screen: ${gameState.currentScreen}");

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black,
              Colors.indigo.shade900,
              Colors.black,
            ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _backgroundAnimation,
          builder: (context, child) {
            return Stack(
              children: [
                // Animated background grid
                CustomPaint(
                  size: Size.infinite,
                  painter: GridPainter(_backgroundAnimation.value),
                ),

                // Main content based on current screen - use AnimatedSwitcher for transitions
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildCurrentScreen(gameState.currentScreen),
                ),

                // Floating elements
                Positioned(
                  top: 16,
                  right: 16,
                  child: _buildInfoPanel(gameState),
                ),

                // Navigation buttons for non-play screens
                if (gameState.currentScreen != GameScreenEnum.play &&
                    gameState.currentScreen != GameScreenEnum.splash)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: _buildNavigationButtons(gameState),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCurrentScreen(GameScreenEnum screen) {
    // Using keys helps Flutter distinguish between different screens
    switch (screen) {
      case GameScreenEnum.splash:
        return _buildSplashScreen(key: const ValueKey('splash'));
      case GameScreenEnum.menu:
        return _buildMenuScreen(key: const ValueKey('menu'));
      case GameScreenEnum.play:
        return _buildGameScreen(key: const ValueKey('play'));
      case GameScreenEnum.settings:
        return _buildSettingsScreen(key: const ValueKey('settings'));
      case GameScreenEnum.gameOver:
        return _buildGameOverScreen(key: const ValueKey('gameover'));
    }
  }

  Widget _buildSplashScreen({Key? key}) {
    return Center(
      key: key,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated logo
          const RiveAnimation.asset(
            'assets/animations/pong_logo.riv',
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ).animate().fade(duration: 800.ms).scale(),

          const SizedBox(height: 40),

          // Loading indicator
          const CircularProgressIndicator(
            color: kAccentColor,
            strokeWidth: 3,
          ).animate().fade(delay: 300.ms),

          const SizedBox(height: 20),

          // Loading text
          Text(
            'Loading AI Model...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
            ),
          ).animate().fade(delay: 500.ms),
        ],
      ),
    );
  }

  Widget _buildMenuScreen({Key? key}) {
    return Center(
      key: key,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Game title
              const Text(
                'PONG AI',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: kNeonGlow,
                      blurRadius: 20,
                    ),
                  ],
                ),
              ).animate()
                  .fade(duration: 400.ms)
                  .slide(begin: const Offset(0, -0.2), curve: Curves.easeOutQuad),

              const SizedBox(height: 40),

              // Menu buttons
              Container(
                width: isWide ? 500 : 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: kAccentColor.withOpacity(0.3), width: 1),
                  color: Colors.black.withOpacity(0.3),
                ),
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    _buildMenuButton(
                      'PLAY VS AI',
                      Icons.sports_esports,
                          () {
                        Provider.of<GameStateProvider>(context, listen: false)
                            .navigateTo(GameScreenEnum.play);
                      },
                    ),
                    _buildMenuDivider(),
                    _buildMenuButton(
                      'SETTINGS',
                      Icons.settings,
                          () {
                        Provider.of<GameStateProvider>(context, listen: false)
                            .navigateTo(GameScreenEnum.settings);
                      },
                    ),
                    _buildMenuDivider(),
                    _buildMenuButton(
                      'EXIT',
                      Icons.exit_to_app,
                          () {
                        SystemNavigator.pop();
                      },
                    ),
                  ]
                      .animate(interval: 200.ms)
                      .fade(duration: 400.ms, delay: 200.ms)
                      .slide(begin: const Offset(0.2, 0)),
                ),
              ),

              const SizedBox(height: 30),

              // Version info
              Text(
                '© RavvApps 2025',  // Updated date
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
              ).animate().fade(delay: 1000.ms),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMenuDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kAccentColor.withOpacity(0),
              kAccentColor.withOpacity(0.5),
              kAccentColor.withOpacity(0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(String title, IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: kAccentColor),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameScreen({Key? key}) {
    return GameScreen(key: key);
  }

  Widget _buildSettingsScreen({Key? key}) {
    return SettingsScreen(key: key);
  }

  Widget _buildGameOverScreen({Key? key}) {
    final gameState = Provider.of<GameStateProvider>(context);
    final playerWon = gameState.playerScore > gameState.aiScore;

    return Center(
      key: key,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Game over text with animation
          Text(
            playerWon ? 'YOU WIN!' : 'AI WINS!',
            style: TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.bold,
              color: playerWon ? kPlayerColor : kAIColor,
              shadows: [
                Shadow(
                  color: playerWon ? kPlayerColor.withOpacity(0.7) : kAIColor.withOpacity(0.7),
                  blurRadius: 15,
                ),
              ],
            ),
          ).animate()
              .fade(duration: 500.ms)
              .scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1))
              .then()
              .shimmer(duration: 1200.ms, color: Colors.white.withOpacity(0.9)),

          const SizedBox(height: 30),

          // Score display
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 50),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: kAccentColor.withOpacity(0.6), width: 2),
            ),
            child: Column(
              children: [
                Text(
                  'FINAL SCORE',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'YOU',
                          style: TextStyle(
                            fontSize: 16,
                            color: kPlayerColor,
                          ),
                        ),
                        Text(
                          '${gameState.playerScore}',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: kPlayerColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 50),
                    Column(
                      children: [
                        const Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 16,
                            color: kAIColor,
                          ),
                        ),
                        Text(
                          '${gameState.aiScore}',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: kAIColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                  'AI Hit Rate: ${(gameState.aiHitRate * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ).animate().fade(delay: 400.ms, duration: 800.ms),

          const SizedBox(height: 40),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildActionButton(
                'PLAY AGAIN',
                Icons.refresh,
                    () {
                  gameState.resetGame();
                  gameState.navigateTo(GameScreenEnum.play);
                },
              ),
              const SizedBox(width: 20),
              _buildActionButton(
                'MAIN MENU',
                Icons.home,
                    () {
                  gameState.resetGame();
                  gameState.navigateTo(GameScreenEnum.menu);
                },
              ),
            ],
          ).animate().fade(delay: 800.ms, duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccentColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoPanel(GameStateProvider gameState) {
    if (gameState.currentScreen == GameScreenEnum.splash) {
      return const SizedBox.shrink();
    }

    // Current date display
    return Container(
      // padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // decoration: BoxDecoration(
      //   color: Colors.black.withOpacity(0.5),
      //   borderRadius: BorderRadius.circular(8),
      //   border: Border.all(color: kAccentColor.withOpacity(0.4)),
      // ),
      // child: Text(
      //   '2025-04-26',  // Updated date
      //   style: TextStyle(
      //     color: Colors.white.withOpacity(0.7),
      //     fontSize: 12,
      //   ),
      // ),
    );
  }

  Widget _buildNavigationButtons(GameStateProvider gameState) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.volume_up),
          color: gameState.soundEnabled ? kAccentColor : Colors.white.withOpacity(0.4),
          onPressed: () => gameState.toggleSound(),
          tooltip: 'Toggle Sound',
        ),
        IconButton(
          icon: const Icon(Icons.home),
          color: Colors.white,
          onPressed: () => gameState.navigateTo(GameScreenEnum.menu),
          tooltip: 'Main Menu',
        ),
      ],
    );
  }
}

// Animated grid background
class GridPainter extends CustomPainter {
  final double animationValue;

  GridPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final paint = Paint()
      ..color = kAccentColor.withOpacity(0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw horizontal lines with wave effect
    for (int i = 0; i < height / 40; i++) {
      final path = Path();
      final y = i * 40.0;

      path.moveTo(0, y);
      for (double x = 0; x < width; x += 20) {
        final wave = math.sin(x / 100 + animationValue + i * 0.2) * 5;
        path.lineTo(x, y + wave);
      }

      canvas.drawPath(path, paint);
    }

    // Draw vertical lines with perspective effect
    for (int i = 0; i <= width / 40; i++) {
      final x = i * 40.0;

      // Create perspective distortion
      final perspectiveShiftTop = (x - width / 2) * 0.1 * math.sin(animationValue * 0.5);
      final perspectiveShiftBottom = (x - width / 2) * 0.2 * math.sin(animationValue * 0.5);

      final path = Path();
      path.moveTo(x + perspectiveShiftTop, 0);
      path.lineTo(x + perspectiveShiftBottom, height);

      canvas.drawPath(path, paint);
    }

    // Draw animated particles
    final particlePaint = Paint()
      ..color = kNeonGlow.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 20; i++) {
      final seed = i * 123.456;
      final x = ((math.sin(seed + animationValue) + 1) / 2) * width;
      final y = ((math.cos(seed * 2 + animationValue * 1.5) + 1) / 2) * height;
      final size = (math.sin(animationValue + seed * 3) + 1) * 2 + 1;

      canvas.drawCircle(Offset(x, y), size, particlePaint);
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

// Add this class to main.dart for storing game settings
class GameSettings {
  final GameDifficulty difficulty;
  final double paddleSensitivity; // 0.0-1.0 value
  final double ballSpeed; // 0.0-1.0 value
  final bool soundEnabled;
  final double masterVolume;
  final double sfxVolume;
  final double musicVolume;
  final bool showAIDebug;

  GameSettings({
    required this.difficulty,
    required this.paddleSensitivity,
    required this.ballSpeed,
    required this.soundEnabled,
    required this.masterVolume,
    required this.sfxVolume,
    required this.musicVolume,
    required this.showAIDebug,
  });

  // Create a copy with updated values
  GameSettings copyWith({
    GameDifficulty? difficulty,
    double? paddleSensitivity,
    double? ballSpeed,
    bool? soundEnabled,
    double? masterVolume,
    double? sfxVolume,
    double? musicVolume,
    bool? showAIDebug,
  }) {
    return GameSettings(
      difficulty: difficulty ?? this.difficulty,
      paddleSensitivity: paddleSensitivity ?? this.paddleSensitivity,
      ballSpeed: ballSpeed ?? this.ballSpeed,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      masterVolume: masterVolume ?? this.masterVolume,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      musicVolume: musicVolume ?? this.musicVolume,
      showAIDebug: showAIDebug ?? this.showAIDebug,
    );
  }
}
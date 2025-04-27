import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';

import '../main.dart';
import '../ai/model_loader.dart';

// Game colors
const Color kBackgroundColor = Color(0xFF121212);
const Color kAccentColor = Color(0xFF00C6FF);
const Color kSecondaryColor = Color(0xFFFF5252);
const Color kPlayerColor = Color(0xFF4CAF50);
const Color kAIColor = Color(0xFFFFEB3B);
const Color kNeonGlow = Color(0xFF00FFFF);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
  late AnimationController _backgroundController;
  late AnimationController _cardController;
  late TabController _tabController;

  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Particle system for background effect
  late List<Particle> _particles;

  // Game settings
  double _paddleSensitivity = 0.5;
  double _ballSpeed = 0.5;

  // Audio settings
  double _masterVolume = 0.7;
  double _sfxVolume = 0.8;
  double _musicVolume = 0.5;

  // Model info
  bool _isModelLoaded = false;
  String _modelStatus = "Loading...";

  // UI refresh key - to force rebuild of specific sections
  final GlobalKey _difficultyRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(minutes: 20),
    )..repeat();

    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();

    _tabController = TabController(length: 3, vsync: this);

    // Initialize particle system for background
    _particles = List.generate(50, (_) => _createParticle());
    _startParticleAnimation();

    // Load current settings
    _loadSettings();

    // Initialize audio
    _initAudio();

    // Check model status
    _checkModelStatus();
  }

  // Load settings from GameStateProvider
  void _loadSettings() {
    final gameState = Provider.of<GameStateProvider>(context, listen: false);
    final settings = gameState.settings;

    setState(() {
      // Load gameplay settings
      _paddleSensitivity = settings.paddleSensitivity;
      _ballSpeed = settings.ballSpeed;

      // Load audio settings
      _masterVolume = settings.masterVolume;
      _musicVolume = settings.musicVolume;
      _sfxVolume = settings.sfxVolume;
    });

    print("Settings loaded - paddle: $_paddleSensitivity, ball: $_ballSpeed, difficulty: ${settings.difficulty}");
  }

  // Check model loading status
  void _checkModelStatus() {
    final modelLoader = Provider.of<ModelLoader>(context, listen: false);

    setState(() {
      _isModelLoaded = modelLoader.isInitialized;
      _modelStatus = modelLoader.isLoading
          ? "Loading models..."
          : modelLoader.hasError
          ? "Error: ${modelLoader.errorMessage}"
          : modelLoader.isInitialized
          ? "Models loaded successfully"
          : "Models not loaded";
    });

    // If models are still loading, check again in a second
    if (modelLoader.isLoading) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _checkModelStatus();
        }
      });
    }
  }

  void _initAudio() async {
    final gameState = Provider.of<GameStateProvider>(context, listen: false);
    if (gameState.soundEnabled) {
      try {
        await _audioPlayer.setVolume(_musicVolume * _masterVolume);
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.setSourceAsset('audio/background_music.mp3');
        await _audioPlayer.resume();
      } catch (e) {
        print("Error playing audio: $e");
      }
    }
  }

  void _playSound(String soundEffect) async {
    final effectPlayer = AudioPlayer();
    final gameState = Provider.of<GameStateProvider>(context, listen: false);

    if (gameState.soundEnabled) {
      try {
        await effectPlayer.setVolume(_sfxVolume * _masterVolume);
        await effectPlayer.setSourceAsset('audio/$soundEffect.mp3');
        await effectPlayer.resume();
      } catch (e) {
        print("Error playing sound effect: $e");
      }
    }
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _cardController.dispose();
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Particle _createParticle() {
    return Particle(
      x: math.Random().nextDouble(),
      y: math.Random().nextDouble(),
      size: math.Random().nextDouble() * 3 + 1,
      speed: math.Random().nextDouble() * 0.003 + 0.001,
      angle: math.Random().nextDouble() * 2 * math.pi,
      color: _getRandomColor(),
    );
  }

  Color _getRandomColor() {
    final colors = [
      kAccentColor.withOpacity(0.4),
      kPlayerColor.withOpacity(0.3),
      kAIColor.withOpacity(0.3),
    ];
    return colors[math.Random().nextInt(colors.length)];
  }

  void _startParticleAnimation() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;

      setState(() {
        for (var particle in _particles) {
          particle.move();
          if (particle.x < 0 || particle.x > 1 || particle.y < 0 || particle.y > 1) {
            if (math.Random().nextBool()) {
              particle.x = math.Random().nextBool() ? 0 : 1;
              particle.y = math.Random().nextDouble();
            } else {
              particle.x = math.Random().nextDouble();
              particle.y = math.Random().nextBool() ? 0 : 1;
            }
            particle.angle = math.Random().nextDouble() * 2 * math.pi;
          }
        }
      });

      _startParticleAnimation();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen to GameStateProvider updates
    final gameState = Provider.of<GameStateProvider>(context);
    final modelLoader = Provider.of<ModelLoader>(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Animated Background
          CustomPaint(
            size: Size.infinite,
            painter: ParticlePainter(_particles, _backgroundController.value),
          ),

          // Main Content
          SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: _cardController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.9 + (_cardController.value * 0.1),
                    child: Opacity(
                      opacity: _cardController.value,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: math.min(600, size.width * 0.95),
                  height: math.min(600, size.height * 0.85),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kAccentColor.withOpacity(0.5), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: kNeonGlow.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Column(
                        children: [
                          // Header
                          _buildHeader(),

                          // Tab bar
                          TabBar(
                            controller: _tabController,
                            tabs: const [
                              Tab(icon: Icon(Icons.sports_esports), text: "Gameplay"),
                              Tab(icon: Icon(Icons.volume_up), text: "Audio"),
                              Tab(icon: Icon(Icons.info), text: "About"),
                            ],
                            indicatorColor: kAccentColor,
                            labelColor: kAccentColor,
                            unselectedLabelColor: Colors.white.withOpacity(0.6),
                          ),

                          // Tab content
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildGameplaySettings(gameState),
                                _buildAudioSettings(gameState),
                                _buildAboutInfo(modelLoader),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Save button
          Positioned(
            right: 24,
            top: 60,
            child: ElevatedButton.icon(
              onPressed: () => _saveSettings(gameState),
              icon: const Icon(Icons.save),
              label: const Text("SAVE"),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              ),
            ).animate().fade(delay: 300.ms),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: kAccentColor.withOpacity(0.3), width: 2),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: kAccentColor, size: 28),
            onPressed: () {
              Provider.of<GameStateProvider>(context, listen: false)
                  .navigateTo(GameScreenEnum.menu);
            },
          ),
          const SizedBox(width: 15),
          Text(
            "SETTINGS",
            style: GoogleFonts.pressStart2p(
              textStyle: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: kNeonGlow.withOpacity(0.8),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameplaySettings(GameStateProvider gameState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle("Difficulty"),
          const SizedBox(height: 20),

          // Difficulty selector - simplified
          Row(
            key: _difficultyRowKey,
            children: [
              _buildDifficultyButton(
                gameState,
                GameDifficulty.easy,
                "EASY",
                Icons.sentiment_satisfied,
              ),
              const SizedBox(width: 12),
              _buildDifficultyButton(
                gameState,
                GameDifficulty.medium,
                "MEDIUM",
                Icons.sentiment_neutral,
              ),
              const SizedBox(width: 12),
              _buildDifficultyButton(
                gameState,
                GameDifficulty.hard,
                "HARD",
                Icons.sentiment_very_dissatisfied,
              ),
            ],
          ),

          const SizedBox(height: 32),
          _buildSectionTitle("Game Controls"),
          const SizedBox(height: 20),

          // Paddle sensitivity
          _buildSliderSetting(
            "Paddle Sensitivity",
            _paddleSensitivity,
                (value) => setState(() => _paddleSensitivity = value),
            icon: Icons.swipe,
          ),

          const SizedBox(height: 20),

          // Ball speed
          _buildSliderSetting(
            "Ball Speed",
            _ballSpeed,
                (value) => setState(() => _ballSpeed = value),
            icon: Icons.speed,
          ),

          const SizedBox(height: 20),

          // AI debug toggle
          _buildSwitchSetting(
            "Show AI Debug Info",
            gameState.showAIDebug,
                (value) => gameState.toggleAIDebug(),
            icon: Icons.bug_report,
          ),

          // Model status indicator
          const SizedBox(height: 32),
          _buildSectionTitle("AI Model Status"),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isModelLoaded ? Colors.green.withOpacity(0.5) : Colors.orange.withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isModelLoaded ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _modelStatus,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
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

  Widget _buildAudioSettings(GameStateProvider gameState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSwitchSetting(
            "Sound Enabled",
            gameState.soundEnabled,
                (value) {
              gameState.toggleSound();
              if (gameState.soundEnabled) {
                _initAudio();
              } else {
                _audioPlayer.pause();
              }
            },
            icon: gameState.soundEnabled ? Icons.volume_up : Icons.volume_off,
          ),

          const SizedBox(height: 24),
          Opacity(
            opacity: gameState.soundEnabled ? 1.0 : 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSliderSetting(
                  "Master Volume",
                  _masterVolume,
                      (value) {
                    setState(() => _masterVolume = value);
                    if (gameState.soundEnabled) {
                      _audioPlayer.setVolume(_musicVolume * _masterVolume);
                    }
                  },
                  icon: _getVolumeIcon(_masterVolume),
                  enabled: gameState.soundEnabled,
                ),

                const SizedBox(height: 20),
                _buildSliderSetting(
                  "Music Volume",
                  _musicVolume,
                      (value) {
                    setState(() => _musicVolume = value);
                    if (gameState.soundEnabled) {
                      _audioPlayer.setVolume(_musicVolume * _masterVolume);
                    }
                  },
                  icon: Icons.music_note,
                  enabled: gameState.soundEnabled,
                ),

                const SizedBox(height: 20),
                _buildSliderSetting(
                  "Sound Effects",
                  _sfxVolume,
                      (value) => setState(() => _sfxVolume = value),
                  icon: Icons.waves,
                  enabled: gameState.soundEnabled,
                ),

                const SizedBox(height: 32),
                _buildSectionTitle("Sound Test"),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSoundButton("Paddle Hit", Icons.sports_baseball, "paddle_hit"),
                    const SizedBox(width: 24),
                    _buildSoundButton("Score", Icons.celebration, "score"),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutInfo(ModelLoader modelLoader) {
    final modelInfo = modelLoader.getModelInfo();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Game information
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kAccentColor.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow("Game Version", "1.0.0"),
                _buildInfoRow("Release Date", "2025-04-26"),
                _buildInfoRow("AI Model", modelInfo['Version'] ?? "Unknown"),
              ],
            ),
          ).animate().fade(delay: 200.ms),

          // AI Model information
          const SizedBox(height: 24),
          _buildSectionTitle("AI Model Details"),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kAccentColor.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow("Model Version", modelInfo['Version'] ?? "Unknown"),
                _buildInfoRow("Training Date", modelInfo['Training Date'] ?? "Unknown"),
                _buildInfoRow("Framework", modelInfo['Framework'] ?? "Unknown"),
                _buildInfoRow("Source", modelInfo['Source'] ?? "Unknown"),
                _buildInfoRow("Status", modelInfo['Status'] ?? "Unknown"),
              ],
            ),
          ),

          const SizedBox(height: 32),
          _buildSectionTitle("Performance"),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _buildMetricCard("95%", "AI Win Rate", kAccentColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard("14ms", "Response Time", kAIColor),
              ),
            ],
          ).animate().fade(delay: 400.ms),

          const SizedBox(height: 32),
          _buildSectionTitle("About"),
          const SizedBox(height: 20),

          Text(
            "Pong AI combines the classic arcade gameplay with modern machine learning to create a challenging and responsive opponent. The game adapts to your skill level and provides a fun experience for players of all abilities.",
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 15,
              height: 1.5,
            ),
          ).animate().fade(delay: 600.ms),

          const SizedBox(height: 24),
          Text(
            "Created by: Gaurav Kumar Jha",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kAccentColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: kAccentColor,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        shadows: [
          Shadow(
            color: kAccentColor.withOpacity(0.5),
            blurRadius: 10,
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyButton(
      GameStateProvider gameState,
      GameDifficulty difficulty,
      String label,
      IconData icon,
      ) {
    // Check the current difficulty directly from the provider
    final isSelected = gameState.difficulty == difficulty;
    final color = difficulty == GameDifficulty.easy
        ? Colors.green
        : difficulty == GameDifficulty.medium
        ? Colors.orange
        : Colors.red;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          // Only update the provider - don't keep local state
          gameState.setDifficulty(difficulty);
          print("Difficulty selected: $difficulty");
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.3) : Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : Colors.white.withOpacity(0.2),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ] : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ).animate(
      target: isSelected ? 1 : 0,
      effects: [
        MoveEffect(
          begin: const Offset(0, 0),
          end: const Offset(0, -4),
        ),
      ],
    );
  }

  Widget _buildSliderSetting(
      String label,
      double value,
      Function(double) onChanged, {
        IconData? icon,
        bool enabled = true,
      }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) Icon(icon, color: kAccentColor, size: 24),
              if (icon != null) const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                "${(value * 100).toInt()}%",
                style: TextStyle(
                  color: kAccentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: kAccentColor,
              inactiveTrackColor: Colors.white.withOpacity(0.2),
              thumbColor: Colors.white,
              overlayColor: kAccentColor.withOpacity(0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchSetting(
      String label,
      bool value,
      Function(bool) onChanged, {
        IconData? icon,
      }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (icon != null) Icon(icon, color: kAccentColor, size: 24),
            if (icon != null) const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Switch(
          value: value,
          activeColor: kAccentColor,
          activeTrackColor: kAccentColor.withOpacity(0.4),
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: Colors.white.withOpacity(0.2),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSoundButton(String label, IconData icon, String soundFile) {
    return InkWell(
      onTap: () => _playSound(soundFile),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kAccentColor.withOpacity(0.5)),
          color: Colors.black.withOpacity(0.3),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kAccentColor, size: 28),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    ).animate(
      onPlay: (controller) => controller.repeat(reverse: true),
    ).shimmer(
      duration: 2.seconds,
      color: Colors.white.withOpacity(0.2),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 15,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // Save all settings to the GameStateProvider
  void _saveSettings(GameStateProvider gameState) {
    final newSettings = GameSettings(
      difficulty: gameState.difficulty, // Use the provider's value directly
      paddleSensitivity: _paddleSensitivity,
      ballSpeed: _ballSpeed,
      soundEnabled: gameState.soundEnabled,
      masterVolume: _masterVolume,
      sfxVolume: _sfxVolume,
      musicVolume: _musicVolume,
      showAIDebug: gameState.showAIDebug,
    );

    // Update all settings in the provider
    gameState.updateSettings(newSettings);

    // Update AI model to match the selected difficulty
    final modelLoader = Provider.of<ModelLoader>(context, listen: false);
    modelLoader.setActiveDifficulty(gameState.difficulty);

    // Provide user feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Settings saved successfully"),
        backgroundColor: Colors.green,
        duration: Duration(milliseconds: 300),
      ),
    );

    // Log settings for debugging
    print("Settings saved: paddle=$_paddleSensitivity, ball=$_ballSpeed, difficulty=${gameState.difficulty}");
  }

  IconData _getVolumeIcon(double volume) {
    if (volume <= 0) return Icons.volume_off;
    if (volume < 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }
}

// Helper class for background particles
class Particle {
  double x;
  double y;
  double size;
  double speed;
  double angle;
  Color color;

  Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.angle,
    required this.color,
  });

  void move() {
    x += math.cos(angle) * speed;
    y += math.sin(angle) * speed;
  }
}

// Custom painter for background particles
class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double animation;

  ParticlePainter(this.particles, this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw particles
    for (var particle in particles) {
      final paint = Paint()
        ..color = particle.color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.size,
        paint,
      );
    }

    // Draw minimal grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Grid spacing
    const spacing = 60.0;

    // Horizontal lines with subtle wave effect
    for (double y = 0; y < size.height; y += spacing) {
      final path = Path();
      path.moveTo(0, y);
      for (double x = 0; x < size.width; x += 5) {
        final wave = 1.5 * math.sin(x / 120 + animation + y / 200);
        path.lineTo(x, y + wave);
      }
      canvas.drawPath(path, gridPaint);
    }

    // Vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(ParticlePainter oldDelegate) => true;
}
// game/physics.dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vector;

// Physics constants
class PhysicsConstants {
  // Base constants (scaled by display size later)
  static const double defaultBallRadius = 7.5;
  static const double defaultPaddleWidth = 15.0;
  static const double defaultPaddleHeight = 100.0;
  static const double defaultBallMaxSpeed = 15.0;
  static const double defaultBallMinSpeed = 6.0;
  static const double defaultBallAcceleration = 0.05;
  static const double defaultBallSpinEffect = 0.8;
  static const double defaultWallBounceDamping = 0.98;
  static const double defaultPaddleBounceDamping = 1.03;
  static const double defaultGravityEffect = 0.02;

  // Physics behavior modifiers (adjustable via settings)
  static double ballSpeedMultiplier = 1.0;
  static double spinEffectMultiplier = 1.0;
  static double bounceDampingMultiplier = 1.0;
  static double gravityEffectMultiplier = 1.0;
  static bool enableSpin = true;
  static bool enableGravity = false;

  // Collision response thresholds
  static const double edgeHitThreshold = 0.2; // Percentage of paddle height considered "edge"
  static const double sweetSpotThreshold = 0.1; // Percentage of paddle height considered "sweet spot"

  // Hit zone definitions for paddle
  static const double topEdgeStart = 0.0;
  static const double topEdgeEnd = edgeHitThreshold;
  static const double bottomEdgeStart = 1.0 - edgeHitThreshold;
  static const double bottomEdgeEnd = 1.0;
  static const double sweetSpotStart = 0.5 - sweetSpotThreshold;
  static const double sweetSpotEnd = 0.5 + sweetSpotThreshold;

  // Game area boundaries
  static double gameWidth = 800.0;
  static double gameHeight = 600.0;

  // Collision response calibration
  static const double maxBounceAngle = 75.0; // Maximum bounce angle in degrees

  // Time-based physics scaling
  static const double physicsFPS = 60.0; // Target FPS for physics calculations
  static double timeScale = 1.0; // Adjusted based on actual frame rate

  // Update game dimensions
  static void updateGameDimensions(double width, double height) {
    gameWidth = width;
    gameHeight = height;
  }
}

// Core physics objects
class PhysicsObject {
  Vector2D position;
  Vector2D velocity;
  Vector2D acceleration;
  double mass;
  double restitution; // Bounciness
  Rect bounds;

  PhysicsObject({
    required double x,
    required double y,
    double vx = 0.0,
    double vy = 0.0,
    double ax = 0.0,
    double ay = 0.0,
    this.mass = 1.0,
    this.restitution = 1.0,
    required double width,
    required double height,
  }) :
        position = Vector2D(x, y),
        velocity = Vector2D(vx, vy),
        acceleration = Vector2D(ax, ay),
        bounds = Rect.fromLTWH(x, y, width, height);

  void update(double deltaTime) {
    // Apply acceleration to velocity
    velocity.x += acceleration.x * deltaTime * PhysicsConstants.timeScale;
    velocity.y += acceleration.y * deltaTime * PhysicsConstants.timeScale;

    // Apply velocity to position
    position.x += velocity.x * deltaTime * PhysicsConstants.timeScale;
    position.y += velocity.y * deltaTime * PhysicsConstants.timeScale;

    // Update bounds
    bounds = Rect.fromLTWH(position.x, position.y, bounds.width, bounds.height);
  }
}

class Ball extends PhysicsObject {
  double radius;
  double spin = 0.0; // Positive for clockwise, negative for counter-clockwise
  Color color;
  double maxSpeed;
  double speedMultiplier = 1.0;
  TrailEffect trail = TrailEffect();

  Ball({
    required double x,
    required double y,
    double vx = 0.0,
    double vy = 0.0,
    this.radius = PhysicsConstants.defaultBallRadius,
    this.color = Colors.white,
    this.maxSpeed = PhysicsConstants.defaultBallMaxSpeed,
    double mass = 1.0,
    double restitution = 1.0,
  }) : super(
    x: x,
    y: y,
    vx: vx,
    vy: vy,
    mass: mass,
    restitution: restitution,
    width: radius * 2,
    height: radius * 2,
  );

  @override
  void update(double deltaTime) {
    // Add spin effects to velocity if enabled
    if (PhysicsConstants.enableSpin && spin != 0) {
      // Spin affects the y-velocity
      velocity.y += spin * PhysicsConstants.defaultBallSpinEffect *
          PhysicsConstants.spinEffectMultiplier *
          deltaTime * PhysicsConstants.timeScale;

      // Spin decays over time
      spin *= 0.99;
    }

    // Apply gravity if enabled
    if (PhysicsConstants.enableGravity) {
      acceleration.y += PhysicsConstants.defaultGravityEffect *
          PhysicsConstants.gravityEffectMultiplier;
    }

    // Cap maximum speed
    double speed = velocity.magnitude;
    if (speed > maxSpeed * PhysicsConstants.ballSpeedMultiplier) {
      velocity.normalize();
      velocity.scale(maxSpeed * PhysicsConstants.ballSpeedMultiplier);
    }

    // Ensure ball doesn't go too slow horizontally
    if (velocity.x.abs() < PhysicsConstants.defaultBallMinSpeed) {
      velocity.x = PhysicsConstants.defaultBallMinSpeed * (velocity.x < 0 ? -1 : 1);
    }

    // Update trail effect before updating position
    trail.update(position, radius);

    // Call parent update method for standard physics
    super.update(deltaTime);

    // Special bounds handling for ball (different from rectangle bounds)
    bounds = Rect.fromCircle(center: Offset(position.x + radius, position.y + radius), radius: radius);
  }

  // Reset ball to center with optional direction control
  void reset(bool serveToRight) {
    position.x = PhysicsConstants.gameWidth / 2 - radius;
    position.y = PhysicsConstants.gameHeight / 2 - radius;

    // Set initial velocity with some randomization
    double speed = PhysicsConstants.defaultBallMinSpeed * 1.5;
    double angle = math.pi/4 + math.Random().nextDouble() * math.pi/2;

    if (!serveToRight) {
      angle = math.pi - angle; // Serve to the left
    }

    velocity.x = speed * math.cos(angle);
    velocity.y = speed * math.sin(angle) * (math.Random().nextBool() ? 1 : -1);

    acceleration.x = 0;
    acceleration.y = 0;
    spin = 0;
    trail.clear();
  }

  Map<String, dynamic> getDebugInfo() {
    return {
      'position': '(${position.x.toStringAsFixed(1)}, ${position.y.toStringAsFixed(1)})',
      'velocity': '(${velocity.x.toStringAsFixed(1)}, ${velocity.y.toStringAsFixed(1)})',
      'speed': velocity.magnitude.toStringAsFixed(1),
      'spin': spin.toStringAsFixed(2),
    };
  }
}

class Paddle extends PhysicsObject {
  double width;
  double height;
  double moveSpeed;
  Color color;
  bool isAI;
  double targetY = 0;
  double lerpFactor = 0.1; // How quickly to move to target position (0-1)
  HitEffect hitEffect = HitEffect();

  Paddle({
    required double x,
    required double y,
    this.width = PhysicsConstants.defaultPaddleWidth,
    this.height = PhysicsConstants.defaultPaddleHeight,
    this.moveSpeed = 10.0,
    this.color = Colors.white,
    this.isAI = false,
    double mass = double.infinity, // Immovable by default
  }) : super(
    x: x,
    y: y,
    width: width,
    height: height,
    mass: mass,
  );

  @override
  void update(double deltaTime) {
    if (isAI && targetY != position.y) {
      // Smooth AI movement using lerp
      double step = (targetY - position.y) * lerpFactor;
      // Clamp step to max movement speed
      if (step.abs() > moveSpeed * PhysicsConstants.timeScale * deltaTime) {
        step = moveSpeed * PhysicsConstants.timeScale * deltaTime * (step < 0 ? -1 : 1);
      }
      position.y += step;
    }

    // Update hit effect
    hitEffect.update();

    // Keep paddle within game bounds
    position.y = position.y.clamp(0, PhysicsConstants.gameHeight - height);

    // Update bounds
    bounds = Rect.fromLTWH(position.x, position.y, width, height);
  }

  // Set target position for AI paddle
  void setTarget(double y) {
    targetY = y.clamp(0, PhysicsConstants.gameHeight - height);
  }

  // Calculate where on the paddle the ball hit (0 = top, 1 = bottom)
  double getHitPosition(Ball ball) {
    double ballCenter = ball.position.y + ball.radius;
    double paddleTop = position.y;
    return (ballCenter - paddleTop) / height;
  }

  // Trigger hit effect animation
  void triggerHitEffect() {
    hitEffect.trigger();
  }
}

// Physics engine that handles the entire system
class PhysicsEngine {
  Ball ball;
  Paddle leftPaddle;
  Paddle rightPaddle;

  bool isPaused = false;
  double timeAccumulator = 0;
  double fixedTimeStep = 1 / PhysicsConstants.physicsFPS;

  List<BounceEffect> bounceEffects = [];

  // Callback functions for game events
  Function(bool isLeftPaddle)? onPaddleHit;
  Function(bool isLeftPoint)? onScore;
  Function()? onWallHit;
  Function(bool isLeftPaddle, HitZone hitZone)? onSpecialHit;

  PhysicsEngine({
    required this.ball,
    required this.leftPaddle,
    required this.rightPaddle,
  });

  // Factory constructor with default objects
  factory PhysicsEngine.standard() {
    return PhysicsEngine(
      ball: Ball(
        x: PhysicsConstants.gameWidth / 2 - PhysicsConstants.defaultBallRadius,
        y: PhysicsConstants.gameHeight / 2 - PhysicsConstants.defaultBallRadius,
      ),
      leftPaddle: Paddle(
        x: 20,
        y: PhysicsConstants.gameHeight / 2 - PhysicsConstants.defaultPaddleHeight / 2,
        isAI: true,
        color: const Color(0xFFFFEB3B), // Yellow for AI
      ),
      rightPaddle: Paddle(
        x: PhysicsConstants.gameWidth - 20 - PhysicsConstants.defaultPaddleWidth,
        y: PhysicsConstants.gameHeight / 2 - PhysicsConstants.defaultPaddleHeight / 2,
        color: const Color(0xFF4CAF50), // Green for player
      ),
    );
  }

  // Main update function
  void update(double deltaTime) {
    if (isPaused) return;

    // Adjust time scale based on frame rate to keep physics consistent
    PhysicsConstants.timeScale = math.min(2.0, math.max(0.5, 60 * deltaTime));

    // Accumulate time for fixed time step physics
    timeAccumulator += deltaTime;

    // Update physics in fixed time steps for stability
    while (timeAccumulator >= fixedTimeStep) {
      updatePhysics(fixedTimeStep);
      timeAccumulator -= fixedTimeStep;
    }

    // Clean up expired bounce effects
    bounceEffects.removeWhere((effect) => effect.isDead);
  }

  // Fixed time step physics update
  void updatePhysics(double deltaTime) {
    // Update all objects
    ball.update(deltaTime);
    leftPaddle.update(deltaTime);
    rightPaddle.update(deltaTime);

    // Check collisions
    _checkCollisions();

    // Check if ball is out of bounds (scoring)
    _checkScoring();
  }

  // Collision detection and resolution
  void _checkCollisions() {
    // Ball collision with top and bottom walls
    if (ball.position.y <= 0 || ball.position.y + ball.radius * 2 >= PhysicsConstants.gameHeight) {
      ball.velocity.y = -ball.velocity.y * PhysicsConstants.defaultWallBounceDamping;

      // Ensure ball stays in bounds
      if (ball.position.y <= 0) {
        ball.position.y = 0;
      } else {
        ball.position.y = PhysicsConstants.gameHeight - ball.radius * 2;
      }

      // Add bounce effect
      _addBounceEffect(
          ball.position.x + ball.radius,
          ball.position.y + (ball.velocity.y < 0 ? 0 : ball.radius * 2),
          isWall: true
      );

      // Notify wall hit if callback exists
      if (onWallHit != null) {
        onWallHit!();
      }
    }

    // Ball collision with left paddle (AI)
    if (_checkPaddleCollision(leftPaddle)) {
      _handlePaddleCollision(leftPaddle, true);
    }

    // Ball collision with right paddle (Player)
    if (_checkPaddleCollision(rightPaddle)) {
      _handlePaddleCollision(rightPaddle, false);
    }
  }

  // Check if ball collides with a specific paddle
  bool _checkPaddleCollision(Paddle paddle) {
    return ball.bounds.overlaps(paddle.bounds);
  }

  // Handle paddle collision physics and effects
  void _handlePaddleCollision(Paddle paddle, bool isLeftPaddle) {
    // Calculate hit position on paddle (0 = top, 1 = bottom)
    double hitPosition = paddle.getHitPosition(ball);

    // Calculate bounce angle based on hit position
    // Map hitPosition 0-1 to angle range -maxAngle to +maxAngle
    double bounceAngle = mapRange(hitPosition, 0, 1,
        -PhysicsConstants.maxBounceAngle,
        PhysicsConstants.maxBounceAngle);
    bounceAngle = bounceAngle * math.pi / 180; // Convert to radians

    // Calculate new velocity components
    double speed = ball.velocity.magnitude * PhysicsConstants.defaultPaddleBounceDamping;
    double directionX = isLeftPaddle ? 1 : -1; // Direction away from paddle

    // Apply new velocity
    ball.velocity.x = directionX * speed * math.cos(bounceAngle);
    ball.velocity.y = speed * math.sin(bounceAngle);

    // Add spin effect based on hit position
    ball.spin = (hitPosition - 0.5) * 2.0; // -1 to 1

    // Determine hit zone and apply special effects
    HitZone hitZone = _determineHitZone(hitPosition);

    switch (hitZone) {
      case HitZone.topEdge:
      // Sharper angle on top edge hit
        ball.velocity.y -= 2.0;
        break;
      case HitZone.bottomEdge:
      // Sharper angle on bottom edge hit
        ball.velocity.y += 2.0;
        break;
      case HitZone.sweetSpot:
      // Speed boost on sweet spot
        ball.velocity.scale(1.2);
        break;
      case HitZone.normal:
      // Normal bounce
        break;
    }

    // Position correction to prevent sticking
    if (isLeftPaddle) {
      ball.position.x = paddle.position.x + paddle.width;
    } else {
      ball.position.x = paddle.position.x - ball.radius * 2;
    }

    // Trigger paddle hit effect
    paddle.triggerHitEffect();

    // Add visual bounce effect
    _addBounceEffect(
        isLeftPaddle ? paddle.position.x + paddle.width : paddle.position.x,
        ball.position.y + ball.radius,
        isWall: false,
        hitZone: hitZone
    );

    // Trigger callbacks
    if (onPaddleHit != null) {
      onPaddleHit!(isLeftPaddle);
    }

    if (onSpecialHit != null && hitZone != HitZone.normal) {
      onSpecialHit!(isLeftPaddle, hitZone);
    }
  }

  // Check if ball is out of bounds (scoring)
  void _checkScoring() {
    bool scored = false;
    bool isLeftPoint = false;

    // Ball out on left side (player scores)
    if (ball.position.x + ball.radius * 2 < 0) {
      scored = true;
      isLeftPoint = false; // Right (player) scores
    }

    // Ball out on right side (AI scores)
    if (ball.position.x > PhysicsConstants.gameWidth) {
      scored = true;
      isLeftPoint = true; // Left (AI) scores
    }

    if (scored && onScore != null) {
      onScore!(isLeftPoint);
    }
  }

  // Determine which zone of the paddle was hit
  HitZone _determineHitZone(double hitPosition) {
    if (hitPosition <= PhysicsConstants.topEdgeEnd) {
      return HitZone.topEdge;
    } else if (hitPosition >= PhysicsConstants.bottomEdgeStart) {
      return HitZone.bottomEdge;
    } else if (hitPosition >= PhysicsConstants.sweetSpotStart &&
        hitPosition <= PhysicsConstants.sweetSpotEnd) {
      return HitZone.sweetSpot;
    } else {
      return HitZone.normal;
    }
  }

  // Add visual bounce effect
  void _addBounceEffect(double x, double y, {bool isWall = false, HitZone hitZone = HitZone.normal}) {
    // Create different types of effects based on where the ball hit
    Color effectColor;
    int particleCount;

    switch (hitZone) {
      case HitZone.topEdge:
      case HitZone.bottomEdge:
        effectColor = Colors.orange;
        particleCount = 15;
        break;
      case HitZone.sweetSpot:
        effectColor = Colors.purpleAccent;
        particleCount = 20;
        break;
      case HitZone.normal:
      default:
        effectColor = isWall ? Colors.blueAccent : Colors.white;
        particleCount = isWall ? 8 : 12;
        break;
    }

    bounceEffects.add(BounceEffect(
      x: x,
      y: y,
      color: effectColor,
      particleCount: particleCount,
      isWall: isWall,
      hitZone: hitZone,
    ));
  }

  // Reset the entire physics state
  void reset({bool serveToRight = true}) {
    ball.reset(serveToRight);
    leftPaddle.position.y = PhysicsConstants.gameHeight / 2 - leftPaddle.height / 2;
    rightPaddle.position.y = PhysicsConstants.gameHeight / 2 - rightPaddle.height / 2;
    bounceEffects.clear();
  }

  // Utility function to map a value from one range to another
  double mapRange(double value, double min1, double max1, double min2, double max2) {
    return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
  }
}

// Vector class for 2D physics calculations
class Vector2D {
  double x;
  double y;

  Vector2D(this.x, this.y);

  double get magnitude => math.sqrt(x * x + y * y);

  void normalize() {
    double mag = magnitude;
    if (mag > 0) {
      x /= mag;
      y /= mag;
    }
  }

  void scale(double factor) {
    x *= factor;
    y *= factor;
  }

  double dot(Vector2D other) {
    return x * other.x + y * other.y;
  }

  Vector2D reflected(Vector2D normal) {
    double dot2 = 2 * dot(normal);
    return Vector2D(x - normal.x * dot2, y - normal.y * dot2);
  }
}

// Special effect for paddle hits
class HitEffect {
  int duration = 10;
  int currentFrame = 0;
  bool isActive = false;

  void trigger() {
    currentFrame = duration;
    isActive = true;
  }

  void update() {
    if (isActive) {
      currentFrame--;
      if (currentFrame <= 0) {
        isActive = false;
      }
    }
  }

  double get intensity => isActive ? currentFrame / duration : 0.0;
}

// Effect for ball's motion trail
class TrailEffect {
  final int maxPoints = 10;
  final List<Offset> points = [];
  final List<double> sizes = [];

  void update(Vector2D position, double radius) {
    // Add current position to trail
    points.add(Offset(position.x + radius, position.y + radius));
    sizes.add(radius * 2);

    // Keep trail at fixed length
    if (points.length > maxPoints) {
      points.removeAt(0);
      sizes.removeAt(0);
    }
  }

  void clear() {
    points.clear();
    sizes.clear();
  }
}

// Visual effect for ball bounces
class BounceEffect {
  final double x;
  final double y;
  final Color color;
  final int lifetime;
  final bool isWall;
  final HitZone hitZone;
  int age = 0;
  late List<Particle> particles;

  BounceEffect({
    required this.x,
    required this.y,
    required this.color,
    int particleCount = 12,
    this.lifetime = 30,
    this.isWall = false,
    this.hitZone = HitZone.normal,
  }) {
    // Create particles with random directions
    particles = List.generate(particleCount, (_) {
      double angle;
      if (isWall) {
        // Wall hits spray in a half-circle away from the wall
        angle = math.Random().nextDouble() * math.pi - math.pi / 2;
        if (y <= 10) angle += math.pi; // Top wall
        if (y >= PhysicsConstants.gameHeight - 10) angle -= math.pi; // Bottom wall
      } else {
        // Paddle hits spray in a directional pattern
        angle = math.Random().nextDouble() * math.pi - math.pi / 2;
        if (x <= PhysicsConstants.gameWidth / 2) {
          // Left paddle, spray right
          angle -= math.pi / 2;
        } else {
          // Right paddle, spray left
          angle += math.pi / 2;
        }
      }

      double speed = math.Random().nextDouble() * 3.0 + 1.0;

      // Special effects for different hit zones
      double size = math.Random().nextDouble() * 2.0 + 2.0;
      if (hitZone == HitZone.sweetSpot) {
        speed *= 1.5;
        size *= 1.5;
      }

      return Particle(
        x: x,
        y: y,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        size: size,
        color: color,
        decayRate: math.Random().nextDouble() * 0.05 + 0.95,
        fadeRate: 1.0 / (lifetime * 0.7),
      );
    });
  }

  void update() {
    for (var particle in particles) {
      particle.update();
    }
    age++;
  }

  bool get isDead => age >= lifetime;
}

// Individual particle for effects
class Particle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  Color color;
  double opacity = 1.0;
  double decayRate;
  double fadeRate;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    this.decayRate = 0.97,
    this.fadeRate = 0.03,
  });

  void update() {
    x += vx;
    y += vy;
    size *= decayRate;
    opacity -= fadeRate;
    if (opacity < 0) opacity = 0;

    // Add gravity effect
    vy += 0.05;

    // Slow down over time
    vx *= 0.97;
    vy *= 0.97;
  }
}

// Hit zone enum for different paddle collision areas
enum HitZone {
  normal,
  topEdge,
  bottomEdge,
  sweetSpot,
}

// Physics difficulty presets
class PhysicsDifficulty {
  static void setEasyMode() {
    PhysicsConstants.ballSpeedMultiplier = 0.7;
    PhysicsConstants.spinEffectMultiplier = 0.5;
    PhysicsConstants.enableGravity = false;
    PhysicsConstants.gravityEffectMultiplier = 0;
  }

  static void setMediumMode() {
    PhysicsConstants.ballSpeedMultiplier = 1.0;
    PhysicsConstants.spinEffectMultiplier = 0.8;
    PhysicsConstants.enableGravity = false;
    PhysicsConstants.gravityEffectMultiplier = 0;
  }

  static void setHardMode() {
    PhysicsConstants.ballSpeedMultiplier = 1.3;
    PhysicsConstants.spinEffectMultiplier = 1.0;
    PhysicsConstants.enableGravity = false;
    PhysicsConstants.gravityEffectMultiplier = 0;
  }

  static void setCrazyMode() {
    PhysicsConstants.ballSpeedMultiplier = 1.5;
    PhysicsConstants.spinEffectMultiplier = 1.2;
    PhysicsConstants.enableGravity = true;
    PhysicsConstants.gravityEffectMultiplier = 1.0;
  }

  static void setCustomMode({
    double? ballSpeed,
    double? spinEffect,
    bool? gravity,
    double? gravityStrength,
  }) {
    if (ballSpeed != null) PhysicsConstants.ballSpeedMultiplier = ballSpeed;
    if (spinEffect != null) PhysicsConstants.spinEffectMultiplier = spinEffect;
    if (gravity != null) PhysicsConstants.enableGravity = gravity;
    if (gravityStrength != null) PhysicsConstants.gravityEffectMultiplier = gravityStrength;
  }
}

// Physics renderer that handles drawing all physics objects
class PhysicsRenderer {
  final PhysicsEngine engine;
  final bool showDebug;

  PhysicsRenderer(this.engine, {this.showDebug = false});

  void render(Canvas canvas, Size size) {
    // Draw background features (grid lines, etc.) if desired

    // Draw ball trail
    _drawBallTrail(canvas);

    // Draw paddles
    _drawPaddle(canvas, engine.leftPaddle);
    _drawPaddle(canvas, engine.rightPaddle);

    // Draw ball
    _drawBall(canvas, engine.ball);

    // Draw bounce effects
    for (var effect in engine.bounceEffects) {
      _drawBounceEffect(canvas, effect);
    }

    // Draw debug info
    if (showDebug) {
      _drawDebugInfo(canvas, size);
    }
  }

  void _drawBallTrail(Canvas canvas) {
    final trail = engine.ball.trail;

    if (trail.points.isEmpty) return;

    // Draw trail with gradient opacity
    for (int i = 0; i < trail.points.length - 1; i++) {
      final opacity = i / trail.points.length;
      final paint = Paint()
        ..color = engine.ball.color.withOpacity(opacity * 0.5)
        ..style = PaintingStyle.fill;

      final size = trail.sizes[i] * (0.5 + (i / trail.points.length) * 0.5);

      canvas.drawCircle(
        trail.points[i],
        size * 0.5,
        paint,
      );
    }
  }

  void _drawBall(Canvas canvas, Ball ball) {
    // Draw ball glow
    final glowPaint = Paint()
      ..color = ball.color.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawCircle(
      Offset(ball.position.x + ball.radius, ball.position.y + ball.radius),
      ball.radius * 1.5,
      glowPaint,
    );

    // Draw ball
    final paint = Paint()
      ..color = ball.color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(ball.position.x + ball.radius, ball.position.y + ball.radius),
      ball.radius,
      paint,
    );

    // Draw spin indicator (subtle visual cue for spin)
    if (ball.spin.abs() > 0.1) {
      final spinPaint = Paint()
        ..color = ball.spin > 0
            ? Colors.red.withOpacity(0.6)
            : Colors.blue.withOpacity(0.6)
        ..style = PaintingStyle.fill;

      final spinOffset = Offset(
        ball.position.x + ball.radius,
        ball.position.y + ball.radius + (ball.spin > 0 ? -ball.radius * 0.5 : ball.radius * 0.5),
      );

      canvas.drawCircle(spinOffset, ball.radius * 0.3, spinPaint);
    }
  }

  void _drawPaddle(Canvas canvas, Paddle paddle) {
    // Draw paddle glow effect when hit
    if (paddle.hitEffect.isActive) {
      final glowIntensity = paddle.hitEffect.intensity;
      final glowPaint = Paint()
        ..color = paddle.color.withOpacity(glowIntensity * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 15 * glowIntensity);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            paddle.position.x - 5 * glowIntensity,
            paddle.position.y - 5 * glowIntensity,
            paddle.width + 10 * glowIntensity,
            paddle.height + 10 * glowIntensity,
          ),
          const Radius.circular(8),
        ),
        glowPaint,
      );
    }

    // Draw paddle with rounded corners
    final paint = Paint()
      ..color = paddle.color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          paddle.position.x,
          paddle.position.y,
          paddle.width,
          paddle.height,
        ),
        const Radius.circular(4),
      ),
      paint,
    );

    // Draw paddle hit zones if debug is enabled
    if (showDebug) {
      // Draw top edge zone
      canvas.drawRect(
        Rect.fromLTWH(
          paddle.position.x,
          paddle.position.y,
          paddle.width,
          paddle.height * PhysicsConstants.edgeHitThreshold,
        ),
        Paint()..color = Colors.orange.withOpacity(0.5),
      );

      // Draw bottom edge zone
      canvas.drawRect(
        Rect.fromLTWH(
          paddle.position.x,
          paddle.position.y + paddle.height * (1 - PhysicsConstants.edgeHitThreshold),
          paddle.width,
          paddle.height * PhysicsConstants.edgeHitThreshold,
        ),
        Paint()..color = Colors.orange.withOpacity(0.5),
      );

      // Draw sweet spot
      canvas.drawRect(
        Rect.fromLTWH(
          paddle.position.x,
          paddle.position.y + paddle.height * PhysicsConstants.sweetSpotStart,
          paddle.width,
          paddle.height * (PhysicsConstants.sweetSpotEnd - PhysicsConstants.sweetSpotStart),
        ),
        Paint()..color = Colors.purple.withOpacity(0.5),
      );
    }
  }

  void _drawBounceEffect(Canvas canvas, BounceEffect effect) {
    // Progress ratio (0 to 1)
    final progress = effect.age / effect.lifetime;

    // Draw particles
    for (var particle in effect.particles) {
      if (particle.opacity <= 0) continue;

      final paint = Paint()
        ..color = particle.color.withOpacity(particle.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size,
        paint,
      );
    }

    // Draw additional effects based on hit zone
    if (progress < 0.3) {
      switch (effect.hitZone) {
        case HitZone.sweetSpot:
          final ringPaint = Paint()
            ..color = Colors.purpleAccent.withOpacity(0.5 * (1 - progress * 3))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;

          canvas.drawCircle(
            Offset(effect.x, effect.y),
            20 + progress * 30,
            ringPaint,
          );
          break;

        case HitZone.topEdge:
        case HitZone.bottomEdge:
          final linePaint = Paint()
            ..color = Colors.orangeAccent.withOpacity(0.5 * (1 - progress * 3))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;

          // Draw horizontal highlight line
          canvas.drawLine(
            Offset(effect.x - 15, effect.y),
            Offset(effect.x + 15, effect.y),
            linePaint,
          );
          break;

        default:
          break;
      }
    }
  }

  void _drawDebugInfo(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: Colors.white.withOpacity(0.7),
      fontSize: 12,
    );
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final ballInfo = engine.ball.getDebugInfo();

    // Draw ball velocity vector
    final velocityStart = Offset(
      engine.ball.position.x + engine.ball.radius,
      engine.ball.position.y + engine.ball.radius,
    );

    final velocityEnd = Offset(
      velocityStart.dx + engine.ball.velocity.x * 3,
      velocityStart.dy + engine.ball.velocity.y * 3,
    );

    final velocityPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(velocityStart, velocityEnd, velocityPaint);
    canvas.drawCircle(velocityEnd, 2, velocityPaint..style = PaintingStyle.fill);

    // Draw ball info
    String debugText = 'Ball: ${ballInfo['position']}\n'
        + 'Vel: ${ballInfo['velocity']} (${ballInfo['speed']})\n'
        + 'Spin: ${ballInfo['spin']}';

    textPainter.text = TextSpan(text: debugText, style: textStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(10, size.height - textPainter.height - 10));
  }
}

// Extension on the physics engine to add high-level game mechanics
extension PhysicsGameExtensions on PhysicsEngine {
  // Predict where the ball will intersect with the AI paddle's y-position
  double predictBallIntersection() {
    if (ball.velocity.x >= 0) {
      // Ball moving away from AI, use simple tracking
      return ball.position.y;
    }

    // Calculate time to reach the paddle position
    final distanceX = (leftPaddle.position.x + leftPaddle.width) -
        (ball.position.x + ball.radius);

    if (ball.velocity.x == 0) return ball.position.y; // Avoid division by zero

    // Time to reach paddle
    final timeToReach = distanceX / -ball.velocity.x;

    // Predicted y position without taking bounces into account
    double predictedY = ball.position.y + ball.velocity.y * timeToReach;

    // Account for wall bounces
    int bounces = 0;
    final maxBounces = 5; // Limit calculation to prevent infinite loops

    while ((predictedY < 0 || predictedY + ball.radius * 2 > PhysicsConstants.gameHeight) &&
        bounces < maxBounces) {

      if (predictedY < 0) {
        // Bounce off top wall
        predictedY = -predictedY;
      } else {
        // Bounce off bottom wall
        predictedY = 2 * PhysicsConstants.gameHeight - predictedY - ball.radius * 2;
      }

      bounces++;
    }

    // Return the center y-position of the ball
    return predictedY + ball.radius;
  }

  // Adjust AI difficulty by adding prediction errors
  double getAIPaddleTarget(double difficulty) {
    // Base prediction
    double targetY = predictBallIntersection();

    // Add error based on difficulty (0 = perfect, 1 = worst)
    double error = (1 - difficulty) * 150; // Max error in pixels

    // Apply random error
    targetY += (math.Random().nextDouble() * 2 - 1) * error;

    // Account for paddle height - center paddle on predicted position
    targetY -= leftPaddle.height / 2;

    // Keep paddle within game bounds
    return targetY.clamp(0, PhysicsConstants.gameHeight - leftPaddle.height);
  }

  // Add advanced game mechanics based on score or game state
  void applyGameModifiers({int aiScore = 0, int playerScore = 0}) {
    // Make the game slightly more challenging as AI gets points
    if (aiScore > playerScore && aiScore > 5) {
      PhysicsConstants.ballSpeedMultiplier =
          math.min(1.5, 1.0 + (aiScore - playerScore) * 0.05);
    }

    // Apply comeback mechanic if player is far behind
    if (playerScore < aiScore - 3) {
      PhysicsConstants.spinEffectMultiplier = 1.2; // Increased spin gives more control

      // Also slow down AI reactions slightly
      if (leftPaddle.isAI) {
        leftPaddle.lerpFactor = 0.08; // Default is 0.1
      }
    } else {
      PhysicsConstants.spinEffectMultiplier = 1.0;
      if (leftPaddle.isAI) {
        leftPaddle.lerpFactor = 0.1;
      }
    }
  }

  // Adapt to screen size changes
  void adaptToScreenSize(double width, double height) {
    // Update game dimensions
    PhysicsConstants.updateGameDimensions(width, height);

    // Scale physics objects
    final scaleX = width / 800; // Assuming 800 is the base width
    final scaleY = height / 600; // Assuming 600 is the base height
    final scale = math.min(scaleX, scaleY);

    // Update ball
    ball.radius = PhysicsConstants.defaultBallRadius * scale;

    // Update paddles
    leftPaddle.width = PhysicsConstants.defaultPaddleWidth * scale;
    leftPaddle.height = PhysicsConstants.defaultPaddleHeight * scale;
    rightPaddle.width = PhysicsConstants.defaultPaddleWidth * scale;
    rightPaddle.height = PhysicsConstants.defaultPaddleHeight * scale;

    // Position paddles
    leftPaddle.position.x = 20;
    rightPaddle.position.x = width - 20 - rightPaddle.width;

    // Update speeds and other physics properties
    ball.maxSpeed = PhysicsConstants.defaultBallMaxSpeed * scale;
    leftPaddle.moveSpeed *= scale;
    rightPaddle.moveSpeed *= scale;
  }
}// game/physics.dart

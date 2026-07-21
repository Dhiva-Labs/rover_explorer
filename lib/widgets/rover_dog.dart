import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/sound_service.dart';

enum DogMood { idle, searching, found }

/// Tricks modelled on the real XP search companion's documented animation
/// set (WagTail, FlickHead, Scratch, ScratchFloor/Pawmarks, LieDown, Read,
/// LiftPaw, Lick, Playful, Sniff, Thinking, Sports, Found-with-bone...).
enum DogTrick {
  none,
  wagBurst, // WagTail
  earFlap, // FlickHead
  headTilt, // Thinking
  scratch, // Scratch (hind leg by the ear)
  scratchFloor, // ScratchFloor + Pawmarks
  dig, // digging while processing
  sleep, // LieDown / doze with Zzz
  bark, // with sound
  read, // Read — red book
  jump, // Playful
  wave, // LiftPaw
  lick, // Lick
  ball, // Sports — soccer ball
}

/// Original code-drawn companion dog recreating the XP search assistant's
/// behaviour and build: golden fur, chunky body with a proper neck, big
/// muzzle, close-set eyes under heavy brows, long floppy ears, red collar.
class RoverDog extends StatefulWidget {
  final DogMood mood;
  final double size;

  /// When false the dog never claims taps (so a parent can handle them) and
  /// skips random tricks/sounds — used for the tiny toolbar dog.
  final bool interactive;
  const RoverDog({
    super.key,
    this.mood = DogMood.idle,
    this.size = 140,
    this.interactive = true,
  });

  @override
  State<RoverDog> createState() => _RoverDogState();
}

class _RoverDogState extends State<RoverDog> with TickerProviderStateMixin {
  // Only the interactive companion animates. The decorative toolbar dog
  // holds a single pose: a permanently repeating ticker there would repaint
  // the whole window at 60fps for the entire life of the app.
  late final AnimationController _tick = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  late final AnimationController _trickCtl = AnimationController(vsync: this);

  DogTrick _trick = DogTrick.none;
  final _rng = math.Random();
  Timer? _blinkTimer;
  Timer? _trickTimer;

  static const _trickDurations = {
    DogTrick.wagBurst: Duration(milliseconds: 1800),
    DogTrick.earFlap: Duration(milliseconds: 1400),
    DogTrick.headTilt: Duration(milliseconds: 2000),
    DogTrick.scratch: Duration(milliseconds: 2200),
    DogTrick.scratchFloor: Duration(milliseconds: 2400),
    DogTrick.dig: Duration(milliseconds: 2400),
    DogTrick.sleep: Duration(milliseconds: 5000),
    DogTrick.bark: Duration(milliseconds: 1500),
    DogTrick.read: Duration(milliseconds: 4200),
    DogTrick.jump: Duration(milliseconds: 1700),
    DogTrick.wave: Duration(milliseconds: 2100),
    DogTrick.lick: Duration(milliseconds: 1900),
    DogTrick.ball: Duration(milliseconds: 3000),
  };

  @override
  void initState() {
    super.initState();
    if (widget.interactive) {
      _tick.repeat();
      _scheduleBlink();
      _scheduleTrick(first: true);
    } else {
      _tick.value = 0.25; // resting pose, no ticker
    }
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(
      Duration(milliseconds: 1800 + _rng.nextInt(2600)),
      () async {
        if (!mounted) return;
        await _blink.forward();
        if (!mounted) return;
        await _blink.reverse();
        if (!mounted) return;
        _scheduleBlink();
      },
    );
  }

  void _scheduleTrick({bool first = false}) {
    _trickTimer?.cancel();
    _trickTimer = Timer(
      Duration(milliseconds: first ? 2500 : 5000 + _rng.nextInt(7000)),
      () {
        if (!mounted) return;
        if (widget.interactive &&
            widget.mood == DogMood.idle &&
            _trick == DogTrick.none) {
          final options = DogTrick.values
              .where((t) => t != DogTrick.none)
              .toList();
          _playTrick(options[_rng.nextInt(options.length)]);
        }
        _scheduleTrick();
      },
    );
  }

  Future<void> _playTrick(DogTrick trick) async {
    if (trick == DogTrick.bark) SoundService.playWoof();
    setState(() => _trick = trick);
    _trickCtl.duration = _trickDurations[trick];
    _trickCtl.reset();
    await _trickCtl.forward();
    if (mounted) setState(() => _trick = DogTrick.none);
  }

  void _onTap() {
    if (widget.mood != DogMood.idle) return;
    if (_trick != DogTrick.none) return;
    final clickable = DogTrick.values
        .where((t) => t != DogTrick.none && t != DogTrick.sleep)
        .toList();
    _playTrick(clickable[_rng.nextInt(clickable.length)]);
  }

  @override
  void didUpdateWidget(RoverDog old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) {
      if (widget.mood != DogMood.idle && _trick != DogTrick.none) {
        _trickCtl.stop();
        _trick = DogTrick.none;
      }
      if (widget.interactive && widget.mood == DogMood.found) {
        SoundService.playWoof();
      }
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _trickTimer?.cancel();
    _tick.dispose();
    _blink.dispose();
    _trickCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.interactive ? _onTap : null,
      child: MouseRegion(
        cursor: widget.interactive && widget.mood == DogMood.idle
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        child: SizedBox(
          width: widget.size,
          height: widget.size * 0.95,
          // Isolated so his 60fps repaints do not dirty the whole window.
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_tick, _blink, _trickCtl]),
              builder: (context, _) => CustomPaint(
                painter: _DogPainter(
                  t: _tick.value,
                  blink: _blink.value,
                  mood: widget.mood,
                  trick: widget.mood == DogMood.idle ? _trick : DogTrick.none,
                  trickT: _trickCtl.value,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DogPainter extends CustomPainter {
  final double t; // 0..1 looping
  final double blink; // 0 open .. 1 closed
  final DogMood mood;
  final DogTrick trick;
  final double trickT; // 0..1 progress of current trick
  _DogPainter({
    required this.t,
    required this.blink,
    required this.mood,
    required this.trick,
    required this.trickT,
  });

  // Rover palette: yellow fur, black eyes/nose, red collar, white eye whites.
  static const _fur = Color(0xFFF2C230);
  static const _furShade = Color(0xFFD79E1A);
  static const _furLight = Color(0xFFFADF7D);
  static const _earFur = Color(0xFFE8B325);
  static const _outline = Color(0xFF7A5308);
  static const _collar = Color(0xFFD42B1E);
  static const _bookRed = Color(0xFFB92D21);

  Paint get _outlineP => Paint()
    ..color = _outline
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Design space 140 x 133, dog sitting centred facing the viewer.
    canvas.scale(size.width / 140, size.height / 133);

    final wagSpeed = switch (mood) {
      DogMood.found => 4.0,
      _ => trick == DogTrick.wagBurst || trick == DogTrick.jump ? 5.0 : 1.4,
    };
    final wag = math.sin(t * math.pi * 2 * wagSpeed);
    final breathe = math.sin(t * math.pi * 2) * 1.0;
    final asleep = trick == DogTrick.sleep && trickT > 0.12 && trickT < 0.9;
    final reading = trick == DogTrick.read && trickT > 0.1 && trickT < 0.92;

    // Whole-body vertical motion: happy bounce on found, hops for Playful.
    double bodyY = 0;
    double squash = 1.0;
    if (mood == DogMood.found) {
      bodyY = -math.sin(t * math.pi * 2 * 2).abs() * 4;
    } else if (trick == DogTrick.jump) {
      final hop = math.sin(trickT * math.pi * 2).abs();
      final ease = math.sin(trickT * math.pi);
      bodyY = -hop * 14 * ease;
      squash = 1.0 - hop * 0.06 * ease + (hop < 0.15 ? 0.05 * ease : 0);
    }
    canvas.translate(0, bodyY);
    canvas.translate(70, 133);
    canvas.scale(1 / squash * 0.02 + 0.98, squash);
    canvas.translate(-70, -133);

    // Shadow stays on the ground; shrinks while airborne.
    final shadowW = 96 + bodyY * 1.2;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(70, 127 - bodyY),
        width: shadowW,
        height: 11,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.13),
    );

    // ---------------- tail ----------------
    canvas.save();
    canvas.translate(112, 102);
    canvas.rotate(
      -0.35 +
          wag *
              (mood == DogMood.found ||
                      trick == DogTrick.wagBurst ||
                      trick == DogTrick.jump
                  ? 0.55
                  : 0.3),
    );
    final tail = Path()
      ..moveTo(0, 3)
      ..quadraticBezierTo(18, -2, 26, -16)
      ..quadraticBezierTo(29, -22, 22, -22)
      ..quadraticBezierTo(11, -12, 0, -4)
      ..close();
    canvas.drawPath(tail, Paint()..color = _furShade);
    canvas.drawPath(tail, _outlineP);
    canvas.restore();

    // ---------------- haunches (hind legs, seated) ----------------
    void haunch(double cx) {
      final r = Rect.fromCenter(center: Offset(cx, 101), width: 36, height: 42);
      canvas.drawOval(
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: [_furLight.withValues(alpha: 0.9), _fur, _furShade],
          ).createShader(r),
      );
      canvas.drawOval(r, _outlineP);
    }

    haunch(44);
    haunch(96);

    // hind paws with toes, pointing at the viewer
    void hindPaw(double cx) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, 120), width: 27, height: 13),
        const Radius.circular(6),
      );
      canvas.drawRRect(r, Paint()..color = _furLight);
      canvas.drawRRect(r, _outlineP);
      for (final dx in [-5.0, 1.0, 7.0]) {
        canvas.drawLine(
          Offset(cx + dx, 116),
          Offset(cx + dx, 123),
          Paint()
            ..color = _outline
            ..strokeWidth = 1.2,
        );
      }
    }

    hindPaw(40);
    hindPaw(100);

    // ---------------- torso (chunky chest, up to the neck) ---------------
    final torso = Path()
      ..moveTo(50, 58)
      ..quadraticBezierTo(70, 50 + breathe * 0.4, 90, 58)
      ..quadraticBezierTo(101, 82, 95, 112)
      ..lineTo(45, 112)
      ..quadraticBezierTo(39, 82, 50, 58)
      ..close();
    canvas.drawPath(
      torso,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.4, -1),
          end: Alignment.bottomCenter,
          colors: [_furLight, _fur, _furShade],
        ).createShader(const Rect.fromLTWH(39, 50, 62, 62)),
    );
    canvas.drawPath(torso, _outlineP);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(70, 92 + breathe * 0.3),
        width: 26,
        height: 34,
      ),
      Paint()..color = _furLight,
    );

    // ---------------- front legs ----------------
    double legLift(int which) {
      if (trick == DogTrick.dig) {
        final phase = math.sin((trickT * 10 + which * 0.5) * math.pi * 2);
        return phase > 0 ? phase * 6 : 0;
      }
      if (trick == DogTrick.ball && which == 1) {
        // tapping the ball
        final k = math.sin(trickT * math.pi);
        final tap = math.sin(trickT * math.pi * 6);
        return tap > 0 ? tap * 5 * k : 0;
      }
      return 0;
    }

    double floorScratchX(int which) {
      if (trick != DogTrick.scratchFloor || which != 1) return 0;
      final k = math.sin(trickT * math.pi);
      return math.sin(trickT * math.pi * 6) * 7 * k;
    }

    final waving = trick == DogTrick.wave;
    void frontLeg(double cx, int which) {
      if (waving && which == 1) return;
      final lift = legLift(which);
      final sx = floorScratchX(which);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 6 + sx * 0.4, 86 - lift, 12, 30 + lift * 0.4),
        const Radius.circular(6),
      );
      canvas.drawRRect(r, Paint()..color = _fur);
      canvas.drawRRect(r, _outlineP);
      final paw = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx + sx, 116 - lift),
          width: 19,
          height: 12,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(paw, Paint()..color = _furLight);
      canvas.drawRRect(paw, _outlineP);
      for (final dx in [-4.0, 1.0]) {
        canvas.drawLine(
          Offset(cx + sx + dx + 1.5, 112 - lift),
          Offset(cx + sx + dx + 1.5, 119 - lift),
          Paint()
            ..color = _outline
            ..strokeWidth = 1.2,
        );
      }
    }

    frontLeg(59, 0);
    frontLeg(81, 1);

    // Pawmarks streaks while scratching the floor
    if (trick == DogTrick.scratchFloor) {
      final k = math.sin(trickT * math.pi);
      final mark = Paint()
        ..color = const Color(0xFF8A97B8).withValues(alpha: 0.55 * k)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (final dx in [-8.0, 0.0, 8.0]) {
        canvas.drawLine(Offset(86 + dx, 124), Offset(94 + dx, 124), mark);
      }
    }

    // dirt kicked up while digging
    if (trick == DogTrick.dig) {
      final dirt = Paint()..color = const Color(0xFF9B7653);
      for (var i = 0; i < 6; i++) {
        final phase = ((trickT * 6) + i / 6.0) % 1.0;
        final dx = 70 + (i - 3) * 9.0 * phase;
        final dy = 116 - 18 * phase * (1 - phase) * 4;
        canvas.drawCircle(Offset(dx, dy), 1.8 * (1 - phase) + 0.6, dirt);
      }
    }

    // Sports: soccer ball rolls in, he leans and taps it
    if (trick == DogTrick.ball) {
      final k = math.sin(trickT * math.pi); // in and out
      final bx = 128 - k * 26; // rolls in from the right
      final by = 118 - math.sin(trickT * math.pi * 6).abs() * 4 * k;
      canvas.save();
      canvas.translate(bx, by);
      canvas.rotate(trickT * math.pi * 4);
      canvas.drawCircle(Offset.zero, 10, Paint()..color = Colors.white);
      canvas.drawCircle(Offset.zero, 10, _outlineP..strokeWidth = 1.6);
      final patch = Paint()..color = const Color(0xFF2B2B2B);
      canvas.drawCircle(Offset.zero, 3.4, patch);
      for (var i = 0; i < 5; i++) {
        final a = i / 5 * math.pi * 2;
        canvas.drawCircle(
          Offset(math.cos(a) * 7.5, math.sin(a) * 7.5),
          2.2,
          patch,
        );
      }
      canvas.restore();
    }

    // LiftPaw: raised right foreleg waving at the user.
    if (waving) {
      final k = math.sin(trickT * math.pi);
      canvas.save();
      canvas.translate(84, 92);
      canvas.rotate(-0.9 * k + math.sin(trickT * math.pi * 5) * 0.25 * k);
      final leg = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-6, -30, 12, 34),
        const Radius.circular(6),
      );
      canvas.drawRRect(leg, Paint()..color = _fur);
      canvas.drawRRect(leg, _outlineP);
      final paw = RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, -32), width: 17, height: 11),
        const Radius.circular(5),
      );
      canvas.drawRRect(paw, Paint()..color = _furLight);
      canvas.drawRRect(paw, _outlineP);
      canvas.restore();
    }

    // Scratch: hind leg up by the ear
    if (trick == DogTrick.scratch) {
      final k = math.sin(trickT * math.pi);
      if (k > 0.15) {
        canvas.save();
        canvas.translate(104, 92);
        canvas.rotate(-1.1 * k + math.sin(trickT * math.pi * 12) * 0.12 * k);
        final leg = RRect.fromRectAndRadius(
          const Rect.fromLTWH(-5, -34, 11, 36),
          const Radius.circular(5),
        );
        canvas.drawRRect(leg, Paint()..color = _fur);
        canvas.drawRRect(leg, _outlineP);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(0, -35), width: 15, height: 10),
          Paint()..color = _furLight,
        );
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(0, -35), width: 15, height: 10),
          _outlineP,
        );
        canvas.restore();
      }
    }

    // ---------------- red book while Reading ----------------
    if (reading) {
      final settle = math.min(1.0, (trickT - 0.1) * 6);
      canvas.save();
      canvas.translate(70, 108 - settle * 6);
      final cover = Path()
        ..moveTo(-24, 0)
        ..lineTo(0, 6)
        ..lineTo(24, 0)
        ..lineTo(24, 4)
        ..lineTo(0, 10)
        ..lineTo(-24, 4)
        ..close();
      canvas.drawPath(cover, Paint()..color = _bookRed);
      canvas.drawPath(cover, _outlineP);
      Path page(double sx) => Path()
        ..moveTo(0, 5)
        ..lineTo(sx * 22, -1)
        ..lineTo(sx * 22, 3)
        ..lineTo(0, 9)
        ..close();
      canvas.drawPath(page(-1), Paint()..color = Colors.white);
      canvas.drawPath(page(1), Paint()..color = Colors.white);
      canvas.drawPath(page(-1), _outlineP..strokeWidth = 1.2);
      canvas.drawPath(page(1), _outlineP..strokeWidth = 1.2);
      final tp = Paint()
        ..color = const Color(0xFF9AA4B8)
        ..strokeWidth = 1;
      for (final sx in [-1.0, 1.0]) {
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            Offset(sx * 4, 4.0 + i * 1.6),
            Offset(sx * 18, 1.0 + i * 1.6),
            tp,
          );
        }
      }
      final flip = ((trickT - 0.5) * 8).clamp(-1.0, 1.0);
      if (flip > -1 && flip < 1) {
        canvas.drawPath(
          Path()
            ..moveTo(0, 5)
            ..lineTo(flip * 20, -3 - (1 - flip.abs()) * 6)
            ..lineTo(flip * 20, 1 - (1 - flip.abs()) * 6)
            ..lineTo(0, 9)
            ..close(),
          Paint()..color = const Color(0xFFF2F2F2),
        );
      }
      canvas.restore();
    }

    // ================= head assembly =================
    // The head pivots at the top of the neck; the neck is drawn from the
    // torso to wherever the head currently is, so the head never detaches.
    double headTilt = math.sin(t * math.pi * 2 * 0.5) * 0.03;
    Offset pivot = Offset(70, 50 + breathe * 0.5);
    if (mood == DogMood.searching) {
      final scan = math.sin(t * math.pi * 2 * 1.2);
      pivot = Offset(70 + scan * 12, 60);
      headTilt = scan * 0.15;
    } else if (mood == DogMood.found) {
      pivot = Offset(70, 48);
      headTilt = wag * 0.05;
    } else if (trick == DogTrick.headTilt) {
      final k = math.sin(trickT * math.pi);
      headTilt = math.sin(trickT * math.pi * 2) * 0.32 * k;
    } else if (trick == DogTrick.scratch) {
      headTilt = -0.22 * math.sin(trickT * math.pi);
    } else if (asleep) {
      pivot = Offset(70, 55);
      headTilt = 0.14;
    } else if (reading) {
      pivot = Offset(70, 54);
    } else if (trick == DogTrick.bark) {
      pivot = Offset(70, 50 + _barkOpen(trickT) * 3);
    } else if (trick == DogTrick.ball) {
      final k = math.sin(trickT * math.pi);
      pivot = Offset(70 + k * 8, 52);
      headTilt = k * 0.25;
    }

    // Neck: filled quad from torso shoulders up to under the head.
    final neck = Path()
      ..moveTo(pivot.dx - 14, pivot.dy - 6)
      ..lineTo(pivot.dx + 14, pivot.dy - 6)
      ..quadraticBezierTo(88, 62, 86, 70)
      ..lineTo(54, 70)
      ..quadraticBezierTo(52, 62, pivot.dx - 14, pivot.dy - 6)
      ..close();
    canvas.drawPath(neck, Paint()..color = _fur);
    // only side outlines so no seam cuts across fur
    canvas.drawPath(
      Path()
        ..moveTo(pivot.dx - 14, pivot.dy - 4)
        ..quadraticBezierTo(52, 62, 54, 70),
      _outlineP,
    );
    canvas.drawPath(
      Path()
        ..moveTo(pivot.dx + 14, pivot.dy - 4)
        ..quadraticBezierTo(88, 62, 86, 70),
      _outlineP,
    );

    // Collar wraps the neck just under the head.
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(headTilt * 0.6);
    final collarBand = Path()
      ..moveTo(-15, 2)
      ..quadraticBezierTo(0, 8, 15, 2)
      ..lineTo(15, 8)
      ..quadraticBezierTo(0, 14, -15, 8)
      ..close();
    canvas.drawPath(collarBand, Paint()..color = _collar);
    canvas.drawPath(collarBand, _outlineP..strokeWidth = 1.6);
    canvas.drawCircle(
      const Offset(0, 12),
      3.2,
      Paint()..color = const Color(0xFFF6C13C),
    );
    canvas.drawCircle(
      const Offset(0, 12),
      3.2,
      Paint()
        ..color = _outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.restore();

    // ---------------- head ----------------
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(headTilt);

    // Ear parameters (drawn behind the skull).
    double earLift = 0;
    if (trick == DogTrick.earFlap) {
      earLift =
          math.sin(trickT * math.pi * 3).abs() * math.sin(trickT * math.pi);
    } else if (mood == DogMood.found) {
      earLift = wag.abs() * 0.35;
    } else if (trick == DogTrick.jump) {
      earLift = (-bodyY / 14) * 0.5;
    }

    void ear(bool left) {
      final sx = left ? -1.0 : 1.0;
      canvas.save();
      canvas.translate(sx * 23, -32);
      canvas.rotate(
        sx * (0.10 - earLift * 1.15) +
            sx * math.sin(t * math.pi * 2 * wagSpeed) * 0.02,
      );
      // Big rounded flop that widens toward the tip, like the reference.
      final earPath = Path()
        ..moveTo(0, -3)
        ..quadraticBezierTo(sx * 14, 4, sx * 14, 22)
        ..quadraticBezierTo(sx * 13, 36, sx * 3, 37)
        ..quadraticBezierTo(sx * -6, 36, sx * -6, 22)
        ..quadraticBezierTo(sx * -6, 6, 0, -3)
        ..close();
      canvas.drawPath(
        earPath,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(-sx * 0.3, -0.5),
            radius: 1.3,
            colors: [_earFur, _furShade],
          ).createShader(Rect.fromLTWH(sx * -8, -4, 24, 42)),
      );
      canvas.drawPath(earPath, _outlineP);
      canvas.restore();
    }

    ear(true);
    ear(false);

    // Skull: broad and round, brow ridge bulging at the top.
    final skull = Path()
      ..moveTo(-26, -22)
      ..quadraticBezierTo(-27, -42, -10, -44)
      ..quadraticBezierTo(0, -47, 10, -44)
      ..quadraticBezierTo(27, -42, 26, -22)
      ..quadraticBezierTo(27, -8, 18, 0)
      ..quadraticBezierTo(0, 8, -18, 0)
      ..quadraticBezierTo(-27, -8, -26, -22)
      ..close();
    canvas.drawPath(
      skull,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.55),
          radius: 1.25,
          colors: [_furLight, _fur, _furShade],
        ).createShader(const Rect.fromLTWH(-27, -47, 54, 55)),
    );
    canvas.drawPath(skull, _outlineP);

    // Big protruding muzzle: rounded mass over the lower half of the face,
    // nose sitting on top of it — the Rover snout.
    final muzzle = Path()
      ..moveTo(-16, -14)
      ..quadraticBezierTo(0, -20, 16, -14)
      ..quadraticBezierTo(22, -4, 16, 6)
      ..quadraticBezierTo(0, 14, -16, 6)
      ..quadraticBezierTo(-22, -4, -16, -14)
      ..close();
    canvas.drawPath(
      muzzle,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.5),
          radius: 1.2,
          colors: [const Color(0xFFFCEBAF), _furLight, _fur],
        ).createShader(const Rect.fromLTWH(-22, -20, 44, 34)),
    );
    canvas.drawPath(muzzle, _outlineP);

    // nose: big black rounded triangle at the top of the muzzle
    final noseWiggle = mood == DogMood.searching
        ? math.sin(t * math.pi * 2 * 6) * 1.0
        : 0.0;
    final nose = Path()
      ..moveTo(-7, -14 + noseWiggle * 0.4)
      ..quadraticBezierTo(0, -18 + noseWiggle * 0.4, 7, -14 + noseWiggle * 0.4)
      ..quadraticBezierTo(8, -8, 0, -6 + noseWiggle * 0.4)
      ..quadraticBezierTo(-8, -8, -7, -14 + noseWiggle * 0.4)
      ..close();
    canvas.drawPath(nose, Paint()..color = const Color(0xFF241812));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-2.5, -13 + noseWiggle * 0.4),
        width: 4,
        height: 2.6,
      ),
      Paint()..color = Colors.white24,
    );

    // ---------------- mouth on the muzzle ----------------
    final barkOpen = trick == DogTrick.bark ? _barkOpen(trickT) : 0.0;
    if (mood == DogMood.found) {
      _bone(canvas, const Offset(0, 6));
    } else if (barkOpen > 0.05) {
      final open = barkOpen * 8;
      final mouth = Path()
        ..moveTo(-8, 2)
        ..quadraticBezierTo(0, 2 + open, 8, 2)
        ..quadraticBezierTo(0, 6 + open, -8, 2)
        ..close();
      canvas.drawPath(mouth, Paint()..color = const Color(0xFF5A1F18));
      canvas.drawPath(mouth, _outlineP..strokeWidth = 1.6);
      final sp = Paint()
        ..color = const Color(0xFF39507C).withValues(alpha: 0.7 * barkOpen)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      for (var i = 1; i <= 2; i++) {
        canvas.drawArc(
          Rect.fromCenter(
            center: const Offset(0, 4),
            width: 30.0 * i,
            height: 22.0 * i,
          ),
          -0.5,
          1.0,
          false,
          sp,
        );
      }
    } else if (trick == DogTrick.wagBurst ||
        trick == DogTrick.jump ||
        trick == DogTrick.wave ||
        trick == DogTrick.ball) {
      final mouth = Path()
        ..moveTo(-9, 1)
        ..quadraticBezierTo(0, 9, 9, 1);
      canvas.drawPath(
        mouth,
        Paint()
          ..color = _outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      final tongue = Path()
        ..moveTo(-4, 4)
        ..quadraticBezierTo(0, 13 + wag * 1.5, 4, 4)
        ..close();
      canvas.drawPath(tongue, Paint()..color = const Color(0xFFE0645C));
    } else if (trick == DogTrick.lick) {
      final k = math.sin(trickT * math.pi);
      final sweep = math.sin(trickT * math.pi * 4) * 6 * k;
      final tongue = Path()
        ..moveTo(-4, 5)
        ..quadraticBezierTo(sweep - 6, -10, sweep, -12)
        ..quadraticBezierTo(sweep + 6, -10, 4, 5)
        ..close();
      canvas.drawPath(tongue, Paint()..color = const Color(0xFFE0645C));
      canvas.drawPath(tongue, _outlineP..strokeWidth = 1.3);
    } else {
      // resting jowls: two curves from under the nose
      for (final sx in [-1.0, 1.0]) {
        final mouth = Path()
          ..moveTo(0, -4)
          ..quadraticBezierTo(sx * 6, 3, sx * 12, 0);
        canvas.drawPath(
          mouth,
          Paint()
            ..color = _outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // ---------------- eyes: close-set on top of the muzzle ----------------
    final happySquint = trick == DogTrick.lick || mood == DogMood.found;
    final eyesClosed = asleep || blink > 0.6 || mood == DogMood.searching;
    for (final sx in [-1.0, 1.0]) {
      final c = Offset(sx * 8, -27);
      if (eyesClosed) {
        canvas.drawArc(
          Rect.fromCenter(center: c, width: 12, height: 9),
          asleep ? 0.2 : math.pi * 0.15,
          asleep ? math.pi * 0.8 : math.pi * 0.7,
          false,
          Paint()
            ..color = _outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      } else {
        final h = happySquint ? 11.0 : 15.0;
        canvas.drawOval(
          Rect.fromCenter(center: c, width: 14, height: h),
          Paint()..color = Colors.white,
        );
        canvas.drawOval(
          Rect.fromCenter(center: c, width: 14, height: h),
          Paint()
            ..color = _outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        double lookY = 0.5;
        double lookX = 0;
        if (trick == DogTrick.dig || reading) lookY = 3.2;
        if (trick == DogTrick.headTilt) {
          lookX = math.sin(trickT * math.pi * 2) * 2.5;
        }
        if (trick == DogTrick.ball) {
          lookX = 3.0 * math.sin(trickT * math.pi);
          lookY = 2.0;
        }
        canvas.drawCircle(
          c.translate(lookX, lookY),
          3.6,
          Paint()..color = const Color(0xFF17110B),
        );
        canvas.drawCircle(
          c.translate(lookX - 1.1, lookY - 1.2),
          1.0,
          Paint()..color = Colors.white,
        );
      }
      // heavy brow ridge
      canvas.drawArc(
        Rect.fromCenter(center: c.translate(0, -9), width: 14, height: 7),
        math.pi * 1.08,
        math.pi * 0.84,
        false,
        Paint()
          ..color = _outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    canvas.restore(); // head

    // sniff puffs while searching
    if (mood == DogMood.searching) {
      final phase = (t * 3) % 1.0;
      final puff = Paint()
        ..color = const Color(0xFF9BB4D8).withValues(alpha: (1 - phase) * 0.5);
      canvas.drawCircle(
        Offset(58 - phase * 8, 74 + phase * 4),
        2 + phase * 3,
        puff,
      );
      canvas.drawCircle(
        Offset(84 + phase * 8, 76 + phase * 3),
        1.5 + phase * 2.5,
        puff,
      );
    }

    // Zzz while sleeping
    if (asleep) {
      for (var i = 0; i < 3; i++) {
        final phase = ((t * 0.8) + i * 0.33) % 1.0;
        final tp = TextPainter(
          text: TextSpan(
            text: 'z',
            style: TextStyle(
              fontSize: 8.0 + i * 3,
              fontWeight: FontWeight.bold,
              color: const Color(
                0xFF39507C,
              ).withValues(alpha: (1 - phase) * 0.8),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(96 + i * 8.0 + phase * 4, 14 - i * 9.0 - phase * 8),
        );
      }
    }

    canvas.restore();
  }

  /// Mouth-open envelope for the two woofs, matching the bundled sound.
  double _barkOpen(double tt) {
    double pulse(double start, double len) {
      if (tt < start || tt > start + len) return 0;
      return math.sin((tt - start) / len * math.pi);
    }

    return pulse(0.05, 0.3) + pulse(0.5, 0.28);
  }

  void _bone(Canvas canvas, Offset c) {
    final bonePaint = Paint()..color = const Color(0xFFF3EBD7);
    const r = 4.0;
    final bar = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: 26, height: 6),
      const Radius.circular(3),
    );
    canvas.drawRRect(bar, bonePaint);
    for (final sx in [-1.0, 1.0]) {
      canvas.drawCircle(c.translate(sx * 13, -2.5), r, bonePaint);
      canvas.drawCircle(c.translate(sx * 13, 2.5), r, bonePaint);
    }
    canvas.drawRRect(bar, _outlineP..strokeWidth = 1.4);
    for (final sx in [-1.0, 1.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: c.translate(sx * 13, -2.5), radius: r),
        sx > 0 ? -math.pi * 0.75 : math.pi * 0.75,
        sx > 0 ? math.pi : -math.pi,
        false,
        _outlineP,
      );
      canvas.drawArc(
        Rect.fromCircle(center: c.translate(sx * 13, 2.5), radius: r),
        sx > 0 ? -math.pi * 0.25 : math.pi * 1.25,
        sx > 0 ? math.pi : -math.pi,
        false,
        _outlineP,
      );
    }
  }

  @override
  bool shouldRepaint(_DogPainter old) =>
      old.t != t ||
      old.blink != blink ||
      old.mood != mood ||
      old.trick != trick ||
      old.trickT != trickT;
}

/// XP-style yellow speech balloon with a tail, used above the dog.
class SpeechBubble extends StatelessWidget {
  final Widget child;
  const SpeechBubble({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFE1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF808080)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                offset: Offset(2, 2),
                blurRadius: 3,
              ),
            ],
          ),
          child: child,
        ),
        CustomPaint(size: const Size(18, 10), painter: _BubbleTailPainter()),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(2, 0)
      ..lineTo(14, 0)
      ..lineTo(5, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFFFE1));
    canvas.drawLine(
      const Offset(2, 0),
      Offset(5, size.height),
      Paint()..color = const Color(0xFF808080),
    );
    canvas.drawLine(
      const Offset(14, 0),
      Offset(5, size.height),
      Paint()..color = const Color(0xFF808080),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

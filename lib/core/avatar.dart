import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A customizable little character. All choices are indices into the palettes
/// below, so an avatar encodes to a tiny string that is cheap to store locally
/// and sync to the partner.
class Avatar {
  const Avatar({
    this.skin = 1,
    this.hairStyle = 0,
    this.hairColor = 1,
    this.outfit = 0,
    this.accessory = 0,
  });

  final int skin;
  final int hairStyle;
  final int hairColor;
  final int outfit;
  final int accessory;

  Avatar copyWith({
    int? skin,
    int? hairStyle,
    int? hairColor,
    int? outfit,
    int? accessory,
  }) => Avatar(
    skin: skin ?? this.skin,
    hairStyle: hairStyle ?? this.hairStyle,
    hairColor: hairColor ?? this.hairColor,
    outfit: outfit ?? this.outfit,
    accessory: accessory ?? this.accessory,
  );

  String encode() => '$skin.$hairStyle.$hairColor.$outfit.$accessory';

  static Avatar decode(String? s) {
    if (s == null || s.isEmpty) return const Avatar();
    final p = s.split('.');
    int at(int i, int max) {
      if (i >= p.length) return 0;
      return (int.tryParse(p[i]) ?? 0).clamp(0, max - 1);
    }

    return Avatar(
      skin: at(0, skinTones.length),
      hairStyle: at(1, hairStyleCount),
      hairColor: at(2, hairColors.length),
      outfit: at(3, outfitColors.length),
      accessory: at(4, accessoryCount),
    );
  }

  static const skinTones = <Color>[
    Color(0xFFFFE0BD),
    Color(0xFFF3C9A6),
    Color(0xFFE0A87E),
    Color(0xFFC68642),
    Color(0xFF8D5524),
    Color(0xFF5C3A21),
  ];

  static const hairColors = <Color>[
    Color(0xFF2B2B2B),
    Color(0xFF4B2E1E),
    Color(0xFF8D6E4A),
    Color(0xFFD9B04A),
    Color(0xFFB0453B),
    Color(0xFF9E9E9E),
    Color(0xFF5C6BC0),
    Color(0xFFB44FA0),
  ];

  static const outfitColors = <Color>[
    Color(0xFF7C4DFF),
    Color(0xFFFF5FA2),
    Color(0xFF29B6F6),
    Color(0xFF66BB6A),
    Color(0xFFFFB300),
    Color(0xFFEF5350),
    Color(0xFF26A69A),
    Color(0xFF5C6BC0),
  ];

  // 0 short · 1 long · 2 bun · 3 curly · 4 ponytail · 5 buzz
  static const hairStyleCount = 6;
  static const hairStyleNames = [
    'قصير',
    'طويل',
    'كعكة',
    'مجعّد',
    'ذيل',
    'حليق',
  ];

  // 0 none · 1 glasses · 2 bow · 3 cap · 4 sparkle
  static const accessoryCount = 5;
  static const accessoryNames = ['بدون', 'نظارة', 'فيونكة', 'قبعة', 'بريق'];
}

/// Loads/saves the local user's avatar.
class AvatarStore {
  static const _key = 'avatar_v1';

  static Future<Avatar> load() async {
    final p = await SharedPreferences.getInstance();
    return Avatar.decode(p.getString(_key));
  }

  static Future<void> save(Avatar a) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, a.encode());
  }

  static Future<bool> exists() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_key) ?? '').isNotEmpty;
  }
}

/// Renders an [Avatar] at a given size (always square).
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.avatar,
    this.size = 64,
    this.background,
    this.ringColor,
  });

  final Avatar avatar;
  final double size;
  final Color? background;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    Widget child = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: AvatarPainter(avatar)),
    );
    if (background != null || ringColor != null) {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background,
          border: ringColor != null
              ? Border.all(color: ringColor!, width: 2)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    return child;
  }
}

class AvatarPainter extends CustomPainter {
  AvatarPainter(this.avatar);

  final Avatar avatar;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is authored in a 0..100 virtual space, then scaled to fit.
    final u = size.width / 100.0;
    canvas.save();
    canvas.scale(u);

    final skin = Avatar.skinTones[avatar.skin];
    final skinShade = Color.lerp(skin, Colors.black, 0.14)!;
    final hair = Avatar.hairColors[avatar.hairColor];
    final outfit = Avatar.outfitColors[avatar.outfit];

    _backHair(canvas, hair);
    _body(canvas, outfit, skin);
    _head(canvas, skin, skinShade);
    _frontHair(canvas, hair);
    _face(canvas, skin);
    _accessory(canvas, outfit, hair);

    canvas.restore();
  }

  void _body(Canvas canvas, Color outfit, Color skin) {
    // Neck.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(44, 56, 12, 14),
        const Radius.circular(4),
      ),
      Paint()..color = Color.lerp(skin, Colors.black, 0.08)!,
    );
    // Shoulders / shirt.
    final shirt = Path()
      ..moveTo(20, 100)
      ..lineTo(26, 80)
      ..quadraticBezierTo(30, 68, 42, 66)
      ..lineTo(58, 66)
      ..quadraticBezierTo(70, 68, 74, 80)
      ..lineTo(80, 100)
      ..close();
    canvas.drawPath(shirt, Paint()..color = outfit);
    // Collar highlight.
    canvas.drawPath(
      Path()
        ..moveTo(42, 66)
        ..quadraticBezierTo(50, 74, 58, 66),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  void _head(Canvas canvas, Color skin, Color skinShade) {
    final p = Paint()..color = skin;
    canvas.drawCircle(const Offset(26, 44), 5, p); // ears
    canvas.drawCircle(const Offset(74, 44), 5, p);
    canvas.drawCircle(const Offset(50, 42), 24, p);
    // soft shading on the right.
    canvas.drawArc(
      const Rect.fromLTWH(26, 18, 48, 48),
      -0.6,
      1.6,
      false,
      Paint()
        ..color = skinShade.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
  }

  void _face(Canvas canvas, Color skin) {
    final eye = Paint()..color = const Color(0xFF3A2A22);
    canvas.drawCircle(const Offset(42, 44), 3.1, eye);
    canvas.drawCircle(const Offset(58, 44), 3.1, eye);
    final glint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(const Offset(43, 43), 1.0, glint);
    canvas.drawCircle(const Offset(59, 43), 1.0, glint);
    // Cheeks.
    final cheek = Paint()
      ..color = const Color(0xFFFF8A9B).withValues(alpha: 0.35);
    canvas.drawCircle(const Offset(37, 51), 3.5, cheek);
    canvas.drawCircle(const Offset(63, 51), 3.5, cheek);
    // Smile.
    canvas.drawPath(
      Path()
        ..moveTo(44, 52)
        ..quadraticBezierTo(50, 58, 56, 52),
      Paint()
        ..color = const Color(0xFF7A4A3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _backHair(Canvas canvas, Color hair) {
    final p = Paint()..color = hair;
    switch (avatar.hairStyle) {
      case 1: // long — falls behind the shoulders
        canvas.drawPath(
          Path()
            ..moveTo(24, 40)
            ..quadraticBezierTo(18, 84, 34, 92)
            ..lineTo(66, 92)
            ..quadraticBezierTo(82, 84, 76, 40)
            ..quadraticBezierTo(50, 26, 24, 40)
            ..close(),
          p,
        );
      case 4: // ponytail — a tail to one side
        canvas.drawCircle(const Offset(80, 40), 7, p);
        canvas.drawPath(
          Path()
            ..moveTo(78, 36)
            ..quadraticBezierTo(94, 52, 84, 74)
            ..quadraticBezierTo(80, 60, 72, 50)
            ..close(),
          p,
        );
      case 3: // curly — cloud behind the head
        for (var i = 0; i < 10; i++) {
          final a = i / 10 * math.pi * 2;
          canvas.drawCircle(
            Offset(50 + math.cos(a) * 24, 34 + math.sin(a) * 22),
            8,
            p,
          );
        }
    }
  }

  void _frontHair(Canvas canvas, Color hair) {
    final p = Paint()..color = hair;
    if (avatar.hairStyle == 5) {
      // buzz — a thin hairline only
      canvas.drawPath(
        Path()
          ..moveTo(28, 44)
          ..quadraticBezierTo(50, 24, 72, 44)
          ..quadraticBezierTo(60, 38, 50, 39)
          ..quadraticBezierTo(40, 38, 28, 44)
          ..close(),
        p..color = hair.withValues(alpha: 0.9),
      );
      return;
    }
    // A rounded cap with a soft fringe — shared by short/long/bun/ponytail.
    final cap = Path()
      ..moveTo(25, 48)
      ..quadraticBezierTo(22, 14, 50, 13)
      ..quadraticBezierTo(78, 14, 75, 48)
      ..quadraticBezierTo(70, 34, 60, 33)
      ..quadraticBezierTo(50, 42, 40, 33)
      ..quadraticBezierTo(30, 34, 25, 48)
      ..close();
    canvas.drawPath(cap, p);
    // Shine.
    canvas.drawArc(
      const Rect.fromLTWH(30, 18, 26, 22),
      3.6,
      1.1,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    if (avatar.hairStyle == 3) {
      // curly — extra bumps on top
      for (var i = 0; i < 6; i++) {
        canvas.drawCircle(Offset(30.0 + i * 8, 20 + (i.isEven ? 0 : 3)), 7, p);
      }
    }
    if (avatar.hairStyle == 2) {
      // bun on top
      canvas.drawCircle(const Offset(50, 12), 8, p);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(45, 18, 10, 5),
          const Radius.circular(2),
        ),
        p,
      );
    }
  }

  void _accessory(Canvas canvas, Color outfit, Color hair) {
    switch (avatar.accessory) {
      case 1: // glasses
        final g = Paint()
          ..color = const Color(0xFF37474F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2;
        canvas.drawCircle(const Offset(42, 44), 7, g);
        canvas.drawCircle(const Offset(58, 44), 7, g);
        canvas.drawLine(const Offset(49, 44), const Offset(51, 44), g);
      case 2: // bow
        final b = Paint()..color = const Color(0xFFFF5FA2);
        canvas.drawPath(
          Path()
            ..moveTo(34, 20)
            ..lineTo(26, 15)
            ..lineTo(26, 25)
            ..close(),
          b,
        );
        canvas.drawPath(
          Path()
            ..moveTo(34, 20)
            ..lineTo(42, 15)
            ..lineTo(42, 25)
            ..close(),
          b,
        );
        canvas.drawCircle(
          const Offset(34, 20),
          2.4,
          Paint()..color = const Color(0xFFD81B60),
        );
      case 3: // cap
        final capColor = Color.lerp(outfit, Colors.black, 0.15)!;
        canvas.drawPath(
          Path()
            ..moveTo(26, 40)
            ..quadraticBezierTo(50, 8, 74, 40)
            ..quadraticBezierTo(50, 30, 26, 40)
            ..close(),
          Paint()..color = capColor,
        );
        canvas.drawPath(
          Path()
            ..moveTo(20, 40)
            ..quadraticBezierTo(40, 34, 50, 38)
            ..quadraticBezierTo(38, 44, 20, 44)
            ..close(),
          Paint()..color = capColor,
        );
        canvas.drawCircle(
          const Offset(50, 14),
          2.4,
          Paint()..color = Colors.white,
        );
      case 4: // sparkle
        final s = Paint()..color = const Color(0xFFFFD54F);
        for (final c in const [
          Offset(78, 22),
          Offset(22, 28),
          Offset(70, 12),
        ]) {
          canvas.drawCircle(c, 2.2, s);
          canvas.drawLine(
            c.translate(-4, 0),
            c.translate(4, 0),
            Paint()
              ..color = s.color
              ..strokeWidth = 1.2,
          );
          canvas.drawLine(
            c.translate(0, -4),
            c.translate(0, 4),
            Paint()
              ..color = s.color
              ..strokeWidth = 1.2,
          );
        }
    }
  }

  @override
  bool shouldRepaint(AvatarPainter old) =>
      old.avatar.skin != avatar.skin ||
      old.avatar.hairStyle != avatar.hairStyle ||
      old.avatar.hairColor != avatar.hairColor ||
      old.avatar.outfit != avatar.outfit ||
      old.avatar.accessory != avatar.accessory;
}

/// A full-screen editor letting the user build/tweak their character. Returns
/// the saved [Avatar] via Navigator.pop.
class AvatarBuilderScreen extends StatefulWidget {
  const AvatarBuilderScreen({super.key, this.initial});

  final Avatar? initial;

  @override
  State<AvatarBuilderScreen> createState() => _AvatarBuilderScreenState();
}

class _AvatarBuilderScreenState extends State<AvatarBuilderScreen> {
  late Avatar _a = widget.initial ?? const Avatar();
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await AvatarStore.save(_a);
    if (!mounted) return;
    Navigator.of(context).pop(_a);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('شخصيتك')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [scheme.primaryContainer, scheme.secondaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: AvatarView(avatar: _a, size: 150),
            ),
          ),
          const SizedBox(height: 24),
          _label('لون البشرة'),
          _swatches(
            Avatar.skinTones,
            _a.skin,
            (i) => setState(() => _a = _a.copyWith(skin: i)),
          ),
          const SizedBox(height: 18),
          _label('تسريحة الشعر'),
          _hairStylePicker(),
          const SizedBox(height: 18),
          _label('لون الشعر'),
          _swatches(
            Avatar.hairColors,
            _a.hairColor,
            (i) => setState(() => _a = _a.copyWith(hairColor: i)),
          ),
          const SizedBox(height: 18),
          _label('الملابس'),
          _swatches(
            Avatar.outfitColors,
            _a.outfit,
            (i) => setState(() => _a = _a.copyWith(outfit: i)),
          ),
          const SizedBox(height: 18),
          _label('إكسسوار'),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < Avatar.accessoryCount; i++)
                ChoiceChip(
                  label: Text(Avatar.accessoryNames[i]),
                  selected: _a.accessory == i,
                  onSelected: (_) =>
                      setState(() => _a = _a.copyWith(accessory: i)),
                ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('حفظ الشخصية'),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  );

  Widget _swatches(List<Color> colors, int selected, ValueChanged<int> onPick) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < colors.length; i++)
          GestureDetector(
            onTap: () => onPick(i),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == i ? Colors.black87 : Colors.black12,
                  width: selected == i ? 3 : 1,
                ),
              ),
              child: selected == i
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _hairStylePicker() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: Avatar.hairStyleCount,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final selected = _a.hairStyle == i;
          return GestureDetector(
            onTap: () => setState(() => _a = _a.copyWith(hairStyle: i)),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AvatarView(
                    avatar: _a.copyWith(hairStyle: i),
                    size: 50,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Avatar.hairStyleNames[i],
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

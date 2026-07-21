import 'package:flutter/material.dart';

/// Windows XP "Luna" palette and shared chrome widgets.
class Xp {
  static const titleBlueDark = Color(0xFF0A246A);
  static const titleBlue = Color(0xFF0055EA);
  static const titleBlueLight = Color(0xFF3C8CF8);

  static const toolbarTop = Color(0xFF5296F3);
  static const toolbarBottom = Color(0xFF1E62D0);

  static const taskPaneTop = Color(0xFF7AA1E6);
  static const taskPaneBody = Color(0xFFD6DFF7);
  static const taskCardHeaderLeft = Color(0xFFFFFFFF);
  static const taskCardHeaderRight = Color(0xFFC7D3F7);
  static const taskLink = Color(0xFF215DC6);

  static const face = Color(0xFFECE9D8); // classic dialog beige
  static const faceDark = Color(0xFFACA899);
  static const selection = Color(0xFF316AC5);
  static const selectionFaded = Color(0xFFC1D2EE);

  static const addressBarBg = Color(0xFFFFFFFF);
  static const statusBg = Color(0xFFECE9D8);

  static const text = Color(0xFF000000);
  static const dimText = Color(0xFF666666);

  static const LinearGradient toolbarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6CA8F7), Color(0xFF2E6FE0), Color(0xFF1D5CC8)],
    stops: [0.0, 0.7, 1.0],
  );

  static const LinearGradient titleGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [titleBlueDark, titleBlue, titleBlueLight],
  );

  static const fontFamily = 'Tahoma';

  static TextStyle style({
    double size = 12,
    Color color = text,
    FontWeight weight = FontWeight.normal,
  }) => TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    fontFamily: fontFamily,
    decoration: TextDecoration.none,
  );
}

/// Classic raised 3-D bordered button (toolbar style: flat until hovered).
class XpToolButton extends StatefulWidget {
  final Widget icon;
  final String? label;
  final VoidCallback? onTap;
  final bool active;
  final String? tooltip;
  const XpToolButton({
    super.key,
    required this.icon,
    this.label,
    this.onTap,
    this.active = false,
    this.tooltip,
  });

  @override
  State<XpToolButton> createState() => _XpToolButtonState();
}

class _XpToolButtonState extends State<XpToolButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: widget.active
            ? Colors.white.withValues(alpha: 0.25)
            : _hover && enabled
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: (_hover && enabled) || widget.active
            ? Border.all(color: Colors.white.withValues(alpha: 0.55))
            : Border.all(color: Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(opacity: enabled ? 1 : 0.4, child: widget.icon),
          if (widget.label != null) ...[
            const SizedBox(width: 5),
            Text(
              widget.label!,
              style: Xp.style(
                color: enabled ? Colors.white : const Color(0xFFBBCCEE),
                size: 12,
              ),
            ),
          ],
        ],
      ),
    );
    final w = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(onTap: widget.onTap, child: child),
    );
    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        textStyle: Xp.style(size: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFE1),
          border: Border.all(color: Colors.black),
        ),
        child: w,
      );
    }
    return w;
  }
}

/// Classic beige push button with 3-D border.
class XpButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const XpButton({super.key, required this.label, this.onTap});

  @override
  State<XpButton> createState() => _XpButtonState();
}

class _XpButtonState extends State<XpButton> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: _down ? const Color(0xFFDDD8C8) : Xp.face,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: _hover ? const Color(0xFFF8B334) : const Color(0xFF003C74),
            ),
            boxShadow: _down
                ? []
                : [
                    const BoxShadow(
                      color: Color(0x33000000),
                      offset: Offset(1, 1),
                      blurRadius: 1,
                    ),
                  ],
          ),
          child: Text(widget.label, style: Xp.style(size: 12)),
        ),
      ),
    );
  }
}

/// Blue-link styled text used in the task panes.
class XpLink extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget? icon;
  final bool bold;
  const XpLink({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.bold = false,
  });

  @override
  State<XpLink> createState() => _XpLinkState();
}

class _XpLinkState extends State<XpLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                widget.icon!,
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: Xp.fontFamily,
                    color: _hover ? const Color(0xFF4A87E8) : Xp.taskLink,
                    fontWeight: widget.bold
                        ? FontWeight.bold
                        : FontWeight.normal,
                    decoration: _hover
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: const Color(0xFF4A87E8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded white-headed card used in the XP task pane.
class XpTaskCard extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final bool initiallyOpen;
  const XpTaskCard({
    super.key,
    required this.title,
    required this.children,
    this.initiallyOpen = true,
  });

  @override
  State<XpTaskCard> createState() => _XpTaskCardState();
}

class _XpTaskCardState extends State<XpTaskCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FD),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Xp.taskCardHeaderLeft, Xp.taskCardHeaderRight],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Xp.style(
                        size: 12,
                        weight: FontWeight.bold,
                        color: const Color(0xFF0C327D),
                      ),
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF9DBBEA)),
                    ),
                    child: Icon(
                      _open
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 14,
                      color: const Color(0xFF4B6EAF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}

/// Sunken white field border (address bar, inputs).
class XpSunken extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const XpSunken({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF7F9DB9)),
      ),
      child: child,
    );
  }
}

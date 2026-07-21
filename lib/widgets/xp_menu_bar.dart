import 'package:flutter/material.dart';

import '../xp/xp_theme.dart';

/// One entry inside a menu. A label of `-` renders as a separator.
class XpMenuEntry {
  final String label;
  final VoidCallback? onTap;
  final String? shortcut;
  final bool checked;
  final bool radio;
  final bool enabled;

  const XpMenuEntry(
    this.label, {
    this.onTap,
    this.shortcut,
    this.checked = false,
    this.radio = false,
    this.enabled = true,
  });

  static const XpMenuEntry separator = XpMenuEntry('-');

  bool get isSeparator => label == '-';
}

class XpMenu {
  final String label;
  final List<XpMenuEntry> Function() builder;
  const XpMenu(this.label, this.builder);
}

/// Classic beige menu bar (File / Edit / View / Help) with drop-downs.
class XpMenuBar extends StatelessWidget {
  final List<XpMenu> menus;
  const XpMenuBar({super.key, required this.menus});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      decoration: const BoxDecoration(
        color: Xp.face,
        border: Border(bottom: BorderSide(color: Color(0xFFD8D5C8))),
      ),
      child: Row(children: [for (final m in menus) _MenuLabel(menu: m)]),
    );
  }
}

class _MenuLabel extends StatefulWidget {
  final XpMenu menu;
  const _MenuLabel({required this.menu});

  @override
  State<_MenuLabel> createState() => _MenuLabelState();
}

class _MenuLabelState extends State<_MenuLabel> {
  final _key = GlobalKey();
  bool _hover = false;
  bool _open = false;

  Future<void> _show() async {
    final box = _key.currentContext!.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(
      Offset(0, box.size.height),
      ancestor: overlay,
    );
    final entries = widget.menu.builder();

    setState(() => _open = true);
    final selected = await showMenu<VoidCallback?>(
      context: context,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF999999)),
        borderRadius: BorderRadius.circular(2),
      ),
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx,
        0,
      ),
      items: [
        for (final e in entries)
          if (e.isSeparator)
            const PopupMenuDivider(height: 6)
          else
            PopupMenuItem<VoidCallback?>(
              value: e.onTap,
              enabled: e.enabled && e.onTap != null,
              height: 26,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: e.checked
                        ? Icon(
                            e.radio ? Icons.circle : Icons.check,
                            size: e.radio ? 8 : 13,
                            color: const Color(0xFF21A121),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      e.label,
                      style: Xp.style(
                        size: 12,
                        color: e.enabled && e.onTap != null
                            ? Xp.text
                            : Xp.dimText,
                      ),
                    ),
                  ),
                  if (e.shortcut != null) ...[
                    const SizedBox(width: 24),
                    Text(
                      e.shortcut!,
                      style: Xp.style(size: 11, color: Xp.dimText),
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
    if (mounted) setState(() => _open = false);
    selected?.call();
  }

  @override
  Widget build(BuildContext context) {
    final highlight = _hover || _open;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _show,
        child: Container(
          key: _key,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          color: highlight ? Xp.selection : Colors.transparent,
          child: Text(
            widget.menu.label,
            style: Xp.style(
              size: 12,
              color: highlight ? Colors.white : Xp.text,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'xp_theme.dart';

/// Classic XP dialog frame: blue gradient title bar, beige body, buttons
/// right-aligned along the bottom.
class XpDialogShell extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final double width;
  const XpDialogShell({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.width = 340,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Xp.face,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Xp.titleBlueDark, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 12,
                offset: Offset(3, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: const BoxDecoration(
                  gradient: Xp.titleGradient,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Xp.style(
                          size: 12.5,
                          weight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _TitleCloseButton(onTap: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: content,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final a in actions) ...[a, const SizedBox(width: 8)],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _TitleCloseButton({required this.onTap});

  @override
  State<_TitleCloseButton> createState() => _TitleCloseButtonState();
}

class _TitleCloseButtonState extends State<_TitleCloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFE8776A) : const Color(0xFFD05B4C),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.white70),
          ),
          child: const Icon(Icons.close, size: 13, color: Colors.white),
        ),
      ),
    );
  }
}

/// Yes/No confirmation with the classic question icon.
Future<bool?> xpConfirm(BuildContext context, String title, String message) {
  return showDialog<bool>(
    context: context,
    builder: (context) => XpDialogShell(
      title: title,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.help, color: Color(0xFF3B6EA5), size: 34),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: Xp.style(size: 12))),
        ],
      ),
      actions: [
        XpButton(label: 'Yes', onTap: () => Navigator.pop(context, true)),
        XpButton(label: 'No', onTap: () => Navigator.pop(context, false)),
      ],
    ),
  );
}

/// Error/notice box.
Future<void> xpAlert(
  BuildContext context,
  String message, {
  String title = 'Rover Explorer',
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => XpDialogShell(
      title: title,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error, color: Color(0xFFC53030), size: 34),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: Xp.style(size: 12))),
        ],
      ),
      actions: [XpButton(label: 'OK', onTap: () => Navigator.pop(context))],
    ),
  );
}

/// Single-line text prompt (used by Rename).
Future<String?> xpPrompt(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => XpDialogShell(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(label, style: Xp.style(size: 12)),
          ),
          const SizedBox(height: 4),
          XpSunken(
            child: TextField(
              controller: controller,
              autofocus: true,
              style: Xp.style(size: 12),
              onSubmitted: (v) => Navigator.pop(context, v),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
        ],
      ),
      actions: [
        XpButton(
          label: 'OK',
          onTap: () => Navigator.pop(context, controller.text),
        ),
        XpButton(label: 'Cancel', onTap: () => Navigator.pop(context)),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../xp/xp_dialog.dart';
import '../xp/xp_theme.dart';

class RoverSettings {
  bool showHidden;
  bool soundEnabled;
  bool companionEnabled;

  RoverSettings({
    this.showHidden = false,
    this.soundEnabled = true,
    this.companionEnabled = true,
  });

  RoverSettings copy() => RoverSettings(
    showHidden: showHidden,
    soundEnabled: soundEnabled,
    companionEnabled: companionEnabled,
  );
}

/// Folder Options-style settings sheet.
Future<RoverSettings?> showSettingsDialog(
  BuildContext context, {
  required RoverSettings current,
  required int indexedItems,
  required bool indexing,
  required VoidCallback onRebuildIndex,
}) {
  return showDialog<RoverSettings>(
    context: context,
    builder: (context) => _SettingsDialog(
      current: current,
      indexedItems: indexedItems,
      indexing: indexing,
      onRebuildIndex: onRebuildIndex,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  final RoverSettings current;
  final int indexedItems;
  final bool indexing;
  final VoidCallback onRebuildIndex;
  const _SettingsDialog({
    required this.current,
    required this.indexedItems,
    required this.indexing,
    required this.onRebuildIndex,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final RoverSettings _draft = widget.current.copy();
  bool _rebuildRequested = false;

  Widget _check(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => onChanged(!value),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                children: [
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFF1D5281)),
                    ),
                    child: value
                        ? const Icon(
                            Icons.check,
                            size: 11,
                            color: Color(0xFF21A121),
                          )
                        : null,
                  ),
                  const SizedBox(width: 7),
                  Text(label, style: Xp.style(size: 12)),
                ],
              ),
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 1),
              child: Text(hint, style: Xp.style(size: 10.5, color: Xp.dimText)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return XpDialogShell(
      title: 'Folder Options',
      width: 400,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('View', style: Xp.style(size: 12, weight: FontWeight.bold)),
          const SizedBox(height: 6),
          _check(
            'Show hidden files and folders',
            _draft.showHidden,
            (v) => setState(() => _draft.showHidden = v),
            hint: 'Files beginning with a dot on Linux.',
          ),
          const SizedBox(height: 4),
          Text(
            'Search Companion',
            style: Xp.style(size: 12, weight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _check(
            'Use the animated companion',
            _draft.companionEnabled,
            (v) => setState(() => _draft.companionEnabled = v),
            hint: 'Turn off for a plain search pane.',
          ),
          _check(
            'Play companion sounds',
            _draft.soundEnabled,
            (v) => setState(() => _draft.soundEnabled = v),
            hint: 'Barking when Rover finds results.',
          ),
          const SizedBox(height: 4),
          Container(height: 1, color: Xp.faceDark),
          const SizedBox(height: 10),
          Text(
            'Search index',
            style: Xp.style(size: 12, weight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            widget.indexing
                ? 'Indexing in progress — ${widget.indexedItems} items so far.'
                : '${widget.indexedItems} items indexed and searchable instantly.',
            style: Xp.style(size: 11.5, color: Xp.dimText),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              XpButton(
                label: _rebuildRequested ? 'Rebuilding…' : 'Rebuild index now',
                onTap: _rebuildRequested
                    ? null
                    : () {
                        setState(() => _rebuildRequested = true);
                        widget.onRebuildIndex();
                      },
              ),
            ],
          ),
        ],
      ),
      actions: [
        XpButton(
          label: 'OK',
          onTap: () {
            SoundService.muted = !_draft.soundEnabled;
            Navigator.pop(context, _draft);
          },
        ),
        XpButton(label: 'Cancel', onTap: () => Navigator.pop(context)),
      ],
    );
  }
}

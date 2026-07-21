import 'dart:async';

import 'package:flutter/material.dart';

import '../services/search_index.dart';
import '../xp/xp_theme.dart';
import 'rover_dog.dart';

class SearchQuerySpec {
  final String text;
  final SearchKind kind;
  final bool currentFolderOnly;
  const SearchQuerySpec(this.text, this.kind, this.currentFolderOnly);
}

/// The XP Search Companion sidebar: dog + speech bubble + live query form.
class SearchPane extends StatefulWidget {
  final void Function(SearchQuerySpec) onQuery;
  final VoidCallback onClose;
  final DogMood mood;
  final IndexStatus indexStatus;
  final String currentFolder;
  final int? resultCount;

  /// When false the animated dog and speech bubble are hidden (Folder
  /// Options → "Use the animated companion").
  final bool showCompanion;

  const SearchPane({
    super.key,
    required this.onQuery,
    required this.onClose,
    required this.mood,
    required this.indexStatus,
    required this.currentFolder,
    this.resultCount,
    this.showCompanion = true,
  });

  @override
  State<SearchPane> createState() => _SearchPaneState();
}

class _SearchPaneState extends State<SearchPane> {
  final _controller = TextEditingController();
  SearchKind _kind = SearchKind.all;
  bool _currentOnly = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _fire({bool immediate = false}) {
    _debounce?.cancel();
    void go() =>
        widget.onQuery(SearchQuerySpec(_controller.text, _kind, _currentOnly));
    if (immediate) {
      go();
    } else {
      _debounce = Timer(const Duration(milliseconds: 130), go);
    }
  }

  String get _bubbleText {
    if (widget.mood == DogMood.searching) return 'Sniffing around for it...';
    if (widget.resultCount != null) {
      if (widget.resultCount == 0) return "Sorry, I couldn't find anything.";
      return 'I found ${widget.resultCount} item${widget.resultCount == 1 ? '' : 's'}! '
          'Woof!';
    }
    return 'What would you like to search for? Just start typing — '
        "I'll fetch results instantly. (Click me for a trick!)";
  }

  Widget _radio(SearchKind value, String label) {
    return GestureDetector(
      onTap: () {
        setState(() => _kind = value);
        _fire(immediate: true);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFF1D5281)),
              ),
              child: _kind == value
                  ? Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF21A121),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: Xp.style(size: 11.5))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idx = widget.indexStatus;
    return Container(
      width: 230,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA9C3F2), Color(0xFFD6DFF7)],
          stops: [0.0, 0.25],
        ),
        border: Border(right: BorderSide(color: Xp.faceDark)),
      ),
      child: Column(
        children: [
          // header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Search Companion',
                    style: Xp.style(
                      size: 12.5,
                      weight: FontWeight.bold,
                      color: const Color(0xFF0C327D),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8E4F8),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF7A96DF)),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 13,
                      color: Color(0xFF39507C),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                if (widget.showCompanion) ...[
                  SpeechBubble(
                    child: Text(
                      _bubbleText,
                      style: Xp.style(size: 11.5),
                      softWrap: true,
                    ),
                  ),
                  Center(child: RoverDog(mood: widget.mood, size: 130)),
                ],
                const SizedBox(height: 10),
                Text(
                  'All or part of the file name:',
                  style: Xp.style(size: 11.5),
                ),
                const SizedBox(height: 3),
                XpSunken(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: (_) => _fire(),
                    onSubmitted: (_) => _fire(immediate: true),
                    style: Xp.style(size: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text('What are you looking for?', style: Xp.style(size: 11.5)),
                const SizedBox(height: 3),
                _radio(SearchKind.all, 'All files and folders'),
                _radio(SearchKind.folders, 'Folders'),
                _radio(SearchKind.pictures, 'Pictures'),
                _radio(SearchKind.music, 'Music'),
                _radio(SearchKind.video, 'Videos'),
                _radio(SearchKind.documents, 'Documents'),
                const SizedBox(height: 10),
                Text('Look in:', style: Xp.style(size: 11.5)),
                const SizedBox(height: 3),
                GestureDetector(
                  onTap: () {
                    setState(() => _currentOnly = !_currentOnly);
                    _fire(immediate: true);
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFF1D5281)),
                        ),
                        child: _currentOnly
                            ? const Icon(
                                Icons.check,
                                size: 11,
                                color: Color(0xFF21A121),
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Only in current folder',
                          style: Xp.style(size: 11.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_currentOnly)
                  Padding(
                    padding: const EdgeInsets.only(left: 19, top: 2),
                    child: Text(
                      widget.currentFolder,
                      style: Xp.style(size: 10.5, color: Xp.dimText),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    XpButton(
                      label: 'Search',
                      onTap: () => _fire(immediate: true),
                    ),
                    const SizedBox(width: 8),
                    XpButton(
                      label: 'Clear',
                      onTap: () {
                        _controller.clear();
                        _fire(immediate: true);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    idx.scanning
                        ? 'Building index... ${_fmt(idx.count)} items so far'
                        : 'Index ready — ${_fmt(idx.count)} items searchable '
                              'instantly',
                    style: Xp.style(size: 10.5, color: const Color(0xFF33507E)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final sb = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) sb.write(',');
      sb.write(s[i]);
    }
    return sb.toString();
  }
}

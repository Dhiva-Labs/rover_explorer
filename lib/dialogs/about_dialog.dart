import 'dart:io';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../widgets/rover_dog.dart';
import '../xp/xp_dialog.dart';
import '../xp/xp_theme.dart';

/// "About Rover Explorer" — XP system-properties styling, with Rover himself
/// sitting in the box doing tricks.
Future<void> showRoverAboutDialog(
  BuildContext context, {
  required int indexedItems,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => XpDialogShell(
      title: 'About ${AppInfo.name}',
      width: 420,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 104, child: RoverDog(size: 104)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppInfo.name,
                      style: Xp.style(size: 17, weight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Version ${AppInfo.fullVersion}',
                      style: Xp.style(size: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppInfo.tagline,
                      style: Xp.style(size: 11.5, color: Xp.dimText),
                    ),
                    const SizedBox(height: 8),
                    Text(AppInfo.copyright, style: Xp.style(size: 11.5)),
                    Text(
                      'A ${AppInfo.vendor} project',
                      style: Xp.style(size: 11.5, weight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Xp.faceDark),
          const SizedBox(height: 10),
          _row('Licence', AppInfo.license),
          _row('Repository', AppInfo.repository),
          _row('Application ID', AppInfo.applicationId),
          _row(
            'Platform',
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          ),
          _row('Dart runtime', Platform.version.split(' ').first),
          _row('Search index', '$indexedItems items'),
          const SizedBox(height: 10),
          Text(
            'Rover is an original character drawn in code for this project and '
            'is not affiliated with, or derived from, Microsoft assets.',
            style: Xp.style(size: 10.5, color: Xp.dimText),
          ),
        ],
      ),
      actions: [XpButton(label: 'OK', onTap: () => Navigator.pop(context))],
    ),
  );
}

Widget _row(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            '$label:',
            style: Xp.style(size: 11.5, color: Xp.dimText),
          ),
        ),
        Expanded(child: Text(value, style: Xp.style(size: 11.5))),
      ],
    ),
  );
}

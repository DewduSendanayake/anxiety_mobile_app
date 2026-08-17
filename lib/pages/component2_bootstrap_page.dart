import 'package:flutter/material.dart';

import '../services/background_service_helper.dart';
import '../services/component2_data_service.dart';
import 'digital_phenotyping_page.dart';

/// Ensures the participant-facing Component 2 page receives the latest
/// display-safe behavioural payload before it reads its SharedPreferences
/// cache. Network/API failures never block the page: it falls back to the
/// previously cached payload or to the existing baseline-building state.
class Component2BootstrapPage extends StatefulWidget {
  final String? userId;

  const Component2BootstrapPage({super.key, this.userId});

  @override
  State<Component2BootstrapPage> createState() =>
      _Component2BootstrapPageState();
}

class _Component2BootstrapPageState extends State<Component2BootstrapPage> {
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _sync();
  }

  Future<void> _sync() async {
    final participantId =
        widget.userId ?? await BackgroundServiceHelper.getCachedId();
    await Component2DataService.sync(participantId);
  }

  Future<void> _retry() async {
    setState(() {
      _bootstrapFuture = _sync();
    });
    await _bootstrapFuture;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F3FF),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF5E60CE)),
            ),
          );
        }

        // A new key ensures the existing page re-reads the freshly synced
        // SharedPreferences payload after a manual retry.
        return DigitalPhenotypingPage(
          key: ValueKey(_bootstrapFuture),
          userId: widget.userId,
        );
      },
    );
  }
}

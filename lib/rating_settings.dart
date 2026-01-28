import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RatingSettingsPage extends StatefulWidget {
  const RatingSettingsPage({Key? key}) : super(key: key);

  @override
  State<RatingSettingsPage> createState() => _RatingSettingsPageState();
}

class _RatingSettingsPageState extends State<RatingSettingsPage> {
  bool _enabled = true;
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enabled = prefs.getBool('rating_enabled') ?? true;
      int h = prefs.getInt('rating_hour') ?? 20;
      int m = prefs.getInt('rating_minute') ?? 0;
      _time = TimeOfDay(hour: h, minute: m);
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rating_enabled', _enabled);
    await prefs.setInt('rating_hour', _time.hour);
    await prefs.setInt('rating_minute', _time.minute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Check-in Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Enable daily rating'),
              value: _enabled,
              onChanged: (v) async {
                setState(() => _enabled = v);
                await _save();
              },
            ),
            ListTile(
              title: const Text('Notification time'),
              subtitle: Text('${_time.format(context)}'),
              onTap: () async {
                TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (picked != null) {
                  setState(() => _time = picked);
                  await _save();
                }
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await _save();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Settings saved')));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

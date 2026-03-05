import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const WomenSafetyApp());
}

class WomenSafetyApp extends StatelessWidget {
  const WomenSafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Pulse Safety',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red, primary: Colors.red.shade800),
        useMaterial3: true,
      ),
      home: const AlertDashboard(),
    );
  }
}

class AlertDashboard extends StatefulWidget {
  const AlertDashboard({super.key});

  @override
  State<AlertDashboard> createState() => _AlertDashboardState();
}

class _AlertDashboardState extends State<AlertDashboard> {
  String? _lastAlertId;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _startListening();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final android = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _startListening() {
    _subscription = FirebaseFirestore.instance.collection('panic_alerts').snapshots().listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        var docs = snapshot.docs.toList();
        docs.sort((a, b) => (double.tryParse(b.id) ?? 0).compareTo(double.tryParse(a.id) ?? 0));
        
        var latestDoc = docs.first;
        var data = latestDoc.data();

        if (_lastAlertId != null && _lastAlertId != latestDoc.id) {
          _triggerAlarm(data);
          _showPanicAlert(data);
        }
        _lastAlertId = latestDoc.id;
      }
    });
  }

  Future<void> _triggerAlarm(Map<String, dynamic> data) async {
    final String content = 'HR: ${data['heart_rate']} | SPO2: ${data['spo2']}% | BP: ${data['bp_sys']}/${data['bp_dia']}\nLocation: 11.084515, 76.997147';

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'emergency_v5', 'Panic Alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      styleInformation: BigTextStyleInformation(''),
    );
    
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond, '🚨 EMERGENCY PANIC DETECTED', content,
      const NotificationDetails(android: androidDetails),
    );
  }

  void _showPanicAlert(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 60),
          Text('EMERGENCY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _statRow('Heart Rate', '${data['heart_rate']} BPM'),
          _statRow('Oxygen', '${data['spo2']}%'),
          _statRow('BP', '${data['bp_sys']}/${data['bp_dia']}'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('DISMISS', style: TextStyle(color: Colors.white))),
          ElevatedButton(onPressed: () { Navigator.pop(context); _openMap(); }, child: const Text('TRACK')),
        ],
      ),
    );
  }

  Widget _statRow(String label, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.white70)),
      Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ]),
  );

  Future<void> _openMap() async {
    const lat = "11.084515"; const lng = "76.997147";
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _deleteAlert(String id) async {
    await FirebaseFirestore.instance.collection('panic_alerts').doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IoT Pulse Safety', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800, foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep), onPressed: () async {
            var snaps = await FirebaseFirestore.instance.collection('panic_alerts').get();
            for (var d in snaps.docs) { await d.reference.delete(); }
          }),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('panic_alerts').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('System Safe'));
          var docs = snapshot.data!.docs.toList();
          docs.sort((a, b) => (double.tryParse(b.id) ?? 0).compareTo(double.tryParse(a.id) ?? 0));

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              return Card(
                color: index == 0 ? Colors.red.shade50 : Colors.white,
                child: ExpansionTile(
                  initiallyExpanded: index == 0,
                  leading: Icon(Icons.warning, color: index == 0 ? Colors.red : Colors.grey),
                  title: Text('Alert ID: ${doc.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Pulse: ${data['heart_rate']} BPM'),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteAlert(doc.id)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                          _infoTile('SPO2', '${data['spo2']}%', Icons.bloodtype, Colors.blue),
                          _infoTile('BP', '${data['bp_sys']}/${data['bp_dia']}', Icons.compress, Colors.orange),
                        ]),
                        const Divider(),
                        ElevatedButton.icon(onPressed: _openMap, icon: const Icon(Icons.location_on), label: const Text('TRACK PINPOINT'), 
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
                      ]),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _infoTile(String l, String v, IconData i, Color c) => Column(children: [
    Icon(i, color: c, size: 20), Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  ]);
}

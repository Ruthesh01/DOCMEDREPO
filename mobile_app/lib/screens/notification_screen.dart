import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive/hive.dart';

import '../services/local_cache_service.dart';
import '../services/notification_service.dart';
import '../widgets/empty_state.dart';
import 'report_detail_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _notifications = LocalCacheService.instance.getCachedNotifications();
    });
  }

  void _handleTap(Map<String, dynamic> notif) {
    if (notif['payload'] == null || notif['payload'].toString().isEmpty || notif['payload'] == '{}') return;

    try {
      final data = jsonDecode(notif['payload'] as String) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final id = data['reportId'] as String? ?? data['prescriptionId'] as String?;
      
      if ((type == 'report_ready' || type == 'analysis_complete') && id != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportDetailScreen(reportId: id),
          ),
        );
      } else if (type != null && id != null) {
        // Fallback for other routing handled by the main app router logic if needed
      }
    } catch (e) {
      debugPrint('[NotificationScreen] Payload parse error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all_rounded),
              tooltip: 'Clear All',
              onPressed: () async {
                // To keep it simple, we just clear the list in Hive
                final box = Hive.box('notifications');
                await box.put('list', []);
                _load();
              },
            ),
        ],
      ),
      body: _notifications.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications',
              message: 'You have no recent notifications.',
            )
          : ListView.separated(
              itemCount: _notifications.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = _notifications[index];
                final title = n['title'] as String? ?? 'Notification';
                final body = n['body'] as String? ?? '';
                final timeStr = n['timestamp'] as String?;
                
                DateTime? time;
                if (timeStr != null) {
                  time = DateTime.tryParse(timeStr);
                }

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.notifications_active_outlined, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(body),
                      if (time != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          DateFormat.yMMMd().add_jm().format(time),
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                  onTap: () => _handleTap(n),
                );
              },
            ),
    );
  }
}

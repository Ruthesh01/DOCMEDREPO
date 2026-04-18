import 'package:flutter/foundation.dart';

/// Holds in-memory notification routing state.
/// The main.dart sets the navigation callback; screens read from this provider
/// to respond to notification taps.
class NotificationProvider extends ChangeNotifier {
  String? _pendingType;
  String? _pendingResourceId;

  String? get pendingType       => _pendingType;
  String? get pendingResourceId => _pendingResourceId;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> get notifications => _notifications;

  /// Clears the unread count
  void markAsRead() {
    _unreadCount = 0;
    notifyListeners();
  }

  /// Called by NotificationService when a notification is tapped.
  void handleNotification(String type, String? resourceId) {
    _pendingType       = type;
    _pendingResourceId = resourceId;
    notifyListeners();
  }

  /// Clears the pending notification after it has been handled by the UI.
  void clear() {
    _pendingType       = null;
    _pendingResourceId = null;
    notifyListeners();
  }
}

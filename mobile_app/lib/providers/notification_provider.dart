import 'package:flutter/foundation.dart';

/// Holds in-memory notification routing state.
/// The main.dart sets the navigation callback; screens read from this provider
/// to respond to notification taps.
class NotificationProvider extends ChangeNotifier {
  String? _pendingType;
  String? _pendingResourceId;

  String? get pendingType       => _pendingType;
  String? get pendingResourceId => _pendingResourceId;

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

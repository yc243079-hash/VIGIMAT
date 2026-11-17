import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/firebase_config.dart';
import '../core/supabase_config.dart';
import 'notification_repository.dart';

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  static const _channelId = 'vigimat_maintenance_alerts';
  static const _channelName = 'Alertes de maintenance';
  static const _channelDescription =
      'Signalements, interventions et entretiens préventifs.';
  static const _channel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDescription,
    importance: Importance.high,
  );

  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _openEvents = StreamController<void>.broadcast();
  final List<Map<String, String>> _pendingOpens = [];
  Completer<String>? _registrationWaiter;
  String? _registeredToken;
  bool _initialized = false;
  bool _notificationsAllowed = false;
  bool _registeringToken = false;

  Stream<void> get openEvents => _openEvents.stream;
  bool get hasPendingOpens => _pendingOpens.isNotEmpty;

  bool get isConfigured =>
      FirebaseConfig.isConfigured &&
      SupabaseConfig.isConfigured &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (_initialized || !isConfigured) return;

    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: FirebaseConfig.apiKey,
        appId: FirebaseConfig.appId,
        messagingSenderId: FirebaseConfig.messagingSenderId,
        projectId: FirebaseConfig.projectId,
      ),
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_vigimat'),
      ),
      onDidReceiveNotificationResponse: (response) {
        _queueOpenPayload(response.payload);
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _queueOpenPayload(launchDetails?.notificationResponse?.payload);
    }

    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onMessage.listen(
      (message) => unawaited(
        _showForegroundNotification(message).catchError((Object error) {
          _reportError(error);
        }),
      ),
      onError: _reportError,
    );
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _queueOpenData(message.data),
      onError: _reportError,
    );
    messaging.onRegistered.listen((token) {
      _registeredToken = token;
      final waiter = _registrationWaiter;
      if (waiter != null && !waiter.isCompleted) waiter.complete(token);
      final user = Supabase.instance.client.auth.currentUser;
      if (_notificationsAllowed && user != null) {
        unawaited(_saveToken(token));
      }
    }, onError: _reportError);
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) unawaited(_registerToken());
    }, onError: _reportError);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) _queueOpenData(initialMessage.data);
    _initialized = true;
    await _registerToken();
  }

  List<Map<String, String>> takePendingOpens() {
    final pending = List<Map<String, String>>.unmodifiable(_pendingOpens);
    _pendingOpens.clear();
    return pending;
  }

  Future<void> unregisterCurrentDevice() async {
    if (!_initialized || Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    final token = _registeredToken ?? await _requestRegistration();
    if (token.isNotEmpty) {
      await NotificationRepository().removePushToken(token);
      await FirebaseMessaging.instance.unregister();
      _registeredToken = null;
      _notificationsAllowed = false;
    }
  }

  Future<void> _registerToken() async {
    if (!_initialized || _registeringToken) return;
    if (Supabase.instance.client.auth.currentUser == null) return;

    _registeringToken = true;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        _notificationsAllowed = false;
        final token = await _requestRegistration();
        await NotificationRepository().removePushToken(token);
        return;
      }
      _notificationsAllowed = true;
      final token = await _requestRegistration();
      await _saveToken(token);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    } finally {
      _registeringToken = false;
    }
  }

  Future<String> _requestRegistration() async {
    final waiter = Completer<String>();
    _registrationWaiter = waiter;
    try {
      await FirebaseMessaging.instance.register();
      return _registeredToken ??
          await waiter.future.timeout(const Duration(seconds: 20));
    } finally {
      if (identical(_registrationWaiter, waiter)) {
        _registrationWaiter = null;
      }
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      await NotificationRepository().registerPushToken(
        token: token,
        platform: 'android',
      );
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_vigimat',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _queueOpenPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _queueOpenData(Map<String, dynamic>.from(decoded));
      }
    } on FormatException catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  void _queueOpenData(Map<String, dynamic> data) {
    final payload = data.map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    );
    if ((payload['report_id']?.isNotEmpty ?? false) == false &&
        (payload['schedule_id']?.isNotEmpty ?? false) == false) {
      return;
    }
    final notificationId = payload['notification_id'];
    if (notificationId != null &&
        _pendingOpens.any(
          (pending) => pending['notification_id'] == notificationId,
        )) {
      return;
    }
    _pendingOpens.add(payload);
    _openEvents.add(null);
  }

  void _reportError(Object error, [StackTrace? stackTrace]) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'VIGIMAT push notifications',
      ),
    );
  }
}

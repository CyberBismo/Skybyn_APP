import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/friend.dart';
import 'screens/chat_screen.dart';

@pragma('vm:entry-point')
void bubbleChatMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const _BubbleChatApp(),
    ),
  );
}

class _BubbleChatApp extends StatefulWidget {
  const _BubbleChatApp();
  @override
  State<_BubbleChatApp> createState() => _BubbleChatAppState();
}

class _BubbleChatAppState extends State<_BubbleChatApp> {
  static const _channel = MethodChannel('no.skybyn.app/bubble_chat');
  Friend? _friend;

  @override
  void initState() {
    super.initState();
    _loadFriendData();
  }

  Future<void> _loadFriendData() async {
    try {
      final data = await _channel.invokeMethod<Map>('getBubbleData');
      if (data != null && mounted) {
        setState(() {
          _friend = Friend(
            id: data['friendId']?.toString() ?? '',
            username: data['friendName']?.toString() ?? '',
            nickname: '',
            avatar: data['friendAvatar']?.toString() ?? '',
            online: false,
          );
        });
      }
    } catch (_) {}
  }

  void _closeOverlay() {
    _channel.invokeMethod('closeChat').catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final friend = _friend;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData.dark(useMaterial3: false),
      darkTheme: ThemeData.dark(useMaterial3: false),
      themeMode: ThemeMode.system,
      home: friend == null
          ? const Scaffold(backgroundColor: Colors.transparent)
          : ChatScreen(friend: friend, onClose: _closeOverlay),
    );
  }
}

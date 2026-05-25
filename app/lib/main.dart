import 'package:flutter/material';
import 'data/api_client.dart';
import 'data/socket_client.dart';
import 'data/notification_service.dart';
import 'presentation/login_screen.dart';
import 'presentation/home_feed_screen.dart';
import 'presentation/chat_list_screen.dart';
import 'presentation/chat_room_screen.dart';
import 'presentation/profile_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    print("Notification init error: $e");
  }

  NotificationService.instance.onNotificationTap = (senderId, username) {
    try {
      if (ApiClient.instance.userId == null) return;
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ChatRoomScreen(
            counterPartyId: senderId,
            counterPartyUsername: username,
            counterPartyPublicKeyHex: "",
          ),
        ),
      );
    } catch (e) {
      print("Notification tap error: $e");
    }
  };

  final isLoggedIn = await ApiClient.instance.initSession();

  if (isLoggedIn) {
    SocketClient.instance.connect();
  }

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Acrypcom',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00E5FF),
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        fontFamily: 'monospace',
        useMaterial3: true,
      ),
      home: AppRoot(isLoggedIn: isLoggedIn),
    );
  }
}

class AppRoot extends StatefulWidget {
  final bool isLoggedIn;
  const AppRoot({super.key, required this.isLoggedIn});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late bool _isLoggedIn;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = widget.isLoggedIn;
  }

  void _onLoginSuccess() {
    setState(() {
      _isLoggedIn = true;
      _currentIndex = 0;
    });
  }

  void _onLogout() {
    setState(() {
      _isLoggedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }

    final List<Widget> screens = [
      HomeFeedScreen(
        onNavigateToProfile: () => setState(() => _currentIndex = 2),
        onNavigateToChats: () => setState(() => _currentIndex = 1),
      ),
      const ChatListScreen(),
      ProfileScreen(onLogout: _onLogout),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: const Color(0xFF111927),
          selectedItemColor: const Color(0xFF00E5FF),
          unselectedItemColor: Colors.white38,
          showSelectedLabels: true,
          showUnselectedLabels: false,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: "Accueil",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.send_outlined),
              activeIcon: Icon(Icons.send_rounded),
              label: "Messages",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person_rounded),
              label: "Profil",
            ),
          ],
        ),
      ),
    );
  }
}

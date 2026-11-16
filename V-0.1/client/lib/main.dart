import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api.dart';
import 'core/app_state.dart';
import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/business/business_shell.dart';
import 'features/customer/customer_shell.dart';
import 'features/shared/launch_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  runApp(ChangeNotifierProvider(create: (_) => AppState(api)..restore(), child: const LoyfinityApp()));
}

class LoyfinityApp extends StatelessWidget {
  const LoyfinityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loyfinity',
      debugShowCheckedModeBanner: false,
      theme: buildLoyfinityTheme(),
      home: const AppGate(),
    );
  }
}

class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      if (!state.initialized) return const LaunchScreen();
      if (!state.signedIn) return const AuthScreen();
      switch (state.role) {
        case 'customer':
          return const CustomerShell();
        case 'business_owner':
        case 'business_staff':
          return const BusinessShell();
        case 'admin':
          return const AdminNoticeScreen();
        default:
          return const AuthScreen();
      }
    });
  }
}

class AdminNoticeScreen extends StatelessWidget {
  const AdminNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.admin_panel_settings_rounded, size: 52, color: LoyColors.blue),
        const SizedBox(height: 16),
        Text('Loyfinity administration', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('Admin accounts are provisioned by an operator. The public mobile workspace is not an admin console.'),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () => context.read<AppState>().logout(), child: const Text('Sign out')),
      ]),
    )),
  );
}

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'customer_pages.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;
  final _pages = const [CustomerExplorePage(), CustomerWalletPage(), CustomerActivityPage(), CustomerProfilePage()];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomerScanPage())),
      backgroundColor: LoyColors.navy,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.qr_code_scanner_rounded),
      label: const Text('Check in', style: TextStyle(fontWeight: FontWeight.w800)),
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      backgroundColor: Colors.white,
      indicatorColor: LoyColors.blueTint,
      elevation: 0,
      height: 68,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore_rounded), label: 'Explore'),
        NavigationDestination(icon: Icon(Icons.wallet_outlined), selectedIcon: Icon(Icons.wallet_rounded), label: 'Wallet'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Activity'),
        NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
      ],
    ),
  );
}

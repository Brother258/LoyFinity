import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'business_pages.dart';

class BusinessShell extends StatefulWidget {
  const BusinessShell({super.key});
  @override
  State<BusinessShell> createState() => _BusinessShellState();
}
class _BusinessShellState extends State<BusinessShell> {
  int _index = 0;
  final _pages = const [BusinessOverviewPage(), BusinessProgramsPage(), BusinessQrPage(), BusinessCustomersPage(), BusinessMorePage()];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      backgroundColor: Colors.white,
      indicatorColor: LoyColors.blueTint,
      height: 68,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Overview'),
        NavigationDestination(icon: Icon(Icons.card_giftcard_outlined), selectedIcon: Icon(Icons.card_giftcard_rounded), label: 'Programs'),
        NavigationDestination(icon: Icon(Icons.qr_code_2_outlined), selectedIcon: Icon(Icons.qr_code_2_rounded), label: 'QR check-in'),
        NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Customers'),
        NavigationDestination(icon: Icon(Icons.more_horiz_rounded), selectedIcon: Icon(Icons.more_horiz_rounded), label: 'More'),
      ],
    ),
  );
}

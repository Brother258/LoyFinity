import 'package:flutter/material.dart';
import '../../core/theme.dart';

class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: LoyColors.navy,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      _LoyfinityMark(), SizedBox(height: 18), Text('Loyfinity', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1)),
      SizedBox(height: 8), Text('A better reason to come back.', style: TextStyle(color: Color(0xFFB8CAD9), fontSize: 14)),
      SizedBox(height: 28), SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: LoyColors.gold)),
    ])),
  );
}

class _LoyfinityMark extends StatelessWidget {
  const _LoyfinityMark();
  @override
  Widget build(BuildContext context) => Container(
    width: 76, height: 76,
    decoration: BoxDecoration(color: LoyColors.blue, borderRadius: BorderRadius.circular(24), border: Border.all(color: LoyColors.gold, width: 3)),
    child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset('assets/brand/loyfinity-app-icon.png', fit: BoxFit.cover)),
  );
}

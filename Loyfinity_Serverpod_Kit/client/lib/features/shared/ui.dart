import 'package:flutter/material.dart';
import '../../core/theme.dart';

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
    if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
  ]);
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: LoyColors.line)),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(22), child: Padding(padding: padding, child: child)),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.good = false, this.gold = false});
  final String label;
  final bool good;
  final bool gold;
  @override
  Widget build(BuildContext context) {
    final color = good ? LoyColors.green : (gold ? const Color(0xFF916B00) : LoyColors.blueDark);
    final bg = good ? LoyColors.greenTint : (gold ? const Color(0xFFFFF6D9) : LoyColors.blueTint);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)), child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)));
  }
}

class LoadingPane extends StatelessWidget {
  const LoadingPane({super.key, this.label = 'Loading'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: LoyColors.blue)), const SizedBox(height: 14), Text(label, style: Theme.of(context).textTheme.bodyMedium)])));
}

class EmptyPane extends StatelessWidget {
  const EmptyPane({super.key, required this.title, required this.body, this.icon = Icons.explore_outlined, this.action, this.onAction});
  final String title;
  final String body;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 68, height: 68, decoration: const BoxDecoration(color: LoyColors.blueTint, shape: BoxShape.circle), child: Icon(icon, size: 32, color: LoyColors.blue)),
    const SizedBox(height: 18), Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8), Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
    if (action != null) ...[const SizedBox(height: 18), OutlinedButton(onPressed: onAction, child: Text(action!))],
  ])));
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, required this.icon, this.tint = LoyColors.blueTint});
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  @override
  Widget build(BuildContext context) => AppCard(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 38, height: 38, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: LoyColors.blue, size: 20)),
    const SizedBox(height: 15), Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: LoyColors.navy, letterSpacing: -0.7)),
    const SizedBox(height: 4), Text(label, style: Theme.of(context).textTheme.bodyMedium),
  ]));
}

String moneyFromCents(dynamic cents) {
  final value = (num.tryParse(cents?.toString() ?? '') ?? 0) / 100;
  if (value == 0) return 'Reward';
  return '৳${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)} value';
}

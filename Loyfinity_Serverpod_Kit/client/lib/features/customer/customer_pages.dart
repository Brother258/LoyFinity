import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../shared/ui.dart';

class CustomerExplorePage extends StatefulWidget {
  const CustomerExplorePage({super.key});
  @override
  State<CustomerExplorePage> createState() => _CustomerExplorePageState();
}

class _CustomerExplorePageState extends State<CustomerExplorePage> {
  List<Map<String, dynamic>> _restaurants = [];
  bool _loading = false;
  String? _error;
  Position? _position;
  double _radius = 10;
  String _sort = 'fastest_reward';

  Future<void> _locateAndLoad() async {
    setState(() { _loading = true; _error = null; });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Turn on location services to discover nearby places.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is off. Enable it in Settings to see nearby businesses.');
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)));
      final result = await context.read<AppState>().api.get('/customer/nearby', query: {
        'lat': position.latitude, 'lng': position.longitude, 'radiusKm': _radius, 'sort': _sort,
      });
      final rows = (result['restaurants'] as List? ?? []).whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList();
      if (!mounted) return;
      setState(() { _position = position; _restaurants = rows; });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is Exception ? error.toString().replaceFirst('Exception: ', '') : context.read<AppState>().api.messageFrom(error));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _refresh() async {
    final position = _position;
    if (position == null) return _locateAndLoad();
    setState(() => _loading = true);
    try {
      final result = await context.read<AppState>().api.get('/customer/nearby', query: {'lat': position.latitude, 'lng': position.longitude, 'radiusKm': _radius, 'sort': _sort});
      final rows = (result['restaurants'] as List? ?? []).whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList();
      if (mounted) setState(() => _restaurants = rows);
    } catch (error) { if (mounted) setState(() => _error = context.read<AppState>().api.messageFrom(error)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: RefreshIndicator(
    onRefresh: _refresh,
    color: LoyColors.blue,
    child: CustomScrollView(slivers: [
      SliverPadding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 8), sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Good day, ${context.watch<AppState>().displayName.split(' ').first}', style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 4), Text('Find your next reward.', style: Theme.of(context).textTheme.headlineMedium)])),
          Container(width: 44, height: 44, decoration: BoxDecoration(color: LoyColors.blueTint, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.all_inclusive_rounded, color: LoyColors.blue, size: 29)),
        ]),
        const SizedBox(height: 18),
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [LoyColors.navy, LoyColors.navySoft], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(24)), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('YOUR NEXT STOP', style: TextStyle(color: Color(0xFFB8CCDB), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4)), const SizedBox(height: 7), const Text('Rewards are closer\nthan you think.', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.5)), const SizedBox(height: 12), TextButton.icon(onPressed: _loading ? null : _locateAndLoad, style: TextButton.styleFrom(foregroundColor: LoyColors.gold, padding: EdgeInsets.zero), icon: const Icon(Icons.my_location_rounded, size: 17), label: Text(_position == null ? 'Use my location' : 'Refresh nearby places'))]),
          const SizedBox(width: 8), Container(width: 76, height: 76, decoration: BoxDecoration(color: LoyColors.blue, borderRadius: BorderRadius.circular(24), border: Border.all(color: LoyColors.gold, width: 2)), child: const Icon(Icons.near_me_rounded, color: Colors.white, size: 40)),
        ])),
        const SizedBox(height: 24),
        Row(children: [Expanded(child: Text('Nearby businesses', style: Theme.of(context).textTheme.titleLarge)), if (_position != null) const StatusPill('LIVE LOCATION', good: true)]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _sortChoice('Fastest reward', 'fastest_reward')),
          const SizedBox(width: 8),
          Expanded(child: _sortChoice('Nearest', 'nearest')),
        ]),
        const SizedBox(height: 12),
        Row(children: [const Icon(Icons.radar_rounded, size: 16, color: LoyColors.muted), const SizedBox(width: 7), Text('Search radius: ${_radius.round()} km', style: Theme.of(context).textTheme.bodyMedium), const Spacer(), if (_position != null) Text('${_restaurants.length} found', style: Theme.of(context).textTheme.bodyMedium)]),
        Slider(value: _radius, min: 2, max: 20, divisions: 9, activeColor: LoyColors.blue, onChanged: (v) => setState(() => _radius = v), onChangeEnd: (_) => _refresh()),
      ]))),
      if (_loading && _restaurants.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: LoadingPane(label: 'Finding nearby rewards'))
      else if (_error != null) SliverFillRemaining(hasScrollBody: false, child: EmptyPane(title: 'Location unavailable', body: _error!, icon: Icons.location_off_outlined, action: 'Try again', onAction: _locateAndLoad))
      else if (_position == null) SliverFillRemaining(hasScrollBody: false, child: EmptyPane(title: 'Discover what is around you', body: 'Allow location access while using Loyfinity. We use it only to find nearby participating businesses.', icon: Icons.location_searching_rounded, action: 'Use my location', onAction: _locateAndLoad))
      else if (_restaurants.isEmpty) SliverFillRemaining(hasScrollBody: false, child: EmptyPane(title: 'No participating places nearby yet', body: 'Try a wider search radius or check again later.', icon: Icons.store_mall_directory_outlined, action: 'Search again', onAction: _locateAndLoad))
      else SliverPadding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 116), sliver: SliverList.builder(
        itemCount: _restaurants.length,
        itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 12), child: RestaurantCard(restaurant: _restaurants[index], onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RestaurantDetailPage(restaurant: _restaurants[index]))))),
      )),
    ]),
  ));

  Widget _sortChoice(String label, String value) {
    final selected = _sort == value;
    return InkWell(onTap: () { setState(() => _sort = value); if (_position != null) _refresh(); }, borderRadius: BorderRadius.circular(14), child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(vertical: 11), decoration: BoxDecoration(color: selected ? LoyColors.blueTint : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? LoyColors.blue : LoyColors.line)), child: Center(child: Text(label, style: TextStyle(color: selected ? LoyColors.blueDark : LoyColors.muted, fontWeight: FontWeight.w800, fontSize: 12)))));
  }
}

class RestaurantCard extends StatelessWidget {
  const RestaurantCard({super.key, required this.restaurant, required this.onTap});
  final Map<String, dynamic> restaurant;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final title = restaurant['name']?.toString() ?? 'Business';
    final visits = int.tryParse(restaurant['visitsRemaining']?.toString() ?? '') ?? -1;
    final progress = (num.tryParse(restaurant['rewardProgressPercent']?.toString() ?? '') ?? 0).toDouble().clamp(0, 100) / 100;
    final distance = num.tryParse(restaurant['distanceKm']?.toString() ?? '') ?? 0;
    final ready = visits == 0;
    return AppCard(onTap: onTap, padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 54, height: 54, decoration: BoxDecoration(color: LoyColors.blueTint, borderRadius: BorderRadius.circular(17)), child: Icon(_categoryIcon(restaurant['category']?.toString()), color: LoyColors.blue, size: 26)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 4), Text('${restaurant['category'] ?? 'Business'} · ${distance.toStringAsFixed(1)} km away', style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 7), Text(restaurant['address']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11))])),
        const Icon(Icons.chevron_right_rounded, color: LoyColors.muted),
      ]),
      const SizedBox(height: 14),
      Container(height: 1, color: LoyColors.line),
      const SizedBox(height: 12),
      if (restaurant['program_id'] != null) ...[
        Row(children: [const Icon(Icons.card_giftcard_rounded, color: LoyColors.gold, size: 18), const SizedBox(width: 7), Expanded(child: Text(restaurant['reward_description']?.toString() ?? 'Loyalty reward', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: LoyColors.navy, fontSize: 13))), StatusPill(ready ? 'READY TO REDEEM' : visits == 1 ? '1 VISIT LEFT' : '$visits VISITS LEFT', good: ready, gold: !ready)],),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: progress, minHeight: 7, backgroundColor: LoyColors.blueTint, color: ready ? LoyColors.green : LoyColors.blue)),
        const SizedBox(height: 6),
        Row(children: [Text('${restaurant['visits_count'] ?? 0}/${restaurant['reward_visits'] ?? 0} visits', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11)), const Spacer(), Text(moneyFromCents(restaurant['reward_value_cents']), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, fontWeight: FontWeight.w700))]),
      ] else const Text('Explore this business. Loyalty program coming soon.', style: TextStyle(color: LoyColors.muted, fontSize: 12)),
    ]));
  }
}

IconData _categoryIcon(String? category) {
  final value = (category ?? '').toLowerCase();
  if (value.contains('cafe') || value.contains('coffee')) return Icons.coffee_rounded;
  if (value.contains('gym') || value.contains('fitness')) return Icons.fitness_center_rounded;
  if (value.contains('salon')) return Icons.content_cut_rounded;
  if (value.contains('retail') || value.contains('shop')) return Icons.shopping_bag_rounded;
  return Icons.restaurant_rounded;
}

class RestaurantDetailPage extends StatefulWidget {
  const RestaurantDetailPage({super.key, required this.restaurant});
  final Map<String, dynamic> restaurant;
  @override
  State<RestaurantDetailPage> createState() => _RestaurantDetailPageState();
}

class _RestaurantDetailPageState extends State<RestaurantDetailPage> {
  bool _busy = false;
  bool _favorite = false;
  @override
  void initState() {
    super.initState();
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    try {
      final result = await context.read<AppState>().api.get('/customer/favorites');
      final id = widget.restaurant['business_id']?.toString();
      final favorites = (result['favorites'] as List? ?? []).whereType<Map>();
      if (mounted) setState(() => _favorite = favorites.any((item) => item['id']?.toString() == id));
    } catch (_) {
      // Favorite status is non-critical; the detail page remains usable offline.
    }
  }

  Future<void> _join() async {
    final id = widget.restaurant['program_id']?.toString();
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.post('/customer/enroll/$id');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to your loyalty wallet.')));
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<AppState>().api.messageFrom(error)))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _toggleFavorite() async {
    final id = widget.restaurant['business_id']?.toString();
    if (id == null) return;
    try {
      if (_favorite) { await context.read<AppState>().api.delete('/customer/favorites/$id'); }
      else { await context.read<AppState>().api.post('/customer/favorites/$id'); }
      if (mounted) setState(() => _favorite = !_favorite);
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<AppState>().api.messageFrom(error)))); }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.restaurant;
    return Scaffold(appBar: AppBar(title: const Text('Business details'), actions: [IconButton(onPressed: _toggleFavorite, icon: Icon(_favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: _favorite ? LoyColors.danger : LoyColors.navy))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
        Container(height: 170, decoration: BoxDecoration(gradient: const LinearGradient(colors: [LoyColors.navy, LoyColors.blue]), borderRadius: BorderRadius.circular(26)), child: const Center(child: Icon(Icons.storefront_rounded, color: Colors.white, size: 68))),
        const SizedBox(height: 20),
        Text(r['name']?.toString() ?? 'Business', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text('${r['category'] ?? 'Business'} · ${r['distanceKm'] ?? '—'} km away', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Location', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(r['address']?.toString() ?? 'Address not provided'), if (r['branch_phone']?.toString().isNotEmpty == true) Text(r['branch_phone'].toString())])),
        const SizedBox(height: 14),
        if (r['program_id'] != null) AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const StatusPill('LOYALTY PROGRAM'), const SizedBox(height: 12), Text(r['program_title']?.toString() ?? 'Loyalty program', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8), Text(r['description']?.toString() ?? 'Collect visits and unlock rewards.'), const SizedBox(height: 15),
          Row(children: [const Icon(Icons.card_giftcard_rounded, color: LoyColors.gold), const SizedBox(width: 8), Expanded(child: Text(r['reward_description']?.toString() ?? 'Reward', style: const TextStyle(fontWeight: FontWeight.w800))) ]),
          const SizedBox(height: 10), Text('${r['visitsRemaining'] ?? '—'} more visits to reward', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16), ElevatedButton(onPressed: _busy ? null : _join, child: Text(_busy ? 'Adding…' : 'Add to my wallet')),
        ])) else const EmptyPane(title: 'No active loyalty program', body: 'This business is part of Loyfinity discovery. Check back later for a reward journey.'),
      ]),
    );
  }
}

class CustomerWalletPage extends StatefulWidget {
  const CustomerWalletPage({super.key});
  @override
  State<CustomerWalletPage> createState() => _CustomerWalletPageState();
}

class _CustomerWalletPageState extends State<CustomerWalletPage> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() { super.initState(); _future = context.read<AppState>().api.get('/customer/wallet'); }
  Future<void> _reload() async { setState(() => _future = context.read<AppState>().api.get('/customer/wallet')); await _future; }
  @override
  Widget build(BuildContext context) => SafeArea(child: RefreshIndicator(onRefresh: _reload, child: FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      final items = (snapshot.data?['wallet'] as List? ?? []).whereType<Map>().map((e) => e.map((k,v) => MapEntry(k.toString(),v))).toList();
      return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 112), children: [
        Text('Your wallet', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 6), Text('Every visit brings a reward closer.', style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 22),
        if (snapshot.connectionState == ConnectionState.waiting) const LoadingPane(label: 'Loading loyalty cards')
        else if (snapshot.hasError) EmptyPane(title: 'Could not load wallet', body: context.read<AppState>().api.messageFrom(snapshot.error!), action: 'Try again', onAction: _reload)
        else if (items.isEmpty) const EmptyPane(title: 'Your wallet is waiting', body: 'Join a nearby loyalty program and your digital cards will appear here.', icon: Icons.wallet_outlined)
        else ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 13), child: _WalletCard(item: item, onReward: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RewardQrPage(programId: item['program_id'].toString()))))))
      ]);
    },
  )));
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.item, required this.onReward});
  final Map<String, dynamic> item;
  final VoidCallback onReward;
  @override
  Widget build(BuildContext context) {
    final ready = item['rewardReady'] == true;
    final current = int.tryParse(item['visits_count']?.toString() ?? '') ?? 0;
    final target = int.tryParse(item['reward_visits']?.toString() ?? '') ?? 1;
    final percent = (num.tryParse(item['progressPercent']?.toString() ?? '') ?? 0).toDouble().clamp(0, 100) / 100;
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(item['business_name']?.toString() ?? 'Business', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))), if (ready) const StatusPill('READY', good: true)]),
      const SizedBox(height: 7), Text(item['program_title']?.toString() ?? 'Loyalty card', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12), Row(children: [const Icon(Icons.card_giftcard_rounded, size: 18, color: LoyColors.gold), const SizedBox(width: 8), Expanded(child: Text(item['reward_description']?.toString() ?? 'Reward', style: const TextStyle(fontWeight: FontWeight.w800)))]),
      const SizedBox(height: 13), ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: percent, minHeight: 9, color: ready ? LoyColors.green : LoyColors.blue, backgroundColor: LoyColors.blueTint)),
      const SizedBox(height: 7), Row(children: [Text('$current/$target visits', style: Theme.of(context).textTheme.bodyMedium), const Spacer(), Text('${item['visitsRemaining'] ?? 0} left', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: ready ? LoyColors.green : LoyColors.navy))]),
      if (ready) ...[const SizedBox(height: 14), ElevatedButton(onPressed: onReward, child: const Text('Show reward QR'))],
    ]));
  }
}

class RewardQrPage extends StatefulWidget {
  const RewardQrPage({super.key, required this.programId});
  final String programId;
  @override
  State<RewardQrPage> createState() => _RewardQrPageState();
}

class _RewardQrPageState extends State<RewardQrPage> {
  String? _payload;
  String? _business;
  String? _reward;
  bool _loading = true;
  String? _error;
  @override
  void initState() { super.initState(); _create(); }
  Future<void> _create() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await context.read<AppState>().api.post('/customer/reward-qr', data: {'programId': widget.programId});
      if (!mounted) return;
      setState(() { _payload = result['payload']?.toString(); _business = result['businessName']?.toString(); _reward = result['reward']?.toString(); });
    } catch (error) { if (mounted) setState(() => _error = context.read<AppState>().api.messageFrom(error)); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Redeem reward')), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: _loading ? const LoadingPane(label: 'Preparing a secure reward code') : _payload == null ? Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline, color: LoyColors.danger, size: 48), const SizedBox(height: 12), Text(_error ?? 'Could not create reward code.', textAlign: TextAlign.center), const SizedBox(height: 18), OutlinedButton(onPressed: _create, child: const Text('Try again'))]) : Column(mainAxisSize: MainAxisSize.min, children: [
    const StatusPill('REWARD UNLOCKED', good: true), const SizedBox(height: 16), Text(_reward ?? 'Your reward', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center), const SizedBox(height: 6), Text(_business ?? '', style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 24),
    Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: LoyColors.line)), child: QrImageView(data: _payload!, version: QrVersions.auto, size: 230)),
    const SizedBox(height: 18), const Text('Show this code to staff at the counter. It expires in 90 seconds and can only be used once.', textAlign: TextAlign.center, style: TextStyle(color: LoyColors.muted, height: 1.5)), const SizedBox(height: 18), OutlinedButton.icon(onPressed: _create, icon: const Icon(Icons.refresh_rounded), label: const Text('Generate a new code')),
  ]))));
}

class CustomerActivityPage extends StatefulWidget {
  const CustomerActivityPage({super.key});
  @override
  State<CustomerActivityPage> createState() => _CustomerActivityPageState();
}

class _CustomerActivityPageState extends State<CustomerActivityPage> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() { super.initState(); _future = context.read<AppState>().api.get('/customer/history'); }
  Future<void> _reload() async { setState(() => _future = context.read<AppState>().api.get('/customer/history')); await _future; }
  @override
  Widget build(BuildContext context) => SafeArea(child: RefreshIndicator(onRefresh: _reload, child: FutureBuilder<Map<String,dynamic>>(future: _future, builder: (context,snapshot) {
    final rows = (snapshot.data?['history'] as List? ?? []).whereType<Map>().map((e)=>e.map((k,v)=>MapEntry(k.toString(),v))).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(20,24,20,110), children: [Text('Your activity',style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:6),Text('Your visits and redeemed rewards.',style:Theme.of(context).textTheme.bodyMedium),const SizedBox(height:20),
      if(snapshot.connectionState==ConnectionState.waiting) const LoadingPane(label:'Loading activity')
      else if(snapshot.hasError) EmptyPane(title:'Could not load activity',body:context.read<AppState>().api.messageFrom(snapshot.error!),action:'Try again',onAction:_reload)
      else if(rows.isEmpty) const EmptyPane(title:'Your story starts here',body:'Check in at a participating business to see your activity.',icon:Icons.receipt_long_outlined)
      else ...rows.map((r)=>Padding(padding:const EdgeInsets.only(bottom:10),child:AppCard(child:Row(children:[Container(width:42,height:42,decoration:BoxDecoration(color:r['event_type']=='redemption'?LoyColors.greenTint:LoyColors.blueTint,borderRadius:BorderRadius.circular(14)),child:Icon(r['event_type']=='redemption'?Icons.card_giftcard_rounded:Icons.location_on_rounded,color:r['event_type']=='redemption'?LoyColors.green:LoyColors.blue)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(r['business_name']?.toString()??'Business',style:const TextStyle(fontWeight:FontWeight.w800)),Text(r['event_type']=='redemption'?'Reward redeemed':'Visit checked in',style:Theme.of(context).textTheme.bodyMedium),if(r['detail']!=null)Text(r['detail'].toString(),style:Theme.of(context).textTheme.bodyMedium)])),Text(_date(r['occurred_at']),style:Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize:10))]))))
    ]);
  })));
  String _date(dynamic value) { final parsed=DateTime.tryParse(value?.toString()??''); return parsed==null?'':DateFormat('d MMM').format(parsed.toLocal()); }
}

class CustomerProfilePage extends StatelessWidget {
  const CustomerProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final state=context.watch<AppState>();
    return SafeArea(child: ListView(padding:const EdgeInsets.fromLTRB(20,24,20,110),children:[
      Text('Your profile',style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:18),
      AppCard(child:Row(children:[CircleAvatar(radius:28,backgroundColor:LoyColors.blueTint,child:Text(state.displayName.isNotEmpty?state.displayName[0].toUpperCase():'L',style:const TextStyle(color:LoyColors.blue,fontWeight:FontWeight.w900,fontSize:22))),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(state.displayName,style:Theme.of(context).textTheme.titleLarge),Text(state.user?['email']?.toString()??'',style:Theme.of(context).textTheme.bodyMedium),const SizedBox(height:6),const StatusPill('CUSTOMER ACCOUNT')]))])),
      const SizedBox(height:14),
      _ProfileAction(icon:Icons.group_add_outlined,title:'Join a business team',subtitle:'Accept an invitation with your verified email',onTap:()=>_acceptInvite(context)),
      _ProfileAction(icon:Icons.favorite_border_rounded,title:'Saved places',subtitle:'Businesses you want to visit again',onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const CustomerFavoritesPage()))),
      _ProfileAction(icon:Icons.notifications_none_rounded,title:'Notifications',subtitle:'Your reward and loyalty updates',onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const NotificationsPage()))),
      _ProfileAction(icon:Icons.privacy_tip_outlined,title:'Privacy & location',subtitle:'Location is used only for nearby discovery',onTap:()=>showDialog(context:context,builder:(_)=>const AlertDialog(title:Text('Your location'),content:Text('Loyfinity requests location only while you use nearby discovery. You can deny permission and manage it at any time in your device settings.')))),
      const SizedBox(height:18),OutlinedButton.icon(onPressed:()=>state.logout(),icon:const Icon(Icons.logout_rounded),label:const Text('Sign out')),
      const SizedBox(height:12),TextButton(onPressed:()=>_confirmDelete(context),style:TextButton.styleFrom(foregroundColor:LoyColors.danger),child:const Text('Delete my account')),
      const SizedBox(height:8),const Center(child:Text('Loyfinity · Version 1.0.0',style:TextStyle(color:LoyColors.muted,fontSize:11))),
    ]));
  }
  Future<void> _acceptInvite(BuildContext context) async {
    final controller=TextEditingController();
    final submit=await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(title:const Text('Join a business team'),content:TextField(controller:controller,decoration:const InputDecoration(labelText:'Invitation code'),autocorrect:false),actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('Cancel')),ElevatedButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('Accept invite'))]));
    if(submit!=true||!context.mounted)return;
    try {
      await context.read<AppState>().api.post('/auth/accept-staff-invite',data:{'token':controller.text.trim()});
      if(!context.mounted)return;
      await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(title:const Text('Invitation accepted'),content:const Text('Your account role is now Business Staff. Sign in again to open the business workspace.'),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Continue'))]));
      if(context.mounted)await context.read<AppState>().logout();
    } catch(error) {
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(context.read<AppState>().api.messageFrom(error))));
    }
  }
  Future<void> _confirmDelete(BuildContext context) async {
    final confirm=await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(title:const Text('Delete your account?'),content:const Text('This permanently deletes your profile and associated loyalty data. If you are the only owner of a business, its workspace and branches will also be deleted.'),actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(dialog,true),style:TextButton.styleFrom(foregroundColor:LoyColors.danger),child:const Text('Delete account'))]));
    if(confirm!=true||!context.mounted)return;
    try { await context.read<AppState>().deleteAccount(); }
    catch(error){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(context.read<AppState>().api.messageFrom(error))));}
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({required this.icon,required this.title,required this.subtitle,required this.onTap});
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  @override
  Widget build(BuildContext context)=>AppCard(onTap:onTap,padding:const EdgeInsets.all(15),child:Row(children:[Icon(icon,color:LoyColors.blue,size:22),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),Text(subtitle,style:Theme.of(context).textTheme.bodyMedium)])),const Icon(Icons.chevron_right_rounded,color:LoyColors.muted)]));
}

class CustomerFavoritesPage extends StatefulWidget {
  const CustomerFavoritesPage({super.key});
  @override
  State<CustomerFavoritesPage> createState() => _CustomerFavoritesPageState();
}

class _CustomerFavoritesPageState extends State<CustomerFavoritesPage> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.get('/customer/favorites');
  }

  Future<void> _reload() async {
    setState(() => _future = context.read<AppState>().api.get('/customer/favorites'));
    await _future;
  }

  Future<void> _remove(String id) async {
    try {
      await context.read<AppState>().api.delete('/customer/favorites/$id');
      await _reload();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<AppState>().api.messageFrom(error))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved places')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const LoadingPane();
        if (snapshot.hasError) return EmptyPane(title: 'Saved places unavailable', body: context.read<AppState>().api.messageFrom(snapshot.error!), action: 'Retry', onAction: _reload);
        final items = (snapshot.data?['favorites'] as List? ?? []).whereType<Map>().toList();
        if (items.isEmpty) return const EmptyPane(title: 'No saved places yet', body: 'Tap the heart on a business to keep it here for later.', icon: Icons.favorite_border_rounded);
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final id = item['id'].toString();
              return AppCard(child: Row(children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: LoyColors.blueTint, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.storefront_rounded, color: LoyColors.blue)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['name']?.toString() ?? 'Business', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(item['category']?.toString() ?? '', style: Theme.of(context).textTheme.bodyMedium),
                  if ((item['description']?.toString() ?? '').isNotEmpty) Text(item['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                ])),
                IconButton(onPressed: () => _remove(id), tooltip: 'Remove saved place', icon: const Icon(Icons.favorite_rounded, color: LoyColors.danger)),
              ]));
            },
          ),
        );
      },
    ),
  );
}

class NotificationsPage extends StatefulWidget { const NotificationsPage({super.key}); @override State<NotificationsPage> createState()=>_NotificationsPageState(); }
class _NotificationsPageState extends State<NotificationsPage>{late Future<Map<String,dynamic>> _future;@override void initState(){super.initState();_future=context.read<AppState>().api.get('/customer/notifications');}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Notifications')),body:FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,snapshot){final rows=(snapshot.data?['notifications'] as List? ?? []).whereType<Map>().toList();if(snapshot.connectionState==ConnectionState.waiting)return const LoadingPane();if(rows.isEmpty)return const EmptyPane(title:'All caught up',body:'Your reward updates will appear here.',icon:Icons.notifications_none_rounded);return ListView.separated(padding:const EdgeInsets.all(20),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(context,i){final r=rows[i];return AppCard(child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.notifications_active_outlined,color:LoyColors.blue),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(r['title']?.toString()??'Update',style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:4),Text(r['body']?.toString()??'')]))]));});}));}

class CustomerScanPage extends StatefulWidget { const CustomerScanPage({super.key}); @override State<CustomerScanPage> createState()=>_CustomerScanPageState(); }
class _CustomerScanPageState extends State<CustomerScanPage>{bool _handled=false;bool _busy=false;String? _message;bool? _success;
  Future<void> _handle(String raw) async {if(_handled||_busy)return;setState(()=>_busy=true);_handled=true;try{final token=raw.replaceFirst('LOYFINITY:','');var permission=await Geolocator.checkPermission();if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever)throw Exception('Allow location while using Loyfinity to verify an in-person visit.');final position=await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:10)));final result=await context.read<AppState>().api.post('/customer/checkin/claim',data:{'token':token,'latitude':position.latitude,'longitude':position.longitude});if(!mounted)return;setState(()=>_message='${result['businessName']}\n${result['visitsCount']}/${result['rewardVisits']} visits completed. ${result['rewardReady']==true?'Your reward is ready!':'${result['visitsRemaining']} more visits to your reward.'}');_success=true;}catch(error){if(!mounted)return;setState(()=>_message=context.read<AppState>().api.messageFrom(error));_success=false;}finally{if(mounted)setState(()=>_busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Scan to check in')),body:Stack(children:[MobileScanner(onDetect:(capture){final raw=capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;if(raw!=null&&raw.startsWith('LOYFINITY:'))_handle(raw);}),Positioned.fill(child:IgnorePointer(child:Center(child:Container(width:260,height:260,decoration:BoxDecoration(border:Border.all(color:LoyColors.gold,width:4),borderRadius:BorderRadius.circular(28)))))),if(_busy||_message!=null)Positioned.fill(child:ColoredBox(color:Colors.black54,child:Center(child:Container(margin:const EdgeInsets.all(28),padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(22)),child:Column(mainAxisSize:MainAxisSize.min,children:[if(_busy)const CircularProgressIndicator()else Icon(_success==true?Icons.check_circle_rounded:Icons.error_outline_rounded,color:_success==true?LoyColors.green:LoyColors.danger,size:40),const SizedBox(height:12),Text(_busy?'Validating your visit…':_success==true?'Check-in complete':'Unable to check in',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),Text(_message??'',textAlign:TextAlign.center),const SizedBox(height:16),if(!_busy)ElevatedButton(onPressed:()=>setState((){_message=null;_handled=false;}),child:const Text('Scan another code'))])))))]));}

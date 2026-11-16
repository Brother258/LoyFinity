import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _business = TextEditingController();
  final _category = TextEditingController(text: 'Restaurant');
  bool _registering = false;
  bool _showPassword = false;
  String _role = 'customer';
  bool _forgotBusy = false;

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _password.dispose(); _business.dispose(); _category.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    if (_registering) {
      await state.register(
        fullName: _name.text,
        email: _email.text,
        password: _password.text,
        role: _role,
        businessName: _business.text,
        businessCategory: _category.text,
      );
      if (!mounted) return;
      if (state.lastMessage != null) _showMessage(state.lastMessage!);
    } else {
      final ok = await state.login(_email.text, _password.text);
      if (!mounted) return;
      if (!ok && state.lastMessage != null) _showMessage(state.lastMessage!);
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) { _showMessage('Enter your email address first.'); return; }
    setState(() => _forgotBusy = true);
    try {
      await context.read<AppState>().api.post('/auth/forgot-password', data: {'email': email});
      if (mounted) _showMessage('If an account exists, a password reset email has been sent.');
    } catch (error) {
      if (mounted) _showMessage(context.read<AppState>().api.messageFrom(error));
    } finally { if (mounted) setState(() => _forgotBusy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 34),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 52, maxWidth: 520),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: LoyColors.blue, borderRadius: BorderRadius.circular(16), border: Border.all(color: LoyColors.gold, width: 2)), child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 31)),
              const SizedBox(width: 12), const Text('Loyfinity', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: LoyColors.navy, letterSpacing: -0.8)),
            ]),
            const SizedBox(height: 42),
            Text(_registering ? 'Start earning\nmore from every visit.' : 'Welcome\nback.', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 10),
            Text(_registering ? 'One account for every loyalty journey.' : 'Your loyalty journeys are waiting.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: LoyColors.muted)),
            const SizedBox(height: 28),
            Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: LoyColors.canvas, borderRadius: BorderRadius.circular(14)), child: Row(children: [
              Expanded(child: _modeButton('Sign in', !_registering, () => setState(() { _registering = false; }))),
              Expanded(child: _modeButton('Create account', _registering, () => setState(() { _registering = true; }))),
            ])),
            const SizedBox(height: 22),
            if (_registering) ...[
              const Text('Choose your workspace', style: TextStyle(fontWeight: FontWeight.w800, color: LoyColors.navy)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _roleCard('Customer', 'Discover & earn', Icons.person_rounded, _role == 'customer', () => setState(() => _role = 'customer'))),
                const SizedBox(width: 10),
                Expanded(child: _roleCard('Business', 'Manage loyalty', Icons.storefront_rounded, _role == 'business_owner', () => setState(() => _role = 'business_owner'))),
              ]),
              const SizedBox(height: 16),
            ],
            Form(key: _formKey, child: Column(children: [
              if (_registering) ...[
                TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name.' : null),
                const SizedBox(height: 12),
              ],
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.mail_outline_rounded)), validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email address.' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _password, obscureText: !_showPassword, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline_rounded), suffixIcon: IconButton(onPressed: () => setState(() => _showPassword = !_showPassword), icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined))), validator: (v) {
                if (v == null || v.length < 12) return 'Use at least 12 characters.';
                if (_registering && (!RegExp(r'[A-Z]').hasMatch(v) || !RegExp(r'[a-z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v))) return 'Include upper-case, lower-case and a number.';
                return null;
              }),
              if (_registering && _role == 'business_owner') ...[
                const SizedBox(height: 12),
                TextFormField(controller: _business, decoration: const InputDecoration(labelText: 'Business name', prefixIcon: Icon(Icons.storefront_outlined)), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your business name.' : null),
                const SizedBox(height: 12),
                TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Business category', prefixIcon: Icon(Icons.category_outlined)), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a category.' : null),
              ],
            ])),
            if (!_registering) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgotBusy ? null : _forgotPassword, child: Text(_forgotBusy ? 'Sending…' : 'Forgot password?'))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: app.busy ? null : _submit, child: app.busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(_registering ? 'Create account' : 'Sign in')),
            const SizedBox(height: 18),
            Text(_registering ? 'Your role is saved to your account. The app opens the matching workspace automatically after sign-in.' : 'Sign in with your account. Loyfinity automatically opens your customer or business workspace.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (_registering && _role == 'business_owner') const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.verified_user_outlined, color: LoyColors.blue, size: 18), SizedBox(width: 8), Expanded(child: Text('New businesses are reviewed before appearing in public discovery. You can prepare your workspace while it is under review.', style: TextStyle(fontSize: 12, color: LoyColors.muted, height: 1.4)))]),
          ]),
        ),
      ))),
    );
  }

  Widget _modeButton(String label, bool selected, VoidCallback onTap) => GestureDetector(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(11), boxShadow: selected ? const [BoxShadow(color: Color(0x0B102D46), blurRadius: 8, offset: Offset(0, 2))] : null), child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? LoyColors.navy : LoyColors.muted, fontSize: 13))));

  Widget _roleCard(String title, String subtitle, IconData icon, bool selected, VoidCallback onTap) => GestureDetector(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 160), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: selected ? LoyColors.blueTint : LoyColors.canvas, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? LoyColors.blue : Colors.transparent, width: 1.4)), child: Row(children: [Icon(icon, color: selected ? LoyColors.blue : LoyColors.muted), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: LoyColors.navy, fontSize: 13)), Text(subtitle, style: const TextStyle(fontSize: 11, color: LoyColors.muted))]))]));
}

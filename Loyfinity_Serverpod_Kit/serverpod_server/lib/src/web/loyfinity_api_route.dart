import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:serverpod/serverpod.dart';

class _ApiFailure implements Exception {
  const _ApiFailure(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
}

class _Actor {
  const _Actor(this.id, this.fullName, this.email, this.role, this.emailVerified);
  final String id;
  final String fullName;
  final String email;
  final String role;
  final bool emailVerified;
}

class _BusinessContext {
  const _BusinessContext(this.id, this.name, this.category, this.description,
      this.phone, this.website, this.status, this.plan, this.memberRole);
  final String id;
  final String name;
  final String category;
  final String description;
  final String phone;
  final String website;
  final String status;
  final String plan;
  final String memberRole;
}

/// Compatibility HTTP API implemented *inside Serverpod*.
/// The Flutter client keeps a small Dio transport, while all request handling,
/// database work and security-sensitive decisions run in this Dart Serverpod
/// process. No Node.js service is involved.
class LoyfinityApiRoute extends Route {
  LoyfinityApiRoute()
      : super(methods: {
          Method.get,
          Method.post,
          Method.patch,
          Method.delete,
          Method.options,
        });

  @override
  Future<Result> handleCall(Session session, Request request) async {
    if (request.method == Method.options) return Response.noContent();

    try {
      final path = request.url.path.replaceFirst(RegExp(r'^/v1'), '');
      final query = request.url.queryParameters;
      Map<String, dynamic> body = <String, dynamic>{};
      if (request.method == Method.post || request.method == Method.patch) {
        final raw = await request.readAsString();
        if (raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is! Map) throw const _ApiFailure(400, 'INVALID_JSON', 'A JSON object is required.');
          body = decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      }
      await _enforceAuthRateLimit(session, request, path, body);
      final result = await _dispatch(session, request, path, query, body);
      if (result == null) return Response.notFound(body: Body.fromString(_json({'error': 'NOT_FOUND', 'message': 'The requested resource was not found.'}), mimeType: MimeType.json));
      if (result.status == 204) return Response.noContent();
      return Response(result.status, body: Body.fromString(_json(result.data), mimeType: MimeType.json));
    } on _ApiFailure catch (error) {
      return Response(error.status, body: Body.fromString(_json({'error': error.code, 'message': error.message}), mimeType: MimeType.json));
    } on FormatException {
      return Response(400, body: Body.fromString(_json({'error': 'INVALID_INPUT', 'message': 'Some submitted values are invalid.'}), mimeType: MimeType.json));
    } catch (error, stack) {
      stderr.writeln('Loyfinity API error: $error\n$stack');
      return Response(500, body: Body.fromString(_json({'error': 'INTERNAL_ERROR', 'message': 'Something went wrong. Please try again.'}), mimeType: MimeType.json));
    }
  }

  Future<void> _enforceAuthRateLimit(Session s, Request r, String path, Map<String, dynamic> b) async {
    const limitedPaths = {
      '/auth/register',
      '/auth/login',
      '/auth/forgot-password',
      '/auth/reset-password',
      '/auth/verify-email',
    };
    if (r.method != Method.post || !limitedPaths.contains(path)) return;

    // Caddy is the only public ingress in the supplied deployment. It forwards
    // the originating address in X-Forwarded-For. The email is hashed before
    // it is included in the database key; no raw IP or email is stored here.
    final forwardedFor = r.headers['X-Forwarded-For']?.first ?? 'direct';
    final email = _string(b['email']).trim().toLowerCase();
    final key = _sha256('$path|$forwardedFor|$email');
    final rows = await _query(s, '''INSERT INTO auth_rate_limits(bucket_key,window_id,attempts)
      VALUES(@key,FLOOR(EXTRACT(EPOCH FROM NOW())/900)::bigint,1)
      ON CONFLICT(bucket_key,window_id) DO UPDATE SET attempts=auth_rate_limits.attempts+1
      RETURNING attempts''', {'key': key});
    if (rows.isNotEmpty && _int(rows.first['attempts']) > 10) {
      throw const _ApiFailure(429, 'RATE_LIMITED', 'Too many attempts. Please try again in 15 minutes.');
    }
    await _exec(s, '''DELETE FROM auth_rate_limits
      WHERE window_id < FLOOR(EXTRACT(EPOCH FROM NOW())/900)::bigint - 4''', {});
  }

  Future<_HttpResult?> _dispatch(Session s, Request r, String path, Map<String, String> q, Map<String, dynamic> b) async {
    final method = r.method;
    if (path == '/auth/register' && method == Method.post) return _register(s, b);
    if (path == '/auth/verify-email' && method == Method.post) return _verifyEmail(s, b);
    if (path == '/auth/login' && method == Method.post) return _login(s, b);
    if (path == '/auth/refresh' && method == Method.post) return _refresh(s, b);
    if (path == '/auth/logout' && method == Method.post) return _logout(s, b);
    if (path == '/auth/forgot-password' && method == Method.post) return _forgotPassword(s, b);
    if (path == '/auth/reset-password' && method == Method.post) return _resetPassword(s, b);

    if (path == '/auth/me' && method == Method.delete) {
      final actor = await _authenticate(s, r);
      await _exec(s, 'DELETE FROM users WHERE id=@id', {'id': actor.id});
      return const _HttpResult(204, null);
    }
    if (path == '/auth/accept-staff-invite' && method == Method.post) {
      final actor = await _authenticate(s, r);
      final token = _string(b['token']);
      if (token.length < 30) throw const _ApiFailure(400, 'INVALID_INVITE', 'This invitation is invalid.');
      final invite = await _one(s, '''SELECT id,business_id,email,member_role FROM staff_invites
        WHERE token_hash=@hash AND accepted_at IS NULL AND expires_at>NOW()''', {'hash': _sha256(token)});
      if (invite == null || invite['email'].toString().toLowerCase() != actor.email.toLowerCase()) {
        throw const _ApiFailure(400, 'INVALID_INVITE', 'This invitation is invalid or belongs to another email address.');
      }
      await s.db.transaction((tx) async {
        await _exec(s, '''INSERT INTO business_members(business_id,user_id,member_role)
          VALUES(@businessId,@userId,@role) ON CONFLICT(business_id,user_id) DO UPDATE SET member_role=EXCLUDED.member_role''',
          {'businessId': invite['business_id'], 'userId': actor.id, 'role': invite['member_role']}, tx: tx);
        await _exec(s, "UPDATE users SET role='business_staff',updated_at=NOW() WHERE id=@userId", {'userId': actor.id}, tx: tx);
        await _exec(s, 'UPDATE staff_invites SET accepted_at=NOW() WHERE id=@id', {'id': invite['id']}, tx: tx);
      });
      return const _HttpResult(200, {'accepted': true});
    }

    if (path.startsWith('/customer/')) {
      final actor = await _authenticate(s, r);
      if (actor.role != 'customer') throw const _ApiFailure(403, 'FORBIDDEN', 'This feature is available to customer accounts.');
      return _customer(s, actor, method, path, q, b);
    }
    if (path.startsWith('/business/')) {
      final actor = await _authenticate(s, r);
      if (actor.role != 'business_owner' && actor.role != 'business_staff') {
        throw const _ApiFailure(403, 'FORBIDDEN', 'This feature is available to business accounts.');
      }
      final business = await _businessContext(s, actor.id);
      return _business(s, actor, business, method, path, b);
    }
    return null;
  }

  Future<_HttpResult?> _customer(Session s, _Actor actor, Method method, String path, Map<String, String> q, Map<String, dynamic> b) async {
    if (path == '/customer/nearby' && method == Method.get) {
      final lat = double.tryParse(q['lat'] ?? '');
      final lng = double.tryParse(q['lng'] ?? '');
      final radius = (double.tryParse(q['radiusKm'] ?? '10') ?? 10).clamp(1, 30);
      final sort = q['sort'] == 'nearest' ? 'nearest' : 'fastest_reward';
      if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        throw const _ApiFailure(400, 'LOCATION_REQUIRED', 'A valid latitude and longitude are required.');
      }
      final rows = await _query(s, '''WITH user_location AS (
        SELECT ST_SetSRID(ST_MakePoint(@lng,@lat),4326)::geography AS point
      )
      SELECT b.id AS business_id,b.name,b.category,b.description,b.status,
        br.id AS branch_id,br.name AS branch_name,br.address,br.phone AS branch_phone,
        ST_Y(br.location::geometry) AS latitude,ST_X(br.location::geometry) AS longitude,
        ROUND((ST_Distance(br.location,ul.point)/1000.0)::numeric,2) AS distance_km,
        p.id AS program_id,p.title AS program_title,p.reward_description,p.reward_visits,p.reward_value_cents,
        COALESCE(cp.visits_count,0)::int AS visits_count,
        CASE WHEN p.id IS NULL THEN NULL ELSE GREATEST(p.reward_visits-COALESCE(cp.visits_count,0),0) END::int AS visits_remaining,
        CASE WHEN p.id IS NULL THEN 0 ELSE LEAST(100,ROUND((COALESCE(cp.visits_count,0)::numeric/p.reward_visits)*100))::int END AS progress_percent
      FROM branches br JOIN businesses b ON b.id=br.business_id AND b.status='approved'
      CROSS JOIN user_location ul
      LEFT JOIN LATERAL (SELECT id,title,reward_description,reward_visits,reward_value_cents FROM loyalty_programs
        WHERE business_id=b.id AND is_active=TRUE AND (starts_at IS NULL OR starts_at<=NOW()) AND (ends_at IS NULL OR ends_at>NOW())
        ORDER BY created_at DESC LIMIT 1) p ON TRUE
      LEFT JOIN customer_progress cp ON cp.program_id=p.id AND cp.customer_id=@customerId
      WHERE br.is_active=TRUE AND ST_DWithin(br.location,ul.point,@radiusMeters)
      ORDER BY
        CASE WHEN @sort='nearest' THEN ST_Distance(br.location,ul.point) END ASC NULLS LAST,
        CASE WHEN @sort='fastest_reward' AND p.id IS NOT NULL AND GREATEST(p.reward_visits-COALESCE(cp.visits_count,0),0)=0 THEN 0
             WHEN @sort='fastest_reward' AND p.id IS NOT NULL THEN 1 ELSE 2 END ASC,
        CASE WHEN @sort='fastest_reward' THEN GREATEST(p.reward_visits-COALESCE(cp.visits_count,0),0) END ASC NULLS LAST,
        CASE WHEN @sort='fastest_reward' THEN ST_Distance(br.location,ul.point) END ASC NULLS LAST,
        p.reward_value_cents DESC NULLS LAST,b.name ASC LIMIT 100''', {
        'lat': lat, 'lng': lng, 'radiusMeters': radius * 1000, 'customerId': actor.id, 'sort': sort,
      });
      final restaurants = <Map<String, dynamic>>[];
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final remaining = row['visits_remaining'] == null ? null : _int(row['visits_remaining']);
        restaurants.add({...row,
          'distanceKm': _double(row['distance_km']),
          'rewardProgressPercent': _int(row['progress_percent']),
          'visitsRemaining': remaining,
          'rewardValue': _int(row['reward_value_cents']) / 100,
          'rank': i + 1,
          'rankLabel': row['program_id'] == null ? 'No active reward' : remaining == 0 ? 'Reward ready' : remaining == 1 ? '1 visit to reward' : '$remaining visits to reward',
        });
      }
      return _HttpResult(200, {'restaurants': restaurants, 'ranking': sort, 'radiusKm': radius, 'generatedAt': DateTime.now().toUtc().toIso8601String()});
    }

    if (path.startsWith('/customer/enroll/') && method == Method.post) {
      final id = path.split('/').last;
      final program = await _one(s, '''SELECT p.id,p.business_id,p.title,p.reward_visits,p.reward_description,b.name AS business_name
        FROM loyalty_programs p JOIN businesses b ON b.id=p.business_id WHERE p.id=@id AND p.is_active=TRUE AND b.status='approved' ''', {'id': id});
      if (program == null) throw const _ApiFailure(404, 'PROGRAM_NOT_FOUND', 'This loyalty program is not available.');
      final progress = await _one(s, '''INSERT INTO customer_progress(customer_id,program_id) VALUES(@userId,@programId)
        ON CONFLICT(customer_id,program_id) DO UPDATE SET updated_at=NOW()
        RETURNING id,visits_count,lifetime_visits''', {'userId': actor.id, 'programId': id});
      return _HttpResult(201, {'enrolled': true, 'businessName': program['business_name'], 'program': program, 'progress': progress});
    }

    if (path == '/customer/wallet' && method == Method.get) {
      final rows = await _query(s, '''SELECT cp.id AS progress_id,cp.visits_count,cp.lifetime_visits,cp.last_visit_at,
        p.id AS program_id,p.title AS program_title,p.reward_visits,p.reward_description,p.reward_value_cents,
        b.id AS business_id,b.name AS business_name,b.category,
        GREATEST(p.reward_visits-cp.visits_count,0)::int AS visits_remaining,
        LEAST(100,ROUND((cp.visits_count::numeric/p.reward_visits)*100))::int AS progress_percent
        FROM customer_progress cp JOIN loyalty_programs p ON p.id=cp.program_id JOIN businesses b ON b.id=p.business_id
        WHERE cp.customer_id=@userId AND p.is_active=TRUE ORDER BY (cp.visits_count>=p.reward_visits) DESC,visits_remaining ASC,b.name''', {'userId': actor.id});
      return _HttpResult(200, {'wallet': rows.map((row) => {...row,
        'visitsRemaining': _int(row['visits_remaining']),
        'progressPercent': _int(row['progress_percent']),
        'rewardValue': _int(row['reward_value_cents']) / 100,
        'rewardReady': _int(row['visits_count']) >= _int(row['reward_visits']),
      }).toList()});
    }

    if (path == '/customer/reward-qr' && method == Method.post) {
      final programId = _string(b['programId']);
      if (programId.isEmpty) throw const _ApiFailure(400, 'PROGRAM_REQUIRED', 'Choose a loyalty card first.');
      final progress = await _one(s, '''SELECT cp.visits_count,p.reward_visits,p.reward_description,b.name AS business_name
        FROM customer_progress cp JOIN loyalty_programs p ON p.id=cp.program_id JOIN businesses b ON b.id=p.business_id
        WHERE cp.customer_id=@userId AND p.id=@programId AND p.is_active=TRUE''', {'userId': actor.id, 'programId': programId});
      if (progress == null || _int(progress['visits_count']) < _int(progress['reward_visits'])) {
        throw const _ApiFailure(409, 'REWARD_NOT_READY', 'Complete the remaining visits before redeeming this reward.');
      }
      final token = _randomToken();
      await _exec(s, '''INSERT INTO qr_tokens(token_hash,purpose,customer_id,program_id,expires_at)
        VALUES(@hash,'redeem',@userId,@programId,NOW()+INTERVAL '90 seconds')''',
        {'hash': _sha256(token), 'userId': actor.id, 'programId': programId});
      return _HttpResult(200, {'payload': 'LOYFINITY:$token', 'expiresInSeconds': 90, 'reward': progress['reward_description'], 'businessName': progress['business_name']});
    }

    if (path == '/customer/checkin/claim' && method == Method.post) {
      final token = _string(b['token']).replaceFirst(RegExp(r'^LOYFINITY:'), '');
      final lat = _doubleOrNull(b['latitude']);
      final lng = _doubleOrNull(b['longitude']);
      if (token.length < 30) throw const _ApiFailure(400, 'INVALID_QR', 'This check-in QR code is invalid.');
      if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        throw const _ApiFailure(400, 'LOCATION_REQUIRED', 'Location is needed to verify this in-person check-in.');
      }
      final result = await s.db.transaction((tx) async {
        final qr = await _one(s, '''SELECT qt.id AS qr_id,br.id AS branch_id,br.business_id,b.name AS business_name
          FROM qr_tokens qt JOIN branches br ON br.id=qt.branch_id JOIN businesses b ON b.id=br.business_id
          WHERE qt.token_hash=@hash AND qt.purpose='checkin' AND qt.used_at IS NULL AND qt.expires_at>NOW()
          AND br.is_active=TRUE AND b.status='approved' FOR UPDATE OF qt''', {'hash': _sha256(token)}, tx: tx);
        if (qr == null) throw const _ApiFailure(400, 'QR_EXPIRED', 'This check-in code has expired. Ask the business for a new code.');
        final proximity = await _one(s, '''SELECT ST_Distance(location,ST_SetSRID(ST_MakePoint(@lng,@lat),4326)::geography) AS distance_m
          FROM branches WHERE id=@branchId''', {'branchId': qr['branch_id'], 'lat': lat, 'lng': lng}, tx: tx);
        if (proximity == null || _double(proximity['distance_m']) > 250) throw const _ApiFailure(403, 'NOT_AT_BRANCH', 'You need to be near this branch to check in.');
        final program = await _one(s, '''SELECT id,title,reward_visits,reward_description FROM loyalty_programs
          WHERE business_id=@businessId AND is_active=TRUE ORDER BY created_at DESC LIMIT 1''', {'businessId': qr['business_id']}, tx: tx);
        if (program == null) throw const _ApiFailure(409, 'NO_ACTIVE_PROGRAM', 'This business has no active loyalty program.');
        final checkin = await _query(s, '''INSERT INTO checkins(customer_id,business_id,branch_id,program_id)
          VALUES(@customerId,@businessId,@branchId,@programId)
          ON CONFLICT(customer_id,branch_id,activity_day) DO NOTHING RETURNING id''', {
          'customerId': actor.id, 'businessId': qr['business_id'], 'branchId': qr['branch_id'], 'programId': program['id'],
        }, tx: tx);
        if (checkin.isEmpty) throw const _ApiFailure(409, 'ALREADY_CHECKED_IN', 'You have already checked in at this branch today.');
        final progress = await _one(s, '''INSERT INTO customer_progress(customer_id,program_id,visits_count,lifetime_visits,last_visit_at)
          VALUES(@customerId,@programId,1,1,NOW())
          ON CONFLICT(customer_id,program_id) DO UPDATE SET visits_count=customer_progress.visits_count+1,
          lifetime_visits=customer_progress.lifetime_visits+1,last_visit_at=NOW(),updated_at=NOW()
          RETURNING visits_count,lifetime_visits''', {'customerId': actor.id, 'programId': program['id']}, tx: tx);
        await _exec(s, 'UPDATE qr_tokens SET used_at=NOW() WHERE id=@id', {'id': qr['qr_id']}, tx: tx);
        final count = _int(progress?['visits_count']);
        final remaining = max(0, _int(program['reward_visits']) - count);
        await _exec(s, '''INSERT INTO notifications(user_id,title,body,kind,data) VALUES(@userId,@title,@body,@kind,@data::jsonb)''', {
          'userId': actor.id,
          'title': remaining == 0 ? 'You unlocked a reward' : 'Loyalty progress updated',
          'body': remaining == 0 ? 'You can now redeem ${program['reward_description']} at ${qr['business_name']}.' : '$remaining more ${remaining == 1 ? 'visit' : 'visits'} until ${program['reward_description']}.',
          'kind': remaining == 0 ? 'reward_unlocked' : 'progress',
          'data': jsonEncode({'businessId': qr['business_id'], 'programId': program['id']}),
        }, tx: tx);
        return {'checkedIn': true, 'businessName': qr['business_name'], 'programTitle': program['title'], 'visitsCount': count,
          'rewardVisits': _int(program['reward_visits']), 'visitsRemaining': remaining, 'rewardReady': remaining == 0};
      });
      return _HttpResult(200, result);
    }

    if (path == '/customer/history' && method == Method.get) {
      final rows = await _query(s, '''SELECT * FROM (
        SELECT c.id,c.checked_in_at AS occurred_at,'checkin'::text AS event_type,b.name AS business_name,p.title AS program_title,NULL::text AS detail
        FROM checkins c JOIN businesses b ON b.id=c.business_id JOIN loyalty_programs p ON p.id=c.program_id WHERE c.customer_id=@userId
        UNION ALL
        SELECT r.id,r.redeemed_at,'redemption',b.name,p.title,r.reward_description
        FROM redemptions r JOIN businesses b ON b.id=r.business_id JOIN loyalty_programs p ON p.id=r.program_id WHERE r.customer_id=@userId
      ) events ORDER BY occurred_at DESC LIMIT 100''', {'userId': actor.id});
      return _HttpResult(200, {'history': rows});
    }

    if (path == '/customer/favorites' && method == Method.get) {
      final rows = await _query(s, '''SELECT b.id,b.name,b.category,b.description FROM favorites f JOIN businesses b ON b.id=f.business_id
        WHERE f.customer_id=@userId AND b.status='approved' ORDER BY f.created_at DESC''', {'userId': actor.id});
      return _HttpResult(200, {'favorites': rows});
    }
    final favoriteMatch = RegExp(r'^/customer/favorites/([0-9a-fA-F-]{36})$').firstMatch(path);
    if (favoriteMatch != null && method == Method.post) {
      final id = favoriteMatch.group(1)!;
      final found = await _one(s, "SELECT id FROM businesses WHERE id=@id AND status='approved'", {'id': id});
      if (found == null) throw const _ApiFailure(404, 'BUSINESS_NOT_FOUND', 'Business not found.');
      await _exec(s, 'INSERT INTO favorites(customer_id,business_id) VALUES(@userId,@businessId) ON CONFLICT DO NOTHING', {'userId': actor.id, 'businessId': id});
      return const _HttpResult(201, {'saved': true});
    }
    if (favoriteMatch != null && method == Method.delete) {
      await _exec(s, 'DELETE FROM favorites WHERE customer_id=@userId AND business_id=@businessId', {'userId': actor.id, 'businessId': favoriteMatch.group(1)});
      return const _HttpResult(204, null);
    }

    if (path == '/customer/notifications' && method == Method.get) {
      final rows = await _query(s, 'SELECT id,title,body,kind,data,read_at,created_at FROM notifications WHERE user_id=@userId ORDER BY created_at DESC LIMIT 100', {'userId': actor.id});
      return _HttpResult(200, {'notifications': rows});
    }
    final readMatch = RegExp(r'^/customer/notifications/([0-9a-fA-F-]{36})/read$').firstMatch(path);
    if (readMatch != null && method == Method.patch) {
      final rows = await _query(s, 'UPDATE notifications SET read_at=COALESCE(read_at,NOW()) WHERE id=@id AND user_id=@userId RETURNING id', {'id': readMatch.group(1), 'userId': actor.id});
      if (rows.isEmpty) throw const _ApiFailure(404, 'NOT_FOUND', 'Notification not found.');
      return const _HttpResult(200, {'read': true});
    }
    return null;
  }

  Future<_HttpResult?> _business(Session s, _Actor actor, _BusinessContext business, Method method, String path, Map<String, dynamic> b) async {
    final manager = business.memberRole == 'owner' || business.memberRole == 'manager';
    void requireManager() {
      if (!manager) throw const _ApiFailure(403, 'MANAGER_REQUIRED', 'Only business owners and managers can change these settings.');
    }
    if (path == '/business/dashboard' && method == Method.get) {
      final rows = await _query(s, '''SELECT
        (SELECT COUNT(DISTINCT cp.customer_id)::int FROM customer_progress cp JOIN loyalty_programs p ON p.id=cp.program_id WHERE p.business_id=@businessId) AS customers,
        (SELECT COUNT(*)::int FROM checkins WHERE business_id=@businessId AND checked_in_at>=NOW()-INTERVAL '30 days') AS visits,
        (SELECT COUNT(DISTINCT customer_id)::int FROM checkins WHERE business_id=@businessId AND checked_in_at>=NOW()-INTERVAL '30 days') AS unique_customers,
        (SELECT COUNT(*)::int FROM redemptions WHERE business_id=@businessId AND redeemed_at>=NOW()-INTERVAL '30 days') AS redemptions,
        (SELECT COUNT(*)::int FROM branches WHERE business_id=@businessId AND is_active=TRUE) AS branches,
        (SELECT COUNT(*)::int FROM loyalty_programs WHERE business_id=@businessId AND is_active=TRUE) AS programs''', {'businessId': business.id});
      final m = rows.first;
      final visits = _int(m['visits']);
      final unique = _int(m['unique_customers']);
      return _HttpResult(200, {'business': {'id': business.id, 'name': business.name, 'status': business.status, 'plan': business.plan},
        'metrics': {'customers': m['customers'], 'visitsLast30Days': visits, 'redemptionsLast30Days': m['redemptions'],
          'branches': m['branches'], 'activePrograms': m['programs'], 'repeatVisitRate': visits > 0 ? ((visits - unique) / visits * 100).round() : 0}});
    }
    if (path == '/business/profile' && method == Method.get) return _HttpResult(200, {'business': _businessJson(business)});
    if (path == '/business/profile' && method == Method.patch) {
      requireManager();
      final rows = await _query(s, '''UPDATE businesses SET name=COALESCE(@name,name),category=COALESCE(@category,category),
        description=COALESCE(@description,description),phone=COALESCE(@phone,phone),website=COALESCE(@website,website),updated_at=NOW()
        WHERE id=@id RETURNING id,name,category,description,phone,website,status,subscription_plan''', {
        'id': business.id, 'name': _optionalString(b, 'name'), 'category': _optionalString(b, 'category'),
        'description': _optionalString(b, 'description'), 'phone': _optionalString(b, 'phone'), 'website': _optionalString(b, 'website'),
      });
      return _HttpResult(200, {'business': rows.first});
    }
    if (path == '/business/branches' && method == Method.get) {
      final rows = await _query(s, '''SELECT id,name,address,phone,ST_Y(location::geometry) AS latitude,ST_X(location::geometry) AS longitude,is_active
        FROM branches WHERE business_id=@id ORDER BY created_at''', {'id': business.id});
      return _HttpResult(200, {'branches': rows});
    }
    if (path == '/business/branches' && method == Method.post) {
      requireManager();
      _requireText(b, 'name', 2, 120); _requireText(b, 'address', 4, 255);
      final lat = _doubleOrNull(b['latitude']); final lng = _doubleOrNull(b['longitude']);
      if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) throw const _ApiFailure(400, 'INVALID_INPUT', 'Enter a valid branch map location.');
      final rows = await _query(s, '''INSERT INTO branches(business_id,name,address,location,phone)
        VALUES(@businessId,@name,@address,ST_SetSRID(ST_MakePoint(@lng,@lat),4326)::geography,@phone)
        RETURNING id,name,address,phone,ST_Y(location::geometry) AS latitude,ST_X(location::geometry) AS longitude''', {
        'businessId': business.id, 'name': _string(b['name']).trim(), 'address': _string(b['address']).trim(),
        'lat': lat, 'lng': lng, 'phone': _string(b['phone']),
      });
      return _HttpResult(201, {'branch': rows.first});
    }
    if (path == '/business/programs' && method == Method.get) {
      final rows = await _query(s, '''SELECT p.id,p.title,p.description,p.program_type,p.reward_visits,p.reward_description,p.reward_value_cents,p.is_active,p.created_at,
        (SELECT COUNT(*)::int FROM customer_progress cp WHERE cp.program_id=p.id) AS enrolled_customers
        FROM loyalty_programs p WHERE p.business_id=@id ORDER BY p.created_at DESC''', {'id': business.id});
      return _HttpResult(200, {'programs': rows});
    }
    if (path == '/business/programs' && method == Method.post) {
      requireManager(); _requireText(b, 'title', 2, 120); _requireText(b, 'rewardDescription', 2, 180);
      final visits = _int(b['rewardVisits']); final value = _int(b['rewardValueCents']);
      if (visits < 1 || visits > 100 || value < 0 || value > 100000000) throw const _ApiFailure(400, 'INVALID_INPUT', 'Check the loyalty program details.');
      final rows = await _query(s, '''INSERT INTO loyalty_programs(business_id,title,description,program_type,reward_visits,reward_description,reward_value_cents)
        VALUES(@businessId,@title,@description,'visits',@visits,@rewardDescription,@value)
        RETURNING id,title,description,program_type,reward_visits,reward_description,reward_value_cents,is_active''', {
        'businessId': business.id, 'title': _string(b['title']).trim(), 'description': _string(b['description']),
        'visits': visits, 'rewardDescription': _string(b['rewardDescription']).trim(), 'value': value,
      });
      return _HttpResult(201, {'program': rows.first});
    }
    final programMatch = RegExp(r'^/business/programs/([0-9a-fA-F-]{36})$').firstMatch(path);
    if (programMatch != null && method == Method.patch) {
      requireManager();
      final rows = await _query(s, '''UPDATE loyalty_programs SET title=COALESCE(@title,title),description=COALESCE(@description,description),
        reward_visits=COALESCE(@visits,reward_visits),reward_description=COALESCE(@rewardDescription,reward_description),
        reward_value_cents=COALESCE(@value,reward_value_cents),is_active=COALESCE(@active,is_active),updated_at=NOW()
        WHERE id=@id AND business_id=@businessId RETURNING id,title,description,program_type,reward_visits,reward_description,reward_value_cents,is_active''', {
        'id': programMatch.group(1), 'businessId': business.id, 'title': _optionalString(b, 'title'), 'description': _optionalString(b, 'description'),
        'visits': b['rewardVisits'], 'rewardDescription': _optionalString(b, 'rewardDescription'), 'value': b['rewardValueCents'], 'active': b['isActive'],
      });
      if (rows.isEmpty) throw const _ApiFailure(404, 'NOT_FOUND', 'Program not found.');
      return _HttpResult(200, {'program': rows.first});
    }
    if (path == '/business/qr/checkin' && method == Method.post) {
      final branchId = _string(b['branchId']);
      if (branchId.isEmpty) throw const _ApiFailure(400, 'BRANCH_REQUIRED', 'Choose a branch first.');
      final branch = await _one(s, 'SELECT id FROM branches WHERE id=@branchId AND business_id=@businessId AND is_active=TRUE', {'branchId': branchId, 'businessId': business.id});
      if (branch == null) throw const _ApiFailure(404, 'BRANCH_NOT_FOUND', 'Active branch not found.');
      final token = _randomToken();
      await _exec(s, "INSERT INTO qr_tokens(token_hash,purpose,branch_id,expires_at) VALUES(@hash,'checkin',@branchId,NOW()+INTERVAL '120 seconds')", {'hash': _sha256(token), 'branchId': branchId});
      return _HttpResult(200, {'payload': 'LOYFINITY:$token', 'expiresInSeconds': 120, 'branchId': branchId});
    }
    if (path == '/business/customers' && method == Method.get) {
      requireManager();
      final rows = await _query(s, '''SELECT u.id,u.full_name,u.email,MAX(cp.last_visit_at) AS last_visit_at,
        SUM(cp.visits_count)::int AS current_progress,SUM(cp.lifetime_visits)::int AS lifetime_visits,
        CASE WHEN MAX(cp.last_visit_at)<NOW()-INTERVAL '30 days' OR MAX(cp.last_visit_at) IS NULL THEN 'inactive_30d' ELSE 'active' END AS segment
        FROM customer_progress cp JOIN loyalty_programs p ON p.id=cp.program_id JOIN users u ON u.id=cp.customer_id
        WHERE p.business_id=@id GROUP BY u.id,u.full_name,u.email ORDER BY last_visit_at DESC NULLS LAST LIMIT 200''', {'id': business.id});
      return _HttpResult(200, {'customers': rows});
    }
    if (path == '/business/analytics' && method == Method.get) {
      final daily = await _query(s, '''SELECT DATE(checked_in_at) AS day,COUNT(*)::int AS visits,COUNT(DISTINCT customer_id)::int AS customers
        FROM checkins WHERE business_id=@id AND checked_in_at>=NOW()-INTERVAL '30 days' GROUP BY DATE(checked_in_at) ORDER BY day''', {'id': business.id});
      final rewards = await _one(s, '''SELECT COUNT(*)::int AS total,COALESCE(SUM(reward_value_cents),0)::bigint AS reward_value_cents
        FROM redemptions WHERE business_id=@id AND redeemed_at>=NOW()-INTERVAL '30 days' ''', {'id': business.id});
      final inactive = await _one(s, '''SELECT COUNT(DISTINCT cp.customer_id)::int AS total FROM customer_progress cp JOIN loyalty_programs p ON p.id=cp.program_id
        WHERE p.business_id=@id AND cp.last_visit_at<NOW()-INTERVAL '30 days' ''', {'id': business.id});
      final programs = await _query(s, '''SELECT p.id,p.title,COUNT(cp.customer_id)::int AS enrolled,COALESCE(SUM(cp.lifetime_visits),0)::int AS visits
        FROM loyalty_programs p LEFT JOIN customer_progress cp ON cp.program_id=p.id WHERE p.business_id=@id
        GROUP BY p.id ORDER BY enrolled DESC LIMIT 5''', {'id': business.id});
      return _HttpResult(200, {'daily': daily, 'rewards': rewards, 'inactiveCustomers': inactive?['total'] ?? 0, 'topPrograms': programs});
    }
    if (path == '/business/campaigns' && method == Method.get) {
      requireManager();
      final rows = await _query(s, 'SELECT id,title,message,segment,status,scheduled_at,created_at FROM campaigns WHERE business_id=@id ORDER BY created_at DESC LIMIT 100', {'id': business.id});
      return _HttpResult(200, {'campaigns': rows});
    }
    if (path == '/business/campaigns' && method == Method.post) {
      requireManager(); _requireText(b, 'title', 2, 120); _requireText(b, 'message', 2, 500);
      final segment = _string(b['segment']).isEmpty ? 'inactive_30d' : _string(b['segment']);
      if (!{'all', 'inactive_30d', 'active', 'reward_ready'}.contains(segment)) throw const _ApiFailure(400, 'INVALID_INPUT', 'Select a valid campaign audience.');
      final rows = await _query(s, '''INSERT INTO campaigns(business_id,created_by,title,message,segment,status)
        VALUES(@businessId,@userId,@title,@message,@segment,'draft') RETURNING id,title,message,segment,status,created_at''', {
        'businessId': business.id, 'userId': actor.id, 'title': _string(b['title']).trim(), 'message': _string(b['message']).trim(), 'segment': segment,
      });
      return _HttpResult(201, {'campaign': rows.first, 'delivery': 'draft_only', 'note': 'Campaigns are stored as drafts until delivery services are configured.'});
    }
    if (path == '/business/subscription' && method == Method.get) {
      return _HttpResult(200, {'plan': business.plan, 'status': 'not_connected', 'checkoutEnabled': false,
        'message': 'Payment-provider credentials and merchant verification are required before live subscriptions can be sold.'});
    }
    if (path == '/business/staff' && method == Method.get) {
      requireManager();
      final rows = await _query(s, '''SELECT u.id,u.full_name,u.email,m.member_role,m.created_at FROM business_members m JOIN users u ON u.id=m.user_id
        WHERE m.business_id=@id ORDER BY m.created_at''', {'id': business.id});
      return _HttpResult(200, {'members': rows});
    }
    if (path == '/business/staff/invite' && method == Method.post) {
      requireManager();
      final email = _string(b['email']).trim().toLowerCase(); final role = _string(b['role']).isEmpty ? 'staff' : _string(b['role']);
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) || !{'manager', 'staff'}.contains(role)) throw const _ApiFailure(400, 'INVALID_INPUT', 'Enter a valid staff email and role.');
      final token = _randomToken();
      await _exec(s, '''INSERT INTO staff_invites(business_id,email,token_hash,member_role,expires_at)
        VALUES(@businessId,@email,@hash,@role,NOW()+INTERVAL '7 days')''', {'businessId': business.id, 'email': email, 'hash': _sha256(token), 'role': role});
      final delivered = await _sendEmail(email, 'Join ${business.name} on Loyfinity', '<p>You have been invited to join ${business.name} on Loyfinity.</p><p><a href="${_env('APP_BASE_URL')}/staff/join?token=$token">Accept invitation</a></p><p>This invitation expires in seven days.</p>');
      return _HttpResult(201, {'invited': true, if (_env('APP_ENV') != 'production') 'developmentInviteToken': token, 'emailDelivered': delivered});
    }
    if (path == '/business/redeem' && method == Method.post) {
      final token = _string(b['token']).replaceFirst(RegExp(r'^LOYFINITY:'), '');
      if (token.length < 30) throw const _ApiFailure(400, 'INVALID_QR', 'This reward QR code is invalid.');
      final result = await s.db.transaction((tx) async {
        final item = await _one(s, '''SELECT qt.id,qt.customer_id,qt.program_id,p.business_id,p.reward_visits,p.reward_description,p.reward_value_cents
          FROM qr_tokens qt JOIN loyalty_programs p ON p.id=qt.program_id
          WHERE qt.token_hash=@hash AND qt.purpose='redeem' AND qt.used_at IS NULL AND qt.expires_at>NOW() FOR UPDATE OF qt''', {'hash': _sha256(token)}, tx: tx);
        if (item == null || item['business_id'] != business.id) throw const _ApiFailure(400, 'INVALID_QR', 'This reward is invalid, expired or belongs to another business.');
        final progress = await _one(s, 'SELECT id,visits_count FROM customer_progress WHERE customer_id=@customerId AND program_id=@programId FOR UPDATE',
          {'customerId': item['customer_id'], 'programId': item['program_id']}, tx: tx);
        if (progress == null || _int(progress['visits_count']) < _int(item['reward_visits'])) throw const _ApiFailure(409, 'REWARD_NOT_READY', 'The customer has not reached the required reward milestone.');
        await _exec(s, 'UPDATE customer_progress SET visits_count=visits_count-@visits,updated_at=NOW() WHERE id=@id', {'visits': item['reward_visits'], 'id': progress['id']}, tx: tx);
        await _exec(s, '''INSERT INTO redemptions(customer_id,business_id,program_id,reward_description,reward_value_cents)
          VALUES(@customerId,@businessId,@programId,@description,@value)''', {'customerId': item['customer_id'], 'businessId': business.id,
          'programId': item['program_id'], 'description': item['reward_description'], 'value': item['reward_value_cents']}, tx: tx);
        await _exec(s, 'UPDATE qr_tokens SET used_at=NOW() WHERE id=@id', {'id': item['id']}, tx: tx);
        await _exec(s, '''INSERT INTO notifications(user_id,title,body,kind,data) VALUES(@userId,'Reward redeemed',@body,'reward_redeemed',@data::jsonb)''', {
          'userId': item['customer_id'], 'body': 'You redeemed ${item['reward_description']} at ${business.name}.',
          'data': jsonEncode({'businessId': business.id, 'programId': item['program_id']}),
        }, tx: tx);
        return {'redeemed': true, 'reward': item['reward_description'], 'customerId': item['customer_id']};
      });
      return _HttpResult(200, result);
    }
    return null;
  }

  Future<_HttpResult> _register(Session s, Map<String, dynamic> b) async {
    final name = _string(b['fullName']).trim(); final email = _string(b['email']).trim().toLowerCase();
    final password = _string(b['password']); final role = _string(b['role']);
    if (name.length < 2 || name.length > 100 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) || email.length > 254 ||
        password.length < 12 || password.length > 72 || !RegExp(r'[a-z]').hasMatch(password) || !RegExp(r'[A-Z]').hasMatch(password) || !RegExp(r'[0-9]').hasMatch(password) ||
        !{'customer', 'business_owner'}.contains(role)) {
      throw const _ApiFailure(400, 'INVALID_INPUT', 'Check your details. Passwords need at least 12 characters with upper-case, lower-case and a number.');
    }
    if (role == 'business_owner' && (_string(b['businessName']).trim().length < 2 || _string(b['businessCategory']).trim().length < 2)) {
      throw const _ApiFailure(400, 'BUSINESS_DETAILS_REQUIRED', 'Business name and category are required for a business account.');
    }
    final hash = BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12));
    final created = await s.db.transaction((tx) async {
      final user = await _one(s, '''INSERT INTO users(full_name,email,password_hash,role)
        VALUES(@name,@email,@passwordHash,@role::user_role) RETURNING id,full_name,email,role''',
        {'name': name, 'email': email, 'passwordHash': hash, 'role': role}, tx: tx);
      if (role == 'business_owner') {
        final business = await _one(s, '''INSERT INTO businesses(owner_id,name,category) VALUES(@ownerId,@name,@category) RETURNING id''',
          {'ownerId': user!['id'], 'name': _string(b['businessName']).trim(), 'category': _string(b['businessCategory']).trim()}, tx: tx);
        await _exec(s, "INSERT INTO business_members(business_id,user_id,member_role) VALUES(@businessId,@userId,'owner')",
          {'businessId': business!['id'], 'userId': user['id']}, tx: tx);
      }
      return user!;
    });
    final token = await _createVerification(s, created['id'].toString(), email, 'verify_email');
    return _HttpResult(201, {'requiresEmailVerification': true, 'message': 'Your account is created. Verify your email before signing in.',
      if (_env('APP_ENV') != 'production') 'developmentVerificationToken': token});
  }

  Future<_HttpResult> _verifyEmail(Session s, Map<String, dynamic> b) async {
    final token = _string(b['token']);
    if (token.length < 30 || token.length > 200) throw const _ApiFailure(400, 'INVALID_TOKEN', 'This verification link is invalid.');
    final found = await _one(s, '''UPDATE verification_tokens SET consumed_at=NOW()
      WHERE token_hash=@hash AND purpose='verify_email' AND consumed_at IS NULL AND expires_at>NOW() RETURNING user_id''', {'hash': _sha256(token)});
    if (found == null) throw const _ApiFailure(400, 'TOKEN_EXPIRED', 'This verification link has expired or was already used.');
    await _exec(s, 'UPDATE users SET email_verified=TRUE,updated_at=NOW() WHERE id=@id', {'id': found['user_id']});
    return const _HttpResult(200, {'verified': true, 'message': 'Email verified. You can sign in now.'});
  }

  Future<_HttpResult> _login(Session s, Map<String, dynamic> b) async {
    final email = _string(b['email']).trim().toLowerCase(); final password = _string(b['password']);
    if (email.isEmpty || password.isEmpty || email.length > 254 || password.length > 72) throw const _ApiFailure(400, 'INVALID_INPUT', 'Enter your email and password.');
    final user = await _one(s, '''SELECT id,full_name,email,role,password_hash,email_verified,is_active FROM users WHERE email=@email''', {'email': email});
    if (user == null || user['is_active'] != true || !BCrypt.checkpw(password, user['password_hash'].toString())) throw const _ApiFailure(401, 'INVALID_CREDENTIALS', 'Email or password is incorrect.');
    if (user['email_verified'] != true) throw const _ApiFailure(403, 'EMAIL_NOT_VERIFIED', 'Verify your email before signing in.');
    final refresh = await _issueRefresh(s, user['id'].toString());
    return _HttpResult(200, {'accessToken': _issueAccess(user['id'].toString(), user['role'].toString()), 'refreshToken': refresh,
      'user': {'id': user['id'], 'fullName': user['full_name'], 'email': user['email'], 'role': user['role']}});
  }

  Future<_HttpResult> _refresh(Session s, Map<String, dynamic> b) async {
    final raw = _string(b['refreshToken']);
    if (raw.length < 40 || raw.length > 200) throw const _ApiFailure(401, 'INVALID_REFRESH_TOKEN', 'Please sign in again.');
    final result = await s.db.transaction((tx) async {
      final user = await _one(s, '''SELECT rt.id AS token_id,rt.user_id,u.full_name,u.email,u.role,u.email_verified,u.is_active
        FROM refresh_tokens rt JOIN users u ON u.id=rt.user_id
        WHERE rt.token_hash=@hash AND rt.revoked_at IS NULL AND rt.expires_at>NOW() FOR UPDATE OF rt''', {'hash': _sha256(raw)}, tx: tx);
      if (user == null || user['is_active'] != true || user['email_verified'] != true) throw const _ApiFailure(401, 'INVALID_REFRESH_TOKEN', 'Please sign in again.');
      await _exec(s, 'UPDATE refresh_tokens SET revoked_at=NOW() WHERE id=@id', {'id': user['token_id']}, tx: tx);
      final nextRefresh = await _issueRefresh(s, user['user_id'].toString(), tx: tx);
      return {'accessToken': _issueAccess(user['user_id'].toString(), user['role'].toString()), 'refreshToken': nextRefresh,
        'user': {'id': user['user_id'], 'fullName': user['full_name'], 'email': user['email'], 'role': user['role']}};
    });
    return _HttpResult(200, result);
  }

  Future<_HttpResult> _logout(Session s, Map<String, dynamic> b) async {
    final raw = _string(b['refreshToken']);
    if (raw.isNotEmpty) await _exec(s, 'UPDATE refresh_tokens SET revoked_at=NOW() WHERE token_hash=@hash AND revoked_at IS NULL', {'hash': _sha256(raw)});
    return const _HttpResult(204, null);
  }

  Future<_HttpResult> _forgotPassword(Session s, Map<String, dynamic> b) async {
    final email = _string(b['email']).trim().toLowerCase();
    if (email.isEmpty || email.length > 254) return const _HttpResult(200, {'message': 'If the account exists, a reset link will be sent.'});
    final user = await _one(s, 'SELECT id,email FROM users WHERE email=@email AND is_active=TRUE', {'email': email});
    if (user != null) {
      final token = await _createVerification(s, user['id'].toString(), email, 'reset_password');
      return _HttpResult(200, {'message': 'If the account exists, a reset link will be sent.', if (_env('APP_ENV') != 'production') 'developmentResetToken': token});
    }
    return const _HttpResult(200, {'message': 'If the account exists, a reset link will be sent.'});
  }

  Future<_HttpResult> _resetPassword(Session s, Map<String, dynamic> b) async {
    final token = _string(b['token']); final password = _string(b['password']);
    if (token.length < 30 || token.length > 200 || password.length < 12 || password.length > 72 ||
        !RegExp(r'[a-z]').hasMatch(password) || !RegExp(r'[A-Z]').hasMatch(password) || !RegExp(r'[0-9]').hasMatch(password)) {
      throw const _ApiFailure(400, 'INVALID_INPUT', 'Use a valid reset link and a strong new password.');
    }
    final user = await s.db.transaction((tx) async {
      final found = await _one(s, '''UPDATE verification_tokens SET consumed_at=NOW()
        WHERE token_hash=@hash AND purpose='reset_password' AND consumed_at IS NULL AND expires_at>NOW() RETURNING user_id''', {'hash': _sha256(token)}, tx: tx);
      if (found == null) throw const _ApiFailure(400, 'TOKEN_EXPIRED', 'This password reset link has expired or was already used.');
      await _exec(s, 'UPDATE users SET password_hash=@hash,updated_at=NOW() WHERE id=@id',
        {'hash': BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12)), 'id': found['user_id']}, tx: tx);
      await _exec(s, 'UPDATE refresh_tokens SET revoked_at=NOW() WHERE user_id=@id AND revoked_at IS NULL', {'id': found['user_id']}, tx: tx);
      return found;
    });
    return const _HttpResult(200, {'reset': true, 'message': 'Password updated. Please sign in again.'});
  }

  Future<String> _createVerification(Session s, String userId, String email, String purpose) async {
    final token = _randomToken();
    final minutes = purpose == 'verify_email' ? 1440 : 30;
    await _exec(s, '''INSERT INTO verification_tokens(user_id,token_hash,purpose,expires_at)
      VALUES(@userId,@hash,@purpose,NOW()+(@minutes || ' minutes')::interval)''',
      {'userId': userId, 'hash': _sha256(token), 'purpose': purpose, 'minutes': minutes.toString()});
    final action = purpose == 'verify_email' ? 'verify_email' : 'reset_password';
    final link = '${_env('APP_BASE_URL')}/account/$action?token=${Uri.encodeComponent(token)}';
    await _sendEmail(email, purpose == 'verify_email' ? 'Verify your Loyfinity account' : 'Reset your Loyfinity password',
      '<div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;color:#102d46"><h1>Loyfinity</h1><p>Use this secure link to continue.</p><p><a href="$link">Continue</a></p><p>This link expires in $minutes minutes.</p></div>');
    return token;
  }

  Future<String> _issueRefresh(Session s, String userId, {Transaction? tx}) async {
    final raw = _randomToken(48);
    final days = int.tryParse(_env('REFRESH_TOKEN_DAYS')) ?? 30;
    await _exec(s, '''INSERT INTO refresh_tokens(user_id,token_hash,expires_at)
      VALUES(@userId,@hash,NOW()+(@days || ' days')::interval)''', {'userId': userId, 'hash': _sha256(raw), 'days': days.toString()}, tx: tx);
    return raw;
  }

  String _issueAccess(String userId, String role) {
    final secret = _env('JWT_ACCESS_SECRET');
    if (secret.length < 48) throw StateError('JWT_ACCESS_SECRET must have at least 48 characters.');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final header = _b64({'alg': 'HS256', 'typ': 'JWT'});
    final payload = _b64({'iss': 'loyfinity-api', 'aud': 'loyfinity-mobile', 'sub': userId, 'role': role, 'iat': now, 'exp': now + 900});
    final unsigned = '$header.$payload';
    final signature = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(unsigned));
    return '$unsigned.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
  }

  Future<_Actor> _authenticate(Session s, Request r) async {
    final header = r.headers.authorization ?? '';
    final match = RegExp(r'^Bearer\s+(.+)$', caseSensitive: false).firstMatch(header);
    if (match == null) throw const _ApiFailure(401, 'AUTH_REQUIRED', 'Please sign in to continue.');
    final parts = match.group(1)!.split('.');
    if (parts.length != 3) throw const _ApiFailure(401, 'INVALID_SESSION', 'Your session has expired. Please sign in again.');
    final unsigned = '${parts[0]}.${parts[1]}';
    final signature = Hmac(sha256, utf8.encode(_env('JWT_ACCESS_SECRET'))).convert(utf8.encode(unsigned));
    final expected = base64Url.encode(signature.bytes).replaceAll('=', '');
    if (!_constantTimeEquals(expected, parts[2])) throw const _ApiFailure(401, 'INVALID_SESSION', 'Your session has expired. Please sign in again.');
    dynamic claim;
    try { claim = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))); } catch (_) {
      throw const _ApiFailure(401, 'INVALID_SESSION', 'Your session has expired. Please sign in again.');
    }
    if (claim is! Map || claim['iss'] != 'loyfinity-api' || claim['aud'] != 'loyfinity-mobile' ||
        _int(claim['exp']) <= DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) {
      throw const _ApiFailure(401, 'INVALID_SESSION', 'Your session has expired. Please sign in again.');
    }
    final user = await _one(s, 'SELECT id,full_name,email,role,email_verified,is_active FROM users WHERE id=@id', {'id': claim['sub']});
    if (user == null || user['is_active'] != true) throw const _ApiFailure(401, 'ACCOUNT_UNAVAILABLE', 'This account is unavailable.');
    // The role is reloaded from PostgreSQL for every request; JWT role claims are never trusted.
    return _Actor(user['id'].toString(), user['full_name'].toString(), user['email'].toString(), user['role'].toString(), user['email_verified'] == true);
  }

  Future<_BusinessContext> _businessContext(Session s, String userId) async {
    final row = await _one(s, '''SELECT b.id,b.name,b.category,b.description,b.phone,b.website,b.status,b.subscription_plan,m.member_role
      FROM business_members m JOIN businesses b ON b.id=m.business_id WHERE m.user_id=@userId
      ORDER BY CASE m.member_role WHEN 'owner' THEN 0 WHEN 'manager' THEN 1 ELSE 2 END LIMIT 1''', {'userId': userId});
    if (row == null) throw const _ApiFailure(403, 'BUSINESS_REQUIRED', 'No business workspace is linked to this account.');
    return _BusinessContext(row['id'].toString(), row['name'].toString(), row['category'].toString(), row['description'].toString(),
      row['phone'].toString(), row['website'].toString(), row['status'].toString(), row['subscription_plan'].toString(), row['member_role'].toString());
  }

  Map<String, dynamic> _businessJson(_BusinessContext b) => {'id': b.id, 'name': b.name, 'category': b.category, 'description': b.description,
    'phone': b.phone, 'website': b.website, 'status': b.status, 'subscription_plan': b.plan, 'member_role': b.memberRole};
}

class _HttpResult {
  const _HttpResult(this.status, this.data);
  final int status;
  final Object? data;
}

Future<List<Map<String, dynamic>>> _query(Session s, String sql, Map<String, Object?> values, {Transaction? tx}) async {
  final result = await s.db.unsafeQuery(sql, parameters: QueryParameters.named(values), transaction: tx);
  return result.map((row) => Map<String, dynamic>.from(row.toColumnMap())).toList();
}

Future<Map<String, dynamic>?> _one(Session s, String sql, Map<String, Object?> values, {Transaction? tx}) async {
  final rows = await _query(s, sql, values, tx: tx);
  return rows.isEmpty ? null : rows.first;
}

Future<void> _exec(Session s, String sql, Map<String, Object?> values, {Transaction? tx}) async {
  await s.db.unsafeExecute(sql, parameters: QueryParameters.named(values), transaction: tx);
}

String _json(Object? value) => jsonEncode(_safe(value));
Object? _safe(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Map) return value.map((key, item) => MapEntry(key.toString(), _safe(item)));
  if (value is Iterable) return value.map(_safe).toList();
  if (value is BigInt) return value.toString();
  return value;
}

String _string(Object? value) => value?.toString() ?? '';
int _int(Object? value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
double _double(Object? value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
double? _doubleOrNull(Object? value) => value == null ? null : value is num ? value.toDouble() : double.tryParse(value.toString());
String? _optionalString(Map<String, dynamic> value, String key) => value.containsKey(key) ? _string(value[key]).trim() : null;
void _requireText(Map<String, dynamic> value, String key, int minLength, int maxLength) {
  final text = _string(value[key]).trim();
  if (text.length < minLength || text.length > maxLength) throw const _ApiFailure(400, 'INVALID_INPUT', 'Check the submitted text fields.');
}
String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();
String _randomToken([int bytes = 32]) => base64Url.encode(List<int>.generate(bytes, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
String _b64(Map<String, Object?> value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) { diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i); }
  return diff == 0;
}
String _env(String key) => Platform.environment[key] ?? '';

Future<bool> _sendEmail(String to, String subject, String html) async {
  final apiKey = _env('RESEND_API_KEY');
  final from = _env('EMAIL_FROM');
  if (apiKey.isEmpty || from.isEmpty) {
    if (_env('APP_ENV') == 'production') throw StateError('RESEND_API_KEY and EMAIL_FROM must be configured in production.');
    return false;
  }
  final response = await http.post(Uri.parse('https://api.resend.com/emails'), headers: {
    'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json',
  }, body: jsonEncode({'from': from, 'to': [to], 'subject': subject, 'html': html}));
  if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Transactional email provider rejected the request.');
  return true;
}

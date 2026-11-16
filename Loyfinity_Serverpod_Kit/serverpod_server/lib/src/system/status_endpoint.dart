import 'package:serverpod/serverpod.dart';

/// A small typed Serverpod endpoint for an authenticated protocol-level ping.
/// The mobile app currently uses the HTTP routes for the product API; this
/// endpoint also keeps the generated Serverpod client protocol non-empty.
class StatusEndpoint extends Endpoint {
  Future<String> ping(Session session) async => 'loyfinity-serverpod-ok';
}

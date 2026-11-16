import 'package:serverpod/serverpod.dart';
import 'src/generated/serverpod.dart';
import 'src/web/loyfinity_api_route.dart';

/// Serverpod entry point. The REST-compatible route is hosted by Serverpod's
/// built-in web server, so both the app and backend remain Dart-based.
Future<void> run(List<String> args) async {
  final pod = Serverpod(args);
  pod.webServer.addRoute(LoyfinityApiRoute(), '/v1/**');
  pod.webServer.addRoute(HealthRoute(), '/health');
  await pod.start();
}

class HealthRoute extends Route {
  @override
  Future<Result> handleCall(Session session, Request request) async {
    try {
      await session.db.unsafeQuery('SELECT 1');
      return Response.ok(
        body: Body.fromString('{"status":"ok","service":"loyfinity-serverpod"}', mimeType: MimeType.json),
      );
    } catch (_) {
      return Response(503, body: Body.fromString('{"status":"unavailable"}', mimeType: MimeType.json));
    }
  }
}

import 'package:dart_frog/dart_frog.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart' as shelf_cors;

/// CORS middleware for the Nexus Hub API.
Handler middleware(Handler handler) {
  return handler.use(
    fromShelfMiddleware(
      shelf_cors.corsHeaders(
        headers: {
          shelf_cors.ACCESS_CONTROL_ALLOW_ORIGIN: '*',
          shelf_cors.ACCESS_CONTROL_ALLOW_METHODS: 'GET, POST, PUT, DELETE, OPTIONS',
          shelf_cors.ACCESS_CONTROL_ALLOW_HEADERS: 'Origin, Content-Type, Accept',
        },
      ),
    ),
  );
}

import 'package:dart_frog/dart_frog.dart';

import '../middleware/cors.dart' as cors;

Handler middleware(Handler handler) => cors.middleware(handler);

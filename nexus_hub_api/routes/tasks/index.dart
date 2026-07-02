import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../lib/database.dart';
import '../../lib/models/task.dart';
import '../../lib/task_validation.dart';

Future<Response> onRequest(RequestContext context) async {
  final db = DatabaseProvider.instance;

  switch (context.request.method) {
    case HttpMethod.get:
      final status = context.request.uri.queryParameters['status'];
      final rows = db
          .select(
            '''
        SELECT * FROM tasks
        WHERE (?1 IS NULL OR status = ?1)
        ORDER BY updated_at DESC
      ''',
            [status],
          )
          .cast<Row>();
      final tasks = rows.map(Task.fromRow).map((t) => t.toJson()).toList();
      return Response.json(body: tasks);

    case HttpMethod.post:
      final body = await context.request.json() as Map<String, dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      final title = body['title'] as String? ?? '';
      final description = body['description'] as String? ?? '';
      final descriptionError = validateDescription(description);
      if (descriptionError != null) {
        return Response.json(
          statusCode: HttpStatus.badRequest,
          body: {'error': descriptionError},
        );
      }
      final tag = body['tag'] as String? ?? '';
      final priority = body['priority'] as String? ?? 'medium';
      final status = body['status'] as String? ?? 'todo';
      final dueDateRaw = body['dueDate'] as String?;
      final dueDate = dueDateRaw != null ? DateTime.parse(dueDateRaw) : null;

      db.execute(
        '''
        INSERT INTO tasks
        (title, description, tag, priority, status, due_date, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          title,
          description,
          tag,
          priority,
          status,
          dueDate?.millisecondsSinceEpoch,
          now,
          now,
        ],
      );

      final id = db.lastInsertRowId;
      return Response.json(
        statusCode: HttpStatus.created,
        body: Task(
          id: id,
          title: title,
          description: description,
          tag: tag,
          priority: priority,
          status: status,
          dueDate: dueDate,
          createdAt: DateTime.fromMillisecondsSinceEpoch(now),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        ).toJson(),
      );

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

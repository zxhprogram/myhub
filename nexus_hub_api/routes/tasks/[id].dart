import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import '../../lib/database.dart';
import '../../lib/models/task.dart';
import '../../lib/task_validation.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  final db = DatabaseProvider.instance;
  final taskId = int.tryParse(id);
  if (taskId == null) {
    return Response(statusCode: HttpStatus.badRequest);
  }

  final existing = db.select('SELECT * FROM tasks WHERE id = ?', [taskId]);
  if (existing.isEmpty) {
    return Response(statusCode: HttpStatus.notFound);
  }

  switch (context.request.method) {
    case HttpMethod.get:
      return Response.json(body: Task.fromRow(existing.first).toJson());

    case HttpMethod.put:
      final body = await context.request.json() as Map<String, dynamic>;
      final task = Task.fromRow(existing.first);
      final now = DateTime.now().millisecondsSinceEpoch;
      final title = body['title'] as String? ?? task.title;
      final description = body['description'] as String? ?? task.description;
      final descriptionError = validateDescription(description);
      if (descriptionError != null) {
        return Response.json(
          statusCode: HttpStatus.badRequest,
          body: {'error': descriptionError},
        );
      }
      final tag = body['tag'] as String? ?? task.tag;
      final priority = body['priority'] as String? ?? task.priority;
      final status = body['status'] as String? ?? task.status;
      final dueDateRaw = body['dueDate'] as String?;
      final dueDate = dueDateRaw != null
          ? DateTime.parse(dueDateRaw)
          : task.dueDate;

      db.execute(
        '''
        UPDATE tasks
        SET title = ?, description = ?, tag = ?, priority = ?, status = ?,
            due_date = ?, updated_at = ?
        WHERE id = ?
      ''',
        [
          title,
          description,
          tag,
          priority,
          status,
          dueDate?.millisecondsSinceEpoch,
          now,
          taskId,
        ],
      );

      return Response.json(
        body: task
            .copyWith(
              title: title,
              description: description,
              tag: tag,
              priority: priority,
              status: status,
              dueDate: dueDate,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
            )
            .toJson(),
      );

    case HttpMethod.delete:
      db.execute('DELETE FROM tasks WHERE id = ?', [taskId]);
      return Response(statusCode: HttpStatus.noContent);

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

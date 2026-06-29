# Nexus Hub API

A Dart Frog REST API for the Nexus Hub application.

## Prerequisites

- Dart SDK 3.x
- `dart_frog_cli` globally activated:

```powershell
dart pub global activate dart_frog_cli
```

## Run locally

```powershell
cd nexus_hub_api
dart_frog dev
```

The API is available at `http://localhost:8080`.

## Production build

```powershell
dart_frog build
dart build\bin\server.dart
```

## Routes

- `GET/POST /bookmarks`
- `GET/PUT/DELETE /bookmarks/<id>`
- `GET/POST /tasks`
- `GET/PUT/DELETE /tasks/<id>`
- `GET/POST/DELETE /clipboard`
- `GET/POST /rss`

## Tests

```powershell
dart test
```

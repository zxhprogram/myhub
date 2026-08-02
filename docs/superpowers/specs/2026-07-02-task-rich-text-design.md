# Task Rich Text & Detail View Design

## Overview

Enhance the existing task management system so users can create tasks with rich text descriptions and view task details in a dedicated side panel.

## User Decisions

- **Detail view interaction**: Right-side drawer panel that slides in over the Kanban board.
- **Rich text editor**: `flutter_quill` package with built-in toolbar.
- **Edit mode**: Read-first, then edit. The detail panel opens in read-only mode and a toggle switches to the Quill editor.

## Goals

- Support basic formatting in task descriptions: bold, italic, underline, ordered lists, unordered lists, and hyperlinks.
- Provide a smooth, non-blocking detail view that keeps board context visible.
- Prevent malicious content injection through input validation and controlled rendering.
- Maintain responsive behavior on desktop and mobile.
- Preserve existing design system colors, typography, and spacing.

## Non-Goals

- Full page-based navigation for task details.
- Collaborative real-time editing.
- Media embeds (images, files) in task descriptions.
- Markdown syntax support.

## Architecture

### Frontend

```
TasksPage
├── Kanban board (existing)
│   └── TaskCard (now tappable)
└── TaskDetailPanel (new, right-side drawer)
    ├── ReadMode (new)
    │   └── QuillReadOnly (new)
    └── EditMode (new)
        └── NexusRichTextEditor (new)
            └── QuillEditor + QuillToolbar
```

### Backend

No new tables required. The existing `tasks.description` column stores the serialized rich text payload. The backend validates and sanitizes the payload before persistence.

## Data Format

- Store rich text as **Quill Delta JSON** serialized to a string.
- `TaskModel.description` remains a `String`, but its content is JSON.
- Example payload:
  ```json
  {
    "ops": [
      {"insert": "Review "},
      {"insert": "design mockups", "attributes": {"bold": true}},
      {"insert": "\n"}
    ]
  }
  ```
- Backend treats `description` as opaque text with maximum length and structural validation.

## Components

### `NexusRichTextEditor`

- Wraps `QuillEditor` and `QuillToolbar`.
- Toolbar includes: bold, italic, underline, bullet list, ordered list, link.
- Uses `NexusColors` and `NexusTypography` for consistent styling.
- Exposes `controller` (or accepts initial Delta / onChanged callback).

### `TaskDetailPanel`

- Slides in from the right with a `SlideTransition` or `AnimatedContainer`.
- Width: 420 px on desktop, full-screen width on mobile.
- Contains:
  - Header with title, close button, and edit/save/cancel actions.
  - Tag, priority, due date, and status display.
  - Read-only description renderer (`QuillReadOnly`).
  - Editable description (`NexusRichTextEditor`) when in edit mode.
- Loading overlay during save.
- Error messages shown via SnackBar from `TasksState`.

### `QuillReadOnly`

- Renders Delta JSON without editing controls.
- Uses `QuillEditor` with `readOnly: true` and `showCursor: false`.

## Interaction Flow

1. User taps a task card in the Kanban column.
2. `TasksState.selectedTask` is set; the detail panel slides in.
3. Panel displays task metadata and rendered description.
4. User taps **Edit**:
   - Title becomes editable.
   - Description switches to `NexusRichTextEditor` with the current Delta.
   - Toolbar appears.
5. User taps **Save**:
   - Panel shows loading state.
   - `TasksState.update()` persists changes locally and to the API.
   - On success, panel returns to read mode with updated content.
6. User taps **Close** or presses **Escape** / swipes on mobile:
   - Panel slides out and `selectedTask` is cleared.

## State Changes

Add to `TasksState`:

- `selectedTask` signal: tracks the currently viewed task.
- `updateTask(TaskModel task)` method: optimistic local update followed by API persistence.

## Backend Changes

### `Task` model

No field changes. `description` continues to be a `String`.

### API routes

- `POST /tasks` and `PUT /tasks/:id`:
  - Validate `description` length (max 10000 characters).
  - Optionally verify that the string is valid JSON if it appears to be a Delta payload.
  - Strip or escape any embedded HTML to prevent injection.

### Database

No schema migration required. Existing `description TEXT NOT NULL` is sufficient.

## Responsive Design

- Desktop: panel width 420 px, board remains visible on the left.
- Tablet: panel width 60 % of screen.
- Mobile: panel is full width; supports drag-to-dismiss from the right edge.

## Animations

- Panel slide-in: 250 ms, `Curves.easeOutCubic`.
- Mode transition between read and edit: 150 ms cross-fade.
- Task card tap: subtle scale/ripple feedback.

## Accessibility

- Task cards are focusable and activatable with Enter / Space.
- Panel close button has an accessible label.
- ESC closes the panel.
- Toolbar buttons have tooltips and keyboard shortcuts where provided by Quill.

## Error Handling

- API failure during save reverts optimistic update and shows SnackBar.
- Invalid Delta JSON falls back to plain text rendering.
- Loading states prevent duplicate submissions.

## Security

- Rich text is stored as Delta JSON, not HTML, limiting injection vectors.
- Backend validates JSON structure and length.
- Renderer uses Quill's built-in document parsing, which ignores unknown attributes.
- User-provided link URLs are rendered as plain links without script execution.

## Testing

- Unit tests:
  - `TaskModel` serializes and deserializes Delta JSON.
  - `NexusRichTextEditor` controller initialization.
- Widget tests:
  - Tapping a task card opens the detail panel.
  - Edit/save toggles between read and edit modes.
  - Saving updates the task list.
- Integration tests:
  - Create a task with rich text, verify persistence and rendering round-trip.

## Dependencies

- `flutter_quill: ^9.0.0` — rich text editor and Delta support.

## Open Questions

None. All major design decisions have been confirmed with the user.

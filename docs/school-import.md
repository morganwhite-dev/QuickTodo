# Importing a school plan

You can load a list of assignments, tests, and labs into QuickToDo from a JSON file. This saves you from typing each one. You can write the file by hand or with any tool you like.

[Back to the README](../README.md)

## What you get

Every task in the file becomes a QuickToDo task. Each course becomes its own list. QuickToDo shows you a preview first. Nothing is added until you approve it.

## The file format

The file must be a JSON array. Each item in the array is one task.

### The sample

This is the sample in [samples/sample-school-plan.json](../samples/sample-school-plan.json), shortened to two items:

```json
[
  {
    "course": "Cloud Computing",
    "title": "Test 3 Cloud data security",
    "dueDate": "2026-11-03",
    "dueTime": "17:30"
  },
  {
    "course": "Network Security",
    "title": "Week 3 Discussion",
    "dueDate": "2026-11-04",
    "dueTime": "23:59"
  }
]
```

### Fields

Only `title` is required. Every other field is optional.

| Field | Required | Format | What it does |
|-------|----------|--------|--------------|
| `title` | Yes | Text | The task name |
| `course` | No | Text | The list the task goes in. Without it, the task goes in a list named School |
| `dueDate` | No | `YYYY-MM-DD` | The due date |
| `dueTime` | No | `HH:mm` (24 hour) | The due time. Without it, the time is set to noon |
| `module` | No | Text | Added to the task's notes as `Module: ...` |
| `type` | No | Text | Shown as a label in the preview |
| `priority` | No | `high`, `medium`, or `low` | The task priority. Anything else becomes medium |
| `materialsNeeded` | No | List of text | Added to the task's notes as a bullet list |
| `notes` | No | Text | Added to the task's notes |

### Example with every field

```json
[
  {
    "title": "Read chapters 5 and 6",
    "course": "Psychology",
    "module": "Week 4",
    "type": "Reading",
    "priority": "high",
    "dueDate": "2026-11-10",
    "dueTime": "09:00",
    "materialsNeeded": ["Textbook", "Highlighter"],
    "notes": "Focus on the case studies."
  }
]
```

### Tasks with a missing or bad date

If `dueDate` is missing, blank, the words "Needs review", or not in `YYYY-MM-DD` form, QuickToDo still imports the task. It adds `(Needs Review)` to the title and a note that explains the problem. The preview warns you about these tasks. A task with no due date lands in General.

## How to import

1. Open Settings. Use the menu QuickToDo, then Settings, or press Command and comma.
2. Find the **Import School Plan** card.
3. Click **Choose File** and pick your JSON file.
4. Read the preview. Each row shows the title, course, due date, and any warning.
5. If you want to skip some tasks, click **Select**, then uncheck the ones to leave out.
6. Click **Approve & Import**.

### Duplicates

If a task with the same title, list, and due day already exists, QuickToDo marks it as already there. It leaves it unchecked so it isn't added twice. You can check it again if you do want a copy.

### Where tasks start

An imported task starts on the Decision Board. If it's overdue or due within 7 days, it starts in Ready. If it's due later, it starts in Scheduled. With no date, it starts in Capture. You can move it after that.

## Common problems

- **"That file isn't a valid school plan JSON file."** The file must be an array in square brackets, with each task in curly braces. Check for a missing comma or quote.
- **"That file doesn't contain any tasks."** The array is empty.
- **Dates show "Needs review".** Write dates as `2026-11-03`, with the year first.

## Calendar import (planned)

I plan to add an import to calendar feature. It would bring your due dates and your calendar into one view. It is not available yet, so for now use the JSON import above.

## Try it

Import [samples/sample-school-plan.json](../samples/sample-school-plan.json). It has 7 tasks in two courses.

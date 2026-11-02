# Samples

This folder holds an example file you can import into QuickToDo.

## sample-school-plan.json

A small school plan with 7 tasks across two courses: Cloud Computing and Network Security. It has tests, labs, a discussion, and an exam.

Each item uses four fields:

| Field | Example | Meaning |
|-------|---------|---------|
| `course` | `Cloud Computing` | The list the task goes in |
| `title` | `Mid-Term Test` | The task name. This is the only required field |
| `dueDate` | `2026-11-06` | The due date, as `YYYY-MM-DD` |
| `dueTime` | `18:30` | The due time, as `HH:mm` on a 24 hour clock |

The dates in the sample are in November 2026. QuickToDo still imports tasks whose dates have passed. They show up as overdue.

## How to import it

1. Open QuickToDo and go to Settings.
2. Find **Import School Plan**.
3. Click **Choose File** and pick `sample-school-plan.json`.
4. Review the preview, then click **Approve & Import**.

You'll get two new lists, one per course. A calendar import is planned for a later version. It is not built yet.

The full format, including the optional fields, is in [docs/school-import.md](../docs/school-import.md).

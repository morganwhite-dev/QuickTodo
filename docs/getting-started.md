# Getting started

This guide takes you from nothing to a running QuickToDo and your first tasks. It assumes you have never used Xcode.

[Back to the README](../README.md)

## What you need

- A Mac running macOS 26.0 or later.
- Xcode. The project was created with Xcode 27.0, so use that version or newer.
- Free space for Xcode. It's a large download.

## Build and run

1. Open the Mac App Store. Search for Xcode and install it.
2. Open Xcode once. Accept the license and let it finish installing extras.
3. Download this project from GitHub. Click **Code**, then **Download ZIP**. Unzip it.
4. Open the unzipped folder, then the `QuickToDo` folder inside it.
5. Double click `QuickToDo.xcodeproj`.
6. At the top of the window, pick the `QuickTodo` scheme and **My Mac** as the destination. The scheme is spelled `QuickTodo` in the project.
7. Press the **Run** button (the play triangle), or press Command and R.
8. Wait for the build. QuickToDo opens when it's done.

### If something goes wrong

- **A signing error appears.** Click the project name in the left sidebar. Open **Signing & Capabilities**. Choose your own Apple ID as the Team, or choose to sign the app to run locally.
- **Xcode says your macOS is not new enough.** QuickToDo needs macOS 26.0 or later.
- **The build fails right away.** Make sure you opened `QuickToDo.xcodeproj` and not a folder.

## What you see on first launch

A welcome tour opens. It has a few pages about capture, the Decision Board, and Next Move. Swipe or click through it. You can replay it later in Settings with **Replay Welcome**.

Running from Xcode builds a debug version. On its first launch, that version adds example tasks so the screens aren't empty. To remove them, open Settings and use **Clear Everything**. That deletes every task and list, so only do it on a fresh install.

## Add your first task

1. Click **+ Capture** in the top bar.
2. Type: `read chapter 3 tomorrow 7pm #School !medium`
3. Press Return.

Command and N opens the Detailed Task form instead. Use it when you want notes, reminders, or exact settings.

QuickToDo reads your words. It sets the due date to tomorrow at 7 PM, files the task in a list named School, and sets the priority to medium. If the School list doesn't exist yet, QuickToDo creates it.

The words you can use:

| You type | What happens |
|----------|--------------|
| `today`, `tomorrow`, `friday`, `june 15` | Sets the due date |
| `2pm`, `in 10 minutes` | Sets the time |
| `#Work` | Files the task in the Work list, and creates the list if needed |
| `!high`, `!medium`, `!low` | Sets the priority |

## Find your way around

The top bar has these tabs:

- **Decision Board.** Your main screen.
- **General.** Tasks with no due date.
- **Today.** What's overdue or due later today.
- **Upcoming.** The next seven days.
- **Lists.** Tasks grouped by list.
- **Completed.** Finished tasks.

The gear icon at the top right opens Trash and Settings.

## Capture from anywhere

- **Shortcut.** Press Control, Option, Command and Space in any app. A Quick Add window opens.
- **Menu bar.** Click the QuickToDo icon in the menu bar and type in the field.

## Next steps

- Build a routine with the [daily workflow guide](daily-workflow.md).
- Import assignments with the [school import guide](school-import.md).
- Learn the keys in [keyboard shortcuts](keyboard-shortcuts.md).

I plan to add an import to calendar feature in the future. It is not built yet.

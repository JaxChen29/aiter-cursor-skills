---
name: daily-report
description: Daily work report and task pool management. Use when the user says "daily report", "end of day", "standup", "what did I do today", "update my report", "update tasks", or at the start of a workday session to check if today's entry exists. Reminds the user to fill in their daily report on workdays (Mon-Fri).
---

# Daily Report and Task Pool

## Workday Reminder

When the user starts a session on a workday (Monday-Friday), check if today's daily report
entry exists. If not, remind the user:

1. Determine today's date and day of week
2. Calculate the ISO week number: `date +%G-W%V`
3. Check if `reports/YYYY-WNN.md` exists for the current week
4. If the file exists, check if it contains a section header `## YYYY-MM-DD`
5. If today's entry is missing, remind the user:
   "You haven't filled in today's daily report yet. Say 'daily report' when you're ready."

Skip reminders on Saturday and Sunday.

## Daily Report Workflow

When the user asks to fill in their daily report:

### Step 1: Determine file paths

```bash
YEAR_WEEK=$(date +%G-W%V)
TODAY=$(date +%Y-%m-%d)
DAY_NAME=$(date +%A)
REPORT_DIR="<repo_root>/reports"
REPORT_FILE="$REPORT_DIR/$YEAR_WEEK.md"
TASKS_FILE="<repo_root>/tasks.md"
```

Where `<repo_root>` is the path to the `aiter-cursor-skills` repo.

### Step 2: Create week file if needed

If the weekly report file doesn't exist, create it with:

```markdown
# Week NN (Mon_date - Fri_date, YYYY)
```

### Step 3: Ask the user

Ask the user these questions (use AskQuestion if available, otherwise ask conversationally):

1. **What did you work on today?** (Progress -- main tasks, meetings, reviews)
2. **Any problems or blockers?** (Problems -- things that slowed you down)
3. **Any achievements or milestones?** (Achievements -- things completed, tests passing)
4. **Tasks to update?** (mark done, add new, carry over)

### Step 4: Write the daily entry

Add a new section to the weekly report file with today's date. Insert it at the
top (after the week title), so the most recent day is first.

```markdown
---

## YYYY-MM-DD (DayName)

### Progress
- [items from user's answer]

### Problems
- [items from user's answer, or "None" if clear]

### Achievements
- [items from user's answer]

### Tasks Updated
- [x] completed tasks
- [ ] new or carried-over tasks
```

### Step 5: Update tasks.md

Based on the user's task updates:
- Move completed tasks from **Active** to **Completed (recent)**, add completion date
- Add new tasks to **Active** with today's date
- Keep uncompleted active tasks as-is (they carry over automatically)

### Step 6: Confirm

Tell the user what was written and where:
- "Updated `reports/YYYY-WNN.md` with today's entry"
- "Updated `tasks.md`: N tasks completed, M new tasks added"

## End-of-Week Summary

On Friday (or when the user asks for a weekly summary), read all entries from the
current week's report and generate:

1. **Week highlights** -- top 3-5 achievements across the week
2. **Unresolved problems** -- any blockers that persisted
3. **Task progress** -- how many tasks completed vs added vs carried over
4. **Next week outlook** -- active tasks remaining + backlog priorities

## Task Pool Format

`tasks.md` uses this structure:

```markdown
# Task Pool

## Active
- [ ] [YYYY-MM-DD] task description
- [x] [YYYY-MM-DD] completed task -- completed YYYY-MM-DD

## Backlog
- [ ] task description (no date, lower priority)

## Completed (recent)
- [x] [YYYY-MM-DD] task description -- completed YYYY-MM-DD
```

Rules:
- **Active**: tasks currently being worked on, with start date
- **Backlog**: future tasks, no urgency
- **Completed**: keep last ~2 weeks, archive older entries
- When a task is completed, move it from Active to Completed with completion date
- When promoting from Backlog to Active, add today's date

## Report File Naming

| Period | File path | Example |
|--------|-----------|---------|
| Week 10 of 2026 | `reports/2026-W10.md` | Mar 2-6, 2026 |
| Week 11 of 2026 | `reports/2026-W11.md` | Mar 9-13, 2026 |

Use `date +%G-W%V` to get the current ISO week.

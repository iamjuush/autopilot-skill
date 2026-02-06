---
description: Automated end-to-end loop - pick ticket, brainstorm, plan, implement, test, review
---

# Autopilot - End-to-End Ticket Processing

Automated loop: select highest-priority ticket → brainstorm design → plan → implement → verify build → submit for review.

## Prerequisites

A **"Brainstorm"** workflow state must exist in your Linear team's board settings. After creating it, update `BRAINSTORM` below.

## Constants

> **CONFIGURE THESE FOR YOUR PROJECT**

```
TEAM_ID          = <YOUR_TEAM_ID>
PROJECT_ID       = <YOUR_PROJECT_ID>

# Workflow State IDs
BACKLOG          = <YOUR_BACKLOG_STATE_ID>
TODO             = <YOUR_TODO_STATE_ID>
BRAINSTORM       = <YOUR_BRAINSTORM_STATE_ID>
IN_PROGRESS      = <YOUR_IN_PROGRESS_STATE_ID>
IN_REVIEW        = <YOUR_IN_REVIEW_STATE_ID>
BLOCKED          = <YOUR_BLOCKED_STATE_ID>
DONE             = <YOUR_DONE_STATE_ID>

# Labels (optional - remove if not using)
NEEDS_INVESTIGATION = <YOUR_LABEL_ID>
BUG              = <YOUR_LABEL_ID>
FEATURE          = <YOUR_LABEL_ID>

# User (for auto-assignment)
DEFAULT_ASSIGNEE = <YOUR_USER_ID>
```

---

## Phase 1: Ticket Selection

### If a ticket identifier is provided (e.g. `XXX-123`):

1. Fetch the ticket with `mcp__linear-server__get_issue`
2. Read all comments with `mcp__linear-server__list_comments`
3. Check the ticket's current state:
   - If **Brainstorm** → go to Phase 2 Resume
   - If **In Progress** → go to Phase 3
   - If **Todo** or **Backlog** → go to Phase 2 Fresh
   - If **In Review** → go to Phase 7 (Handle Review Feedback)
   - If **Done** → inform user, stop

### If no ticket is provided:

1. **Check In Review column first** - fetch tickets in **In Review** state:
   ```
   mcp__linear-server__list_issues with:
     team: "<YOUR_TEAM_NAME>"
     state: IN_REVIEW
     limit: 10
   ```
   For each In Review ticket, fetch its comments. Look for the `## Implementation Complete` comment (posted by autopilot in Phase 6). If there are **new comments after** that comment, this ticket has review feedback → select it and go to **Phase 7**.

2. **Check Brainstorm column next** - fetch tickets in **Brainstorm** state:
   ```
   mcp__linear-server__list_issues with:
     team: "<YOUR_TEAM_NAME>"
     state: BRAINSTORM_STATE_ID
     limit: 10
   ```
   For each Brainstorm ticket, fetch its comments and check if all `INPUT NEEDED` items and open questions have been answered. If any ticket has all answers → select it and go to **Phase 2 Resume**.

3. **If nothing ready above**, fetch from **Todo**:
   ```
   mcp__linear-server__list_issues with:
     team: "<YOUR_TEAM_NAME>"
     state: "Todo"
     limit: 10
     orderBy: "updatedAt"
   ```

4. Select the highest-priority ticket. If multiple share the same priority, prefer tickets **without** a `parentId` (parent tickets before sub-tasks). If all are sub-tasks, pick the first one.

5. Show the selected ticket to the user:
   ```
   Selected: XXX-123 - [title] (Priority: [priority])
   Source: [In Review (feedback) | Brainstorm (answers ready) | Todo (new)]
   Proceeding...
   ```

6. Assign to DEFAULT_ASSIGNEE if unassigned.

---

## Phase 2: Brainstorm Design

**REQUIRED SKILL:** Invoke `superpowers:brainstorming` before starting this phase. Follow its process for understanding the idea and exploring approaches, but with the modifications below for batch output instead of interactive Q&A.

### Fresh (ticket has no brainstorm comment yet):

1. **Move ticket** to Brainstorm state using `mcp__linear-server__update_issue`

2. **Gather context using the brainstorming skill's understanding phase:**
   - Check current project state (files, docs, recent commits) as the skill directs
   - Spawn parallel research agents:
     - `codebase-locator` to find files relevant to the ticket's domain
     - `codebase-analyzer` to understand current implementation patterns
   - Read the ticket description, any linked design docs, and parent ticket if it's a sub-task
   - Propose 2-3 approaches with trade-offs as the brainstorming skill requires

3. **Generate brainstorm analysis** - instead of the brainstorming skill's normal interactive one-question-at-a-time flow, produce a **single structured document** covering ALL sections at once. Each section that needs user input should end with a clearly marked `**INPUT NEEDED:**` prompt.

   ```markdown
   ## Brainstorm: XXX-123 - [Title]

   ### 1. Problem Understanding
   [Your understanding of what this ticket solves and why it matters]

   ### 2. Proposed Approach
   [Recommended technical approach with rationale]
   **Alternative:** [Brief alternative approach and why it's less preferred]

   ### 3. Architecture & Data Model
   [DB changes, new fields, migrations needed]
   **INPUT NEEDED:** [Any data model questions, e.g. "Should X be nullable or have a default?"]

   ### 4. UI/UX Design
   [Screen layout, components, interaction flow]
   **INPUT NEEDED:** [Any design questions, e.g. "Picker vs free-text for field X?"]

   ### 5. Edge Cases & Validation
   [Boundary conditions, error states, what happens when...]

   ### 6. Impact on Existing Features
   [What existing screens/flows are affected, backward compatibility]

   ### 7. Open Questions
   [Numbered list of ALL remaining questions that block implementation]
   1. ...
   2. ...
   ```

4. **Post to ticket** - add the brainstorm analysis as a comment using `mcp__linear-server__create_comment`

5. **Decision point:**
   - If there are **zero** `INPUT NEEDED` items and **zero** open questions → proceed directly to Phase 3
   - If there are any questions → **STOP** and tell the user:
     ```
     Brainstorm posted to XXX-123 with [N] questions needing your input.

     Please answer in the ticket comments, then re-run:
       /autopilot XXX-123

     View ticket: [ticket URL]
     ```

### Resume (ticket is in Brainstorm state, brainstorm comment exists):

1. Fetch all comments with `mcp__linear-server__list_comments`
2. Find the brainstorm comment (starts with `## Brainstorm:`)
3. Look for reply comments posted **after** the brainstorm comment
4. Check if all `INPUT NEEDED` items and open questions have answers:
   - If **yes** → proceed to Phase 3
   - If **no** → list which questions are still unanswered, **STOP**:
     ```
     Still waiting on answers for:
     - Question 3: [question text]
     - Question 5: [question text]

     Please answer in the ticket comments, then re-run:
       /autopilot XXX-123
     ```

---

## Phase 3: Write Implementation Plan

1. **Move ticket** to In Progress state

2. **Synthesize design** - combine the brainstorm analysis + user answers into a clear design spec

3. **Invoke superpowers:writing-plans** to create a detailed implementation plan:
   - Save to `docs/plans/YYYY-MM-DD-XXX-123-description.md`
   - Plan must include:
     - Bite-sized tasks (one concern per task)
     - Explicit file paths and code snippets
     - DB migration SQL if needed
     - Verification commands per task
   - Commit the plan document to git

4. **Post plan link** as a comment on the ticket:
   ```
   Implementation plan created: `docs/plans/YYYY-MM-DD-XXX-123-description.md`
   [N] tasks across [M] phases. Proceeding to implement.
   ```

---

## Phase 4: Implement

1. **Invoke superpowers:subagent-driven-development** to execute the plan:
   - Fresh subagent per task
   - Two-stage review (spec compliance → code quality)
   - Each task committed individually with message format: `feat: description (XXX-123)`

2. **After all tasks complete**, run full verification:
   - TypeScript: `npx tsc --noEmit`
   - Lint: `npm run lint` (if configured)

---

## Phase 5: Verify Build

**HARD GATE** - the app MUST build successfully before proceeding to Phase 6. You CANNOT move to the next ticket or submit for review if the app does not build. This is non-negotiable.

1. **Run your project's build check:**
   ```
   npx tsc --noEmit
   ```
   > **CUSTOMIZE:** Replace with your project's build verification command

2. If the build check fails:
   - Read the error output
   - Use superpowers:systematic-debugging to diagnose
   - Fix and retry
   - **Keep retrying until the build succeeds.** There is no retry limit — you must fix the build.
   - If you are truly stuck (e.g. environment issue outside your control), **revert all changes** that caused the build to break using `git stash` or `git checkout`, move the ticket to **Blocked**, add the **Needs Investigation** label, post a comment with the build error details, and exit.
   - **NEVER proceed to Phase 6 with a broken build.**

---

## Phase 5.5: Commit All Work

**Before submitting for review, ensure ALL changes are committed.**

1. Run `git status` to check for any uncommitted or untracked files
2. Stage and commit any remaining changes:
   - Use descriptive commit messages with ticket reference: `feat: description (XXX-123)`
   - Do NOT leave uncommitted work — every file change must be in a commit
3. Verify with `git status` that the working tree is clean (nothing unstaged, nothing untracked except ignored files)
4. If there are uncommitted changes that shouldn't be committed (temporary files, debug logs), remove them

---

## Phase 6: Submit for Review

1. **Move ticket** to In Review state using `mcp__linear-server__update_issue`

2. **Post summary comment** on the ticket:
   ```markdown
   ## Implementation Complete

   **Plan:** `docs/plans/YYYY-MM-DD-XXX-123-description.md`
   **Branch:** [current branch name]
   **Commits:** [number] commits

   ### Changes
   - [Bullet summary of what was implemented]

   ### Testing
   - Build check: [Pass/Fail]

   ### Ready for Review
   Please review and leave feedback. If changes needed, comment here and re-assign.
   ```

3. **Print final message and EXIT the session immediately** (do not wait for further input):
   ```
   XXX-123 moved to In Review.

   View ticket: [ticket URL]

   Exiting. The wrapper script will restart for the next ticket.
   ```
   Then exit. The outer `autopilot.sh` loop will restart Claude for the next cycle.

---

## Phase 7: Handle Review Feedback

Triggered when a ticket in **In Review** has new comments after the `## Implementation Complete` comment.

1. **Read all comments** and extract the review feedback (comments after `## Implementation Complete`)

2. **Analyze the feedback** and classify it:

   - **Approval (no changes needed):** Reviewer says it looks good, approved, LGTM, etc.
   - **Minor rework:** Small fixes, tweaks, style changes that can be done in-place
   - **Major rework / new scope:** Feedback that introduces significant new requirements or a different direction
   - **Cannot reproduce / needs more info:** Feedback describes behavior you can't recreate, references unclear scenarios, or reports discrepancies between what was implemented and what the reviewer is seeing

3. **Based on classification:**

   ### Approval → Acknowledge and leave in review
   - Post comment: `Approval acknowledged. Leaving in In Review for human to move to Done.`
   - **Do NOT move the ticket to Done** — only a human can do that
   - Exit session

   ### Minor rework → Fix in-place
   - Move ticket back to **In Progress**
   - Post comment acknowledging the feedback and listing what will be changed
   - Make the fixes directly (no need to re-plan for small changes)
   - Run verification
   - **Re-verify build (Phase 5 — same hard gate applies, build MUST pass)**
   - **Commit all changes (Phase 5.5 — working tree must be clean)**
   - Move back to **In Review** with a new summary comment:
     ```markdown
     ## Rework Complete

     **Feedback addressed:**
     - [What was changed in response to each feedback point]

     **Verification:**
     - Build check: [Pass/Fail]

     Ready for re-review.
     ```
   - Exit session

   ### Major rework / new scope → Create follow-up ticket
   - Post comment on the current ticket explaining that the feedback requires significant new work
   - **Leave ticket in In Review** — only a human can move it to Done
   - Create a **new ticket** using `mcp__linear-server__create_issue`:
     ```
     Title: "[Follow-up] XXX-123: [description of new scope]"
     Description: Summary of the review feedback + what needs to change
     parentId: same parent as original if it was a sub-task
     priority: same as original
     ```
     Include a link back to the original ticket in the description.
   - Post the new ticket link as a comment on the original ticket
   - Exit session (the new ticket will be picked up in a future cycle from Todo)

   ### Cannot reproduce / needs more info → Block the ticket
   When the review feedback describes behavior you cannot verify, reports discrepancies between expected and actual behavior, or you need more information to understand the issue:
   - Move ticket to **Blocked** state
   - Add the **Needs Investigation** label (`NEEDS_INVESTIGATION` label ID)
   - Post comment explaining what was attempted and what couldn't be verified:
     ```markdown
     ## Blocked: Needs Investigation

     **What was reported:**
     - [Summary of the reviewer's feedback]

     **What was attempted:**
     - [Steps taken to reproduce or verify]

     **Why it's blocked:**
     - [What information is missing or what couldn't be recreated]

     **To unblock, please provide:**
     - [Specific information or steps needed]
     ```
   - Exit session

---

## Exit Behavior

Claude **must exit the session** after any of these terminal states:
- Phase 6 complete (ticket moved to In Review)
- Phase 7 complete (approved → acknowledged, rework → In Review, follow-up created, or blocked)
- Phase 2 stopped (brainstorm questions posted, waiting for user input)
- No tickets available in In Review, Brainstorm, or Todo
- Unrecoverable error after max retries

**When there is nothing to do** (no tickets in any actionable state), output exactly:
```
AUTOPILOT_IDLE: No tickets to process.
```
This marker tells the wrapper script to wait longer (1 hour) before the next cycle, since checking every 30 seconds would be wasteful.

The wrapper script `scripts/autopilot.sh` handles restarting.

---

## Error Handling

- **Linear MCP unavailable:** Stop immediately, tell user to check MCP server configuration
- **No tickets in Todo:** Output `AUTOPILOT_IDLE: No tickets to process.` and exit
- **Brainstorm state missing:** If the Brainstorm state ID is not configured, stop and remind user to create it in Linear and update this file
- **Build failures:** Debug up to 3 times, then stop with error details
- **Subagent failures:** Report which task failed and why, don't skip tasks

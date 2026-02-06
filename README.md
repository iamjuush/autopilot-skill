# Autopilot Skill Package

An automated end-to-end ticket processing loop for Claude Code. Picks tickets from Linear, brainstorms designs, creates implementation plans, implements, verifies, and submits for review.

## What's Included

```
autopilot-package/
├── README.md                    # This file
├── .claude/
│   └── commands/
│       └── autopilot.md         # The skill definition
└── scripts/
    └── autopilot.sh             # Continuous loop wrapper
```

## Prerequisites

### 1. Superpowers Plugin (Required)

Autopilot uses skills from the superpowers plugin. Install it via the Claude Code marketplace:

```bash
# In Claude Code
/plugins install superpowers
```

Or manually from: https://github.com/anthropics/superpowers

### 2. Linear MCP Server (Required)

Autopilot uses Linear for ticket management. Add the Linear MCP server to your Claude Code settings:

```json
{
  "mcpServers": {
    "linear-server": {
      "command": "npx",
      "args": ["-y", "@anthropic/linear-mcp-server"],
      "env": {
        "LINEAR_API_KEY": "your-linear-api-key"
      }
    }
  }
}
```

Get your Linear API key from: Settings → API → Personal API keys

### 3. Linear Workflow States

You need two custom workflow states in your Linear team. Create them in:
Linear → Team Settings → Workflow → Add State

1. **Brainstorm** - Used when autopilot is gathering design input before implementation
2. **Blocked** - Used when autopilot can't reproduce an issue or needs more information

## Installation

1. Copy `.claude/commands/autopilot.md` to your project's `.claude/commands/` directory
2. Copy `scripts/autopilot.sh` to your project's `scripts/` directory
3. Make the script executable: `chmod +x scripts/autopilot.sh`

## Configuration

**Edit `.claude/commands/autopilot.md`** and update the Constants section with your IDs:

```markdown
## Constants

TEAM_ID          = <your-linear-team-id>
PROJECT_ID       = <your-linear-project-id>

# Workflow State IDs (get from Linear API or browser dev tools)
BACKLOG          = <backlog-state-id>
TODO             = <todo-state-id>
BRAINSTORM       = <brainstorm-state-id>  # Create this state!
IN_PROGRESS      = <in-progress-state-id>
IN_REVIEW        = <in-review-state-id>
BLOCKED          = <blocked-state-id>     # Create this state!
DONE             = <done-state-id>

# Labels (optional)
NEEDS_INVESTIGATION = <label-id>
BUG              = <label-id>
FEATURE          = <label-id>

# User (for auto-assignment)
YOUR_USER_ID     = <your-linear-user-id>
```

### Finding Linear IDs

Use the Linear MCP in Claude Code:
```
# Get team ID
mcp__linear-server__list_teams

# Get workflow states
mcp__linear-server__list_issue_statuses with team: "YourTeam"

# Get your user ID
mcp__linear-server__get_user with query: "me"
```

### Customize for Your Project

Update these sections in `autopilot.md`:

1. **Plan file path** (Phase 3): Change `docs/plans/` to your preferred location
2. **Build verification** (Phase 5): Change `npx tsc --noEmit` to your project's build command
3. **Commit message format** (Phase 4): Adjust `feat: description (LYN-XX)` to your convention

## Usage

### Single Ticket Mode
```bash
# Process a specific ticket
./scripts/autopilot.sh LYN-123
```

### Continuous Mode
```bash
# Auto-select and process tickets in a loop
./scripts/autopilot.sh

# Custom pause between cycles (default: 30s)
./scripts/autopilot.sh --pause 60
```

### From Claude Code
```
/autopilot           # Auto-select next ticket
/autopilot LYN-123   # Target specific ticket
```

## How It Works

1. **Ticket Selection**: Checks In Review (for feedback) → Brainstorm (for answers) → Todo (new work)
2. **Brainstorm**: Researches the ticket, posts a design document with questions
3. **Planning**: Creates a detailed implementation plan in markdown
4. **Implementation**: Executes the plan using subagent-driven development
5. **Verification**: Runs build checks (TypeScript, etc.)
6. **Review**: Moves ticket to In Review with a summary comment

## Logs

Continuous mode creates logs in `logs/autopilot/<timestamp>/`:
- `run.log` - Master log with cycle summaries
- `summary.json` - Machine-readable metadata
- `cycle-N.log` - Raw Claude output per cycle

## Stopping

- **Ctrl+C** to stop the wrapper script
- Claude will complete its current operation before exiting

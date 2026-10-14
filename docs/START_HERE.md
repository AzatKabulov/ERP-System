# Start here

How to open, run and share work on this project. Written for new teammates and for coding agents (Codex, Claude Code) working with them.

## For people

### 1. Get access
The owner invites you on GitHub: repository **Settings → Collaborators → Add people**. Accept the invite from the email.

### 2. Install once
1. Git for Windows: https://git-scm.com/download/win (the local test server on Windows needs it).
2. VS Code: https://code.visualstudio.com
3. A GitHub account.
4. Tell Git who you are (PowerShell, your own name and the email of your GitHub account):
   ```
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   ```

### 3. Download the project
1. In VS Code press `Ctrl+Shift+P`, run **Git: Clone**.
2. Paste `https://github.com/AzatKabulov/ERP-System.git`, choose a folder.
3. Sign in to GitHub in the browser when asked.
4. Click **Open**, then **Yes, I trust the authors**.

### 4. Add your coding assistant
Install the **Claude Code** extension (sign in with your own account) or use Codex. Then ask it:
"Read docs/START_HERE.md, AGENTS.md and HANDOFF.md, and tell me the current state."

### 5. Run it (optional)
Follow [LOCAL_TEST.md](LOCAL_TEST.md).

### Every working day
1. Pull the latest version first (`Ctrl+Shift+P` → **Git: Pull**).
2. Work on your own branch, for example `feature/your-task`.
3. When finished, commit with a short message and push your branch (Source Control icon → Commit → Sync Changes).
4. Merge into `main` only when the owner or the team agrees.

### Rules for everyone
- Always pull before you start.
- Never force-push. Never rewrite history on `main`.
- Never commit passwords, keys, keystores, generated builds or the `local-data` folder.
- On a conflict, stop and ask for help. Do not delete other people's work.

## For coding agents

Read in this order: [AGENTS.md](../AGENTS.md), [HANDOFF.md](../HANDOFF.md), [PLAN.md](../PLAN.md), then [PRD.md](PRD.md), [ARCHITECTURE.md](ARCHITECTURE.md) and [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) as relevant.

Working with a person who is new to the project:
- The user may not be a developer. Use plain, short language and give step-by-step instructions.
- Before starting, run `git status` and `git pull` so you work on the latest version. If the tree is not clean, say so and ask before touching it.
- Create a branch for the task unless the user says otherwise. Use a neutral name such as `feature/<topic>`.
- Commit and push only when the user asks. Write commit messages in the imperative, one logical change per commit, matching the existing history. Do not add AI credit lines, co-author trailers or model names to commits, pull requests or code comments.
- Never force-push, reset shared branches or rewrite published history.
- Never commit secrets, keystores, generated builds, `local-data/` or `mobile/build/`.
- Keep the state current: update HANDOFF.md (and PLAN.md if the order changes) when you finish a piece of work, with real test results.
- To run tests or the local server, follow [LOCAL_TEST.md](LOCAL_TEST.md) and the commands in AGENTS.md. Do not run two test runs at once.
- Product rules from the owner: this is an ERP, not a cash register; prices are not fixed; costs and prices may be filled in later; keep everything simple.

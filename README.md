# Daily Widget

A simple daily routine planner: drag to create colored task blocks on a time grid, edit them inline, and export the day as a Markdown checklist (handy for feeding into Obsidian or similar).

There are two ways to use it — pick whichever fits:

## Option 1: Just open the HTML (no install)

Double-click `index.html`, or open `file:///path/to/daily-widget/index.html` in any browser. Nothing to install.

Tasks are saved in the browser's local storage, scoped to that browser/profile.

## Option 2: Run as a desktop app (keeps history as files on disk)

Requires [Node.js](https://nodejs.org/) (includes npm).

```bash
git clone <this-repo-url>
cd daily-widget
npm install
npm start
```

This opens the same UI in its own window. Each day's tasks are saved to `data/YYYY-MM-DD.json`, so your history is kept forever as plain files — use the date picker / prev/next buttons in the app to look back at any previous day.

### Optional: run it with a single command

To launch it by just typing `routine` in your terminal, drop a small script on your `PATH`, e.g.:

```bash
cat > /opt/homebrew/bin/routine << 'EOF'
#!/bin/zsh
cd "/absolute/path/to/daily-widget" && exec ./node_modules/.bin/electron . "$@"
EOF
chmod +x /opt/homebrew/bin/routine
```

Adjust the path and the target directory (e.g. `/usr/local/bin`) to your setup.

## Exporting

Click **Export to Obsidian** in the app. It writes a Markdown checklist to `exports/YYYY-MM-DD-tasks.md` (desktop app) or downloads it (browser version), and copies it to your clipboard.

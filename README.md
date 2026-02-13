# GitStack Native

A native Linux desktop application for GitHub management built with Lua and GTK.

## Features

- **Native Linux App** - Lightweight binary using Lua and GTK
- **GitHub OAuth** - Secure device flow authentication
- **Repository Browser** - View owned and starred repositories
- **Issue Tracker** - View and manage GitHub issues
- **Secure Storage** - Tokens stored in system keyring
- **Catppuccin Theme** - Beautiful dark theme matching your web app

## Requirements

- Lua 5.4 or LuaJIT
- GTK4/lgi
- SQLite3
- libsecret

### Install Dependencies (Arch Linux)

```bash
sudo pacman -S lua lua-lgi gtk4 gobject-introspection sqlite3 libsecret
luarocks install --local lsqlite3 luafilesystem luasocket luasec lua-cjson
```

## Setup

1. **Create a GitHub OAuth App**
   - Go to https://github.com/settings/applications/new
   - Set Homepage URL to your app URL
   - No callback URL needed for device flow

2. **Configure Credentials**
   ```bash
   cp src/user.lua.example src/user.lua
   # Edit src/user.lua with your GitHub Client ID
   ```

## Usage

### Authentication

```bash
# First time: authenticate with GitHub
lua auth.lua
```

This will:
1. Start device flow
2. Show you a code to enter at https://github.com/login/device
3. Save your token securely

### Run the App

```bash
# GUI App (requires display)
./run.sh

# CLI (works in terminal)
lua cli.lua
```

### CLI Commands

```
1. View Repositories - Browse your GitHub repos
2. View Issues      - See open issues across repos
3. View Starred    - Browse starred repositories  
4. View Profile    - See your GitHub profile
5. Exit            - Quit the app
```

## Project Structure

```
gitstack-native/
├── main.lua          # GTK GUI application
├── cli.lua           # Terminal interface
├── auth.lua          # Authentication tool
├── run.sh            # Launcher script
├── assets/           # CSS and assets
├── data/             # SQLite database & tokens
└── src/
    ├── api.lua       # GitHub API wrapper
    ├── database.lua  # SQLite operations
    ├── keyring.lua   # libsecret integration
    ├── user.lua     # Your credentials
    └── ui/          # UI components
```

## Theme

Uses Catppuccin Mocha colors:
- Background: #1e1e2e
- Surface: #313244
- Text: #cdd6f4
- Accent: #cba6f7 (Mauve)

## Security

- OAuth tokens stored in system keyring (GNOME Keyring/KWallet)
- File backup also created as fallback
- Never commit credentials to git

## License

MIT

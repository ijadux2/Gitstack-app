#!/usr/bin/env lua

package.preload["lgi.override.Gdk"] = function() return function() end end
package.preload["lgi.override.Gtk"] = function() return function() end end
package.preload["lgi.override.GdkPixbuf"] = function() return function() end end
package.preload["lgi.override.GObject"] = function() return function() end end
package.preload["lgi.override.Gtk-3.0"] = function() return function() end end

package.path = package.path .. ";./src/?.lua;"

local lgi = require("lgi")
local Gtk = lgi.Gtk
local Gdk = lgi.Gdk
local GLib = lgi.GLib

local api = require("src.api")
local Keyring = require("src.keyring")

local current_view = "dashboard"
local repos = {}
local issues = {}
local starred = {}
local current_user = nil

local function load_css()
    local provider = Gtk.CssProvider.new()
    local css = [[
        window { background: #1e1e2e; }
        * { color: #cdd6f4; font-family: sans-serif; }
        button { background: #45475a; border: none; padding: 10px 20px; border-radius: 8px; color: #cdd6f4; }
        button:hover { background: #585b70; }
        entry { background: #313244; color: #cdd6f4; border: 1px solid #45475a; padding: 8px; border-radius: 6px; }
        label { color: #cdd6f4; }
        scrolledwindow { background: #1e1e2e; }
    ]]
    provider:load_from_data(css, #css)
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
end

local win, content, header

local function clear_content()
    if content then
        win:remove(content)
    end
    content = Gtk.Box.new(Gtk.Orientation.VERTICAL, 10)
    content:set_margin_top(20)
    content:set_margin_bottom(20)
    content:set_margin_start(20)
    content:set_margin_end(20)
    win:set_child(content)
end

local function set_title(title)
    header = Gtk.HeaderBar.new()
    local title_label = Gtk.Label.new(title)
    header:set_title_widget(title_label)
    win:set_titlebar(header)
end

local function add_nav_buttons()
    local nav = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 10)
    nav:set_halign(Gtk.Align.CENTER)
    
    local btns = {"Dashboard", "Repos", "Issues", "Stars"}
    for _, name in ipairs(btns) do
        local btn = Gtk.Button.new_with_label(name)
        btn:connect("clicked", function()
            if name == "Dashboard" then show_dashboard()
            elseif name == "Repos" then show_repos()
            elseif name == "Issues" then show_issues()
            elseif name == "Stars" then show_stars()
            end
        end)
        nav:append(btn)
    end
    content:append(nav)
end

local function show_dashboard()
    clear_content()
    set_title("GitStack - " .. current_user.login)
    add_nav_buttons()
    
    local title = Gtk.Label.new("<span size='24' weight='bold'>Welcome, " .. current_user.login .. "!</span>")
    title:set_use_markup(true)
    content:append(title)
    
    local stats = Gtk.Label.new(string.format("Repos: %d | Followers: %d | Following: %d", 
        current_user.public_repos, current_user.followers, current_user.following))
    content:append(stats)
end

local function show_repos()
    clear_content()
    set_title("Repositories")
    add_nav_buttons()
    
    local scroll = Gtk.ScrolledWindow.new()
    scroll:set_vexpand(true)
    
    local list = Gtk.ListBox.new()
    for _, repo in ipairs(repos) do
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 5)
        box:set_margin_start(10)
        box:set_margin_end(10)
        box:set_margin_top(10)
        box:set_margin_bottom(10)
        
        local name = Gtk.Label.new("<b>" .. repo.full_name .. "</b>")
        name:set_use_markup(true)
        
        local desc = Gtk.Label.new(repo.description or "No description")
        desc:set_ellipsize(3)
        
        local meta = Gtk.Label.new((repo.language or "") .. " ★ " .. repo.stargazers_count)
        
        box:append(name)
        box:append(desc)
        box:append(meta)
        row:add(box)
        list:append(row)
    end
    
    scroll:set_child(list)
    content:append(scroll)
end

local function show_issues()
    clear_content()
    set_title("Issues")
    add_nav_buttons()
    
    local scroll = Gtk.ScrolledWindow.new()
    scroll:set_vexpand(true)
    
    local list = Gtk.ListBox.new()
    for _, issue in ipairs(issues) do
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 5)
        box:set_margin_start(10)
        box:set_margin_end(10)
        box:set_margin_top(10)
        box:set_margin_bottom(10)
        
        local title = Gtk.Label.new("<b>#" .. issue.number .. "</b> " .. issue.title)
        title:set_use_markup(true)
        
        box:append(title)
        row:add(box)
        list:append(row)
    end
    
    scroll:set_child(list)
    content:append(scroll)
end

local function show_stars()
    clear_content()
    set_title("Starred")
    add_nav_buttons()
    
    local scroll = Gtk.ScrolledWindow.new()
    scroll:set_vexpand(true)
    
    local list = Gtk.ListBox.new()
    for _, repo in ipairs(starred) do
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 5)
        box:set_margin_start(10)
        box:set_margin_end(10)
        box:set_margin_top(10)
        box:set_margin_bottom(10)
        
        local name = Gtk.Label.new("<b>" .. repo.full_name .. "</b>")
        name:set_use_markup(true)
        
        box:append(name)
        row:add(box)
        list:append(row)
    end
    
    scroll:set_child(list)
    content:append(scroll)
end

-- Init
local token = Keyring.new():get_token()
if not token then
    print("Not authenticated. Run: lua auth.lua")
    os.exit(1)
end

api:set_token(token)
current_user = api:get_user()

repos = api:get_repos({per_page=50}) or {}
issues = api:get_user_issues({state="open", per_page=20}) or {}
starred = api:get_starred_repos({per_page=50}) or {}

print("Loaded", #repos, "repos", #issues, "issues", #starred, "stars")

win = Gtk.Window.new()
win:set_default_size(900, 600)
win:set_title("GitStack Native")

load_css()

clear_content()
show_dashboard()

win:show_all()

win:connect("close-request", function()
    Gtk.main_quit()
end)

Gtk.main()

local lgi = require("lgi")
local Gtk = lgi.Gtk
local Gdk = lgi.Gdk
local GLib = lgi.GLib

local Database = require("src.db.database")
local Keyring = require("src.keyring")
local API = require("src.api")

local ReposView = require("src.ui.repos")
local IssuesView = require("src.ui.issues")
local user_config = require("src.user")

local Window = {}
Window.__index = Window

function Window.new(app)
    local self = setmetatable({}, Window)
    self.app = app
    self.window = nil
    self.stack = nil
    self.header = nil
    
    self.db = Database.new()
    self.db:open("data")
    
    self.keyring = Keyring.new()
    self.api = API.new()
    
    self.token = self.keyring:get_token()
    if self.token then
        self.api:set_token(self.token)
    end
    
    self:setup_theme()
    
    return self
end

function Window:setup_theme()
    local settings = Gtk.Settings.get_default()
    local dark = self.db:get_setting("prefer_dark_theme")
    
    if dark == "true" then
        settings.gtk_application_prefer_dark_theme = true
    else
        settings.gtk_application_prefer_dark_theme = false
    end
end

function Window:build()
    self.window = Gtk.ApplicationWindow.new(self.app)
    self.window:set_title("GitStack Native")
    self.window:set_default_size(1200, 800)
    
    self:setup_content()
    
    if self.token then
        self:load_user_data()
    else
        self:show_auth_view()
    end
    
    return self.window
end

function Window:setup_content()
    self.main_box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0)
    self.main_box:set_vexpand(true)
    self.main_box:set_hexpand(true)
    
    self.window:set_child(self.main_box)
end

function Window:add_page(name, widget, title)
    if not self.stack then
        self.stack = Gtk.Stack.new()
        self.stack:set_vexpand(true)
        self.stack:set_hexpand(true)
        self.main_box:append(self.stack)
    end
    self.stack:add_titled(widget, name, title)
end

function Window:set_page(name)
    if self.stack then
        self.stack:set_visible_child_name(name)
    end
end

function Window:show_auth_view()
    local auth_box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 20)
    auth_box:set_halign(Gtk.Align.CENTER)
    auth_box:set_valign(Gtk.Align.CENTER)
    auth_box:set_margin_top(50)
    auth_box:set_margin_bottom(50)
    auth_box:set_margin_start(50)
    auth_box:set_margin_end(50)
    
    local title_label = Gtk.Label.new("<span size='xx-large' weight='bold'>Welcome to GitStack</span>")
    title_label:set_use_markup(true)
    
    local desc_label = Gtk.Label.new("Sign in with your GitHub account to continue")
    
    local client_id_entry = Gtk.Entry.new()
    client_id_entry:set_placeholder_text("GitHub Client ID")
    client_id_entry:set_hexpand(true)
    client_id_entry:set_width_chars(40)
    
    local login_button = Gtk.Button.new_with_label("Sign In with GitHub")
    login_button:set_halign(Gtk.Align.CENTER)
    login_button:add_css_class("suggested-action")
    
    local status_label = Gtk.Label.new("")
    status_label:set_wrap(true)
    status_label:set_width_chars(50)
    
    local function start_device_flow()
        local client_id = client_id_entry:get_text()
        if not client_id or client_id == "" then
            client_id = user_config.github_client_id
        end
        if not client_id or client_id == "" then
            status_label:set_text("Please enter a GitHub Client ID")
            return
        end
        
        login_button:set_sensitive(false)
        status_label:set_text("Starting device flow...")
        print("DEBUG: Starting device flow with client_id:", client_id)
        
        GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
            local device_info, err = self.api:start_device_flow(client_id)
            print("DEBUG: device_flow result:", device_info, err)
            
            if err then
                status_label:set_text("Error: " .. err)
                login_button:set_sensitive(true)
                return false
            end
            
            status_label:set_text(
                string.format(
                    "Please visit %s and enter code: %s",
                    device_info.verification_uri,
                    device_info.user_code
                )
            )
            
            print("DEBUG: Starting to poll for token, interval:", device_info.interval)
            
            local poll_attempts = 0
            local max_attempts = 120
            
            local function poll()
                poll_attempts = poll_attempts + 1
                print("DEBUG: Poll attempt:", poll_attempts)
                
                local token, token_err = self.api:poll_for_token(
                    client_id,
                    device_info.device_code,
                    device_info.interval
                )
                
                if token then
                    status_label:set_text("Login successful!")
                    self.token = token
                    self.api:set_token(token)
                    self.keyring:store_token(token)
                    self:load_user_data()
                    return false
                end
                
                if token_err then
                    status_label:set_text("Error: " .. token_err)
                    login_button:set_sensitive(true)
                    return false
                end
                
                if poll_attempts >= max_attempts then
                    status_label:set_text("Timeout - please try again")
                    login_button:set_sensitive(true)
                    return false
                end
                
                status_label:set_text("Waiting for authorization... (attempt " .. poll_attempts .. ")")
                return true
            end
            
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, device_info.interval * 1000, poll)
            
            return false
        end)
    end
    
    login_button:on_clicked(start_device_flow)
    
    auth_box:append(title_label)
    auth_box:append(desc_label)
    auth_box:append(client_id_entry)
    auth_box:append(login_button)
    auth_box:append(status_label)
    
    self.auth_view = auth_box
    self.window:set_child(auth_box)
end

function Window:load_user_data()
    if self.auth_view then
        self.window:remove(self.auth_view)
        self.auth_view = nil
    end
    
    GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
        local user, err = self.api:get_user()
        
        if err then
            print("Error loading user: " .. err)
            return false
        end
        
        self.current_user = user
        self.db:save_user(user)
        
        self:show_main_views()
        
        self:refresh_repos()
        
        return false
    end)
end

function Window:show_main_views()
    local repos_view = ReposView.new(self)
    local repos_widget = repos_view:build()
    self:add_page("repos", repos_widget, "Repositories")
    self.repos_view = repos_view
    
    local issues_view = IssuesView.new(self)
    local issues_widget = issues_view:build()
    self:add_page("issues", issues_widget, "Issues")
    self.issues_view = issues_view
    
    local dashboard = self:create_dashboard()
    self:add_page("dashboard", dashboard, "Dashboard")
    
    self:set_page("dashboard")
end

function Window:create_dashboard()
    local box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 20)
    box:set_margin_start(20)
    box:set_margin_end(20)
    box:set_margin_top(20)
    box:set_margin_bottom(20)
    
    local title = Gtk.Label.new("<span size='xx-large' weight='bold'>Dashboard</span>")
    title:set_use_markup(true)
    title:set_halign(Gtk.Align.START)
    
    local welcome = Gtk.Label.new(string.format("Welcome back, %s!", self.current_user.login or "User"))
    welcome:set_halign(Gtk.Align.START)
    
    local stats_box = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 20)
    stats_box:set_halign(Gtk.Align.START)
    
    local function create_stat_card(label_text, count)
        local card = Gtk.Frame.new()
        card:add_css_class("view")
        card:add_css_class("card")
        card:set_size_request(150, 80)
        
        local label = Gtk.Label.new(label_text .. ": " .. tostring(count))
        label:set_halign(Gtk.Align.CENTER)
        label:set_valign(Gtk.Align.CENTER)
        
        card:set_child(label)
        return card
    end
    
    stats_box:append(create_stat_card("Repositories", 0))
    stats_box:append(create_stat_card("Starred", 0))
    stats_box:append(create_stat_card("Issues", 0))
    
    box:append(title)
    box:append(welcome)
    box:append(stats_box)
    
    return box
end

function Window:refresh_repos()
    if self.repos_view then
        self.repos_view:refresh()
    end
end

function Window:logout()
    self.keyring:delete_token()
    self.token = nil
    self.api:set_token(nil)
    
    self.window:close()
end

function Window:cleanup()
    if self.db then
        self.db:close()
    end
end

return Window

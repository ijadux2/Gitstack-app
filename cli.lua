#!/usr/bin/env lua

package.preload["lgi.override.Gdk"] = function() return function() end end
package.preload["lgi.override.Gtk"] = function() return function() end end
package.preload["lgi.override.GdkPixbuf"] = function() return function() end end

package.path = package.path .. ";./src/?.lua;"

local lgi = require("lgi")
local Gtk = lgi.Gtk
local Gdk = lgi.Gdk

Gtk.init()

local api = require("src.api")
local Keyring = require("src.keyring")

local token = Keyring.new():get_token()
if not token then
    print("Not authenticated. Run: lua auth.lua")
    os.exit(1)
end

api:set_token(token)
local user = api:get_user()
print("Authenticated as:", user.login)

print("\n=== GitStack Native ===\n")
print("1. View Repositories")
print("2. View Issues")
print("3. View Starred")
print("4. View Profile")
print("5. Exit")

local function view_repos()
    print("\n--- Your Repositories ---")
    local repos = api:get_repos({per_page=30})
    for i, r in ipairs(repos) do
        print(i .. ". " .. r.full_name)
        print("   " .. (r.description or "No description"))
        print("   ★ " .. tostring(r.stargazers_count) .. " ⑂ " .. tostring(r.forks_count) .. "  " .. (r.language or ""))
    end
end

local function view_issues()
    print("\n--- Your Issues ---")
    local issues = api:get_user_issues({state="open", per_page=20})
    for i, issue in ipairs(issues) do
        print(i .. ". #" .. issue.number .. " " .. issue.title)
    end
end

local function view_stars()
    print("\n--- Starred Repositories ---")
    local stars = api:get_starred_repos({per_page=30})
    for i, r in ipairs(stars) do
        print(i .. ". " .. r.full_name)
    end
end

local function view_profile()
    print("\n--- Your Profile ---")
    print("Login:", user.login)
    print("Name:", user.name or "N/A")
    print("Public Repos:", tostring(user.public_repos))
    print("Followers:", tostring(user.followers))
    print("Following:", tostring(user.following))
    print("Location:", user.location or "N/A")
end

while true do
    io.write("\n> ")
    local choice = io.read()
    if choice == "1" then view_repos()
    elseif choice == "2" then view_issues()
    elseif choice == "3" then view_stars()
    elseif choice == "4" then view_profile()
    elseif choice == "5" then break
    else print("Invalid choice")
    end
end

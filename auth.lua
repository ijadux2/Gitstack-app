#!/usr/bin/env lua

-- GitStack Native - CLI Authentication Tool
-- Run this to authenticate with GitHub

package.path = package.path .. ";./src/?.lua;./src/ui/?.lua;"

local API = require("src.api")
local user_config = require("src.user")

-- Check if token already exists
local function get_cached_token()
	local f = io.open("data/token", "r")
	if f then
		local token = f:read("*a")
		f:close()
		if token and token ~= "" then
			return token
		end
	end
	return nil
end

-- Try to use cached token
local cached = get_cached_token()
if cached then
	print("Found cached token!")

	-- Test if token works
	local api = API.new()
	api:set_token(cached)
	local user, err = api:get_user()

	if user and user.login then
		print("Token is valid! User: " .. user.login)
		print("You're already authenticated.")
		os.exit(0)
	else
		print("Token expired, need to re-authenticate...")
	end
end

local api = API.new()
local client_id = user_config.github_client_id

print("GitStack Native - GitHub Authentication")
print("======================================")
print("")
print("Client ID:", client_id)
print("")

print("Step 1: Starting device flow...")
local device_info, err = api:start_device_flow(client_id)

if err then
	print("ERROR:", err)
	os.exit(1)
end

print("")
print("Step 2: AUTHORIZATION REQUIRED")
print("Please visit: " .. device_info.verification_uri)
print("Enter this code: " .. device_info.user_code)
print("")
print("Waiting for authorization...")
print("(Press Ctrl+C to cancel)")
print("")

-- Poll for token
local token, token_err = api:poll_for_token(client_id, device_info.device_code, device_info.interval)

if token then
	print("")
	print("SUCCESS! Token received!")
	print("Token: " .. token:sub(1, 20) .. "...")

	-- Save token to file
	local f = io.open("data/token", "w")
	if f then
		f:write(token)
		f:close()
		print("Token saved to data/token")

		-- Test the token
		api:set_token(token)
		local user, user_err = api:get_user()
		if user and user.login then
			print("Authenticated as: " .. user.login)
		end
	else
		print("ERROR: Could not save token to file")
	end
else
	print("ERROR:", token_err)
	os.exit(1)
end

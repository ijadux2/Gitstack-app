local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("cjson")
local url = require("socket.url")
local socket = require("socket")

local API = {}
API.__index = API

API.BASE_URL = "https://api.github.com"
API.DEVICE_CODE_URL = "https://github.com/login/device/code"
API.TOKEN_URL = "https://github.com/login/oauth/access_token"

function API.new()
	local self = setmetatable({}, API)
	self.token = nil
	self.rate_limit_remaining = nil
	self.rate_limit_reset = nil
	return self
end

function API:set_token(token)
	self.token = token
end

function API:build_headers()
	local headers = {
		["Accept"] = "application/vnd.github.v3+json",
		["User-Agent"] = "GitStack-Native/1.0",
	}

	if self.token then
		headers["Authorization"] = "Bearer " .. self.token
	end

	return headers
end

function API:request(method, endpoint, params)
	local url_str = API.BASE_URL .. endpoint

	if params then
		local query_params = {}
		for k, v in pairs(params) do
			table.insert(query_params, url.escape(k) .. "=" .. url.escape(tostring(v)))
		end
		if #query_params > 0 then
			url_str = url_str .. "?" .. table.concat(query_params, "&")
		end
	end

	local headers = self:build_headers()

	local body = {}

	local req = {
		url = url_str,
		method = method,
		headers = headers,
		sink = ltn12.sink.table(body),
		timeout = 10
	}

	local res, err = https.request(req)

	if not res then
		return nil, err or "Request failed"
	end

	if type(body) == "table" then
		body = table.concat(body)
	end

	-- luasec returns 1 on success
	if res == 1 or res == 200 or res == 201 then
		if body and body ~= "" then
			local success, data = pcall(json.decode, body)
			if success then
				self:update_rate_limit(response_headers)
				return data, nil
			end
		end
		return { success = true }, nil
	elseif res == 204 then
		return { success = true }, nil
	elseif res == 401 then
		return nil, "Unauthorized - invalid or expired token"
	elseif res == 403 then
		return nil, "Forbidden - rate limit may be exceeded"
	elseif res == 404 then
		return nil, "Not found"
	else
		return nil, "HTTP Error: " .. tostring(res)
	end
end

function API:update_rate_limit(headers)
	if headers and headers["x-ratelimit-remaining"] then
		self.rate_limit_remaining = tonumber(headers["x-ratelimit-remaining"])
	end
	if headers and headers["x-ratelimit-reset"] then
		self.rate_limit_reset = tonumber(headers["x-ratelimit-reset"])
	end
end

function API:get(endpoint, params)
	return self:request("GET", endpoint, params)
end

function API:post(endpoint, data)
	local url_str = API.BASE_URL .. endpoint
	local headers = self:build_headers()
	headers["Content-Type"] = "application/json"

	local body = json.encode(data)
	local response_body = {}

	local req = {
		url = url_str,
		method = "POST",
		headers = headers,
		source = ltn12.source.string(body),
		sink = ltn12.sink.table(response_body),
		redirect = true,
	}

	local res = https.request(req)
	
	if type(response_body) == "table" then
		response_body = table.concat(response_body)
	end
	
	if res == 200 then
		if response_body and response_body ~= "" then
			local success, data = pcall(json.decode, response_body)
			if success then
				return data, nil
			end
		end
		return { success = true }, nil
	end

	return nil, "HTTP Error: " .. tostring(res)
end

function API:delete(endpoint)
	local url_str = API.BASE_URL .. endpoint
	local headers = self:build_headers()

	local response_body = {}

	local req = {
		url = url_str,
		method = "DELETE",
		headers = headers,
		sink = ltn12.sink.table(response_body),
		redirect = true,
	}

	local res = https.request(req)

	if res == 204 or res == 200 then
		return { success = true }, nil
	end

	return nil, "HTTP Error: " .. tostring(res)
end

function API:start_device_flow(client_id)
	local body = "client_id=" .. client_id .. "&scope=repo+user+read:org"
	
	local response_body = {}
	
	local req = {
		url = API.DEVICE_CODE_URL,
		method = "POST",
		headers = {
			["Content-Type"] = "application/x-www-form-urlencoded",
			["Accept"] = "application/json",
		},
		source = ltn12.source.string(body),
		sink = ltn12.sink.table(response_body),
		timeout = 10
	}

 	local res = https.request(req)

	if type(response_body) == "table" then
		response_body = table.concat(response_body)
	end
	
	-- luasec returns 1 on success, body contains the response
	if response_body and response_body ~= "" then
		local success, data = pcall(json.decode, response_body)
		if success and data and data.device_code then
			return {
				device_code = data.device_code,
				user_code = data.user_code,
				verification_uri = data.verification_uri,
				verification_uri_complete = data.verification_uri_complete,
				interval = tonumber(data.interval) or 5,
				expires_in = tonumber(data.expires_in),
			}, nil
		end
	end

	return nil, "Failed to start device flow"
end

function API:poll_for_token(client_id, device_code, interval)
	
	local headers = {
		["Accept"] = "application/json",
		["Content-Type"] = "application/json",
	}

	local body = "client_id=" .. client_id .. "&device_code=" .. device_code .. "&grant_type=urn:ietf:params:oauth:grant-type:device_code"

	local max_attempts = 120
	local attempts = 0
	
	while attempts < max_attempts do
		attempts = attempts + 1
		
		local response_body = {}

		local req = {
			url = API.TOKEN_URL,
			method = "POST",
			headers = {
				["Content-Type"] = "application/x-www-form-urlencoded",
				["Accept"] = "application/json",
			},
			source = ltn12.source.string(body),
			sink = ltn12.sink.table(response_body),
			timeout = 10
		}

		local res = https.request(req)

		if type(response_body) == "table" then
			response_body = table.concat(response_body)
		end
		
		if res == 200 or (type(res) == "number" and res >= 1) then
			local success, data = pcall(json.decode, response_body)
			if success then
				if data.access_token then
					return data.access_token, nil
				elseif data.error then
					if data.error == "expired_token" then
						return nil, "Device flow expired"
					elseif data.error == "authorization_pending" then
						-- Continue polling
					elseif data.error == "slow_down" then
						interval = interval + 1
					else
						return nil, data.error_description or data.error
					end
				end
			end
		end
		
		socket.sleep(interval)
	end
	
	return nil, "Polling timeout - user did not authorize in time"
end

function API:get_user()
	return self:get("/user")
end

function API:get_repos(params)
	params = params or {}
	params.per_page = params.per_page or 30
	params.sort = params.sort or "updated"
	return self:get("/user/repos", params)
end

function API:get_repo(owner, repo)
	return self:get("/repos/" .. owner .. "/" .. repo)
end

function API:get_repo_tree(owner, repo, sha, recursive)
	recursive = recursive and "1" or "0"
	return self:get("/repos/" .. owner .. "/" .. repo .. "/git/trees/" .. sha, { recursive = recursive })
end

function API:get_starred_repos(params)
	params = params or {}
	params.per_page = params.per_page or 30
	return self:get("/user/starred", params)
end

function API:get_issues(owner, repo, params)
	params = params or {}
	params.state = params.state or "open"
	params.per_page = params.per_page or 30
	return self:get("/repos/" .. owner .. "/" .. repo .. "/issues", params)
end

function API:get_user_issues(params)
	params = params or {}
	params.state = params.state or "open"
	params.per_page = params.per_page or 30
	return self:get("/issues", params)
end

function API:get_issue(owner, repo, number)
	return self:get("/repos/" .. owner .. "/" .. repo .. "/issues/" .. number)
end

function API:get_issue_comments(owner, repo, number, params)
	params = params or {}
	params.per_page = params.per_page or 30
	return self:get("/repos/" .. owner .. "/" .. repo .. "/issues/" .. number .. "/comments", params)
end

function API:create_issue(owner, repo, title, body, labels)
	local data = {
		title = title,
		body = body,
	}

	if labels then
		data.labels = labels
	end

	return self:post("/repos/" .. owner .. "/" .. repo .. "/issues", data)
end

function API:create_issue_comment(owner, repo, number, body)
	return self:post("/repos/" .. owner .. "/" .. repo .. "/issues/" .. number .. "/comments", {
		body = body,
	})
end

return API

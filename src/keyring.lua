local lgi = require("lgi")
local Secret = lgi.Secret

local Keyring = {}
Keyring.__index = Keyring

function Keyring.new()
    local self = setmetatable({}, Keyring)
    self.service = "com.gitstack.native"
    return self
end

function Keyring:store_token(token)
    -- Try to save to keyring, but don't fail
    local ok, err = pcall(function()
        local schema = Secret.Schema.new("org.freedesktop.Secret.Generic", {
            service = Secret.SchemaAttribute.STRING
        }, {})

        local attributes = {
            service = self.service
        }

        local collection = Secret.get_default()
        Secret.password_store_sync(schema, attributes, collection, token, nil)
    end)
    
    if not ok then
        print("Warning: Could not save to keyring: " .. tostring(err))
    end
    
    -- Always save to file as backup
    local f = io.open("data/token", "w")
    if f then
        f:write(token)
        f:close()
    end
    
    return true
end

function Keyring:get_token()
    -- Try keyring first
    local ok, result = pcall(function()
        local schema = Secret.Schema.new("org.freedesktop.Secret.Generic", {
            service = Secret.SchemaAttribute.STRING
        }, {})

        local attributes = {
            service = self.service
        }

        return Secret.password_lookup_sync(schema, attributes, nil)
    end)
    
    if ok and result then
        return result
    end
    
    -- Fall back to file
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

function Keyring:delete_token()
    pcall(function()
        local schema = Secret.Schema.new("org.freedesktop.Secret.Generic", {
            service = Secret.SchemaAttribute.STRING
        }, {})

        local attributes = {
            service = self.service
        }

        Secret.password_clear_sync(schema, attributes, nil)
    end)
    
    -- Also delete file
    os.remove("data/token")
    
    return true
end

function Keyring:has_token()
    return self:get_token() ~= nil
end

return Keyring

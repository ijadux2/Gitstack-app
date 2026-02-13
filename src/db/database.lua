local sqlite3 = require("lsqlite3")
local lfs = require("lfs")

local Database = {}
Database.__index = Database

local DB_NAME = "gitstack.db"

function Database.new()
	local self = setmetatable({}, Database)
	self.db = nil
	self.db_path = nil
	return self
end

function Database:open(path)
	local db_dir = path or "data"
	local success = lfs.attributes(db_dir, "mode")
	if not success then
		lfs.mkdir(db_dir)
	end

	self.db_path = db_dir .. "/" .. DB_NAME
	self.db = sqlite3.open(self.db_path)

	if not self.db then
		error("Failed to open database: " .. self.db_path)
	end

	self:run_migrations()
	return self
end

function Database:close()
	if self.db then
		self.db:close()
		self.db = nil
	end
end

function Database:run_migrations()
	self.db:execute([[
        CREATE TABLE IF NOT EXISTS user_profile (
            id INTEGER PRIMARY KEY,
            github_id INTEGER UNIQUE,
            login TEXT NOT NULL,
            avatar_url TEXT,
            name TEXT,
            email TEXT,
            bio TEXT,
            updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    ]])

	self.db:execute([[
        CREATE TABLE IF NOT EXISTS repositories (
            id INTEGER PRIMARY KEY,
            repo_id INTEGER UNIQUE NOT NULL,
            owner TEXT NOT NULL,
            name TEXT NOT NULL,
            full_name TEXT UNIQUE NOT NULL,
            description TEXT,
            private INTEGER DEFAULT 0,
            fork INTEGER DEFAULT 0,
            html_url TEXT,
            clone_url TEXT,
            language TEXT,
            stargazers_count INTEGER DEFAULT 0,
            forks_count INTEGER DEFAULT 0,
            open_issues_count INTEGER DEFAULT 0,
            updated_at INTEGER,
            cached_at INTEGER DEFAULT (strftime('%s', 'now')),
            UNIQUE(owner, name)
        )
    ]])

	self.db:execute([[
        CREATE TABLE IF NOT EXISTS starred_repos (
            id INTEGER PRIMARY KEY,
            repo_id INTEGER UNIQUE NOT NULL,
            owner TEXT NOT NULL,
            name TEXT NOT NULL,
            full_name TEXT UNIQUE NOT NULL,
            description TEXT,
            private INTEGER DEFAULT 0,
            html_url TEXT,
            language TEXT,
            stargazers_count INTEGER DEFAULT 0,
            cached_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    ]])

	self.db:execute([[
        CREATE TABLE IF NOT EXISTS issue_drafts (
            id INTEGER PRIMARY KEY,
            repo_owner TEXT NOT NULL,
            repo_name TEXT NOT NULL,
            title TEXT,
            body TEXT,
            labels TEXT,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    ]])

	self.db:execute([[
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    ]])

	self.db:execute([[
        CREATE INDEX IF NOT EXISTS idx_repositories_full_name ON repositories(full_name)
    ]])

	self.db:execute([[
        CREATE INDEX IF NOT EXISTS idx_starred_repos_full_name ON starred_repos(full_name)
    ]])
end

function Database:save_user(user)
	local stmt = self.db:prepare([[
        INSERT OR REPLACE INTO user_profile 
        (github_id, login, avatar_url, name, email, bio, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, strftime('%s', 'now'))
    ]])
	stmt:bind(user.id, user.login, user.avatar_url, user.name, user.email, user.bio)
	stmt:step()
	stmt:finalize()
end

function Database:get_user()
	local stmt = self.db:prepare("SELECT * FROM user_profile LIMIT 1")
	local user = nil

	for row in stmt:nrows() do
		user = row
		break
	end
	stmt:finalize()
	return user
end

function Database:save_repository(repo)
	local stmt = self.db:prepare([[
        INSERT OR REPLACE INTO repositories
        (repo_id, owner, name, full_name, description, private, fork, html_url, clone_url,
         language, stargazers_count, forks_count, open_issues_count, updated_at, cached_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, strftime('%s', 'now'))
    ]])
	stmt:bind(
		repo.id,
		repo.owner.login,
		repo.name,
		repo.full_name,
		repo.description,
		repo.private and 1 or 0,
		repo.fork and 1 or 0,
		repo.html_url,
		repo.clone_url,
		repo.language,
		repo.stargazers_count,
		repo.forks_count,
		repo.open_issues_count,
		repo.updated_at
	)
	stmt:step()
	stmt:finalize()
end

function Database:get_repositories()
	local stmt = self.db:prepare("SELECT * FROM repositories ORDER BY updated_at DESC")
	local repos = {}

	for row in stmt:nrows() do
		table.insert(repos, row)
	end
	stmt:finalize()
	return repos
end

function Database:get_repository(full_name)
	local stmt = self.db:prepare("SELECT * FROM repositories WHERE full_name = ?")
	stmt:bind(full_name)
	local repo = nil

	for row in stmt:nrows() do
		repo = row
		break
	end
	stmt:finalize()
	return repo
end

function Database:save_starred_repo(repo)
	local stmt = self.db:prepare([[
        INSERT OR REPLACE INTO starred_repos
        (repo_id, owner, name, full_name, description, private, html_url, language, stargazers_count, cached_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, strftime('%s', 'now'))
    ]])
	stmt:bind(
		repo.id,
		repo.owner.login,
		repo.name,
		repo.full_name,
		repo.description,
		repo.private and 1 or 0,
		repo.html_url,
		repo.language,
		repo.stargazers_count
	)
	stmt:step()
	stmt:finalize()
end

function Database:get_starred_repos()
	local stmt = self.db:prepare("SELECT * FROM starred_repos ORDER BY cached_at DESC")
	local repos = {}

	for row in stmt:nrows() do
		table.insert(repos, row)
	end
	stmt:finalize()
	return repos
end

function Database:save_issue_draft(repo_owner, repo_name, title, body, labels)
	local existing = self:get_issue_draft(repo_owner, repo_name)

	if existing then
		local stmt = self.db:prepare([[
            UPDATE issue_drafts 
            SET title = ?, body = ?, labels = ?, updated_at = strftime('%s', 'now')
            WHERE repo_owner = ? AND repo_name = ?
        ]])
		stmt:bind(title, body, labels, repo_owner, repo_name)
		stmt:step()
		stmt:finalize()
	else
		local stmt = self.db:prepare([[
            INSERT INTO issue_drafts (repo_owner, repo_name, title, body, labels)
            VALUES (?, ?, ?, ?, ?)
        ]])
		stmt:bind(repo_owner, repo_name, title, body, labels)
		stmt:step()
		stmt:finalize()
	end
end

function Database:get_issue_draft(repo_owner, repo_name)
	local stmt = self.db:prepare("SELECT * FROM issue_drafts WHERE repo_owner = ? AND repo_name = ?")
	stmt:bind(repo_owner, repo_name)
	local draft = nil

	for row in stmt:nrows() do
		draft = row
		break
	end
	stmt:finalize()
	return draft
end

function Database:get_all_issue_drafts()
	local stmt = self.db:prepare("SELECT * FROM issue_drafts ORDER BY updated_at DESC")
	local drafts = {}

	for row in stmt:nrows() do
		table.insert(drafts, row)
	end
	stmt:finalize()
	return drafts
end

function Database:delete_issue_draft(id)
	local stmt = self.db:prepare("DELETE FROM issue_drafts WHERE id = ?")
	stmt:bind(id)
	stmt:step()
	stmt:finalize()
end

function Database:set_setting(key, value)
	local stmt = self.db:prepare("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)")
	stmt:bind(key, value)
	stmt:step()
	stmt:finalize()
end

function Database:get_setting(key)
	local stmt = self.db:prepare("SELECT value FROM settings WHERE key = ?")
	stmt:bind(1, key)
	local value = nil

	for row in stmt:nrows() do
		value = row.value
		break
	end
	stmt:finalize()
	return value
end

function Database:clear_starred_repos()
	self.db:execute("DELETE FROM starred_repos")
end

function Database:clear_repositories()
	self.db:execute("DELETE FROM repositories")
end

return Database

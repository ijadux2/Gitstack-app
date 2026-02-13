local lgi = require("lgi")
local Gtk = lgi.Gtk
local GLib = lgi.GLib

local ReposView = {}
ReposView.__index = ReposView

function ReposView.new(window)
    local self = setmetatable({}, ReposView)
    self.window = window
    self.api = window.api
    self.db = window.db
    
    self.repos = {}
    self.starred_repos = {}
    
    return self
end

function ReposView:build()
    local paned = Gtk.Paned({
        orientation = Gtk.Orientation.HORIZONTAL,
        wide_handle = true,
        hexpand = true,
        vexpand = true
    })
    
    self.sidebar = self:build_sidebar()
    paned:pack_start(self.sidebar, 300, true)
    
    self.detail_view = self:build_detail_view()
    paned:pack_end(self.detail_view, true, true)
    
    self.paned = paned
    return paned
end

function ReposView:build_sidebar()
    local box = Gtk.Box({
        orientation = Gtk.Orientation.VERTICAL,
        hexpand = true,
        vexpand = true
    })
    
    local header = Gtk.Box({
        orientation = Gtk.Orientation.HORIZONTAL,
        halign = Gtk.Align.CENTER
    })
    
    local owned_label = Gtk.Label({
        label = "Owned Repositories",
        halign = Gtk.Align.START,
        css_classes = { "title" }
    })
    
    local refresh_btn = Gtk.Button({
        icon_name = "view-refresh-symbolic",
        tooltip_text = "Refresh repositories"
    })
    refresh_btn:on_clicked(function()
        self:refresh()
    end)
    
    header:append(owned_label)
    header:append(refresh_btn)
    
    self.owned_list = Gtk.ListBox({
        hexpand = true,
        vexpand = true,
        show_separators = true
    })
    
    self.owned_list:on_row_selected(function(listbox, row)
        if row then
            local index = row:get_index() + 1
            if self.repos[index] then
                self:show_repo_details(self.repos[index])
            end
        end
    end)
    
    local scrolled_owned = Gtk.ScrolledWindow({
        child = self.owned_list,
        hexpand = true,
        vexpand = true
    })
    
    local starred_header = Gtk.Label({
        label = "Starred",
        halign = Gtk.Align.START,
        css_classes = { "title" }
    })
    
    self.starred_list = Gtk.ListBox({
        hexpand = true,
        vexpand = true,
        show_separators = true
    })
    
    self.starred_list:on_row_selected(function(listbox, row)
        if row then
            local index = row:get_index() + 1
            if self.starred_repos[index] then
                self:show_repo_details(self.starred_repos[index])
            end
        end
    end)
    
    local scrolled_starred = Gtk.ScrolledWindow({
        child = self.starred_list,
        hexpand = true,
        vexpand = true
    })
    
    local notebook = Gtk.Notebook({
        hexpand = true,
        vexpand = true
    })
    
    notebook:append_page(scrolled_owned, Gtk.Label({ label = "Owned" }))
    notebook:append_page(scrolled_starred, Gtk.Label({ label = "Starred" }))
    
    box:append(header)
    box:append(notebook)
    
    self.sidebar_box = box
    return box
end

function ReposView:build_detail_view()
    local box = Gtk.Box({
        orientation = Gtk.Orientation.VERTICAL,
        hexpand = true,
        vexpand = true,
        margin_top = 20,
        margin_bottom = 20,
        margin_start = 20,
        margin_end = 20
    })
    
    self.detail_title = Gtk.Label({
        label = "Select a repository",
        halign = Gtk.Align.START,
        css_classes = { "title" }
    })
    
    self.detail_description = Gtk.Label({
        label = "",
        halign = Gtk.Align.START,
        wrap = true,
        width_chars = 60
    })
    
    self.detail_stats = Gtk.Box({
        orientation = Gtk.Orientation.HORIZONTAL,
        halign = Gtk.Align.START,
        spacing = 20
    })
    
    self.tree_view = self:build_tree_view()
    
    local scrolled_tree = Gtk.ScrolledWindow({
        child = self.tree_view,
        hexpand = true,
        vexpand = true
    })
    
    box:append(self.detail_title)
    box:append(self.detail_description)
    box:append(self.detail_stats)
    box:append(scrolled_tree)
    
    self.detail_box = box
    return box
end

function ReposView:build_tree_view()
    self.file_model = Gtk.TreeStore.new({
        { type = "gchararray" },
        { type = "gchararray" },
        { type = "gboolean" }
    })
    
    local view = Gtk.TreeView({
        model = self.file_model,
        headers_visible = false,
        hexpand = true,
        vexpand = true
    })
    
    local col = Gtk.TreeViewColumn({
        expand = true
    })
    
    local icon_renderer = Gtk.CellRendererPixbuf({
        xpad = 5
    })
    col:pack_start(icon_renderer, false)
    col:add_attribute(icon_renderer, "icon_name", 1)
    
    local text_renderer = Gtk.CellRendererText({
        xpad = 5
    })
    col:pack_start(text_renderer, true)
    col:add_attribute(text_renderer, "text", 0)
    
    view:append_column(col)
    
    self.tree = view
    return view
end

function ReposView:refresh()
    GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
        local repos, err = self.api:get_repos({ per_page = 100 })
        
        if err then
            print("Error loading repos: " .. err)
            return false
        end
        
        self.repos = repos or {}
        
        for _, repo in ipairs(self.repos) do
            self.db:save_repository(repo)
        end
        
        self:populate_repos_list()
        
        return false
    end)
    
    GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
        local starred, err = self.api:get_starred_repos({ per_page = 100 })
        
        if err then
            print("Error loading starred repos: " .. err)
            return false
        end
        
        self.starred_repos = starred or {}
        
        for _, repo in ipairs(self.starred_repos) do
            self.db:save_starred_repo(repo)
        end
        
        self:populate_starred_list()
        
        return false
    end)
end

function ReposView:populate_repos_list()
    for child in self.owned_list:observe_children() do
        self.owned_list:remove(child)
    end
    
    for _, repo in ipairs(self.repos) do
        local row = self:create_repo_row(repo)
        self.owned_list:append(row)
    end
end

function ReposView:populate_starred_list()
    for child in self.starred_list:observe_children() do
        self.starred_list:remove(child)
    end
    
    for _, repo in ipairs(self.starred_repos) do
        local row = self:create_repo_row(repo)
        self.starred_list:append(row)
    end
end

function ReposView:create_repo_row(repo)
    local box = Gtk.Box({
        orientation = Gtk.Orientation.VERTICAL,
        margin_top = 10,
        margin_bottom = 10,
        margin_start = 10,
        margin_end = 10,
        spacing = 5
    })
    
    local name_label = Gtk.Label({
        label = repo.full_name,
        halign = Gtk.Align.START,
        weight = "bold"
    })
    
    local desc = repo.description or "No description"
    local desc_label = Gtk.Label({
        label = desc,
        halign = Gtk.Align.START,
        wrap = true,
        max_width_chars = 40,
        css_classes = { "dim-label" }
    })
    
    local meta_box = Gtk.Box({
        orientation = Gtk.Orientation.HORIZONTAL,
        halign = Gtk.Align.START,
        spacing = 10
    })
    
    if repo.language then
        local lang_label = Gtk.Label({
            label = repo.language,
            halign = Gtk.Align.START,
            css_classes = { "dim-label" }
        })
        meta_box:append(lang_label)
    end
    
    if repo.stargazers_count and repo.stargazers_count > 0 then
        local stars_label = Gtk.Label({
            label = "★ " .. repo.stargazers_count,
            halign = Gtk.Align.START,
            css_classes = { "dim-label" }
        })
        meta_box:append(stars_label)
    end
    
    if repo.forks_count and repo.forks_count > 0 then
        local forks_label = Gtk.Label({
            label = "⑂ " .. repo.forks_count,
            halign = Gtk.Align.START,
            css_classes = { "dim-label" }
        })
        meta_box:append(forks_label)
    end
    
    box:append(name_label)
    box:append(desc_label)
    box:append(meta_box)
    
    return box
end

function ReposView:show_repo_details(repo)
    self.detail_title:set_label(repo.full_name)
    self.detail_description:set_label(repo.description or "No description")
    
    for child in self.detail_stats:observe_children() do
        self.detail_stats:remove(child)
    end
    
    if repo.language then
        local lang = Gtk.Label({ label = "Language: " .. repo.language })
        self.detail_stats:append(lang)
    end
    
    local stars = Gtk.Label({ label = "★ " .. (repo.stargazers_count or 0) })
    self.detail_stats:append(stars)
    
    local forks = Gtk.Label({ label = "⑂ " .. (repo.forks_count or 0) })
    self.detail_stats:append(forks)
    
    local issues = Gtk.Label({ label = "⚑ " .. (repo.open_issues_count or 0) })
    self.detail_stats:append(issues)
    
    self.current_repo = repo
    self:load_file_tree(repo)
end

function ReposView:load_file_tree(repo)
    self.file_model:clear()
    
    GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
        local tree_data, err = self.api:get_repo_tree(repo.owner.login, repo.name, repo.default_branch or "main", true)
        
        if err then
            print("Error loading tree: " .. err)
            return false
        end
        
        if tree_data and tree_data.tree then
            self:populate_tree(tree_data.tree)
        end
        
        return false
    end)
end

function ReposView:populate_tree(items)
    local paths = {}
    
    for _, item in ipairs(items) do
        local parts = {}
        for part in string.gmatch(item.path, "[^/]+") do
            table.insert(parts, part)
        end
        paths[item.path] = { item = item, parts = parts }
    end
    
    local roots = {}
    
    for path, data in pairs(paths) do
        if #data.parts == 1 then
            table.insert(roots, data)
        end
    end
    
    table.sort(roots, function(a, b)
        if a.item.type ~= b.item.type then
            return a.item.type == "tree"
        end
        return a.item.path < b.item.path
    end)
    
    for _, root in ipairs(roots) do
        local parent_iter = self.file_model:append(nil)
        self.file_model:set_value(parent_iter, 0, root.item.path)
        
        local icon = "folder"
        if root.item.type == "blob" then
            icon = "text-x-generic"
        end
        self.file_model:set_value(parent_iter, 1, icon)
        
        self:add_child_items(paths, root.item.path, parent_iter)
    end
end

function ReposView:add_child_items(paths, parent_path, parent_iter)
    local children = {}
    
    for path, data in pairs(paths) do
        local parent = ""
        if data.parts[#data.parts - 1] then
            parent = table.concat({unpack(data.parts, 1, #data.parts - 1)}, "/")
        end
        
        if parent == parent_path then
            table.insert(children, data)
        end
    end
    
    if #children == 0 then
        return
    end
    
    table.sort(children, function(a, b)
        if a.item.type ~= b.item.type then
            return a.item.type == "tree"
        end
        return a.item.path < b.item.path
    end)
    
    for _, child in ipairs(children) do
        local iter = self.file_model:append(parent_iter)
        self.file_model:set_value(iter, 0, child.parts[#child.parts])
        
        local icon = "folder"
        if child.item.type == "blob" then
            icon = "text-x-generic"
        end
        self.file_model:set_value(iter, 1, icon)
        
        self:add_child_items(paths, child.item.path, iter)
    end
end

return ReposView

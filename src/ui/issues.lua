local lgi = require("lgi")
local Gtk = lgi.Gtk
local GLib = lgi.GLib

local IssuesView = {}
IssuesView.__index = IssuesView

function IssuesView.new(window)
	local self = setmetatable({}, IssuesView)
	self.window = window
	self.api = window.api
	self.db = window.db

	self.issues = {}
	self.selected_issue = nil
	self.selected_repo = nil

	return self
end

function IssuesView:build()
	local paned = Gtk.Paned({
		orientation = Gtk.Orientation.HORIZONTAL,
		wide_handle = true,
		hexpand = true,
		vexpand = true,
	})

	self.list_view = self:build_list_view()
	paned:pack_start(self.list_view, 350, true)

	self.detail_view = self:build_detail_view()
	paned:pack_end(self.detail_view, true, true)

	self.paned = paned
	return paned
end

function IssuesView:build_list_view()
	local box = Gtk.Box({
		orientation = Gtk.Orientation.VERTICAL,
		hexpand = true,
		vexpand = true,
	})

	local header = Gtk.Box({
		orientation = Gtk.Orientation.VERTICAL,
		margin_top = 10,
		margin_bottom = 10,
		margin_start = 10,
		margin_end = 10,
		spacing = 10,
	})

	local title = Gtk.Label({
		label = "Issues",
		halign = Gtk.Align.START,
		css_classes = { "title" },
	})

	local repo_selector = Gtk.ComboBoxText({
		hexpand = true,
	})

	repo_selector:on_changed(function(combo)
		local active = combo:get_active()
		if active >= 0 and self.repo_list[active + 1] then
			self.selected_repo = self.repo_list[active + 1]
			self:load_issues()
		end
	end)

	self.repo_combo = repo_selector

	local filter_box = Gtk.Box({
		orientation = Gtk.Orientation.HORIZONTAL,
		spacing = 5,
	})

	local open_btn = Gtk.ToggleButton({
		label = "Open",
		active = true,
	})
	open_btn:on_clicked(function()
		self.filter_state = "open"
		self:load_issues()
	end)

	local closed_btn = Gtk.ToggleButton({
		label = "Closed",
	})
	closed_btn:on_clicked(function()
		self.filter_state = "closed"
		self:load_issues()
	end)

	filter_box:append(open_btn)
	filter_box:append(closed_btn)

	header:append(title)
	header:append(repo_selector)
	header:append(filter_box)

	self.issues_list = Gtk.ListBox({
		hexpand = true,
		vexpand = true,
		show_separators = true,
	})

	self.issues_list:on_row_selected(function(listbox, row)
		if row then
			local index = row:get_index() + 1
			if self.issues[index] then
				self:show_issue_details(self.issues[index])
			end
		end
	end)

	local scrolled = Gtk.ScrolledWindow({
		child = self.issues_list,
		hexpand = true,
		vexpand = true,
	})

	box:append(header)
	box:append(scrolled)

	self.list_box = box
	return box
end

function IssuesView:build_detail_view()
	local box = Gtk.Box({
		orientation = Gtk.Orientation.VERTICAL,
		hexpand = true,
		vexpand = true,
	})

	local header = Gtk.Box({
		orientation = Gtk.Orientation.VERTICAL,
		margin_top = 20,
		margin_bottom = 10,
		margin_start = 20,
		margin_end = 20,
		spacing = 10,
		halign = Gtk.Align.START,
	})

	self.issue_title = Gtk.Label({
		label = "Select an issue",
		halign = Gtk.Align.START,
		weight = "bold",
		wrap = true,
	})

	self.issue_meta = Gtk.Label({
		label = "",
		halign = Gtk.Align.START,
		css_classes = { "dim-label" },
	})

	local actions = Gtk.Box({
		orientation = Gtk.Orientation.HORIZONTAL,
		spacing = 10,
		halign = Gtk.Align.START,
	})

	local new_btn = Gtk.Button({
		label = "New Issue",
		icon_name = "list-add-symbolic",
	})
	new_btn:on_clicked(function()
		self:show_new_issue_dialog()
	end)

	local draft_btn = Gtk.Button({
		label = "Drafts",
		icon_name = "document-edit-symbolic",
	})
	draft_btn:on_clicked(function()
		self:show_drafts_view()
	end)

	actions:append(new_btn)
	actions:append(draft_btn)

	header:append(self.issue_title)
	header:append(self.issue_meta)
	header:append(actions)

	local separator = Gtk.Separator({
		orientation = Gtk.Orientation.HORIZONTAL,
	})

	self.comments_view = Gtk.TextView({
		editable = false,
		wrap_mode = Gtk.WrapMode.WORD,
		hexpand = true,
		vexpand = true,
		margin_top = 10,
		margin_bottom = 10,
		margin_start = 20,
		margin_end = 20,
	})

	local scrolled = Gtk.ScrolledWindow({
		child = self.comments_view,
		hexpand = true,
		vexpand = true,
	})

	local comment_input_box = Gtk.Box({
		orientation = Gtk.Orientation.VERTICAL,
		spacing = 5,
		margin_top = 10,
		margin_bottom = 10,
		margin_start = 20,
		margin_end = 20,
	})

	local input_label = Gtk.Label({
		label = "Add a comment:",
		halign = Gtk.Align.START,
	})

	self.comment_input = Gtk.TextView({
		wrap_mode = Gtk.WrapMode.WORD,
		hexpand = true,
		height_request = 100,
		top_margin = 5,
		bottom_margin = 5,
	})

	local input_scroll = Gtk.ScrolledWindow({
		child = self.comment_input,
		hexpand = true,
		height_request = 100,
	})

	local submit_btn = Gtk.Button({
		label = "Submit Comment",
		halign = Gtk.Align.END,
		css_classes = { "suggested-action" },
	})
	submit_btn:on_clicked(function()
		self:submit_comment()
	end)

	comment_input_box:append(input_label)
	comment_input_box:append(input_scroll)
	comment_input_box:append(submit_btn)

	box:append(header)
	box:append(separator)
	box:append(scrolled)
	box:append(comment_input_box)

	self.detail_box = box
	return box
end

function IssuesView:set_repo_list(repos)
	self.repo_list = repos

	self.repo_combo:remove_all()

	for _, repo in ipairs(repos) do
		self.repo_combo:append_text(repo.full_name)
	end

	if #repos > 0 then
		self.repo_combo:set_active(0)
		self.selected_repo = repos[1]
	end
end

function IssuesView:load_issues()
	if not self.selected_repo then
		return
	end

	local owner = self.selected_repo.owner.login
	local name = self.selected_repo.name

	GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
		local issues_data, err = self.api:get_issues(owner, name, {
			state = self.filter_state or "open",
			per_page = 50,
		})

		if err then
			print("Error loading issues: " .. err)
			return false
		end

		self.issues = issues_data or {}

		self:populate_issues_list()

		return false
	end)
end

function IssuesView:populate_issues_list()
	for child in self.issues_list:observe_children() do
		self.issues_list:remove(child)
	end

	for _, issue in ipairs(self.issues) do
		local row = self:create_issue_row(issue)
		self.issues_list:append(row)
	end
end

function IssuesView:create_issue_row(issue)
	local box = Gtk.Box({
		orientation = Gtk.Orientation.VERTICAL,
		margin_top = 10,
		margin_bottom = 10,
		margin_start = 10,
		margin_end = 10,
		spacing = 5,
	})

	local title_label = Gtk.Label({
		label = "#" .. issue.number .. " " .. issue.title,
		halign = Gtk.Align.START,
		weight = "bold",
		wrap = true,
	})

	local meta_label = Gtk.Label({
		label = string.format("opened by %s", issue.user.login),
		halign = Gtk.Align.START,
		css_classes = { "dim-label" },
	})

	if issue.labels and #issue.labels > 0 then
		local labels = {}
		for _, label in ipairs(issue.labels) do
			table.insert(labels, label.name)
		end
		local labels_label = Gtk.Label({
			label = table.concat(labels, ", "),
			halign = Gtk.Align.START,
			wrap = true,
			css_classes = { "dim-label" },
		})
		box:append(labels_label)
	end

	box:append(title_label)
	box:append(meta_label)

	return box
end

function IssuesView:show_issue_details(issue)
	self.selected_issue = issue

	self.issue_title:set_label("#" .. issue.number .. " " .. issue.title)

	local state_icon = issue.state == "open" and "●" or "◎"
	self.issue_meta:set_label(
		string.format("%s %s opened by %s on %s", state_icon, issue.state, issue.user.login, issue.created_at)
	)

	local buffer = self.comments_view:get_buffer()
	buffer:set_text(issue.body or "No description")

	self:load_comments(issue)
end

function IssuesView:load_comments(issue)
	if not self.selected_repo then
		return
	end

	local owner = self.selected_repo.owner.login
	local name = self.selected_repo.name

	GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
		local comments, err = self.api:get_issue_comments(owner, name, issue.number)

		if err then
			print("Error loading comments: " .. err)
			return false
		end

		local buffer = self.comments_view:get_buffer()
		local text = issue.body or "No description"

		text = text .. "\n\n--- Comments ---\n\n"

		for _, comment in ipairs(comments or {}) do
			text = text .. string.format("**%s** (%s):\n%s\n\n", comment.user.login, comment.created_at, comment.body)
		end

		buffer:set_text(text)

		return false
	end)
end

function IssuesView:submit_comment()
	if not self.selected_issue or not self.selected_repo then
		return
	end

	local buffer = self.comment_input:get_buffer()
	local start = buffer:get_start_iter()
	local stop = buffer:get_end_iter()
	local body = buffer:get_text(start, stop, true)

	if not body or body == "" then
		return
	end

	local owner = self.selected_repo.owner.login
	local name = self.selected_repo.name

	GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
		local _, err = self.api:create_issue_comment(owner, name, self.selected_issue.number, body)

		if err then
			print("Error creating comment: " .. err)
		else
			buffer:delete(buffer:get_start_iter(), buffer:get_end_iter())
			self:load_comments(self.selected_issue)
		end

		return false
	end)
end

function IssuesView:show_new_issue_dialog()
	if not self.selected_repo then
		return
	end

	local dialog = Gtk.Dialog({
		title = "New Issue",
		transient_for = self.window.window,
		modal = true,
		width_request = 500,
		height_request = 400,
	})

	dialog:add_button("Cancel", Gtk.ResponseType.CANCEL)
	dialog:add_button("Create", Gtk.ResponseType.OK)

	local content = dialog:get_content_area()

	local box = Gtk.Box({
		orientation = Gtk.Orientation.VERTICAL,
		spacing = 10,
		margin_top = 20,
		margin_bottom = 20,
		margin_start = 20,
		margin_end = 20,
	})

	local title_entry = Gtk.Entry({
		placeholder_text = "Issue title",
		hexpand = true,
	})

	local body_view = Gtk.TextView({
		wrap_mode = Gtk.WrapMode.WORD,
		hexpand = true,
		vexpand = true,
		top_margin = 5,
		bottom_margin = 5,
	})

	local body_scroll = Gtk.ScrolledWindow({
		child = body_view,
		hexpand = true,
		vexpand = true,
		height_request = 200,
	})

	local labels_entry = Gtk.Entry({
		placeholder_text = "Labels (comma-separated)",
		hexpand = true,
	})

	box:append(Gtk.Label({ label = "Title:" }))
	box:append(title_entry)
	box:append(Gtk.Label({ label = "Description (Markdown supported):" }))
	box:append(body_scroll)
	box:append(Gtk.Label({ label = "Labels:" }))
	box:append(labels_entry)

	content:append(box)

	dialog:show()

	local response = dialog:run()

	if response == Gtk.ResponseType.OK then
		local title = title_entry:get_text()
		local buffer = body_view:get_buffer()
		local body = buffer:get_text(buffer:get_start_iter(), buffer:get_end_iter(), true)
		local labels_str = labels_entry:get_text()

		local labels = {}
		if labels_str and labels_str ~= "" then
			for label in string.gmatch(labels_str, "[^,]+") do
				table.insert(labels, string.match(label, "^%s*(.-)%s*$"))
			end
		end

		self:save_draft(title, body, labels)

		self:create_issue(title, body, labels)
	end

	dialog:destroy()
end

function IssuesView:save_draft(title, body, labels)
	if not self.selected_repo then
		return
	end

	local labels_str = table.concat(labels, ",")
	self.db:save_issue_draft(self.selected_repo.owner.login, self.selected_repo.name, title, body, labels_str)
end

function IssuesView:create_issue(title, body, labels)
	if not self.selected_repo then
		return
	end

	local owner = self.selected_repo.owner.login
	local name = self.selected_repo.name

	GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
		local issue, err = self.api:create_issue(owner, name, title, body, labels)

		if err then
			print("Error creating issue: " .. err)
		else
			self:load_issues()
		end

		return false
	end)
end

function IssuesView:show_drafts_view()
	local dialog = Gtk.Dialog({
		title = "Issue Drafts",
		transient_for = self.window.window,
		modal = true,
		width_request = 500,
		height_request = 400,
	})

	dialog:add_button("Close", Gtk.ResponseType.CLOSE)

	local content = dialog:get_content_area()

	local drafts_list = Gtk.ListBox({
		hexpand = true,
		vexpand = true,
	})

	local drafts = self.db:get_all_issue_drafts()

	for _, draft in ipairs(drafts) do
		local row = Gtk.Box({
			orientation = Gtk.Orientation.VERTICAL,
			margin_top = 10,
			margin_bottom = 10,
			margin_start = 10,
			margin_end = 10,
			spacing = 5,
		})

		row:append(Gtk.Label({
			label = draft.title or "(No title)",
			weight = "bold",
		}))

		row:append(Gtk.Label({
			label = draft.repo_owner .. "/" .. draft.repo_name,
			css_classes = { "dim-label" },
		}))

		drafts_list:append(row)
	end

	local scroll = Gtk.ScrolledWindow({
		child = drafts_list,
		hexpand = true,
		vexpand = true,
	})

	content:append(scroll)

	dialog:show()
	dialog:run()
	dialog:destroy()
end

return IssuesView

local installer = require("asset_store.asset_store.installer")
local internal = require("asset_store.asset_store.asset_store_internal")
local dialog_ui = require("asset_store.asset_store.ui.dialog")
local filters_ui = require("asset_store.asset_store.ui.filters")
local search_ui = require("asset_store.asset_store.ui.search")
local settings_ui = require("asset_store.asset_store.ui.settings")
local widget_list_ui = require("asset_store.asset_store.ui.widget_list")

---@class asset_store.config
---@field title string The title of the asset store
---@field store_url string The URL of the asset store
---@field install_prefs_key string The key of the install folder in the preferences
---@field info_url string? The URL of the info page, if nil then info button will be hidden
---@field info_button_label string? The label of the info button
---@field close_button_label string? The label of the close button
---@field empty_search_message string? The message to show when no items are found by search
---@field empty_filter_message string?
---@field labels table
---@field labels.search table
---@field labels.filters table
---@field labels.widget_card table

---@class asset_store.item
---@field id string
---@field version string
---@field title string
---@field author string
---@field description string
---@field api string
---@field author_url string
---@field image string
---@field manifest_url string
---@field zip_url string
---@field json_zip_url string
---@field sha256 string
---@field size number
---@field depends string[]
---@field tags string[]


local M = {}

local INFO_RESULT = "asset_store_open_info"
local DEFAULT_TITLE = "Asset Store"
local DEFAULT_INFO_BUTTON = "Info"
local DEFAULT_CLOSE_BUTTON = "Close"
local DEFAULT_EMPTY_SEARCH_MESSAGE = "No widgets found matching '%s'."
local DEFAULT_EMPTY_FILTER_MESSAGE = "No widgets found matching the current filters."
local DEFAULT_SEARCH_LABELS = {
	search_tooltip = "Search by title, author, or description"
}


local function normalize_config(input)
	assert(type(input) == "table", "asset_store.open expects a config table")
	assert(input.store_url, "asset_store.open requires a store_url")
	assert(input.install_prefs_key)


	local config = {
		store_url = input.store_url,
		install_prefs_key = input.install_prefs_key,
		info_url = input.info_url,
		title = input.title or DEFAULT_TITLE,
		info_button_label = input.info_button_label or DEFAULT_INFO_BUTTON,
		close_button_label = input.close_button_label or DEFAULT_CLOSE_BUTTON,
		empty_search_message = input.empty_search_message or DEFAULT_EMPTY_SEARCH_MESSAGE,
		empty_filter_message = input.empty_filter_message or DEFAULT_EMPTY_FILTER_MESSAGE,
		labels = input.labels or {},
		info_action = input.info_action,
	}

	config.labels.search = config.labels.search or {}
	for key, value in pairs(DEFAULT_SEARCH_LABELS) do
		if config.labels.search[key] == nil then
			config.labels.search[key] = value
		end
	end

	return config
end


---Handle widget installation
---@param item table - Widget item to install
---@param install_folder string - Installation folder
---@param all_items table - List of all widgets for dependency resolution
---@param on_success function - Success callback
---@param on_error function - Error callback
local function handle_install(item, install_folder, all_items, on_success, on_error)
	print("Installing widget:", item.id)

	local success, message = installer.install_widget(item, install_folder, all_items)

	if success then
		print("Installation successful:", message)
		on_success(message)
	else
		print("Installation failed:", message)
		on_error(message)
	end
end


function M.open(config_input)
	local config = normalize_config(config_input)

	print("Opening " .. config.title .. " from:", config.store_url)

	local store_data, fetch_error = internal.download_json(config.store_url)
	if not store_data then
		print("Failed to load store items:", fetch_error)
		return
	end
	print("Successfully loaded", #store_data.items, "items")

	local initial_items = store_data.items
	local initial_install_folder = editor.prefs.get(config.install_prefs_key)
	local filter_overrides = config.labels.filters and { labels = config.labels.filters } or nil

	local dialog_component = editor.ui.component(function(props)
		local all_items = editor.ui.use_state(initial_items)
		local install_folder, set_install_folder = editor.ui.use_state(initial_install_folder)
		local search_query, set_search_query = editor.ui.use_state("")
		local filter_type, set_filter_type = editor.ui.use_state("All")
		local filter_author, set_filter_author = editor.ui.use_state("All Authors")
		local filter_tag, set_filter_tag = editor.ui.use_state("All Tags")
		local install_status, set_install_status = editor.ui.use_state("")

		local authors = editor.ui.use_memo(internal.extract_authors, all_items)
		local tags = editor.ui.use_memo(internal.extract_tags, all_items)

		local type_options = editor.ui.use_memo(filters_ui.build_type_options, filter_overrides)
		local author_options = editor.ui.use_memo(filters_ui.build_author_options, authors, filter_overrides)
		local tag_options = editor.ui.use_memo(filters_ui.build_tag_options, tags, filter_overrides)

		local filtered_items = editor.ui.use_memo(
			internal.filter_items_by_filters,
			all_items,
			search_query,
			filter_type,
			filter_author,
			filter_tag,
			install_folder
		)

		local function on_install(item)
			handle_install(item, install_folder, all_items,
				function(message)
					set_install_status("Success: " .. message)
				end,
				function(message)
					set_install_status("Error: " .. message)
				end
			)
		end

		local content_children = {}

		table.insert(content_children, settings_ui.create({
			install_folder = install_folder,
			on_install_folder_changed = function(new_folder)
				set_install_folder(new_folder)
				editor.prefs.set(config.install_prefs_key, new_folder)
			end,
			labels = config.labels.settings
		}))

		table.insert(content_children, filters_ui.create({
			filter_type = filter_type,
			filter_author = filter_author,
			filter_tag = filter_tag,
			type_options = type_options,
			author_options = author_options,
			tag_options = tag_options,
			on_type_change = set_filter_type,
			on_author_change = set_filter_author,
			on_tag_change = set_filter_tag,
			labels = config.labels.filters,
		}))

		table.insert(content_children, search_ui.create({
			search_query = search_query,
			on_search = set_search_query,
			labels = config.labels.search,
		}))

		if #filtered_items == 0 then
			local message = config.empty_filter_message
			if search_query ~= "" then
				message = string.format(config.empty_search_message, search_query)
			end
			table.insert(content_children, editor.ui.label({
				text = message,
				color = editor.ui.COLOR.HINT,
				alignment = editor.ui.ALIGNMENT.CENTER
			}))
		else
			table.insert(content_children, widget_list_ui.create(filtered_items, {
				on_install = on_install,
				open_url = internal.open_url,
				is_installed = function(item)
					return installer.is_widget_installed(item, install_folder)
				end,
				labels = config.labels.widget_card,
			}))
		end

		if install_status ~= "" then
			table.insert(content_children, editor.ui.label({
				text = install_status,
				color = install_status:find("Success") and editor.ui.COLOR.TEXT or editor.ui.COLOR.ERROR,
				alignment = editor.ui.ALIGNMENT.CENTER
			}))
		end

		local buttons = {}
		if config.info_url then
			table.insert(buttons, editor.ui.dialog_button({
				text = config.info_button_label,
				result = INFO_RESULT,
			}))
		end
		table.insert(buttons, editor.ui.dialog_button({
			text = config.close_button_label,
			cancel = true
		}))

		return dialog_ui.build({
			title = config.title,
			children = content_children,
			buttons = buttons
		})
	end)

	local result = editor.ui.show_dialog(dialog_component({}))

	if result and result == INFO_RESULT then
		if config.info_url then
			internal.open_url(config.info_url)
		end
	end

	return {}
end


return M

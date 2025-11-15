local installer = require("asset_store.asset_store.installer")
local dependency_installer = require("asset_store.asset_store.dependency_installer")
local internal = require("asset_store.asset_store.asset_store_internal")
local dialog_ui = require("asset_store.asset_store.ui.dialog")
local filters_ui = require("asset_store.asset_store.ui.filters")
local search_ui = require("asset_store.asset_store.ui.search")
local settings_ui = require("asset_store.asset_store.ui.settings")
local widget_list_ui = require("asset_store.asset_store.ui.widget_list")

---@class asset_store.config
---@field title string The title of the asset store displayed in the dialog window
---@field store_url string The URL of the asset store JSON file containing items list
---@field install_prefs_key string The preferences key used to store and retrieve the installation folder path
---@field asset_type string? The type of assets in this store: "folder" (default) or "dependency"
---@field info_url string? The URL of the info page, if nil then info button will be hidden
---@field info_button_label string? The label text for the info button (default: "Info")
---@field close_button_label string? The label text for the close button (default: "Close")
---@field empty_search_message string? The message format to show when no items match search query (default: "No items found matching '%s'.")
---@field empty_filter_message string? The message to show when no items match current filters (default: "No items found matching the current filters.")
---@field labels table Table containing UI label overrides for different sections
---@field labels.search table? Overrides for search UI labels (search_label, search_title, search_tooltip)
---@field labels.filters table? Overrides for filter UI labels (type_label, author_label, tag_label, all_types, installed, not_installed, all_authors, all_tags)
---@field labels.widget_card table? Overrides for widget card labels (install_button, api_button, example_button, author_caption, installed_tag, tags_prefix, depends_prefix, size_separator, unknown_size, unknown_version)
---@field labels.settings table? Overrides for settings UI labels (install_label, install_title, install_tooltip)

---@class asset_store.item
---@field id string Unique identifier for the asset item
---@field version string Version string of the asset (e.g., "1.0", "2.3.1")
---@field title string Display name of the asset
---@field author string Author name of the asset
---@field description string Detailed description of the asset functionality
---@field api string? URL to API documentation for the asset
---@field author_url string? URL to author's profile or website
---@field image string? URL to the preview image for the asset
---@field manifest_url string URL to the asset's manifest JSON file
---@field zip_url string URL to download the asset as a ZIP file
---@field json_zip_url string URL to download the asset as base64-encoded JSON with file list
---@field sha256 string SHA256 hash of the ZIP file for integrity verification
---@field size number Size of the ZIP file in bytes
---@field depends string[] Array of dependency strings (format: "author:widget_id@version" or "author@widget_id" or "widget_id")
---@field tags string[] Array of tag strings for categorization and filtering


local M = {}

local INFO_RESULT = "asset_store_open_info"
local SUPPORT_RESULT = "asset_store_open_support"
local DEFAULT_TITLE = "Asset Store"
local DEFAULT_INFO_BUTTON = "Info"
local DEFAULT_CLOSE_BUTTON = "Close"
local DEFAULT_EMPTY_SEARCH_MESSAGE = "No items found matching '%s'."
local DEFAULT_EMPTY_FILTER_MESSAGE = "No items found matching the current filters."
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
		asset_type = input.asset_type or "folder", -- Default to "folder" if not specified
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


---Handle asset installation (widget or dependency)
---@param item table - Asset item to install
---@param install_folder string - Installation folder (for folder type assets)
---@param all_items table - List of all items for dependency resolution
---@param asset_type string - Type of asset: "folder" or "dependency"
---@param on_success function - Success callback
---@param on_error function - Error callback
local function handle_install(item, install_folder, all_items, asset_type, on_success, on_error)
	if asset_type == "dependency" then
		print("Installing dependency:", item.id)
		local success, message = dependency_installer.install_dependency(item, all_items)
		if success then
			print("Installation successful:", message)
			on_success(message)
		else
			print("Installation failed:", message)
			on_error(message)
		end
	else
		-- Default to folder type
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
			handle_install(item, install_folder, all_items, config.asset_type,
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
					if config.asset_type == "dependency" then
						return dependency_installer.is_dependency_installed(item)
					else
						return installer.is_widget_installed(item, install_folder)
					end
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

		-- Add support button
		table.insert(buttons, editor.ui.dialog_button({
			text = "Support",
			result = SUPPORT_RESULT,
		}))

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

	if result then
		if result == INFO_RESULT then
			if config.info_url then
				internal.open_url(config.info_url)
			end
		elseif result == SUPPORT_RESULT then
			internal.open_url("https://github.com/sponsors/insality")
		end
	end

	return {}
end


return M

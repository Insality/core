--- Module for handling dependency installation to game.project
--- Adds dependency URLs to game.project file instead of copying files

local M = {}


---Read and parse game.project file
---@return table|nil - Parsed project data as table with sections, or nil on error
local function read_game_project()
	local project_path = "game.project"
	local file = io.open(project_path, "r")
	if not file then
		print("Failed to open game.project file")
		return nil
	end

	local project_data = {}
	local current_section = nil

	for line in file:lines() do
		line = line:match("^%s*(.-)%s*$") -- Trim whitespace
		
		-- Skip empty lines and comments
		if line ~= "" and not line:match("^#") then
			-- Check for section header [section]
			local section = line:match("^%[([^%]]+)%]$")
			if section then
				current_section = section
				if not project_data[section] then
					project_data[section] = {}
				end
			else
				-- Parse key = value or key#index = value
				if current_section then
					local key, value = line:match("^([^=]+)=(.+)$")
					if key and value then
						key = key:match("^%s*(.-)%s*$") -- Trim key
						value = value:match("^%s*(.-)%s*$") -- Trim value
						
						-- Handle indexed keys like dependencies#0
						local base_key, index = key:match("^([^#]+)#(%d+)$")
						if base_key and index then
							local idx = tonumber(index)
							if not project_data[current_section][base_key] then
								project_data[current_section][base_key] = {}
							end
							project_data[current_section][base_key][idx] = value
						else
							project_data[current_section][key] = value
						end
					end
				end
			end
		end
	end

	file:close()
	return project_data
end


---Write game.project file from parsed data
---@param project_data table - Parsed project data with sections
---@return boolean - Success status
local function write_game_project(project_data)
	if not project_data then
		return false
	end

	local project_path = "game.project"
	local file = io.open(project_path, "w")
	if not file then
		print("Failed to write game.project file")
		return false
	end

	-- Sort sections to maintain order (project section should be early)
	local section_order = { "bootstrap", "script", "display", "android", "html5", "project", "input", "model", "native_extension", "render", "library" }
	local written_sections = {}

	-- Write known sections in order
	for _, section_name in ipairs(section_order) do
		if project_data[section_name] then
			file:write("[" .. section_name .. "]\n")
			local section = project_data[section_name]
			
			-- Write regular keys first
			local regular_keys = {}
			local indexed_keys = {}
			
			for key, value in pairs(section) do
				if type(value) == "table" then
					indexed_keys[key] = value
				else
					table.insert(regular_keys, key)
				end
			end
			
			table.sort(regular_keys)
			for _, key in ipairs(regular_keys) do
				file:write(key .. " = " .. tostring(section[key]) .. "\n")
			end
			
			-- Write indexed keys (like dependencies#0, dependencies#1, etc.)
			for key, indices in pairs(indexed_keys) do
				local sorted_indices = {}
				for idx, _ in pairs(indices) do
					table.insert(sorted_indices, idx)
				end
				table.sort(sorted_indices)
				for _, idx in ipairs(sorted_indices) do
					file:write(key .. "#" .. idx .. " = " .. tostring(indices[idx]) .. "\n")
				end
			end
			
			file:write("\n")
			written_sections[section_name] = true
		end
	end

	-- Write any remaining sections
	for section_name, section in pairs(project_data) do
		if not written_sections[section_name] then
			file:write("[" .. section_name .. "]\n")
			local regular_keys = {}
			local indexed_keys = {}
			
			for key, value in pairs(section) do
				if type(value) == "table" then
					indexed_keys[key] = value
				else
					table.insert(regular_keys, key)
				end
			end
			
			table.sort(regular_keys)
			for _, key in ipairs(regular_keys) do
				file:write(key .. " = " .. tostring(section[key]) .. "\n")
			end
			
			for key, indices in pairs(indexed_keys) do
				local sorted_indices = {}
				for idx, _ in pairs(indices) do
					table.insert(sorted_indices, idx)
				end
				table.sort(sorted_indices)
				for _, idx in ipairs(sorted_indices) do
					file:write(key .. "#" .. idx .. " = " .. tostring(indices[idx]) .. "\n")
				end
			end
			
			file:write("\n")
		end
	end

	file:close()
	return true
end


---Add a dependency URL to game.project
---@param url string - Dependency URL to add
---@return boolean - Success status
local function add_to_game_project(url)
	if not url or url == "" then
		return false
	end

	local project_data = read_game_project()
	if not project_data then
		return false
	end

	-- Ensure project section exists
	if not project_data.project then
		project_data.project = {}
	end

	-- Check if URL already exists
	if project_data.project.dependencies then
		for _, existing_url in pairs(project_data.project.dependencies) do
			if existing_url == url then
				print("Dependency already exists in game.project:", url)
				return true
			end
		end
	end

	-- Find next available index
	local next_index = 0
	if project_data.project.dependencies then
		for idx, _ in pairs(project_data.project.dependencies) do
			if idx >= next_index then
				next_index = idx + 1
			end
		end
	end

	-- Initialize dependencies table if needed
	if not project_data.project.dependencies then
		project_data.project.dependencies = {}
	end

	-- Add the dependency
	project_data.project.dependencies[next_index] = url
	print("Adding dependency to game.project:", url, "at index", next_index)

	return write_game_project(project_data)
end


---Install a dependency by adding URLs from content array to game.project
---@param item table - Dependency item with content array containing URLs
---@param all_items table|nil - Optional list of all items for dependency resolution (not used for dependencies)
---@return boolean, string - Success status and message
function M.install_dependency(item, all_items)
	if not item.content or type(item.content) ~= "table" or #item.content == 0 then
		return false, "Invalid dependency data: missing content array"
	end

	if not item.id then
		return false, "Invalid dependency data: missing id"
	end

	print("Installing dependency:", item.id)

	-- Add all URLs from content array to game.project
	for _, url in ipairs(item.content) do
		if type(url) == "string" and url ~= "" then
			local success = add_to_game_project(url)
			if not success then
				return false, "Failed to add dependency URL to game.project: " .. url
			end
		end
	end

	return true, "Dependency installed successfully. Please run 'Project ▸ Fetch Libraries' to update dependencies."
end


---Check if a dependency is already installed by checking if any URL from content exists in game.project
---@param item table - Dependency item with content array
---@return boolean - True if dependency is installed
function M.is_dependency_installed(item)
	if not item.content or type(item.content) ~= "table" or #item.content == 0 then
		return false
	end

	local project_data = read_game_project()
	if not project_data or not project_data.project or not project_data.project.dependencies then
		return false
	end

	-- Check if any URL from content array exists in game.project
	for _, url in ipairs(item.content) do
		if type(url) == "string" and url ~= "" then
			for _, existing_url in pairs(project_data.project.dependencies) do
				if existing_url == url then
					return true
				end
			end
		end
	end

	return false
end


return M


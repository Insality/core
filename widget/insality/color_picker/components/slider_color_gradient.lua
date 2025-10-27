local event = require("event.event")
local helper = require("druid.helper")

---@class widget.color_picker.slider: druid.widget
---@field root node
---@field text_slider_label druid.text
local M = {}
local COLOR_WHITE = vmath.vector4(1, 1, 1, 1)
local COLOR_BLACK = vmath.vector4(0, 0, 0, 1)


function M:init()
	self._min_value = 0
	self._max_value = 1
	self._format_string = "%.2f"
	self._value = 0

	self.root = self:get_node("root")
	self.panel_color = self:get_node("panel_color")
	self.panel_gradient = self:get_node("panel_gradient")

	self.text_slider_label = self.druid:new_text("text_slider_label")
	self.rich_input = self.druid:new_rich_input("rich_input")
	self.rich_input.input.on_input_select:subscribe(self._on_rich_text_input_select, self)
	self.rich_input.input.on_input_unselect:subscribe(self._on_rich_text_input_unselect, self)
	self.rich_input:set_allowed_characters("[%d.-]")

	self.slider = self.druid:new_slider("slider_pin", vmath.vector3(326, 0, 0), self._on_slider_pin_change)
	self.slider:set_input_node(self:get_node("slider"))

	self.on_value_change = event.create()
end


function M:set_text_label(text)
	self.text_slider_label:set_text(text)
end


function M:set_slider_mode(slider_mode)
	self._mode = slider_mode

	-- Initial state
	gui.set_enabled(self.panel_color, true)
	gui.set_enabled(self.panel_gradient, true)
	gui.play_flipbook(self.panel_color, "panel_rounded")
	gui.set_color(self.panel_gradient, COLOR_WHITE)
	gui.set_rotation(self.panel_gradient, vmath.vector3(0, 0, 180))
	gui.set_pivot(self.panel_gradient, gui.PIVOT_E)

	if self._mode == M.SLIDER_MODE.HUE then
		gui.set_enabled(self.panel_gradient, false)
		gui.play_flipbook(self.panel_color, "panel_hue_gradient")
		gui.set_color(self.panel_color, COLOR_WHITE)
	end

	if self._mode == M.SLIDER_MODE.SATURATION then
		-- Its default and used for colors
		gui.set_color(self.panel_gradient, COLOR_WHITE)
	end

	if self._mode == M.SLIDER_MODE.BRIGHTNESS then
		gui.set_color(self.panel_gradient, COLOR_BLACK)
	end

	if self._mode == M.SLIDER_MODE.OPACITY then
		gui.set_enabled(self.panel_color, false)
		gui.set_rotation(self.panel_gradient, vmath.vector3(0, 0, 0))
		gui.set_pivot(self.panel_gradient, gui.PIVOT_W)
	end

	return self
end


---@param color vector4
function M:set_color(color)
	self._color = color
	gui.set_color(self.panel_color, color)
	return self
end


---@param value number @[0..1]
function M:set_value(value)
	self._value = value
	self.slider:set(value, true)

	local value = self._min_value + (self._max_value - self._min_value) * value
	self.rich_input:set_text(string.format(self._format_string, value))

	return self
end


---Used for user input and set text values
---@param min number
---@param max number
function M:set_value_range(min, max, format_string)
	self._min_value = min
	self._max_value = max
	self._format_string = format_string

	return self
end


---@param value number @[0..1]
function M:_on_slider_pin_change(value)
	self.on_value_change:trigger(value)
end


function M:_on_rich_text_input_select()
	local raw_value = self._min_value + (self._max_value - self._min_value) * self._value
	if self._max_value <= 1 then
		raw_value = helper.round(raw_value, 2)
	else
		raw_value = helper.round(raw_value, 0)
	end

	self.rich_input.input:set_text(tostring(raw_value))
end


function M:_on_rich_text_input_unselect()
	local current_text = self.rich_input:get_text()
	local value = tonumber(current_text) or self._value
	local normalize_value = (value - self._min_value) / (self._max_value - self._min_value)
	self:set_value(normalize_value)
	self.on_value_change:trigger(normalize_value)
end


return M

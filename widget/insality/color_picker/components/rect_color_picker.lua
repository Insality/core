local color = require("druid.color")
local helper = require("druid.helper")
local event = require("event.event")

---@class widget.color_picker.rect_color_picker: druid.widget
---@field root node
---@field slider_pin node
---@field drag_zone node
---@field position vector3
---@field size vector3
---@field drag druid.drag
---@field on_value_change event function(self: rect_color_picker, x: number, y: number)
local M = {}


function M:init()
	self.root = self:get_node("root")
	self.drag_zone = self:get_node("drag_zone")
	self.slider_pin = self:get_node("slider_pin")
	self.position = gui.get_position(self.slider_pin)
	self.size = gui.get_size(self.drag_zone)

	self.drag = self.druid:new_drag(self.drag_zone, self._on_drag)
	self.drag.on_touch_start:subscribe(self._on_touch_start)

	self.on_value_change = event.create()
end


---@param hue number @[0..1]
function M:set_hue(hue)
	local r, g, b = color.hsb2rgb(hue, 1, 1)
	gui.set_color(self:get_node("color_node"), vmath.vector4(r, g, b, 1))
end


---@param saturation number
function M:set_saturation(saturation)
	local x = self.size.x * saturation - self.size.x / 2
	self.position.x = x
	gui.set_position(self.slider_pin, self.position)
end


---@param brightness number
function M:set_brightness(brightness)
	local y = self.size.y * brightness - self.size.y / 2
	self.position.y = y
	gui.set_position(self.slider_pin, self.position)
end


function M:_on_touch_start(touch)
	self.position = gui.screen_to_local(self.slider_pin, vmath.vector3(touch.screen_x, touch.screen_y, 0))
	self._start_drag_pos = vmath.vector3(self.position)
	gui.set_position(self.slider_pin, self.position)

	local saturation = (self.position.x + self.size.x/2) / self.size.x
	local brightness = (self.position.y + self.size.y/2) / self.size.y
	self.on_value_change:trigger(brightness, saturation)
end


function M:_on_drag(dx, dy, x, y)
	self.position.x = helper.clamp(self._start_drag_pos.x + x, -self.size.x/2, self.size.x/2)
	self.position.y = helper.clamp(self._start_drag_pos.y + y, -self.size.y/2, self.size.y/2)
	gui.set_position(self.slider_pin, self.position)

	local saturation = (self.position.x + self.size.x/2) / self.size.x
	local brightness = (self.position.y + self.size.y/2) / self.size.y
	self.on_value_change:trigger(brightness, saturation)
end


return M

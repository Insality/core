local color = require("druid.color")

local rect_color_picker = require("widget.Insality.color_picker.components.rect_color_picker")
local slider_color_gradient = require("widget.Insality.color_picker.components.slider_color_gradient")

---@class widget.color_picker: druid.widget
---@field root node
---@field text_hex druid.lang_text
---@field slider_1 widget.color_picker.slider
---@field slider_2 widget.color_picker.slider
---@field slider_3 widget.color_picker.slider
---@field slider_opacity widget.color_picker.slider
---@field rect_color_picker widget.color_picker.rect_color_picker
---@field rich_input_hex druid.rich_input
local M = {}
M.MODE = {
	HSB = "HSB",
	RGB = "RGB",
}

local PROP_SIZE_X = hash("size.x")


function M:init()
	self.root = self:get_node("root")
	self.blocker = self.druid:new_blocker(self.root)
	self._width = gui.get(self.root, PROP_SIZE_X)
	local h, s, b = color.rgb2hsb(1, 1, 1)
	self.color_hsb = vmath.vector3(h, s, b)
	self.alpha = 1

	self.container = self.druid:new_container(self.root)
	self.text_hex = self.druid:new_lang_text("text_hex", "ui_color_picker_hex")

	self.slider_1 = self.druid:new_widget(slider_color_gradient, "slider_color_1")
	self.slider_2 = self.druid:new_widget(slider_color_gradient, "slider_color_2")
	self.slider_3 = self.druid:new_widget(slider_color_gradient, "slider_color_3")
	self.slider_opacity = self.druid:new_widget(slider_color_gradient, "slider_color_opacity")
	self.rect_color_picker = self.druid:new_widget(rect_color_picker, "rect_color_picker")

	self.slider_1.on_value_change:subscribe(self._on_slider_1_change, self)
	self.slider_2.on_value_change:subscribe(self._on_slider_2_change, self)
	self.slider_3.on_value_change:subscribe(self._on_slider_3_change, self)
	self.slider_opacity.on_value_change:subscribe(self._on_slider_opacity_change, self)
	self.rect_color_picker.on_value_change:subscribe(self._on_rect_color_change, self)

	self.rich_input_hex = self.druid:new_rich_input("rich_input_hex")
	self.rich_input_hex:set_allowed_characters("[0123456789abcdefABCDEF#]")
	self.rich_input_hex.input.on_input_unselect:subscribe(self._on_rich_input_hex_change, self)
end


---@param color_hsb vector3
---@param alpha number|nil
function M:set_color(color_hsb, alpha)
	self.color_hsb = color_hsb
	self.alpha = alpha or self.alpha

	local r, g, b = color.hsb2rgb(color_hsb.x, color_hsb.y, color_hsb.z)
	local color_rgb = vmath.vector4(r, g, b, self.alpha)

	local hex_value = color.rgb2hex(color_rgb.x, color_rgb.y, color_rgb.z)
	self.rich_input_hex:set_text("#" .. hex_value)

	if self._mode == M.MODE.RGB then
		self.slider_1:set_value(color_rgb.x)
		self.slider_2:set_value(color_rgb.y)
		self.slider_3:set_value(color_rgb.z)
	end

	if self._mode == M.MODE.HSB then
		self.slider_1:set_value(self.color_hsb.x)
		self.slider_2:set_value(self.color_hsb.y)
		self.slider_3:set_value(self.color_hsb.z)

		local r, g, b = color.hsb2rgb(self.color_hsb.x, 1, 1)
		local color_slider = vmath.vector4(r, g, b, 1)
		self.slider_2:set_color(color_slider)
		self.slider_3:set_color(color_slider)
	end

	self.slider_opacity:set_value(self.alpha)

	self.rect_color_picker:set_hue(self.color_hsb.x)
	self.rect_color_picker:set_saturation(self.color_hsb.y)
	self.rect_color_picker:set_brightness(self.color_hsb.z)
end


function M:_select_mode(mode)
	self._mode = mode

	if mode == M.MODE.HSB then
		self.slider_1:set_text_label("Color")
		self.slider_2:set_text_label("Saturation")
		self.slider_3:set_text_label("Brightness")
		self.slider_opacity:set_text_label("Opacity")

		self.slider_1:set_slider_mode(slider_color_gradient.SLIDER_MODE.HUE)
		self.slider_2:set_slider_mode(slider_color_gradient.SLIDER_MODE.SATURATION)
		self.slider_3:set_slider_mode(slider_color_gradient.SLIDER_MODE.BRIGHTNESS)
		self.slider_opacity:set_slider_mode(slider_color_gradient.SLIDER_MODE.OPACITY)

		self.slider_1:set_value_range(0, 360, "%.0f")
		self.slider_2:set_value_range(0, 100, "%.0f%%")
		self.slider_3:set_value_range(0, 100, "%.0f%%")
		self.slider_opacity:set_value_range(0, 100, "%.0f%%")

		self:set_color(self.color_hsb, self.alpha)
	end

	if mode == M.MODE.RGB then
		self.slider_1:set_text_label("Red")
		self.slider_2:set_text_label("Green")
		self.slider_3:set_text_label("Blue")
		self.slider_opacity:set_text_label("Opacity")

		self.slider_1:set_slider_mode(slider_color_gradient.SLIDER_MODE.BRIGHTNESS)
		self.slider_1:set_color(vmath.vector4(1, 0, 0, 1))
		self.slider_2:set_slider_mode(slider_color_gradient.SLIDER_MODE.BRIGHTNESS)
		self.slider_2:set_color(vmath.vector4(0, 1, 0, 1))
		self.slider_3:set_slider_mode(slider_color_gradient.SLIDER_MODE.BRIGHTNESS)
		self.slider_3:set_color(vmath.vector4(0, 0, 1, 1))
		self.slider_opacity:set_slider_mode(slider_color_gradient.SLIDER_MODE.OPACITY)

		self.slider_1:set_value_range(0, 255, "%.0f")
		self.slider_2:set_value_range(0, 255, "%.0f")
		self.slider_3:set_value_range(0, 255, "%.0f")
		self.slider_opacity:set_value_range(0, 100, "%.0f%%")

		self:set_color(self.color_hsb, self.alpha)
	end
end


function M:_on_rect_color_change(brightness, saturation)
	self.color_hsb.y = saturation
	self.color_hsb.z = brightness
	self:set_color(self.color_hsb)
end


---@param value number @[0..1]
function M:_on_slider_1_change(value)
	if self._mode == M.MODE.RGB then
		local r, g, b = color.hsb2rgb(self.color_hsb.x, self.color_hsb.y, self.color_hsb.z)
		r = value
		local h, s, b = color.rgb2hsb(r, g, b)

		-- Don't override Hue if color is black
		if h == 0 then
			h = self.color_hsb.x
		end

		self.color_hsb.x = h
		self.color_hsb.y = s
		self.color_hsb.z = b

		self:set_color(self.color_hsb, self.alpha)
	end

	if self._mode == M.MODE.HSB then
		self.color_hsb.x = value
		self:set_color(self.color_hsb, self.alpha)
	end
end


---@param value number @[0..1]
function M:_on_slider_2_change(value)
	if self._mode == M.MODE.RGB then
		local r, g, b = color.hsb2rgb(self.color_hsb.x, self.color_hsb.y, self.color_hsb.z)
		g = value
		local h, s, b = color.rgb2hsb(r, g, b)

		-- Don't override Hue if color is black
		if h == 0 then
			h = self.color_hsb.x
		end

		self.color_hsb.x = h
		self.color_hsb.y = s
		self.color_hsb.z = b

		self:set_color(self.color_hsb, self.alpha)
	end

	if self._mode == M.MODE.HSB then
		self.color_hsb.y = value
		self:set_color(self.color_hsb, self.alpha)
	end
end


---@param value number @[0..1]
function M:_on_slider_3_change(value)
	if self._mode == M.MODE.RGB then
		local r, g, b = color.hsb2rgb(self.color_hsb.x, self.color_hsb.y, self.color_hsb.z)
		b = value
		local h, s, b = color.rgb2hsb(r, g, b)

		-- Don't override Hue if color is black
		if h == 0 then
			h = self.color_hsb.x
		end

		self.color_hsb.x = h
		self.color_hsb.y = s
		self.color_hsb.z = b

		self:set_color(self.color_hsb, self.alpha)
	end

	if self._mode == M.MODE.HSB then
		self.color_hsb.z = value
		self:set_color(self.color_hsb, self.alpha)
	end
end


---@param value number @[0..1]
function M:_on_slider_opacity_change(value)
	self.alpha = value
	self:set_color(self.color_hsb, self.alpha)
end


function M:_on_rich_input_hex_change()
	local current_value = self.rich_input_hex:get_text()
	local r, g, b = color.hex2rgb(current_value)
	local h, s, b = color.rgb2hsb(r, g, b)
	self.color_hsb.x = h
	self.color_hsb.y = s
	self.color_hsb.z = b

	self:set_color(self.color_hsb)
end


---@param value number
function M:on_set_alpha(value)
	self:set_color(self.color_hsb, value)
end


function M:_animate_highlight(node)
	gui.set_alpha(node, 1.3)
	gui.animate(node, "color.w", 1, gui.EASING_OUTSINE, 0.2)
end


function M:get_width()
	return self._width
end


return M

-- Title: Navigation Handler
-- Description: Adds support for navigating with keyboard and gamepad.
-- Author: NaakkaDev <https://github.com/NaakkaDev>
-- Widget: navigation_handler
-- Tags: input
-- Version: 1


local event = require("event.event")
local const = require("druid.const")


---Widget force handling GUI navigation via keyboard/gamepad.
---
---### Setup
---Loads the widget module:
---`local navigation_handler = require("druid.widgets.navigation_handler.navigation_handler")`
---
---Create the new widget instance:
---`self.nav = self.druid:new_widget(navigation_handler)`
---
---Set the first component instance (likely a button) to be selected. This is **required**.
---`self.nav:select_component(self.my_button)`
---
---
---### Example using the `on_select` event
---```
---local function on_select_btn(self, new, current)
---    gui.play_flipbook(new.node, "button_selected")
---    gui.play_flipbook(current.node, "button")
---end
---```
---With `self.nav.on_select:subscribe(on_select_btn)`
---
---
---### Notes
---- `on_select` event callback params: (self, component_instance, component_instance).
----   - **self** - Druid self context.
----   - **new** - The component that will be selected next.
----   - **current** - The component that is about to be de-selected.
---- Key triggers in `input.binding` should match your setup.
---- Used `action_id`'s are:' `key_up`, `key_down`, `key_left` and `key_right`.
---@class widget.navigation_handler: druid.widget
---@field on_select event fun(self, component_instance, component_instance) Triggers when a new component is selected. The first component is for the newly selected and the second is for the previous component.
---@field private _weight number The value used to control of the next button diagonal finding logic strictness.
---@field private _tolerance number Determines how lenient the next button finding logic is. Set larger value for further diagonal navigation.
---@field private _select_trigger hash Select trigger for the current component. Defaults to `druid.const.ACTION_SPACE`.
---@field private _selected_triggers table Table of action_ids that can trigger the selected component. Valid only for the current button when set.
---@field private _selected_component druid.component|druid.button|druid.slider Currently selected button instance.
---@field private _deselect_directions table<string> The valid "escape" direction of the current selection.
local M = {}

-- Components that support navigation.
local COMPONENTS = { "button", "slider" }


---The constructor for the navigation_handler widget.
function M:init()
    self._weight = 10
    self._tolerance = 250
    self._select_trigger = const.ACTION_SPACE
    self._selected_triggers = {}
    self._selected_component = nil
    self._deselect_directions = {}

    -- Events
    self.on_select = event.create()
end


---@private
---@param action_id hash Action id from on_input.
---@param action table Action from on_input.
---@return boolean is_consumed True if the input was consumed.
function M:on_input(action_id, action)
    -- Do nothing if the selected component is not set.
    if not self._selected_component then
        return
    end

    -- Trigger an action with the selected component, e.g. button click.
    if self:_action_id_is_trigger(action_id) and self:_selected_is_button() then
        ---@type druid.button
        local btn = self._selected_component
        local is_consume = false

        if action.pressed then
            btn.is_repeated_started = false
            btn.last_pressed_time = socket.gettime()
            btn.on_pressed:trigger(self:get_context(), btn, self)
            btn.can_action = true
            return is_consume
        end

        -- While hold button, repeat rate pick from input.repeat_interval
        if action.repeated then
            if not btn.on_repeated_click:is_empty() and btn.can_action then
                btn:_on_button_repeated_click()
                return is_consume
            end
        end

        if action.released then
            return btn:_on_button_release() and is_consume
        end

        return not btn.disabled and is_consume
    end

    local is_left = action_id == const.ACTION_LEFT
    local is_right = action_id == const.ACTION_RIGHT
    local is_up = action_id == const.ACTION_UP
    local is_down = action_id == const.ACTION_DOWN

    if action.pressed then
        ---@type druid.component|nil
        local component = nil

        if is_up then
            component = self:_find_next_button("up")
        elseif is_down then
            component = self:_find_next_button("down")
        elseif is_left then
            component = self:_find_next_button("left")
        elseif is_right then
            component = self:_find_next_button("right")
        end

        if component ~= nil and component ~= self._selected_component then
            return self:_on_new_select(component)
        end
    end

    -- Handle chaning slider values when pressing left or right keys.
    if (action.pressed or action.repeated)
        and self:_selected_is_slider()
    then
        local is_directional = is_left or is_right or is_up or is_down

        -- The action_id was not one of the directions so go no further.
        if not is_directional then
            return false
        end

        ---@type druid.slider
        local slider = self._selected_component
        local value = slider.value
        local new_value = 0.01
        local is_horizontal = slider.dist.x > 0
        local negative_value = is_left or is_down
        local positive_value = is_right or is_up

        -- Reteurn if a navigation should happen instead of a value change.
        if is_horizontal and (is_up or is_down) then
            return false
        elseif not is_horizontal and (is_left or is_right) then
            return false
        end

        -- Speedup when holding the button.
        if action.repeated and not action.pressed then
            new_value = 0.05
        end

        if negative_value then
            value = value - new_value
        elseif positive_value then
            value = value + new_value
        end

        slider:set(value)
    end

    return false
end


---Set the given `druid.component` as selected component.
---@param component druid.component Current druid component that starts as selected.
---@return widget.navigation_handler self
function M:select_component(component)
    self._selected_component = component

    -- Select the component if it's a button.
    if component.hover then
        component.hover:set_hover(true)
    end

    return self
end


---Sets a new weight value which affects the next button diagonal finding logic.
---@param new_value number
---@return widget.navigation_handler self
function M:set_weight(new_value)
    self._weight = new_value
    return self
end


---Sets a new tolerance value. Can be useful when scale or window size changes.
---@param new_value number How far to allow misalignment on the perpendicular axis when finding the next button.
---@return widget.navigation_handler self The current navigation handler instance.
function M:set_tolerance(new_value)
    self._tolerance = new_value
    return self
end


---Set input action_id name to trigger selected component by keyboard/gamepad.
---@param key hash The action_id of the input key. Example: "key_space".
---@return widget.navigation_handler self The current navigation handler instance.
function M:set_select_trigger(key)
    self._select_trigger = key
    return self
end


---Get current the trigger key for currently selected component.
---@return hash _select_trigger The action_id of the input key.
function M:get_select_trigger()
    return self._select_trigger
end


---Set the trigger keys for the selected component. Stays valid until the selected component changes.
---@param keys table|string|hash Supports multiple action_ids if the given value is a table with the action_id hashes or strings.
---@return widget.navigation_handler self The current navigation handler instance.
function M:set_temporary_select_triggers(keys)
    if type(keys) == "table" then
        for index, value in ipairs(keys) do
            if type(value) == "string" then
                keys[index] = hash(value)
            end
        end
        self._selected_triggers = keys
    elseif type(keys) == "string" then
        self._selected_triggers = { hash(keys) }
    else
        self._selected_triggers = { keys }
    end

    return self
end


---Get the currently selected component.
---@return druid.component|nil _selected_component Selected component, which often is a `druid.button`.
function M:get_selected_component()
    return self._selected_component
end


---Set the de-select direction for the selected button. If this is set
---then the next button can only be in that direction.
---@param dir string|table Valid directions: "up", "down", "left", "right". Can take multiple values as a table of strings.
---@return widget.navigation_handler self The current navigation handler instance.
function M:set_deselect_directions(dir)
    if type(dir) == "table" then
        self._deselect_directions = dir
    elseif type(dir) == "string" then
        self._deselect_directions = { dir }
    end

    return self
end


---Returns true if the currently selected `druid.component` is a `druid.button`.
---@private
---@return boolean
function M:_selected_is_button()
    return self._selected_component._component.name == "button"
end


---Returns true if the currently selected `druid.component` is a `druid.slider`.
---@private
---@return boolean
function M:_selected_is_slider()
    return self._selected_component._component.name == "slider"
end


---Find the best next button based on the direction from the currently selected button.
---@private
---@param dir string Valid directions: "top", "bottom", "left", "right".
---@return druid.component|nil
function M:_find_next_button(dir)
    -- Check if the deselect direction is set and
    -- the direction is different from it.
    if next(self._deselect_directions) ~= nil and not M._valid_direction(self._deselect_directions, dir) then
        return nil
    end

    local best_component, best_score = nil, math.huge
    local screen_pos = gui.get_screen_position(self._selected_component.node)

    -- Use the slider parent node instead of the pin node.
    if self._selected_component._component.name == "slider" then
        screen_pos = gui.get_screen_position(gui.get_parent(self._selected_component.node))
    end

    ---@type druid.component
    for _, input_component in ipairs(self._meta.druid.components_interest[const.ON_INPUT]) do
        -- GUI node of the component being iterated.
        local node = input_component.node

        -- If it is a slider component then use its parent node instead,
        -- since the pin node moves around.
        if input_component._component.name == "slider" then
            node = gui.get_parent(node)
        end

        -- Only check components that are supported.
        if input_component ~= self._selected_component and M._valid_component(input_component) then
            local pos = gui.get_screen_position(node)
            local dx, dy = pos.x - screen_pos.x, pos.y - screen_pos.y
            local valid = false
            local score = math.huge

            if dir == "right" and dx > 0 and math.abs(dy) <= self._tolerance then
                valid = true
                score = dx * dx + dy * dy * self._weight
            elseif dir == "left" and dx < 0 and math.abs(dy) <= self._tolerance then
                valid = true
                score = dx * dx + dy * dy * self._weight
            elseif dir == "up" and dy > 0 and math.abs(dx) <= self._tolerance then
                valid = true
                score = dy * dy + dx * dx * self._weight
            elseif dir == "down" and dy < 0 and math.abs(dx) <= self._tolerance then
                valid = true
                score = dy * dy + dx * dx * self._weight
            end

            if valid and score < best_score then
                best_score = score
                best_component = input_component
            end
        end
    end

    return best_component
end


---De-select the current selected component.
---@private
function M:_deselect_current()
    if self._selected_component.hover then
        self._selected_component.hover:set_hover(false)
    end
    self._selected_component = nil
    self._selected_triggers = {}

    -- The deselect direction was used so remove it.
    if self._deselect_directions then
        self._deselect_directions = {}
    end
end


---Check if the supplied action_id can trigger the selected component.
---@private
---@param action_id hash
---@return boolean
function M:_action_id_is_trigger(action_id)
    for _, key in ipairs(self._selected_triggers) do
        if action_id == key then
            return true
        end
    end

    return action_id == self._select_trigger
end


---Handle new selection.
---@private
---@param new druid.component Instance of the selected component.
---@return boolean
function M:_on_new_select(new)
    ---@type druid.component
    local current = self._selected_component

    -- De-select the current component.
    self:_deselect_current()
    self._selected_component = new

    --- BUTTON
    if new._component.name == "button" then
        -- Set the active button hover state.
        new.hover:set_hover(true)
    end

    --- SLIDER
    if new._component.name == "slider" then
        -- Check if the slider is horizontal, if so then
        -- the next component should be above or below of this one.
        if new.dist.x > 0 then
            self:set_deselect_directions({ "up", "down" })
        end

        -- Check if the slider is vertical, if so then
        -- the next component should be left or right of this one.
        if new.dist.y > 0 then
            self:set_deselect_directions({ "left, right" })
        end
    end

    --- EVENT
    self.on_select:trigger(self:get_context(), new, current)

    return false
end


---Helper method for checking if the given direction is valid.
---@private
---@param dirs table<string>
---@param dir string
---@return boolean
function M._valid_direction(dirs, dir)
    for _index, value in ipairs(dirs) do
        if value == dir then
            return true
        end
    end
    return false
end


---Helper method for checking iterating through components.
---Returns true if the given component is in the table of valid components.
---@private
---@param input_component druid.component
---@return boolean
function M._valid_component(input_component)
    local component_name = input_component._component.name
    for _index, component in ipairs(COMPONENTS) do
        if component_name == component then
            return true
        end
    end
    return false
end


return M

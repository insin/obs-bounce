--[[
obs-bounce v1.2 - https://github.com/insin/obs-bounce

Bounces a scene item around, DVD logo style or throw & bounce with physics.

MIT Licensed
]]--

local obs = obslua
local bit = require('bit')

-- type of bounce to be performed
local bounce_type = 'dvd_bounce'
--- name of the scene item to be moved
local source_name = ''

--- if true bouncing will auto start on scene change
local start_on_scene_change = false
--- the hotkey assigned to toggle_bounce in OBS's hotkey config
local hotkey_id = obs.OBS_INVALID_HOTKEY_ID
--- true when the scene item is being moved
local active = false
--- scene item to be moved
local scene_item = nil
--- original position the scene item was in before we started moving it
local original_pos = nil
--- width of the scene the scene item belongs to
local scene_width = nil
--- height of the scene the scene item belongs to
local scene_height = nil

-- DVD Bounce
--- number of pixels the scene item is moved by each tick
local speed = 10
--- if true the scene item is currently being moved down, otherwise up
local moving_down = true
--- if true the scene item is currently being moved right, otherwise left
local moving_right = true

-- Throw & Bounce
--- Range of initial horizontal velocity
local throw_speed_x = 100
--- Range of initial vertical velocity
local throw_speed_y = 50
--- current horizontal velocity
local velocity_x = 0
--- current vertical velocity
local velocity_y = 0
--- current maximum and minimal frames to wait before throwing again
local max_frames = 10
local min_frames = 60
--- frames to wait before throwing again. This variable is randomized or set using the max and min timer variables above. 
local wait_frames = 0
-- physics config
local gravity = 100           -- Gravity used to be 0.98. OBS didn't like using float so to still having the option to be accurate I instead increased the gravity by 100 times here. 
local air_drag = 0.99         -- Later in the code it gets divided by 100 again. Making sure the ratio stays the same while still giving people the option to change strength with accuracy
local ground_friction = 0.95
local elasticity = 0.8

--- find the named scene item and its original position in the current scene
local function find_scene_item()
   local source = obs.obs_frontend_get_current_scene()
   if not source then
      print('there is no current scene')
      return
   end
   scene_width = obs.obs_source_get_width(source)
   scene_height = obs.obs_source_get_height(source)
   local scene = obs.obs_scene_from_source(source)
   obs.obs_source_release(source)
   scene_item = obs.obs_scene_find_source(scene, source_name)
   if scene_item then
      original_pos = get_scene_item_pos(scene_item)
      return true
   end
   print(source_name..' not found')
   return false
end

function script_description()
   return 'Bounce a selected source around its scene.\n\n' ..
          'By Jonny Buchanan'
end

function script_properties()
   local props = obs.obs_properties_create()
   local source = obs.obs_properties_add_list(
      props,
      'source',
      'Source:',
      obs.OBS_COMBO_TYPE_EDITABLE,
      obs.OBS_COMBO_FORMAT_STRING)
   for _, name in ipairs(get_source_names()) do
      obs.obs_property_list_add_string(source, name, name)
   end
   local bounce_type = obs.obs_properties_add_list(
      props,
      'bounce_type',
      'Bounce Type:',
      obs.OBS_COMBO_TYPE_LIST,
      obs.OBS_COMBO_FORMAT_STRING)
   obs.obs_property_list_add_string(bounce_type, 'DVD Bounce', 'dvd_bounce')
   obs.obs_property_list_add_string(bounce_type, 'Throw & Bounce', 'throw_bounce')
   obs.obs_properties_add_int_slider(props, 'speed', 'DVD Bounce Speed:', 1, 30, 1)
   obs.obs_properties_add_int_slider(props, 'throw_speed_x', 'Max Throw Speed (X):', 1, 200, 1)
   obs.obs_properties_add_int_slider(props, 'throw_speed_y', 'Max Throw Speed (Y):', 1, 100, 1)
   obs.obs_properties_add_int(props, 'min_frames', 'Shortest time until next throw (seconds)', 1, 3600, 1)
   obs.obs_properties_add_int(props, 'max_frames', 'Longest amount of time until next throw(seconds)', 1, 3600, 1 )
   obs.obs_properties_add_int_slider(props, 'gravity', 'Strength of gravity (%) (Default is 100%)', 1, 300, 1)
   obs.obs_properties_add_bool(props, 'start_on_scene_change', 'Start on scene change')
   obs.obs_properties_add_button(props, 'button', 'Toggle', toggle)
   return props
end

function script_defaults(settings)
   obs.obs_data_set_default_string(settings, 'bounce_type', bounce_type)
   obs.obs_data_set_default_int(settings, 'speed', speed)
   obs.obs_data_set_default_int(settings, 'throw_speed_x', throw_speed_x)
   obs.obs_data_set_default_int(settings, 'throw_speed_y', throw_speed_y)
   obs.obs_data_set_default_int(settings, 'min_frames', min_frames)
   obs.obs_data_set_default_int(settings, 'max_frames', max_frames)
   obs.obs_data_set_default_int(settings, 'gravity', gravity)
end

function script_update(settings)
   local old_source_name = source_name
   source_name = obs.obs_data_get_string(settings, 'source')
   local old_bounce_type = bounce_type
   bounce_type = obs.obs_data_get_string(settings, 'bounce_type')
   speed = obs.obs_data_get_int(settings, 'speed')
   throw_speed_x = obs.obs_data_get_int(settings, 'throw_speed_x')
   throw_speed_y = obs.obs_data_get_int(settings, 'throw_speed_y')
   min_frames= obs.obs_data_get_int(settings, 'min_frames')
   max_frames = obs.obs_data_get_int(settings, 'max_frames')
   gravity = obs.obs_data_get_int(settings, 'gravity') / 100
   start_on_scene_change = obs.obs_data_get_bool(settings, 'start_on_scene_change')
   -- don't lose original_pos when config is changed
   if old_source_name ~= source_name or old_bounce_type ~= bounce_type then
      restart_if_active()
   end
end

function script_load(settings)
   hotkey_id = obs.obs_hotkey_register_frontend('toggle_bounce', 'Toggle Bounce', toggle)
   local hotkey_save_array = obs.obs_data_get_array(settings, 'toggle_hotkey')
   obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
   obs.obs_data_array_release(hotkey_save_array)
   obs.obs_frontend_add_event_callback(on_event)
end

function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        if start_on_scene_change then
            scene_changed()
        end
    end
    if event == obs.OBS_FRONTEND_EVENT_EXIT then
        if active then
            toggle()
        end
    end
end

function script_save(settings)
   local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
   obs.obs_data_set_array(settings, 'toggle_hotkey', hotkey_save_array)
   obs.obs_data_array_release(hotkey_save_array)
end

function script_tick(seconds)
   if active then
      if bounce_type == 'dvd_bounce' then
         move_scene_item(scene_item)
      elseif bounce_type == 'throw_bounce' then
         throw_scene_item(scene_item)
      end
   end
end

--- get a list of source names, sorted alphabetically
function get_source_names()
   local sources = obs.obs_enum_sources()
   local source_names = {}
   if sources then
      for _, source in ipairs(sources) do
         -- exclude Desktop Audio and Mic/Aux by their capabilities
         local capability_flags = obs.obs_source_get_output_flags(source)
         if bit.band(capability_flags, obs.OBS_SOURCE_DO_NOT_SELF_MONITOR) == 0 and
            capability_flags ~= bit.bor(obs.OBS_SOURCE_AUDIO, obs.OBS_SOURCE_DO_NOT_DUPLICATE) then
            table.insert(source_names, obs.obs_source_get_name(source))
         end
      end
   end
   obs.source_list_release(sources)
   table.sort(source_names, function(a, b)
      return string.lower(a) < string.lower(b)
   end)
   return source_names
end

--- convenience wrapper for getting a scene item's crop in a single statement
function get_scene_item_crop(scene_item)
   local crop = obs.obs_sceneitem_crop()
   obs.obs_sceneitem_get_crop(scene_item, crop)
   return crop
end

--- convenience wrapper for getting a scene item's pos in a single statement
function get_scene_item_pos(scene_item)
   local pos = obs.vec2()
   obs.obs_sceneitem_get_pos(scene_item, pos)
   return pos
end

--- convenience wrapper for getting a scene item's scale in a single statement
function get_scene_item_scale(scene_item)
   local scale = obs.vec2()
   obs.obs_sceneitem_get_scale(scene_item, scale)
   return scale
end

function get_scene_item_dimensions(scene_item)
   local pos = get_scene_item_pos(scene_item)
   local scale = get_scene_item_scale(scene_item)
   local crop = get_scene_item_crop(scene_item)
   local source = obs.obs_sceneitem_get_source(scene_item)
   -- displayed dimensions need to account for cropping and scaling
   local width = round((obs.obs_source_get_width(source) - crop.left - crop.right) * scale.x)
   local height = round((obs.obs_source_get_height(source) - crop.top - crop.bottom) * scale.y)
   return pos, width, height
end

--- move a scene item the next step in the current directions being moved
function move_scene_item(scene_item)
   local pos, width, height = get_scene_item_dimensions(scene_item)
   local next_pos = obs.vec2()

   if moving_right and pos.x + width < scene_width then
      next_pos.x = math.min(pos.x + speed, scene_width - width)
   else
      moving_right = false
      next_pos.x = math.max(pos.x - speed, 0)
      if next_pos.x == 0 then moving_right = true end
   end

   if moving_down and pos.y + height < scene_height then
      next_pos.y = math.min(pos.y + speed, scene_height - height)
   else
      moving_down = false
      next_pos.y = math.max(pos.y - speed, 0)
      if next_pos.y == 0 then moving_down = true end
   end

   obs.obs_sceneitem_set_pos(scene_item, next_pos)
end

--- throw a scene item and let it come to rest with physics
function throw_scene_item(scene_item)
   if velocity_x == 0 and velocity_y == 0 then
      wait_frames = wait_frames - 1
      if wait_frames == 0 then
         velocity_x = math.random(-throw_speed_x, throw_speed_x)
         velocity_y = -round(throw_speed_y * 0.5) - math.random(round(throw_speed_y * 0.5))
      end
      return
   end

   if velocity_y == 0 and velocity_x < 0.75 then
      velocity_x = 0
      wait_frames = math.random(min_frames, max_frames) * 60 
      return
   end

   local pos, width, height = get_scene_item_dimensions(scene_item)
   local next_pos = obs.vec2()

   local was_bottomed = pos.y == scene_height - height

   next_pos.x = pos.x + velocity_x
   next_pos.y = pos.y + velocity_y

   -- bounce off the bottom
   if next_pos.y >= scene_height - height then
      next_pos.y = scene_height - height
      if was_bottomed then
         velocity_y = 0
      else
         velocity_y = -(velocity_y * elasticity)
      end
   end

   -- bounce off the sides
   if next_pos.x >= scene_width - width or next_pos.x <= 0 then
      if next_pos.x <= 0 then
         next_pos.x = 0
      else
         next_pos.x = scene_width - width
      end
      velocity_x = -(velocity_x * elasticity)
   end

   if velocity_y ~= 0 then
      velocity_y = velocity_y + gravity
      velocity_y = velocity_y * air_drag
   end
   velocity_x = velocity_x * air_drag

   if next_pos.y == scene_height - height then
      velocity_x = velocity_x * ground_friction
   end

   obs.obs_sceneitem_set_pos(scene_item, next_pos)
end

--- toggle bouncing the scene item, restoring its original position if stopping
function toggle()
   if active then
      active = false
      velocity_x = 0
      velocity_y = 0
      if scene_item then
         obs.obs_sceneitem_set_pos(scene_item, original_pos)
      end
      scene_item = nil
      return
   end
   if not scene_item then find_scene_item() end
   if scene_item then
      active = true
      if bounce_type == 'throw_bounce' then
         velocity_x = math.random(-throw_speed_x, throw_speed_x)
         velocity_y = -math.random(throw_speed_y)
      end
   end
end

--- restores any currently-bouncing scene item to its original position and
--- restarts, if it was active.
function restart_if_active()
   local was_active = active
   if active then
      toggle()
   end
   find_scene_item()
   if was_active then
      toggle()
   end
end

--- restores any currently-bouncing scene item to its original position and
--- restarts bouncing on scene change.
function scene_changed()
   if active then
      toggle()
   end
   find_scene_item()
   toggle()
end

--- round a number to the nearest integer
function round(n)
   return math.floor(n + 0.5)
end

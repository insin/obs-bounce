--[[
obs-bounce v1.2 - https://github.com/insin/obs-bounce

Bounces a scene item around, DVD logo style or throw & bounce with physics.

To enable changing color on DVD bounces, add a Color Correction filter to the scene item.

MIT Licensed
]]--

local obs = obslua
local bit = require('bit')

-- Shared config
--- type of bounce to be performed (dvd_bounce or throw_bounce)
local bounce_type = 'dvd_bounce'
--- name of the scene item to be moved
local source_name = ''
--- if true bouncing will auto start and stop on scene change
local start_on_scene_change = true
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
local speed = 3
--- if true the scene item is currently being moved down, otherwise up
local moving_down = math.random() < 0.5
--- if true the scene item is currently being moved right, otherwise left
local moving_right = math.random() < 0.5
--- if true bounces will change the scene item's Color Correction filter's color_add setting
local dvd_bounces_change_color = true
--- the scene item's Color Correction filter, if it has one
local color_filter = nil
--- original color_add of the scene item's Color Correction filter before we started changing it
local original_color_add = nil
--- colors to cycle through on bounces (format: 0xBBGGRR)
local dvd_colors = {
   0xFFFE00, -- cyan
   0x0083FF, -- orange
   0xFF2600, -- blue
   0x01FAFF, -- yellow
   0x0026FF, -- red
   0x8B00FF, -- pink
   0xFF00BE  -- purple
}
--- set to true after we hit a corner, until the next bounce
local special_bounce = false
--- used to cycle through HSV colors, 0-360
local hsv_color_degrees = 0

-- Throw & Bounce
--- Range of initial horizontal velocity
local throw_speed_x = 100
--- Range of initial vertical velocity
local throw_speed_y = 50
--- current horizontal velocity
local velocity_x = 0
--- current vertical velocity
local velocity_y = 0
--- frames to wait before throwing again
local wait_frames = 0
-- physics config
local gravity = 0.98
local air_drag = 0.99
local ground_friction = 0.95
local elasticity = 0.8

--- find the named scene item in the current scene
--- store its original position and color_add, to be restored when we stop bouncing it
local function find_scene_item()
   local source = obs.obs_frontend_get_current_scene()
   if not source then
      return
   end

   scene_width = obs.obs_source_get_width(source)
   scene_height = obs.obs_source_get_height(source)
   local scene = obs.obs_scene_from_source(source)
   obs.obs_source_release(source)

   scene_item = obs.obs_scene_find_source(scene, source_name)
   if not scene_item then
      return
   end

   original_pos = get_scene_item_pos(scene_item)
   if bounce_type == 'dvd_bounce' and dvd_bounces_change_color then
      get_color_filter()
   end
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
   obs.obs_properties_add_bool(props, 'dvd_bounces_change_color', 'Change color on DVD bounce')
   obs.obs_properties_add_int_slider(props, 'throw_speed_x', 'Max Throw Speed (X):', 1, 200, 1)
   obs.obs_properties_add_int_slider(props, 'throw_speed_y', 'Max Throw Speed (Y):', 1, 100, 1)
   obs.obs_properties_add_bool(props, 'start_on_scene_change', 'Auto start/stop on scene change')
   obs.obs_properties_add_button(props, 'button', 'Toggle', toggle)
   return props
end

function script_defaults(settings)
   obs.obs_data_set_default_string(settings, 'bounce_type', bounce_type)
   obs.obs_data_set_default_bool(settings, 'dvd_bounces_change_color', dvd_bounces_change_color)
   obs.obs_data_set_default_int(settings, 'speed', speed)
   obs.obs_data_set_default_int(settings, 'throw_speed_x', throw_speed_x)
   obs.obs_data_set_default_int(settings, 'throw_speed_y', throw_speed_y)
end

function script_update(settings)
   local old_source_name = source_name
   source_name = obs.obs_data_get_string(settings, 'source')
   local old_bounce_type = bounce_type
   bounce_type = obs.obs_data_get_string(settings, 'bounce_type')
   speed = obs.obs_data_get_int(settings, 'speed')
   local old_dvd_bounces_change_color = dvd_bounces_change_color
   dvd_bounces_change_color = obs.obs_data_get_bool(settings, 'dvd_bounces_change_color')
   throw_speed_x = obs.obs_data_get_int(settings, 'throw_speed_x')
   throw_speed_y = obs.obs_data_get_int(settings, 'throw_speed_y')
   start_on_scene_change = obs.obs_data_get_bool(settings, 'start_on_scene_change')

   -- reconfigure and restart if the scene item name or bounce type has changed
   if old_source_name ~= source_name or old_bounce_type ~= bounce_type then
      restart_if_active()
   -- reconfigure if dvd_bounces_change_color changed and is relevant
   elseif bounce_type == 'dvd_bounce' and old_dvd_bounces_change_color ~= dvd_bounces_change_color then
      restore_original_color()
      if dvd_bounces_change_color then
         get_color_filter()
      else
         release_color_filter_reference()
      end
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
   if event == obs.OBS_FRONTEND_EVENT_SCRIPTING_SHUTDOWN then
      if active then
         stop()
      else
         release_color_filter_reference()
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

function get_color_filter()
   release_color_filter_reference()
   color_filter = get_filter_by_id(scene_item, 'color_filter')
   if color_filter then
      obs.script_log(obs.LOG_INFO, 'got color_filter reference')
      local settings = obs.obs_source_get_settings(color_filter)
      original_color_add = obs.obs_data_get_int(settings, 'color_add')
      obs.obs_data_release(settings)
   end
end

function release_color_filter_reference()
   if color_filter then
      obs.script_log(obs.LOG_INFO, 'releasing color_filter reference')
      obs.obs_source_release(color_filter)
      color_filter = nil
   end
end

function get_filter_by_id(scene_item, filter_id)
   local filters = obs.obs_source_enum_filters(obs.obs_sceneitem_get_source(scene_item))
   for _, filter in pairs(filters) do
      if obs.obs_source_get_unversioned_id(filter) == filter_id then
         return filter
      end
   end
   return nil
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
   local was_moving_right = moving_right
   local was_moving_down = moving_down

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

   -- change color on bounces
   local bounced = was_moving_right ~= moving_right or was_moving_down ~= moving_down
   if bounced then
      special_bounce = was_moving_right ~= moving_right and was_moving_down ~= moving_down
      if special_bounce then
         obs.script_log(obs.LOG_INFO, 'special bounce!')
         hsv_color_degrees = 0
      end
   end
   if dvd_bounces_change_color and color_filter and (bounced or special_bounce) then
      local settings = obs.obs_source_get_settings(color_filter)
      local next_color = nil
      if special_bounce then
         -- cycle through rainbow colors after hitting the corner
         local r, g, b = HSV(hsv_color_degrees / 360, 1, 1)
         r = math.floor(r * 255 + 0.5)
         g = math.floor(g * 255 + 0.5)
         b = math.floor(b * 255 + 0.5)
         next_color = bit.bor(bit.lshift(b, 16), bit.lshift(g, 8), r)
         hsv_color_degrees = hsv_color_degrees + 8
         if hsv_color_degrees > 360 then
            hsv_color_degrees = 0
         end
      else
         -- cycle through dvd_colors after single bounces
         local current_color = obs.obs_data_get_int(settings, 'color_add')
         for i, color in ipairs(dvd_colors) do
            if color == current_color then
               next_color = dvd_colors[(i % #dvd_colors) + 1]
               break
            end
         end
         if not next_color then
            next_color = dvd_colors[1]
         end
      end
      obs.obs_data_set_int(settings, 'color_add', next_color)
      obs.obs_source_update(color_filter, settings)
      obs.obs_data_release(settings)
   end

   obs.obs_sceneitem_set_pos(scene_item, next_pos)
end

--- throw a scene item and let it come to rest with physics
function throw_scene_item(scene_item)
   if velocity_x == 0 and velocity_y == 0 and wait_frames > 0 then
      wait_frames = wait_frames - 1
      if wait_frames == 0 then
         velocity_x = math.random(-throw_speed_x, throw_speed_x)
         velocity_y = -round(throw_speed_y * 0.5) - math.random(round(throw_speed_y * 0.5))
      end
      return
   end

   if velocity_y == 0 and velocity_x < 0.75 then
      velocity_x = 0
      wait_frames = 60 * 1
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

--- start bouncing the scene item
function start()
   if scene_item then
      obs.script_log(obs.LOG_INFO, 'starting bounce')
      active = true
      moving_down = math.random() < 0.5
      moving_right = math.random() < 0.5
      special_bounce = false
      if bounce_type == 'throw_bounce' then
         velocity_x = math.random(-throw_speed_x, throw_speed_x)
         velocity_y = -math.random(throw_speed_y)
      end
   end
end

--- stop bouncing the scene item, restoring its original position and color
function stop()
   if active then
      obs.script_log(obs.LOG_INFO, 'stopping bounce')
      active = false
      velocity_x = 0
      velocity_y = 0
      if scene_item then
         obs.script_log(obs.LOG_INFO, 'restoring original position')
         obs.obs_sceneitem_set_pos(scene_item, original_pos)
         if color_filter then
            restore_original_color()
            release_color_filter_reference()
            original_color_add = nil
         end
         scene_item = nil
      end
   end
end

--- toggle bouncing the scene item
function toggle()
   if active then
      stop()
   else
      if not scene_item then
         find_scene_item()
      end
      if scene_item then
         start()
      end
   end
end

--- restore the original color_add of a scene item's Color Correction filter
function restore_original_color()
   if color_filter then
      local settings = obs.obs_source_get_settings(color_filter)
      local current_color_add = obs.obs_data_get_int(settings, 'color_add')
      if current_color_add ~= original_color_add then
         obs.script_log(obs.LOG_INFO, 'restoring original color')
         obs.obs_data_set_int(settings, 'color_add', original_color_add)
         obs.obs_source_update(color_filter, settings)
      end
      obs.obs_data_release(settings)
   end
end

--- if it's active, restores the currently-bouncing scene item to its original position and color
--- and restarts bouncing
function restart_if_active()
   local was_active = active
   if active then
      stop()
   end
   find_scene_item()
   if was_active then
      start()
   end
end

--- on scene change, stops bouncing the scene item if it's currently bouncing. If the scene item is
--- present in the current scene, starts bouncing it.
function scene_changed()
   if active then
      stop()
   end
   find_scene_item()
   if scene_item then
      start()
   end
end

--- round a number to the nearest integer
function round(n)
   return math.floor(n + 0.5)
end

--- https://love2d.org/wiki/HSV_color
function HSV(h, s, v)
   if s <= 0 then return v,v,v end
   h = h*6
   local c = v*s
   local x = (1-math.abs((h%2)-1))*c
   local m,r,g,b = (v-c), 0, 0, 0
   if h < 1 then
      r, g, b = c, x, 0
   elseif h < 2 then
      r, g, b = x, c, 0
   elseif h < 3 then
      r, g, b = 0, c, x
   elseif h < 4 then
      r, g, b = 0, x, c
   elseif h < 5 then
      r, g, b = x, 0, c
   else
      r, g, b = c, 0, x
   end
   return r+m, g+m, b+m
end
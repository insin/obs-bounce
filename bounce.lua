local obs = obslua
local bit = require('bit')

--- number of pixels the scene item is moved by each tick
local speed = 10
--- name of the scene item to be moved
local source_name = ''
--- the hotkey assigned to toggle_bounce in OBS's hotkey config
local hotkey_id = obs.OBS_INVALID_HOTKEY_ID

--- true when the scene item is being moved
local active = false
--- if true the scene item is currently being moved down, otherwise up
local moving_down = true
--- if true the scene item is currently being moved right, otherwise left
local moving_right = true
--- scene item to be moved
local scene_item = nil
--- original position the scene item was in before we started moving it
local original_pos = nil
--- width of the scene the scene item belongs to
local scene_width = nil
--- height of the scene the scene item belongs to
local scene_height = nil

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
   obs.obs_properties_add_int(props, 'speed', 'Speed:', 1, 25, 1)
   local source = obs.obs_properties_add_list(
      props,
      'source',
      'Source:',
      obs.OBS_COMBO_TYPE_EDITABLE,
      obs.OBS_COMBO_FORMAT_STRING)
   for _, name in ipairs(get_source_names()) do
      obs.obs_property_list_add_string(source, name, name)
   end
   obs.obs_properties_add_button(props, 'button', 'Toggle', toggle)
   return props
end

function script_update(settings)
   speed = obs.obs_data_get_int(settings, 'speed')
   local old_source_name = source_name
   source_name = obs.obs_data_get_string(settings, 'source')
   -- don't lose original_pos when the speed config is changed!
   if old_source_name ~= source_name then
      source_name_changed()
   end
end

function script_load(settings)
   hotkey_id = obs.obs_hotkey_register_frontend('toggle_bounce', 'Toggle Bounce', toggle)
   local hotkey_save_array = obs.obs_data_get_array(settings, 'toggle_hotkey')
   obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
   obs.obs_data_array_release(hotkey_save_array)
end

function script_save(settings)
   local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
   obs.obs_data_set_array(settings, 'toggle_hotkey', hotkey_save_array)
   obs.obs_data_array_release(hotkey_save_array)
end

function script_tick(seconds)
   if active then
      move_scene_item(scene_item)
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

--- move a scene item the next step in the current directions being moved
function move_scene_item(scene_item)
   local pos = get_scene_item_pos(scene_item)
   local scale = get_scene_item_scale(scene_item)
   local crop = get_scene_item_crop(scene_item)
   local source = obs.obs_sceneitem_get_source(scene_item)
   -- displayed dimensions need to account for cropping and scaling
   local width = round((obs.obs_source_get_width(source) - crop.left - crop.right) * scale.x)
   local height = round((obs.obs_source_get_height(source) - crop.top - crop.bottom) * scale.y)

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

--- toggle moving the scene item, restoring its original position if stopping
function toggle()
   if active then
      active = false
      if scene_item then
         obs.obs_sceneitem_set_pos(scene_item, original_pos)
      end
      scene_item = nil
      return
   end
   if not scene_item then find_scene_item() end
   if scene_item then
      active = true
   end
end

--- restores any currently-bouncing scene item to its original position
function source_name_changed()
   local was_active = active
   if active then
      toggle()
   end
   find_scene_item()
   if was_active then
      toggle()
   end
end

--- round a number to the nearest integer
function round(n)
   return math.floor(n + 0.5)
end

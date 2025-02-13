# obs-bounce

OBS script to bounce a scene item around, DVD logo style, or a throw & bounce with physics.

> [!NOTE]
> Currently only works for top-level sources/groups in a scene.

## Usage

After installing the script, select a scene item by name, a type of bounce (DVD Bounce or Throw & Bounce), and configure the DVD Bounce movement speed or the maximum strength of the Throw & Bounce.

When the "Auto start/stop on scene change" option is enabled (enabled by default), the script will automatically start bouncing the scene item when you switch to the scene containing it, and restore its original state and stop bouncing it when you switch away to another scene.

Alternatively, you can click the Toggle button (or configure a Toggle Bounce hotkey) to manually control starting/stopping bouncing.

### DVD Bounce color changing

To enable changing the scene item's color on DVD bounces, add a Color Correction filter to the scene item. Set the filter's Color Add setting to the default color you want to use until the first bounce.

Perhaps something special will happen if you hit the corner?

## Demo

### DVD Bounce Mode

[![Example video of a background logo bouncing DVD logo style](https://img.youtube.com/vi/FbtzencagAM/sddefault.jpg)](https://www.youtube.com/watch?v=FbtzencagAM)

### Throw & Bounce Mode

[![Example video of a background logo being thrown and bouncing with physics](https://img.youtube.com/vi/TtZ3PpDrpIY/sddefault.jpg)](https://www.youtube.com/watch?v=TtZ3PpDrpIY)

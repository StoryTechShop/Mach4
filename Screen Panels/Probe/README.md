# Story Tech Shop Probe

![Probe Modal Window](docs/modal.png?raw=true "Probe Modal Window")

## Installation

* Place `StoryTechShopProbe.lua` in Mach4 base or profile `Modules` directory.
> **Note:** Alternatively, append cloned git repoistory path to lua paths in screen load event script.
```
package.path = package.path..";C:/StoryTechShop/Mach4/Screen Panels/Probe/?.lua"
```

### Modal Window
* Add a button to screen, with `click` event script:
```
stsProbe = require "StoryTechShopProbe"
stsProbe.Initialize()
stsProbe.UI.Panel:ShowModal()
```

### Screen Panel
* Add a lua panel, with event script:
> ```
> stsProbe = require "StoryTechShopProbe"
> stsProbe.Initialize(mcLuaPanel)
> ```
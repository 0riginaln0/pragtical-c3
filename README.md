# Features

- Syntax highlighting [language_c3.lua](https://github.com/pragtical/plugins/blob/master/plugins/language_c3.lua).
- Go-To & Find symbol [c3find.lua](https://github.com/0riginaln0/pragtical-c3/blob/main/c3find.lua)
  - Builds regex to find a function, macro, method, faultdef, const, enum, etc.
  - Performs Go-To when only one result is found
  - include & exclude search paths can be configured
- Formatter [c3fmt.lua](https://github.com/0riginaln0/pragtical-c3/blob/main/c3fmt.lua)
  - Format whole file
  - Format selection


# Installation

Place `c3find.lua`, `c3fmt.lua` and `init.lua` into c3 folder inside `.config/pragtical/plugins`.

- `.config/pragtical/plugins/c3/c3find.lua`
- `.config/pragtical/plugins/c3/c3fmt.lua`
- `.config/pragtical/plugins/c3/init.lua`

`c3fmt.lua` requires to configure a path for the [c3fmt](https://github.com/lmichaudel/c3fmt) binary.

Also place [language_c3.lua](https://github.com/pragtical/plugins/blob/master/plugins/language_c3.lua) file into the `.config/pragtical/plugins` for the syntax highlighting.

- `.config/pragtical/plugins/language_c3.lua`

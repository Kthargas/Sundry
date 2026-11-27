# Changelog

## 1.2.0 - 2026-11-27

- Flight time bar: counts down from the estimate already on the first flight of a route (the bar drains; past the estimate it shows +m:ss).
- Flight times: routes you have not flown yet get an estimate from their length on the flight map and the flights you measured on the same map, or from the usual flight speed before your first flight there (shown with ~). Measured times are now also stored by route ID, so they work in every client language.
- Sundry can ship flight times (FlightData.lua); your own measured times always win.
- `/sundry flights` (and a button on the Actions page) lists your measured routes, ready to be copied.

## 1.1.1 - 2026-11-27

- Micro menu: lined up buttons keep Blizzard's own distance (their art overlaps), so the bar is no longer longer than Blizzard's; the spacing slider adds to it.
- Bag bar: folding the bag slots away also hides the empty slot backgrounds the bar draws behind them.
- Bag windows: the title bar and the portrait can be dragged to move the window; the bag menu (sorting, bag settings) now opens with a right click there instead of a left click. Dragging the docked reagent bag moves the whole bag window.
- Reagent bag: its portrait icon is shown again when it is docked.
- Flight map: the tooltip of a destination shows the measured flight time.

## 1.1.0 - 2026-11-27

- Bars: the outer frame of the micro menu and the bag bar can be hidden (the buttons keep their own look). Hidden micro buttons leave no gap; the others line up left to right, right to left, top to bottom or bottom to top, with a spacing slider.
- Chat: the arrow key history is now Sundry's own and works without Alt.
- Automation: accepting and turning in quests are two switches. Choose the kinds of quests to accept (normal, repeatable, low level, group, dungeon and raid, PvP, timed, escort, shared by group members) and whether a reward to choose is left to you or the highest sell value is taken.
- Windows: the bag windows can be moved and keep their position.
- New page Bags: slots filled from the top left, reagent bag docked below the combined bag.
- Travel: a flight time bar shows the destination and the time left (each route is measured on its first flight).
- `/sundry inspect` also lists the parents of the frame under the mouse.

## 1.0.0 - 2026-11-27

- First version.
- Loot & merchants: fast loot, selling grey items, repairing (guild bank optional), Alt + click buys a stack, DELETE filled in, quality borders, bind on pickup confirmed when alone.
- Windows: drag Blizzard's windows, positions kept (all characters, per character or until logout), Ctrl + mouse wheel scales, Shift + Ctrl + right click resets.
- Bars: micro menu and bag bar without frames or with a thin line, fading, hidden micro buttons, arrow to fold the bag slots away, red error messages filtered, action button texts, bar art, out of range colour, class coloured health bars, portrait combat text.
- Tooltip: at the mouse, hidden in combat, class colours, the unit's target, health bar, item and spell IDs.
- Chat: arrow keys walk through sent messages, the history survives a reload, clickable links, short channel names, hidden buttons, input box on top, more lines, copy window.
- Automation (off by default): quests, gossip, duels, guild invites, group invites from friends, resurrections, "Take all" for mail, "Learn all" at trainers.
- Camera & sound: larger camera distance, screenshot on level up, muted sounds, /rl.
- Options in the game's settings window, minimap button and addon compartment entry, own settings per character, English and German.

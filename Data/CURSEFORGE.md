# Summary

The world map, smooth again on a controller. No more hitch when it opens or closes: install it and explore.

# Categories

- Map & Minimap
- Quests & Leveling

# License

GNU General Public License version 3 (GPLv3)

# Description

With the controller UI on, the world map hitches each time it opens or closes: a tenth to a third of a second, more with a long quest log.

The cause is in the game: as it lets go of the map's quest pins, it rebuilds the whole quest list once for each pin. With 20 quests on the map, that's 20 rebuilds in one frame.

[![Support me on Ko-fi](https://images.weserv.nl/?url=storage.ko-fi.com/cdn/kofi5.png&h=36)](https://ko-fi.com/artisangw)

This addon stops those rebuilds. The only thing they did was clear the quest list's highlight when the cursor leaves a quest pin, and the addon still clears it. The map looks and works exactly the same, just without the hitch.

## Measured

The longest frame each time the map opened or closed, with 20 quests on the map:

| | Without | With Gamepad Fast Map |
|---|---|---|
| Closing the map | 110 ms | 10 ms |
| Opening it again | 155 ms | 20 ms |
| First opening after a reload | 370 ms | 209 ms |
| Quest list rebuilds per close | 20 | 0 |

It's a simple tool with no dependencies:
- On as soon as it's installed
- Turn it off in Options > AddOns > Gamepad Fast Map, or /gpfm

## Goes well with
- [Gamepad Camera Offset](https://www.curseforge.com/projects/1818297): moves the camera over your shoulder.
- [Gamepad Reticle Customizer](https://www.curseforge.com/projects/1818557): turns the reticle into an icon on your target: a player's class or faction, an NPC's job.
- [Gamepad Reticle On Target](https://www.curseforge.com/projects/1819101): puts the controller's reticle on your target's nameplate.

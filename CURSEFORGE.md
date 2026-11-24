**Summary:** Opens and closes the world map without its hitch on the controller UI. Install it and the map is smooth again.

## Description

With the controller UI on, the world map hitches each time it opens or closes: a tenth to a third of a second, more with a long quest log.

The cause is in the game: as it lets go of the map's quest pins, it rebuilds the whole quest list once for each pin. With 20 quests on the map, that's 20 rebuilds in one frame.

This addon has the quest list rebuild only when it's needed, when the cursor leaves a quest pin. The map looks and works exactly the same, just without the hitch.

It's a simple tool with no dependencies:
- On as soon as it's installed
- Turn it off in Options > AddOns > Gamepad Fast Map, or /gfm

## Goes well with
- [Gamepad Camera Offset](https://www.curseforge.com/projects/1818297): moves the camera over your shoulder.
- [Gamepad Reticle Customizer](https://www.curseforge.com/projects/1818557): turns the reticle into an icon on your target: a player's class or faction, an NPC's job.
- [Gamepad Reticle On Target](https://www.curseforge.com/projects/1819101): puts the controller's reticle on your target's nameplate.

The code is free to copy, as long as you credit it.

[![Support me on Ko-fi](https://images.weserv.nl/?url=storage.ko-fi.com/cdn/kofi5.png&h=36)](https://ko-fi.com/artisangw)

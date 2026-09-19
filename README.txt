AutoCook Return Fix v1.0.0
==========================

What it does
------------
- Improves AutoCook "put items back" when cooking finishes.
- Tracks source container by type + parent tile (helps multiplayer).
- Tracks the pot/pan if AutoCook pulled it from furniture.
- Returns items STILL in your inventory (leftover stacks, pot, unused pulls).
- Cannot return food fully used in the meal (that is expected).

Install / test
--------------
1. Mod is at: F:\Grok\Nipsy\AutoCookReturnFix
   Copied to: X:\Users\USER\Zomboid\mods\AutoCookReturnFix
2. Enable AFTER AutoCook:
   - AutoCook
   - AutoCookReturnFix
3. For dedicated server: add Mod ID AutoCookReturnFix to Mods= (no extra Workshop ID
   unless you upload it). Clients need the same local/workshop copy for MP.
4. Join, cook with ingredients in a fridge/crate (leave fridge open / nearby).
5. Watch console / DebugLog for lines starting with [AutoCookReturnFix]

Verbose logging
---------------
common/media/lua/client/AutoCookReturnFix.lua
  AutoCookReturnFix.Verbose = true   -- testing
  AutoCookReturnFix.Verbose = false  -- after test

Expected log when it works
--------------------------
[AutoCookReturnFix] track 'Pot' ...
[AutoCookReturnFix] track 'Tomato' ...
[AutoCookReturnFix] stopAutoCook — attempting returns
[AutoCookReturnFix] queue transfer 'Pot' -> ...
[AutoCookReturnFix] skip 'Tomato' (consumed or not in inventory)   <-- normal if fully used
[AutoCookReturnFix] queue transfer 'Tomato' -> ...               <-- leftover stack

Tips
----
- Keep the fridge/crate open or stand next to it when AutoCook finishes.
- Fully eaten ingredients will never reappear in the fridge.

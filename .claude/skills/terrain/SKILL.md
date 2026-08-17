---
name: terrain
description: Sculpt, carve, blend, restyle, and verify coherent Roblox voxel terrain with Bricklayer tools. Use for mountains, hills, islands, lakes, rivers, caves, ramps, ground, snowcaps, terrain cleanup, or any request to build or improve a natural landscape.
---

# /terrain — sculpt and verify a landform

Input: the requested feature, approximate location/size, and optional materials or style.
If dimensions are missing, inspect the place and choose conservative values that fit the existing build.

## Orient

1. Call `bl_status`; require an edit-mode Studio connection.
2. Inspect nearby structure with `bl_get_tree` and spatial objects with `bl_get_bounds`.
3. Sample the intended region with `bl_terrain_heights` to learn the current ground and avoid burying builds.
4. Before a large or destructive pass, call `bl_checkpoint` when available.

## Build

1. Establish connected mass first:
   - Start with a wide, low `bl_terrain_fill`.
   - Add progressively narrower/taller fills on the same `(x,z)` column, or shift the column smoothly for a ridge.
   - Overlap each new fill's vertical range with the previous top by 30–40% of the new fill's height.
   - Never assemble one intended landform from separated floating balls or cylinders.
2. Use blocks/wedges for foundations and slopes; balls for rounded mass; cylinders sparingly for columns/wells; Air to carve.
3. Run `bl_terrain_smooth` over each connected group. Keep each smoothing region within the tool's voxel cap and avoid water unless it should also soften.
4. Apply material changes after the silhouette is sound:
   - `bl_terrain_replace` for snowcaps, beaches, strata, or retheming.
   - `bl_terrain_set_material_color` only when a global material color change is intended.
   - Put Water in a separate fill and tune Terrain water properties with `bl_set_properties`.

## Verify and iterate

1. Re-sample with `bl_terrain_heights`. A coherent landform has a gradual rise/fall without unexpected `false` gaps or abrupt seams.
2. Correct only the failing area, then sample again. Do not keep adding decorative fills to hide a structural gap.
3. Frame the result with `bl_frame_camera` and call `bl_screenshot` for the user.
4. Do not claim the screenshot “looks good”: on this chat wire it is visible to the user, not the model. Report verified dimensions, heights, materials, and whether numeric continuity passed.
5. Finish with the exact region changed and any tradeoffs or areas the user should inspect.


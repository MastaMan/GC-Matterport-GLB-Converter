# GC Matterport GLB Converter 1.1.2

2026-09-29

- Fixed AO assignment when multiple materials share one Bitmap: the target material receives a separate map, while already unique maps are reused on subsequent bakes. Other slots retain their original map.
- LOD and Materials context menus now operate on the current selection, without cursor-coordinate or row-height calculations. Right-click preserves the selection; no selection means no menu. Unwrap preview is available only for a single selected material.

Verified in 3ds Max 2027: isolated AO assignment tests and converter script loading. Menu behavior on previously affected computers still needs confirmation.

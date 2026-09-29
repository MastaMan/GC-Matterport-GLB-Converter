# GC Matterport GLB Converter 1.2.0

- **Fixed:** Preview Unwrap resolves the selected material when the command is invoked.
- **Added:** Override Color applies an AO color to selected material IDs through an OK/Cancel dialog.
- **Changed:** Default Corona AO occluded color is RGB 140, 140, 140; saved colors are preserved.
- **Added:** Passes and Size menus include 10, 20, 25 and Custom dialogs.
- **Added:** Material rows show their LOD0-LOD3 prefix, including mixed LOD selections.
- **Added:** Flatten Ch: 2 generates and packs UVs for selected material IDs, including objects without channel 1.
- **Changed:** Transfer IDs copies and packs only selected material IDs while preserving other channel 2 UVs.
- **Improved:** UV packing runs without opening Edit UVWs or rotating clusters; summaries show elapsed seconds.

Tested in 3ds Max 2027: script loading, dialog confirmation/cancellation, selected-ID UV transfer and flatten, preservation of other IDs, and flatten without channel 1. MaxPkg archive validation and source hash checks completed. Clean installation/update/uninstall were not repeated for this release.

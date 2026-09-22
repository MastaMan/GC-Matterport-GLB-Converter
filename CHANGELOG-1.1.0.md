# GC Matterport GLB Converter 1.1.0

2026-09-22

- LOD statistics now report evaluated triangle counts (Tris), including Editable Poly objects.
- Moved Bottom, Center, Top and Move to Center Scene into Exporter between Corona AO Settings and Render AO; removed the redundant Set Pivot label.
- Increased the main window height to 740 pixels while retaining its 360-pixel width.
- Select All beside Transfer All IDs selects every material ID in the Materials list.
- Removed the optional fileType keyword from AO color-conversion calls while retaining output-state restoration.
- Add to LOD now uses a standard Yes/No confirmation instead of requiring typed OK.
- AO assignment preserves existing glTF materials and shared references, reuses the existing AO Bitmap, and refreshes its file on repeated bakes.
- Open Scene Folder in the LOD context menu opens the saved MAX scene folder and handles unsaved or unavailable paths.
- AO defaults to 1024 for every LOD and material. Explicit resolution overrides and separate export texture limits remain unchanged.
- Assign Default Materials starts with one Material ID instead of six.

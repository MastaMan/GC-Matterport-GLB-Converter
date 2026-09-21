# Release Process

This project currently releases by updating the script version, committing to
`main`, and pushing to `origin/main`. Git tags are not used in the existing
history. These steps describe a release; reviewing or editing this document
does not itself request version changes, commits, or publication.

## Version Selection

Before changing `VERSION`, decide the release number intentionally.

- If the user explicitly names a version, use that exact version.
- If the user corrects the version after a release, make a follow-up release
  commit with the corrected version unless they explicitly ask to rewrite
  history.
- Do not mechanically increment the last patch number just because the previous
  release used that pattern.
- Use a patch release, for example `1.1.9` -> `1.1.10`, for small fixes and
  internal improvements.
- Use a minor release, for example `1.1.9` -> `1.2.0`, when behavior changes
  how external systems consume output, GLB assets, texture paths, file
  naming, or other integration contracts.
- When unsure whether the change is patch or minor, stop and ask the user
  before editing files or committing.

## Steps

1. Check the current state:

```powershell
git -c safe.directory=[...CURDIR...]/GC-Matterport-GLB-Converter status --short --branch
git -c safe.directory=[...CURDIR...]/GC-Matterport-GLB-Converter log --oneline --decorate -5
```

2. Update `GC-Matterport-GLB-Converter.ms`:

- Change `[INFO] VERSION` to the new version.
- Add a changelog block near the top, for example:

```ini
[1.0.7]
+ Added: ...
* Improved: ...
- BugFix: ...
* Changed: ...
- Deleted: ...
```

3. Verify the runtime files in the script header's [FILES] section. Each entry
is a filename followed by `=`; values are unused. Keep this single manifest in
sync with the files shipped at the update endpoint. The updater reads its own
manifest with getINISetting and, for a newer script containing [FILES], uses
that release's manifest so newly added dependencies are included. The entry
script must be listed and is replaced last. Older installed updaters that do
not read [FILES] still require a one-time complete package update to acquire
new dependencies.

- Store both viewers as ZIP archives only. Do not commit extracted model-viewer/
  or playcanvas-viewer/, staged models, generated GLB/AO files, logs, or temporary
  ._viewer_*, ._pcviewer_*, and ._update_* files. Preserve the .gitignore rules.
- Check archive contents against GCMatterportViewerFiles and
  GCMatterportPCViewerFiles; keep decoder/runtime assets and licenses included.
  PlayCanvas includes only the Artist Workshop HDRI and the agreed defaults.
- Preserve [INFO] NAME = GC Matterport GLB Converter: the updater checks identity.
  VERSION must increase for an existing installation to offer an update.
- Both the converter updater and Google's separate viewer updater use
  https://raw.githubusercontent.com/MastaMan/GC-Matterport-GLB-Converter/main/,
  matching origin. Verify every [FILES] entry at that endpoint before release.
  The Google viewer button installs the project's patched archive, preserving
  its local defaults and wheel zoom changes.
- Updates download every listed file and validate both viewer archives before
  stopping converter-owned preview servers. Existing files and both extracted
  viewer folders remain backed up until the complete transaction succeeds.
  A failure restores them; failed rollback retains recovery files in staging.
- GC-Preview-Server.exe is precompiled with the .NET Framework 64-bit C# compiler,
  referencing System.Drawing.dll and System.Web.Extensions.dll. It is not built
  on client startup or update. The .cs source is included because [FILES] lists
  it, but execution requires the .exe and GC-Preview-Screenshot.js.
- Installations still using the old MastaArt endpoint cannot discover this fix
  through that unavailable endpoint. Distribute this corrected package once;
  later higher-version releases use the new manifest-based updater.

4. Run release checks:

```powershell
git -c safe.directory=[...CURDIR...]/GC-Matterport-GLB-Converter diff --check
rg -n -- "AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|aws_secret_access_key|aws_access_key_id|AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID|secretAccessKey|accessKeyId" GC-Matterport-GLB-Converter.ms denoise.bat gltfpack_webgl.bat
```

`rg` should return no matches for credential patterns.

5. Commit the release:

```powershell
git -c safe.directory=[...CURDIR...]/GC-Matterport-GLB-Converter add GC-Matterport-GLB-Converter.ms <other changed files>
git -c safe.directory=[...CURDIR...]/GC-Matterport-GLB-Converter commit -m "1.0.7"
```

Run commands from the actual project checkout; replace [...CURDIR...] with its
parent directory. Stage only reviewed release files by explicit path. Existing
history uses descriptive commit messages; a version-only message above is an
example, not an established requirement. Do not create a tag unless requested.

6. When publishing is requested, verify git remote -v and the target branch
before pushing to origin/main. Resolve any approval block before sending:


```powershell
git -c safe.directory=[...CURDIR...]/GC-Matterport-GLB-Converter push origin main
```

7. Confirm the release:

```powershell
git -c safe.directory=[...CURDIR...]/GC-Matterport-GLB-Converter status --short --branch
git -c safe.directory=[...CURDIR...]/GC-Matterport-GLB-Converter log --oneline --decorate -3
```

Expected result:

- `main` is synchronized with `origin/main`.
- The intended release commit is at remote refs/heads/main (verify with git ls-remote origin refs/heads/main).
- The working tree is clean.

## Notes

- Do not add per-user/per-machine INI settings to git; *.ini is ignored.
- Keep local settings files with credentials out of credential scans and out of
  commits.
- If `git push` prints a `credential-manager-core` warning but still updates
  `origin/main`, treat the push as successful and verify with `git status`.

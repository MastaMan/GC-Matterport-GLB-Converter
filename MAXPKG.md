# MaxPkg build

The original converter remains the runtime entry. Sources and the two viewer ZIPs remain in this repository. The official packager and both standard hooks are pinned to maxpkg-dev/max-dev-tool commit `1281d283b30d885382c12804ca12da3f092d888b`.

1. The repository includes the unpacked, allowlisted viewer resources in `maxpkg-assets`; these are standard MaxPkg Files List inputs, not ignored temporary files. No PowerShell preparation is required for the normal build.
2. Run the project-root `maxpkg-packager.ms` in 3ds Max, reload project settings and validate. Retain the configured package identity for future releases.
3. Use the official Build MZP action (or its `MaxPkgPackerApi.build()` API after successful validation). Output belongs in `dist`. Do not manually create or rename the MZP.

The configured license category is Free. The conservative minimum is 3ds Max 2027; older versions have not been verified. The official packager calculates the maximum supported year itself. Runtime dependencies such as renderer plugins and a browser with WebGL remain external.

## Runtime layout

- Entry compilation is disabled intentionally: About and the existing updater read the text `.ms` INI header, and restart targets the `.ms` entry.
- The official packager excludes ZIP inputs. `maxpkg-assets` is remapped to the package root, supplying complete `model-viewer` and `playcanvas-viewer` runtime folders on first launch. Both existing EnsureViewer functions accept these installed folders. No network download is required to install the bundled viewers.
- The original ZIP files stay in the source repository. Converter updates still read `[FILES]`, download the ZIPs and replace both viewer folders transactionally. Packaging does not replace the existing updater.
- Both standard hooks are unchanged upstream files. The focused `maxpkg-cleanup.ms` custom uninstall hook stops only processes owned by the verified installed package path and removes runtime callbacks/UI only when that package is the loaded converter. The standard uninstaller owns package, macro and icon removal.
- Package-owned user INIs are created beside the installed entry and are never build inputs. Reinstall/update does not ship defaults over these files. Scene properties, exported assets and screenshots stay where the converter already stores them.
- Height-to-Normal sources remain separate and are not installed or registered by this package.

## Exclusions and verification

No user INIs, scenes, live sessions, exported GLBs, preview caches, logs, `.git`, `.agents`, build tooling or previous MZPs belong in the payload. Viewer files are prepared from the ZIP allowlists, never copied from a running preview folder.

When viewer archives change, refresh the matching files in `maxpkg-assets`, then reload and validate the official packager. `Prepare-MaxPkg.ps1` is an optional maintainer convenience for that refresh and for rebasing saved absolute paths after moving a checkout. It does not build or replace the official packager. The upstream packager stores absolute source paths: in a different checkout location these paths must be reselected through its Files and Setup UI, or rebased with the optional helper. Check the built archive for both hooks, entry, all runtime files, icon and manifests. Real clean-install, package update and uninstall tests are distinct from static archive inspection and must be performed in a suitable test environment. Never replace live converter global functions with test mocks.
## Verification of this package

The official MaxPkg Packager 1.2.1 API in 3ds Max 2027 successfully completed ping, schema inspection, reload, validation and build. The MZP contains 53 files: 44 runtime inputs, both standard hooks, focused cleanup, icon and five generated metadata/launch files. All 48 copied file hashes match the source inputs. The updated M-and-cube SVG is included. No developer checkout paths occur in the packaged MaxScript/manifests.

The source entry launched successfully in an empty Max scene; the scene remained empty and unmodified. The custom cleanup compiles and refuses execution outside an installed package, before any cleanup actions. Clean installation, launch from an installed GUID folder, installed-package update and actual uninstall have not been tested. The current manifest uses the official packager's calculated 2027 maximum, as its API does not expose an open-ended range; no future-version compatibility is claimed.
## GitHub release helper

Run release-github.bat --check-only to validate the highest numeric MZP version in dist and inspect GitHub without publication. Both release-github.bat and release-github.ps1 are required. Normal mode verifies the package identity/version against this project, requires the release source commit to be clean and pushed, then asks for Y before creating a GitHub Release. Existing releases are left unchanged. This action is separate from committing or pushing source code.

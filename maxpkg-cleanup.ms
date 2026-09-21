-- Focused MaxPkg cleanup. The official hook owns file, macro and icon removal.
(
    local pathClass = dotNetClass "System.IO.Path"
    local packageFolder = pathClass.GetFullPath (getFilenamePath (getThisScriptFileName()))
    local manifestFile = packageFolder + "manifest.ini"
    if (not doesFileExist manifestFile) do throw "Run cleanup only through the installed MaxPkg package."
    local packageIdentity = getINISetting manifestFile "package" "packageGuid"
    local parsedIdentity = try ((dotNetObject "System.Guid" packageIdentity).ToString()) catch (undefined)
    if (parsedIdentity == undefined) do throw "Invalid MaxPkg package identity."
    local expectedFolder = pathClass.GetFullPath ((getDir #temp) + "\\" + packageIdentity + "\\")
    if ((toLower packageFolder) != (toLower expectedFolder)) do throw "Cleanup refused outside the verified MaxPkg runtime folder."
    if ((getINISetting manifestFile "package" "entry") != "GC-Matterport-GLB-Converter.ms") do throw "Unexpected converter entry in package manifest."
    local ownsLoadedRuntime = false
    if (globalVars.isGlobal #GCMatterportRuntimeFolder) do (
        local loadedFolder = globalVars.get #GCMatterportRuntimeFolder
        if (loadedFolder != undefined) do ownsLoadedRuntime = ((toLower (pathClass.GetFullPath loadedFolder)) == (toLower packageFolder))
    )
    if (ownsLoadedRuntime) do (
        if (GCMatterportLiveBusy or _rExportGCMatterportGLBConverter.isRenderingAO or _rExportGCMatterportGLBConverter.isExportingLODs) do throw "Finish the converter operation before uninstalling."
        GCMatterportLiveStop()
        GCMatterportStopAllPreviewServers()
        callbacks.removeScripts id: #GCMatterportPreviewShutdown
        callbacks.removeScripts id: #GCMatterportPCPreviewShutdown
        deleteAllChangeHandlers id: #GCMatterportLiveGeometry
        try (destroyDialog GCMatterportLiveRollout) catch()
        try (closeRolloutFloater floaterGCMatterportGLBConverter) catch()
    )
    -- Also release owned servers if the converter UI was already closed or another copy is loaded.
    local ownedExecutables = for relativeFile in #("GC-Preview-Server.exe", "model-viewer\\localhost.exe", "playcanvas-viewer\\localhost.exe") collect (toLower (pathClass.GetFullPath (packageFolder + relativeFile)))
    for processName in #("GC-Preview-Server", "localhost") do (
        for serverProcess in ((dotNetClass "System.Diagnostics.Process").GetProcessesByName processName) do (
            local executableFile = undefined
            try (if (not serverProcess.HasExited) do executableFile = toLower (pathClass.GetFullPath (serverProcess.MainModule.FileName as string))) catch()
            if (executableFile != undefined and (findItem ownedExecutables executableFile) > 0) do (
                try (
                    if (not serverProcess.HasExited) do (
                        serverProcess.Kill()
                        if (not serverProcess.WaitForExit 3000) do throw "Owned preview server did not exit."
                    )
                ) catch (
                    serverProcess.Dispose()
                    throw()
                )
            )
            serverProcess.Dispose()
        )
    )
    true
)
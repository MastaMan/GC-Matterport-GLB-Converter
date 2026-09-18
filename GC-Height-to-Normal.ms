-- GC Height to Normal: register by loading the converter; no system installation.
global GCMatterportHeightNormal
global GCMatterportHeightNormalRegistrationVersion
global GCMatterportRenderHeightNormal
global GCMatterportHeightNormalCode = (dotNetClass "System.IO.File").ReadAllText ((getFilenamePath (getThisScriptFileName())) + "GC-Height-to-Normal.osl")
global GCMatterportNormalSyncBusy = false

fn GCMatterportHeightBitmapIssue sourceMap = (
    if (sourceMap == undefined) do return "Connect a Bitmap height map."
    if (classOf sourceMap != Bitmaptexture) do return "Height input requires a file Bitmap."
    local sourceFile = mapPaths.getFullFilePath sourceMap.filename
    if (sourceFile == undefined or sourceFile == "" or not doesFileExist sourceFile) do return "Height bitmap file is missing."
    if ((findItem #(".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".exr") (toLower (getFilenameType sourceFile))) == 0) do return "Use a still PNG, JPEG, TIFF, BMP or EXR height image."
    local coordinates = sourceMap.coords
    if (coordinates.mappingType != 0 or coordinates.UVW_Type != 0 or coordinates.realWorldScale or coordinates.Noise_On or abs coordinates.U_Angle > 0.00001 or abs coordinates.V_Angle > 0.00001) do return "Use standard UV mapping without real-world scale, noise or U/V rotation."
    if ((findItem #(1,2) coordinates.mapChannel) == 0) do return "Height Bitmap requires UV channel 1 or 2."
    if (sourceMap.apply or sourceMap.useJitter or sourceMap.rgbOutput != 0) do return "Disable Bitmap crop/placement, jitter and alpha-as-RGB."
    if (sourceMap.output.enableColorMap or sourceMap.output.invert or sourceMap.output.RGB_Level != 1 or sourceMap.output.output_amount != 1 or sourceMap.output.RGB_Offset != 0) do return "Use unmodified Bitmap RGB output; height is read as raw data."
    return undefined
)

-- Set only changed values, outside Max's reference notifications.
fn GCMatterportNormalSet shaderMap propertyName propertyValue = (
    if ((getProperty shaderMap propertyName) != propertyValue) do setProperty shaderMap propertyName propertyValue
    return true
)

if (GCMatterportHeightNormal == undefined or GCMatterportHeightNormalRegistrationVersion != 3) do (
    plugin textureMap GCMatterportHeightNormal
        name: "GC Height to Normal"
        category: "GC"
        classID: #(0x61ce2854, 0x42bd7309)
        extends: OSLMap
        replaceUI: true
        version: 3
    (
        local isSyncing = false
        local statusMessage = "Connect a Bitmap height map."
        parameters settings rollout: controls (
            HeightBitmap type: #texturemap ui: btnHeight
            Strength type: #float default: 2.0 animatable: false ui: spnStrength
            Blur type: #float default: 0.0 animatable: false ui: spnBlur
            Sharpness type: #float default: 0.0 animatable: false ui: spnSharpness
            FlipGreen type: #boolean default: false animatable: false ui: cbxFlipGreen
        )
        fn synchronize = (
            if (isSyncing) do return false
            isSyncing = true
            local failureReason = undefined
            try (
                failureReason = GCMatterportHeightBitmapIssue HeightBitmap
                if (failureReason == undefined) then (
                    local coordinates = HeightBitmap.coords
                    GCMatterportNormalSet delegate #SourceFile (mapPaths.getFullFilePath HeightBitmap.filename)
                    GCMatterportNormalSet delegate #Strength Strength
                    GCMatterportNormalSet delegate #Blur Blur
                    GCMatterportNormalSet delegate #Sharpness Sharpness
                    GCMatterportNormalSet delegate #FlipGreen (if FlipGreen then 1 else 0)
                    GCMatterportNormalSet delegate #MapChannel coordinates.mapChannel
                    GCMatterportNormalSet delegate #TileU coordinates.U_Tiling
                    GCMatterportNormalSet delegate #TileV coordinates.V_Tiling
                    GCMatterportNormalSet delegate #OffsetU coordinates.U_Offset
                    GCMatterportNormalSet delegate #OffsetV coordinates.V_Offset
                    GCMatterportNormalSet delegate #Rotation coordinates.W_Angle
                    GCMatterportNormalSet delegate #WrapU (if coordinates.U_Mirror then "mirror" else if coordinates.U_Tile then "periodic" else "clamp")
                    GCMatterportNormalSet delegate #WrapV (if coordinates.V_Mirror then "mirror" else if coordinates.V_Tile then "periodic" else "clamp")
                    statusMessage = "Raw height -> tangent normal. +Y / glTF by default."
                ) else (
                    GCMatterportNormalSet delegate #SourceFile ""
                    statusMessage = failureReason
                )
            ) catch (failureReason = getCurrentException() as string; statusMessage = failureReason)
            isSyncing = false
            return (failureReason == undefined)
        )
        fn getIssue = (
            return statusMessage
        )
        rollout controls "Height to Normal" (
            mapButton btnHeight "Height Bitmap" width: 210
            spinner spnStrength "Strength: " range: [0,100,2] type: #float fieldWidth: 65
            spinner spnBlur "Blur (pixels): " range: [0,20,0] type: #float fieldWidth: 65
            spinner spnSharpness "Sharpness: " range: [0,5,0] type: #float fieldWidth: 65
            checkbox cbxFlipGreen "Flip green (DirectX)" checked: false
            label lblStatus "Height is raw/non-color data." width: 225 height: 42
            button btnRenderMap "Render Map" width: 210
            timer tmrSync interval: 150 active: true
            on btnRenderMap pressed do (
                btnRenderMap.enabled = false
                tmrSync.active = false
                try (
                    local savedFile = GCMatterportRenderHeightNormal this
                    if (savedFile != undefined) do messageBox ("Normal map saved:\n" + savedFile) title: "Render Map"
                ) catch (messageBox ("Could not render the normal map:\n" + (getCurrentException() as string)) title: "Render Map")
                tmrSync.active = true
                btnRenderMap.enabled = true
            )
            on tmrSync tick do (
                synchronize()
                if (lblStatus.text != statusMessage) do lblStatus.text = statusMessage
            )
        )
        on create do (
            delegate.OSLCode = GCMatterportHeightNormalCode
            delegate.OSLAutoUpdate = false
        )
    )
)

global GCMatterportHeightNormalRegistrationVersion = 3

fn GCMatterportSyncHeightNormalMaps = (
    if (GCMatterportNormalSyncBusy or GCMatterportHeightNormal == undefined) do return false
    GCMatterportNormalSyncBusy = true
    local failureReason = undefined
    try (
        for normalMap in (getClassInstances GCMatterportHeightNormal processAllAnimatables: true) do normalMap.synchronize()
    ) catch (failureReason = getCurrentException() as string)
    GCMatterportNormalSyncBusy = false
    if (failureReason != undefined) do format "Height to Normal sync: %\n" failureReason
    return (failureReason == undefined)
)

fn GCMatterportBakeHeightNormal normalMap outputFile resolution canonical: true returnMap: true jpegOutput: false = (
    if (classOf normalMap != GCMatterportHeightNormal) do throw "Expected GC Height to Normal."
    if (not normalMap.synchronize()) do throw (normalMap.getIssue())
    local bakeMap = copy normalMap.delegate
    bakeMap.BakeCanonical = if canonical then 1 else 0
    -- A standalone image has one UV plane; bake the input transform into that plane.
    if (not canonical) do bakeMap.MapChannel = 1
    local bakeSize = if (classOf resolution == Point2) then resolution else [resolution,resolution]
    -- Canonical texture coordinates: the resulting Bitmap retains the input UV transform.
    local renderedBitmap = undefined
    local outputBitmap = undefined
    local previousPNGType = if jpegOutput then undefined else pngio.getType()
    local previousPNGAlpha = if jpegOutput then undefined else pngio.getAlpha()
    local previousJPEGQuality = if jpegOutput then jpeg.ijpegio.getQuality() else undefined
    local previousJPEGSmoothing = if jpegOutput then jpeg.ijpegio.getSmoothing() else undefined
    local failureReason = undefined
    try (
        renderedBitmap = renderMap bakeMap size: bakeSize display: false filter: false hdr: true disableBitmapProxies: true
        -- Explicit raw bitmap output bypasses display/view transforms.
        if jpegOutput then (
            -- Normal data benefits from maximum JPEG quality and no smoothing.
            jpeg.ijpegio.setQuality 100
            jpeg.ijpegio.setSmoothing 0
        ) else (
            pngio.setType #true24
            pngio.setAlpha false
        )
        outputBitmap = bitmap (bakeSize.x as integer) (bakeSize.y as integer) filename: outputFile gamma: 1.0
        copy renderedBitmap outputBitmap
        if jpegOutput then (
            -- Normal data benefits from maximum JPEG quality and no smoothing.
            jpeg.ijpegio.setQuality 100
            jpeg.ijpegio.setSmoothing 0
        ) else (
            pngio.setType #true24
            pngio.setAlpha false
        )
        if (maxVersion())[1] >= 26000 do SetOutputColorConversion outputBitmap #noConversion
        if (not save outputBitmap gamma: 1.0) do throw "Could not save the baked normal image."
    ) catch (failureReason = getCurrentException() as string)
    try (if (renderedBitmap != undefined) do close renderedBitmap) catch (failureReason = (if failureReason == undefined then "" else failureReason + "\n") + (getCurrentException() as string))
    try (if (outputBitmap != undefined) do close outputBitmap) catch (failureReason = (if failureReason == undefined then "" else failureReason + "\n") + (getCurrentException() as string))
    if (not jpegOutput) do try (pngio.setType previousPNGType) catch (failureReason = (if failureReason == undefined then "" else failureReason + "\n") + "Could not restore PNG type: " + (getCurrentException() as string))
    if (not jpegOutput) do try (pngio.setAlpha previousPNGAlpha) catch (failureReason = (if failureReason == undefined then "" else failureReason + "\n") + "Could not restore PNG alpha: " + (getCurrentException() as string))
    if jpegOutput do (
        try (jpeg.ijpegio.setQuality previousJPEGQuality) catch (failureReason = (if failureReason == undefined then "" else failureReason + "\n") + "Could not restore JPEG quality: " + (getCurrentException() as string))
        try (jpeg.ijpegio.setSmoothing previousJPEGSmoothing) catch (failureReason = (if failureReason == undefined then "" else failureReason + "\n") + "Could not restore JPEG smoothing: " + (getCurrentException() as string))
    )
    if (failureReason != undefined) do throw failureReason
    if (not returnMap) do return outputFile
    local readBitmap = if (ColorPipelineMgr != undefined and ColorPipelineMgr.DataColorSpace != "") then (openBitmap outputFile colorSpace: ColorPipelineMgr.DataColorSpace) else (openBitmap outputFile gamma: 1.0)
    if (readBitmap == undefined) do throw "Could not read the baked normal image."
    local bakedMap = Bitmaptexture name: "GC Baked Normal" bitmap: readBitmap
    bakedMap.coords = copy normalMap.HeightBitmap.coords
    return bakedMap
)

fn GCMatterportBakeMaterialNormals exportMaterial mapsFolder resolution = (
    local bakedCount = 0
    for materialIndex in 1 to exportMaterial.materialList.count do (
        local materialRef = exportMaterial.materialList[materialIndex]
        for slotName in #(#normalMap, #clearcoatNormalMap) where (isProperty materialRef slotName) do (
            local normalMap = getProperty materialRef slotName
            if (normalMap != undefined and classOf normalMap == GCMatterportHeightNormal) do (
                local outputFile = mapsFolder + "normal_" + (materialIndex as string) + "_" + (slotName as string) + ".png"
                setProperty materialRef slotName (GCMatterportBakeHeightNormal normalMap outputFile resolution)
                bakedCount += 1
            )
        )
    )
    return bakedCount
)

-- Save a standalone normal image without changing the material or source Bitmap.
fn GCMatterportRenderHeightNormal normalMap = (
    local inputIssue = GCMatterportHeightBitmapIssue normalMap.HeightBitmap
    if (inputIssue != undefined) do throw inputIssue
    local sourceFile = mapPaths.getFullFilePath normalMap.HeightBitmap.filename
    local outputFolder = getFilenamePath sourceFile
    if (not doesDirectoryExist outputFolder) do throw "The Height Bitmap folder is unavailable."
    local outputFile = outputFolder + (getFilenameFile sourceFile) + "_normal.jpg"
    local overwriteApproved = doesFileExist outputFile
    if overwriteApproved do (
        if (not queryBox ("Replace the existing normal map?\n" + outputFile) title: "Render Map" beep: false defaultButton: 2) do return undefined
    )
    local sourceBitmap = openBitmap sourceFile
    if (sourceBitmap == undefined) do throw "Could not read the Height Bitmap dimensions."
    local bakeSize = [sourceBitmap.width,sourceBitmap.height]
    close sourceBitmap
    if (bakeSize.x < 1 or bakeSize.y < 1) do throw "The Height Bitmap has invalid dimensions."
    local stagingFile = outputFolder + "._gc_normal_" + ((dotNetClass "System.Guid").NewGuid()).ToString("N") + ".jpg"
    local failureReason = undefined
    try (
        -- Staging in the destination folder also verifies write access before publishing.
        GCMatterportBakeHeightNormal normalMap stagingFile bakeSize canonical: false returnMap: false jpegOutput: true
        if (doesFileExist outputFile) then (
            if (not overwriteApproved) do throw "The output file appeared during rendering. Render again to confirm replacement."
            (dotNetClass "System.IO.File").Replace stagingFile outputFile undefined
        ) else (
            (dotNetClass "System.IO.File").Move stagingFile outputFile
        )
    ) catch (failureReason = getCurrentException() as string)
    if (doesFileExist stagingFile) do (
        try (
            if (not deleteFile stagingFile) do throw "Could not remove the temporary normal JPG."
        ) catch (
            failureReason = (if failureReason == undefined then "" else failureReason + "\n") + (getCurrentException() as string)
        )
    )
    if (failureReason != undefined) do throw ("Cannot save the normal JPG in " + outputFolder + "\n" + failureReason)
    return outputFile
)
/*  
[INFO] 
NAME = GC Matterport GLB Converter
VERSION = 1.0.0
AUTHOR = Lukianenko Vasyl
DEV = https://3dground.net
HELP = 
CLIENT=Eugen Zharnikov

[ABOUT]
Script for proper conversion model to GLB=


[1.0.0]
* Initial release =

[SCRIPT]
*/


try(closeRolloutFloater floaterGCMatterportGLBConverter) catch()
global floaterGCMatterportGLBConverter = newRolloutFloater "Matterport Converter" 360 560

struct '@' (
	currScript = getThisScriptFileName(),
	name = getFilenameFile currScript,
	pth = getFileNamePath currScript,
	ini = pth +  sysinfo.username + "@" + sysinfo.computername + ".ini",
	--ini = (getThisScriptFileName()) + ".ini",
	sec = name,
	fn add k v = (
		setIniSetting this.ini this.sec k (v as string)
	),
	fn get k type: #string = (
		v = getIniSetting this.ini this.sec k
		
		case type of (
			#bool_true: return if (v == "true") then true else false
			#bool_false: return if (v == "false") then false else true
			#int: return try (v as integer) catch(0)
		)
		
		return v
	),
	fn trim s tag: "" = (
		s as string
		return (trimLeft (trimRight s tag) tag)
	)
)

global '*' = '@'()

struct GCMatterportLODEntry (
	layerName,
	displayText,
	objectCount,
	isReady
)

fn GCMatterportIsLODReady layerNodes = (
	if (layerNodes.count != 1 or glTFMaterial == undefined) do return false
	local lodMaterial = layerNodes[1].material
	if (lodMaterial == undefined or classOf lodMaterial != MultiMaterial) do return false
	if (lodMaterial.materialList.count == 0) do return false
	for subMaterial in lodMaterial.materialList do (
		if (subMaterial == undefined or classOf subMaterial != glTFMaterial) do return false
	)
	return true
)

struct GCMatterportMaterialEntry (
	layerName,
	nodeRef,
	materialRef,
	slotIndex,
	materialID,
	materialName,
	displayText
)

-- Native typed File Properties are saved with the scene; no evaluated serialization.
struct GCMatterportScenePropertyStore (
	propertyPrefix = "GC.Matterport.AO.v1.",
	fn getValue propertyKey defaultValue = (
		local propertyIndex = fileProperties.findProperty #custom (propertyPrefix + propertyKey)
		if (propertyIndex == 0) do return defaultValue
		return fileProperties.getPropertyValue #custom propertyIndex
	),
	fn setValue propertyKey propertyValue = (
		fileProperties.addProperty #custom (propertyPrefix + propertyKey) propertyValue
		setSaveRequired true
		return true
	)
)

struct GCMatterportAOOptions (
	useCoronaAO = true,
	passes = 15,
	sizeCM = 5.0,
	useVRayDenoiser = true,
	customResolution = false,
	manualResolution = 1024,
	resolution = 1024,
	sizeWorldUnits = 0.0
)

global GCMatterportRuntimeFolder = getFilenamePath (getThisScriptFileName())

global GCMatterportSceneProperties = GCMatterportScenePropertyStore()

fn GCMatterportAOKey materialEntry = (
	if (materialEntry == undefined or not isValidNode materialEntry.nodeRef) do return undefined
	return "node." + (materialEntry.nodeRef.inode.handle as string) + ".id." + (materialEntry.materialID as string) + "."
)

fn GCMatterportIsCurrentMaterialEntry materialEntry = (
	if (materialEntry == undefined or not isValidNode materialEntry.nodeRef) do return false
	if (materialEntry.nodeRef.layer.name != materialEntry.layerName) do return false
	local parentMaterial = materialEntry.nodeRef.material
	if (parentMaterial == undefined or classOf parentMaterial != MultiMaterial) do return false
	local slotIndex = materialEntry.slotIndex
	if (slotIndex < 1 or slotIndex > parentMaterial.materialList.count or slotIndex > parentMaterial.materialIDList.count) do return false
	return (parentMaterial.materialList[slotIndex] == materialEntry.materialRef and parentMaterial.materialIDList[slotIndex] == materialEntry.materialID)
)

fn GCMatterportAutomaticAOResolution layerName = (
	if (layerName.count < 4) do return undefined
	case (toUpper (substring layerName (layerName.count - 3) 4)) of (
		"LOD3": return 4096
		"LOD2": return 2048
		"LOD1": return 1024
		"LOD0": return 512
		default: return undefined
	)
)

-- One getter for UI and future AO baking. Size is stored in cm, converted at use time.
fn GCMatterportGetEffectiveAOOptions materialEntry = (
	if (not GCMatterportIsCurrentMaterialEntry materialEntry) do return undefined
	local propertyKey = GCMatterportAOKey materialEntry
	local aoOptions = GCMatterportAOOptions()
	aoOptions.useCoronaAO = GCMatterportSceneProperties.getValue (propertyKey + "enabled") true
	aoOptions.passes = GCMatterportSceneProperties.getValue (propertyKey + "passes") 15
	aoOptions.sizeCM = GCMatterportSceneProperties.getValue (propertyKey + "sizeCM") 5.0
	aoOptions.useVRayDenoiser = GCMatterportSceneProperties.getValue (propertyKey + "denoise") true
	aoOptions.customResolution = GCMatterportSceneProperties.getValue (propertyKey + "override") false
	aoOptions.manualResolution = GCMatterportSceneProperties.getValue (propertyKey + "manualResolution") 1024
	if (classOf aoOptions.useCoronaAO != BooleanClass or classOf aoOptions.useVRayDenoiser != BooleanClass or classOf aoOptions.customResolution != BooleanClass) do return undefined
	if (classOf aoOptions.passes != Integer or aoOptions.passes < 1 or aoOptions.passes > 9999) do return undefined
	if ((classOf aoOptions.sizeCM != Float and classOf aoOptions.sizeCM != Integer) or not (aoOptions.sizeCM >= 0.01 and aoOptions.sizeCM <= 9999.0)) do return undefined
	if ((findItem #(512, 1024, 2048, 4096) aoOptions.manualResolution) == 0) do return undefined
	aoOptions.resolution = if aoOptions.customResolution then aoOptions.manualResolution else (GCMatterportAutomaticAOResolution materialEntry.layerName)
	if (aoOptions.resolution == undefined) do return undefined
	aoOptions.sizeWorldUnits = aoOptions.sizeCM * (units.decodeValue "1cm")
	return aoOptions
)



fn GCMatterportHasAOMap materialRef = (
	if (materialRef == undefined or not isProperty materialRef #ambientOcclusionMap) do return false
	local aoMap = materialRef.ambientOcclusionMap
	if (materialRef.ambientOcclusion <= 0 or aoMap == undefined or classOf aoMap != Bitmaptexture) do return false
	if (aoMap.coords.mapChannel != 2 or aoMap.filename == "") do return false
	local resolvedFile = mapPaths.getFullFilePath aoMap.filename
	return (resolvedFile != undefined and resolvedFile != "" and doesFileExist resolvedFile)
)

fn GCMatterportDenoiserPath = (
	local programData = (dotNetClass "System.Environment").GetEnvironmentVariable "ProgramData"
	local maxYear = ((maxVersion())[1] / 1000 + 1998) as integer
	return (programData + "\\Autodesk\\ApplicationPlugins\\VRay3dsMax" + (maxYear as string) + "\\bin\\vdenoise.exe")
)

fn GCMatterportVerifyAOFile filePath resolution = (
	if (not doesFileExist filePath) do throw ("AO output is missing: " + filePath)
	local imageStream = (dotNetClass "System.IO.File").OpenRead filePath
	local firstByte = imageStream.ReadByte()
	local secondByte = imageStream.ReadByte()
	imageStream.Dispose()
	if (firstByte != 255 or secondByte != 216) do throw "AO output is not a valid JPEG image."
	local outputBitmap = openBitmap filePath
	if (outputBitmap == undefined) do throw ("Could not read AO output: " + filePath)
	local validSize = (outputBitmap.width == resolution and outputBitmap.height == resolution)
	close outputBitmap
	if (not validSize) do throw "AO output resolution does not match the requested resolution."
	return true
)


fn GCMatterportRunAOProcess executablePath argumentsContent workingFolder operationLabel: "AO image processing" = (
	local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
	startInfo.FileName = executablePath
	startInfo.Arguments = argumentsContent
	startInfo.WorkingDirectory = workingFolder
	startInfo.UseShellExecute = false
	startInfo.CreateNoWindow = true
	startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden
	local workerProcess = undefined
	local failureReason = undefined
	try (
		workerProcess = (dotNetClass "System.Diagnostics.Process").Start startInfo
		while (not workerProcess.WaitForExit 100) do (
			windows.processPostedMessages()
			if (keyboard.escPressed) do throw (operationLabel + " cancelled.")
		)
		if (workerProcess.ExitCode != 0) do throw (operationLabel + " exited with code " + (workerProcess.ExitCode as string) + ".")
	) catch (failureReason = getCurrentException() as string)
	if (workerProcess != undefined) do (
		if (not workerProcess.HasExited) do (
			-- The original BAT launches a child EXE; stop that process tree on cancellation.
			local stopInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
			stopInfo.FileName = (dotNetClass "System.Environment").SystemDirectory + "\\taskkill.exe"
			stopInfo.Arguments = "/PID " + (workerProcess.Id as string) + " /T /F"
			stopInfo.UseShellExecute = false
			stopInfo.CreateNoWindow = true
			stopInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden
			local stopProcess = (dotNetClass "System.Diagnostics.Process").Start stopInfo
			stopProcess.WaitForExit()
			local stopExitCode = stopProcess.ExitCode
			stopProcess.Dispose()
			if (stopExitCode != 0 and not workerProcess.HasExited) do failureReason = "Could not stop " + operationLabel + "."
		)
		workerProcess.Dispose()
	)
	if (failureReason != undefined) do throw failureReason
	return true
)

fn GCMatterportDenoiseAO filePath executablePath = (
	local batchPath = GCMatterportRuntimeFolder + "denoise.bat"
	local configPath = GCMatterportRuntimeFolder + "vdenoise.xml"
	if (not doesFileExist executablePath or not doesFileExist batchPath or not doesFileExist configPath) do throw "V-Ray Denoiser, denoise.bat and vdenoise.xml are required."
	-- Use the original GC Tools BAT and XML unchanged, including its year;image contract.
	for forbiddenPart in #("%", ";", "\r", "\n") do (
		if (findString filePath forbiddenPart != undefined or findString batchPath forbiddenPart != undefined) do throw "The original denoise.bat cannot process paths containing %, semicolons or line breaks. Save the scene in a compatible folder."
	)
	local maxYear = ((maxVersion())[1] / 1000 + 1998) as integer
	local commandLine = "/d /v:off /s /c \"\"" + batchPath + "\" \"" + (maxYear as string) + ";" + filePath + "\"\""
	local commandExecutable = (dotNetClass "System.Environment").SystemDirectory + "\\cmd.exe"
	GCMatterportRunAOProcess commandExecutable commandLine GCMatterportRuntimeFolder
	local denoisedFiles = getFiles ((getFilenamePath filePath) + (getFilenameFile filePath) + "_denoised*" + (getFilenameType filePath))
	if (denoisedFiles.count != 1) do throw "V-Ray Denoiser did not produce exactly one denoised AO image."
	return denoisedFiles[1]
)

fn GCMatterportOptimizeAO filePath = (
	local optimizerPath = GCMatterportRuntimeFolder + "jpegoptim.exe"
	if (not doesFileExist optimizerPath) do throw "jpegoptim.exe is required beside the converter script."
	-- Same quality and switches as GC Tools.optimizeImages, applied after optional denoising.
	local argumentsContent = "--strip-all --all-progressive -f -o -q -m90 \"" + filePath + "\""
	GCMatterportRunAOProcess optimizerPath argumentsContent (getFilenamePath filePath)
	return true
)

-- Read only the chosen ID's faces. Channel support alone does not prove usable UVs.
fn GCMatterportValidateAOBakeMesh sourceMesh materialID = (
	local selectedFaces = for faceIndex in 1 to sourceMesh.numfaces where (getFaceMatID sourceMesh faceIndex == materialID) collect faceIndex
	if (selectedFaces.count == 0) do return ("No faces are assigned to Material ID " + (materialID as string) + ". Select a material ID used by this object, or assign this ID to the intended faces.")
	local uvInstruction = "Cannot bake AO for this ID: UV channel 2 is missing or unusable on its faces. Select this ID and run Transfer UV Channel from 1 -> 2."
	if (not meshop.getMapSupport sourceMesh 2) do return uvInstruction
	local mapVertexCount = meshop.getNumMapVerts sourceMesh 2
	if (mapVertexCount < 3) do return uvInstruction
	try (
		for faceIndex in selectedFaces do (
			local mapFace = meshop.getMapFace sourceMesh 2 faceIndex
			local uvCorners = #()
			for cornerIndex in 1 to 3 do (
				local mapIndex = mapFace[cornerIndex] as integer
				if (mapIndex < 1 or mapIndex > mapVertexCount) do return uvInstruction
				local uvPoint = meshop.getMapVert sourceMesh 2 mapIndex
				-- Positive bounds tests also reject non-finite UV values.
				if (not (uvPoint.x >= -0.0001 and uvPoint.y >= -0.0001 and uvPoint.x <= 1.0001 and uvPoint.y <= 1.0001)) do return ("Cannot bake AO for this ID: its UV channel 2 coordinates are outside 0..1 or invalid. Run Transfer UV Channel from 1 -> 2 for this ID.")
				append uvCorners uvPoint
			)
			local edgeA = uvCorners[2] - uvCorners[1]
			local edgeB = uvCorners[3] - uvCorners[1]
			local uvAreaTwice = abs (edgeA.x * edgeB.y - edgeA.y * edgeB.x)
			if (uvAreaTwice <= 1e-12) do return ("Cannot bake AO for this ID: UV channel 2 contains collapsed faces with no usable UV area. Run Transfer UV Channel from 1 -> 2 for this ID.")
		)
	) catch (
		return uvInstruction
	)
	return undefined
)

fn GCMatterportAOPreflight materialEntry = (
	if (not GCMatterportIsCurrentMaterialEntry materialEntry) do return "The material assignment changed. Refresh the list and select the ID again."
	local sourceMesh = undefined
	local validationMessage = undefined
	try (
		sourceMesh = snapshotAsMesh materialEntry.nodeRef
		validationMessage = GCMatterportValidateAOBakeMesh sourceMesh materialEntry.materialID
	) catch (
		validationMessage = "Cannot inspect this object's geometry for AO baking. Check that the object evaluates to a mesh."
	)
	if (sourceMesh != undefined) do delete sourceMesh
	return validationMessage
)


fn GCMatterportFileKey stringContent = (
	local hasher = (dotNetClass "System.Security.Cryptography.SHA256").Create()
	local inputBytes = (dotNetClass "System.Text.Encoding").UTF8.GetBytes stringContent
	local hashBytes = hasher.ComputeHash inputBytes
	hasher.Dispose()
	return toLower (substituteString ((dotNetClass "System.BitConverter").ToString hashBytes) "-" "")
)

fn GCMatterportPublishAO completedFilePath outputFolder materialEntry = (
	local safeLayerName = trimRight materialEntry.layerName " ."
	for invalidCharacter in #("\\", "/", ":", "*", "?", "\"", "<", ">", "|") do safeLayerName = substituteString safeLayerName invalidCharacter "_"
	if (safeLayerName != materialEntry.layerName) do safeLayerName += "_" + (substring (GCMatterportFileKey materialEntry.layerName) 1 16)
	local fileStem = safeLayerName + "_ID" + (materialEntry.materialID as string) + "_AO"
	local finalFilePath = outputFolder + fileStem + ".jpg"
	local publicationError = undefined
	try (
		if (doesFileExist finalFilePath) then (
			(dotNetClass "System.IO.File").Replace completedFilePath finalFilePath ((getFilenamePath completedFilePath) + "previous_AO.jpg")
		) else (
			(dotNetClass "System.IO.File").Move completedFilePath finalFilePath
		)
	) catch (
		-- Only a publication failure may choose a new filename; processing failures never reach here.
		local publicationReason = getCurrentException() as string
		local dateSuffix = (dotNetClass "System.DateTime").Now.ToString "yyyyMMdd_HHmmss_fff"
		finalFilePath = outputFolder + fileStem + "_" + dateSuffix + ".jpg"
		if (doesFileExist finalFilePath) do finalFilePath = outputFolder + fileStem + "_" + dateSuffix + "_" + ((dotNetClass "System.Guid").NewGuid()).ToString("N") + ".jpg"
		try (
			(dotNetClass "System.IO.File").Move completedFilePath finalFilePath
			format "AO saved with a timestamp because the stable output could not be replaced: %\n" publicationReason
		) catch (
			publicationError = "Cannot publish either the stable AO file or its timestamp fallback. The previous AO map is preserved. " + (getCurrentException() as string)
		)
	)
	if (publicationError != undefined) do throw publicationError
	return finalFilePath
)

struct GCMatterportAOBakeResult (filePath, errorMessage, cancelled = false)

fn GCMatterportBakeAO materialEntry aoOptions outputFolder denoiserPath = (
	local bakeResult = GCMatterportAOBakeResult()
	bakeResult.errorMessage = GCMatterportAOPreflight materialEntry
	if (bakeResult.errorMessage != undefined) do return bakeResult
	local originalRenderer = renderers.current
	local originalSelection = selection as array
	local originalPanelMode = getCommandPanelTaskMode()
	local originalStackObject = modPanel.getCurrentObject()
	local originalSubObjectLevel = subObjectLevel
	local originalRenderStates = for sceneNode in objects collect #(sceneNode, sceneNode.renderable, sceneNode.renderByLayer)
	local temporaryNode = undefined
	local occluderNode = undefined
	local renderBitmap = undefined
	local wasCancelled = false
	local rawFilePath = ""
	local runFolder = undefined
	local runToken = undefined
	try (
		if (not GCMatterportIsCurrentMaterialEntry materialEntry) do throw "The material assignment changed. Refresh the list."
		if (Corona == undefined or CoronaAO == undefined or CoronaPhysicalMtl == undefined or Corona_DiffuseColor == undefined) do throw "Corona renderer, AO map, physical material and DiffuseColor bake element are required."
		if (aoOptions.useVRayDenoiser and not doesFileExist denoiserPath) do throw ("V-Ray Denoiser was not found: " + denoiserPath)
		if (not doesFileExist (GCMatterportRuntimeFolder + "jpegoptim.exe")) do throw "jpegoptim.exe is required beside the converter script before AO can be rendered."
		if (aoOptions.useVRayDenoiser and (not doesFileExist (GCMatterportRuntimeFolder + "denoise.bat") or not doesFileExist (GCMatterportRuntimeFolder + "vdenoise.xml"))) do throw "The original denoise.bat and vdenoise.xml are required beside the converter script."
		local safeLayerName = materialEntry.layerName
		for invalidCharacter in #("\\", "/", ":", "*", "?", "\"", "<", ">", "|") do safeLayerName = substituteString safeLayerName invalidCharacter "_"
		local fileStem = safeLayerName + "_node" + (materialEntry.nodeRef.inode.handle as string) + "_ID" + (materialEntry.materialID as string) + "_AO"
		runToken = ((dotNetClass "System.Guid").NewGuid()).ToString "N"
		runFolder = outputFolder + "._ao_" + runToken + "\\"
		if (not makeDir runFolder all: true) do throw "Could not create AO output folder."
		rawFilePath = runFolder + fileStem + ".jpg"
		-- Work on an evaluated copy. The original stack, UVs and bake properties stay intact.
		subObjectLevel = 0
		setCommandPanelTaskMode mode: #create
		with undo off (
			temporaryNode = copy materialEntry.nodeRef
			temporaryNode.name = uniqueName "GC_AO_Bake_"
			convertToMesh temporaryNode
			local discardFaces = #{}
			local bakeFaces = #{}
			for faceIndex in 1 to temporaryNode.numfaces do (
				if (getFaceMatID temporaryNode faceIndex != materialEntry.materialID) then discardFaces[faceIndex] = true else bakeFaces[faceIndex] = true
			)
			-- GC Tools shades against the complete object. Keep other IDs as occluders,
			-- but never bake their UVs into the selected ID's image or duplicate its faces.
			if (discardFaces.numberSet > 0) do (
				occluderNode = copy temporaryNode
				occluderNode.name = uniqueName "GC_AO_Occluder_"
				meshop.deleteFaces occluderNode bakeFaces delIsoVerts: true
				occluderNode.renderByLayer = false
				occluderNode.renderable = true
				occluderNode.INodeBakeProperties.removeAllBakeElements()
				occluderNode.INodeBakeProperties.bakeEnabled = false
			)
			meshop.deleteFaces temporaryNode discardFaces delIsoVerts: true
			for renderState in originalRenderStates do (
				renderState[1].renderByLayer = false
				renderState[1].renderable = false
			)
			temporaryNode.renderByLayer = false
			temporaryNode.renderable = true
			local aoMaterial = CoronaPhysicalMtl()
			aoMaterial.baseColor = white
			aoMaterial.baseRoughness = 1.0
			local aoMap = CoronaAO()
			aoMap.maxDistance = aoOptions.sizeWorldUnits
			aoMap.colorSpread = 0.022
			aoMap.quality = 64
			aoMap.normalMode = 0
			aoMap.rayDirectionality = 0.03
			aoMaterial.baseTexmap = aoMap
			temporaryNode.material = aoMaterial
			if (isValidNode occluderNode) do occluderNode.material = aoMaterial
			local bakeElement = Corona_DiffuseColor()
			bakeElement.outputSzX = aoOptions.resolution
			bakeElement.outputSzY = aoOptions.resolution
			bakeElement.autoSzOn = false
			bakeElement.fileType = "jpg"
			bakeElement.filename = rawFilePath
			bakeElement.enabled = true
			bakeElement.filter = true
			temporaryNode.INodeBakeProperties.removeAllBakeElements()
			if (not temporaryNode.INodeBakeProperties.addBakeElement bakeElement) do throw "Could not add the Corona bake element."
			temporaryNode.INodeBakeProperties.bakeEnabled = true
			temporaryNode.INodeBakeProperties.bakeChannel = 2
			temporaryNode.INodeBakeProperties.nDilations = 4
			local bakeRenderer = Corona()
			bakeRenderer.progressive_passLimit = aoOptions.passes
			bakeRenderer.progressive_timeLimit = 0
			bakeRenderer.adaptivity_targetError = 0
			bakeRenderer.denoise_filterType = 0
			bakeRenderer.denoise_blendAmount = 1.0
			bakeRenderer.shading_onlyElements = true
			renderers.current = bakeRenderer
			select temporaryNode
			renderBitmap = render rendertype: #bakeSelected frame: currentTime outputSize: [aoOptions.resolution, aoOptions.resolution] vfb: false progressBar: true renderhiddenobjects: true cancelled: &wasCancelled
		)
		if (wasCancelled or renderBitmap == undefined) do (
			bakeResult.cancelled = true
			throw "AO rendering cancelled or returned no image."
		)
		GCMatterportVerifyAOFile rawFilePath aoOptions.resolution
		local completedFilePath = rawFilePath
		if (aoOptions.useVRayDenoiser) do completedFilePath = GCMatterportDenoiseAO rawFilePath denoiserPath
		GCMatterportVerifyAOFile completedFilePath aoOptions.resolution
		GCMatterportOptimizeAO completedFilePath
		GCMatterportVerifyAOFile completedFilePath aoOptions.resolution
		bakeResult.filePath = GCMatterportPublishAO completedFilePath outputFolder materialEntry
	) catch (
		bakeResult.errorMessage = getCurrentException() as string
		if (wasCancelled or keyboard.escPressed or findString bakeResult.errorMessage "cancelled" != undefined) do bakeResult.cancelled = true
	)
	-- Cleanup runs after success, render cancellation, denoiser failure and setup errors.
	if (renderBitmap != undefined) do try (close renderBitmap) catch (format "AO bitmap cleanup: %\n" (getCurrentException()))
	with undo off (
		try (if (isValidNode occluderNode) do delete occluderNode) catch (bakeResult.errorMessage = "Temporary AO occluder cleanup failed: " + (getCurrentException() as string))
		try (if (isValidNode temporaryNode) do delete temporaryNode) catch (bakeResult.errorMessage = "Temporary AO object cleanup failed: " + (getCurrentException() as string))
		for renderState in originalRenderStates where (isValidNode renderState[1]) do (
			try (
				renderState[1].renderable = renderState[2]
				renderState[1].renderByLayer = renderState[3]
			) catch (bakeResult.errorMessage = "Could not restore object renderability: " + (getCurrentException() as string))
		)
		try (renderers.current = originalRenderer) catch (bakeResult.errorMessage = "Could not restore the original renderer: " + (getCurrentException() as string))
		try (
			select (for sceneNode in originalSelection where (isValidNode sceneNode) collect sceneNode)
			setCommandPanelTaskMode mode: originalPanelMode
			if (originalPanelMode == #modify and originalStackObject != undefined) do modPanel.setCurrentObject originalStackObject
			subObjectLevel = originalSubObjectLevel
		) catch (bakeResult.errorMessage = "Could not restore the original selection/panel: " + (getCurrentException() as string))
	)
	if (runFolder != undefined and doesDirectoryExist runFolder) do (
		try (
			local pathClass = dotNetClass "System.IO.Path"
			local resolvedFolder = pathClass.GetFullPath runFolder
			local expectedFolder = pathClass.GetFullPath (outputFolder + "._ao_" + runToken + "\\")
			local resolvedRoot = pathClass.GetFullPath outputFolder
			if (resolvedFolder != expectedFolder or not (dotNetObject "System.String" resolvedFolder).StartsWith resolvedRoot (dotNetClass "System.StringComparison").OrdinalIgnoreCase) do throw "Refusing cleanup outside this AO run's temporary folder."
			(dotNetClass "System.IO.Directory").Delete resolvedFolder true
		) catch (
			-- A cleanup warning must not prevent assignment of a successfully published image.
			format "AO temporary cleanup: %\n" (getCurrentException())
		)
	)
	return bakeResult
)

fn GCMatterportAssignAO materialEntry filePath = (
	if (not GCMatterportIsCurrentMaterialEntry materialEntry) do throw "The target material changed during rendering. The AO image was kept without assigning it."
	local parentMaterial = materialEntry.nodeRef.material
	local replacementMaterial = copy materialEntry.materialRef
	local aoMap = Bitmaptexture filename: filePath name: "AO"
	reload aoMap.bitmap
	aoMap.coords.mapChannel = 2
	replacementMaterial.ambientOcclusionMap = aoMap
	replacementMaterial.ambientOcclusion = 1.0
	if (not GCMatterportHasAOMap replacementMaterial) do throw "The completed AO map could not be validated."
	undo "Assign per-ID Matterport AO" on (
		-- Preserve other slot references when isolating a shared parent MultiMaterial.
		if ((refs.dependentNodes parentMaterial).count > 1) do (
			local isolatedParent = copy parentMaterial
			isolatedParent.materialList = for subMaterial in parentMaterial.materialList collect subMaterial
			parentMaterial = isolatedParent
		)
		parentMaterial.materialList[materialEntry.slotIndex] = replacementMaterial
		materialEntry.nodeRef.material = parentMaterial
	)
	materialEntry.materialRef = replacementMaterial
	return true
)

fn GCMatterportFormatMaterialRow materialEntry = (
	local aoOptions = GCMatterportGetEffectiveAOOptions materialEntry
	local propertyKey = GCMatterportAOKey materialEntry
	local isEnabled = GCMatterportSceneProperties.getValue (propertyKey + "enabled") true
	local statusGlyph = (dotNetClass "System.Char").ConvertFromUtf32 (if isEnabled then 10003 else 9675)
	local rowText = "[" + statusGlyph + "] " + (materialEntry.materialID as string) + ": " + materialEntry.materialRef.name
	if (GCMatterportHasAOMap materialEntry.materialRef) do rowText = "[AO] " + rowText
	local differences = #()
	if (aoOptions != undefined) do (
		if (aoOptions.passes != 15) do append differences ((aoOptions.passes as string) + " passes")
		if (aoOptions.resolution != GCMatterportAutomaticAOResolution materialEntry.layerName) do append differences ((aoOptions.resolution as string) + " px")
		if (abs (aoOptions.sizeCM - 5.0) > 0.0001) do (
			local sizeCaption = trimRight (trimRight (substituteString (formattedPrint aoOptions.sizeCM format: ".4f") "," ".") "0") "."
			append differences (sizeCaption + " cm")
		)
		if (not aoOptions.useVRayDenoiser) do append differences "No Denoise"
	)
	if (differences.count > 0) do (
		rowText += " ["
		for itemIndex in 1 to differences.count do (
			if (itemIndex > 1) do rowText += ", "
			rowText += differences[itemIndex]
		)
		rowText += "]"
	)
	return rowText
)

fn GCMatterportUVChannelsMatch sourceMesh sourceChannel resultMesh resultChannel = (
	if (sourceMesh.numfaces != resultMesh.numfaces or not meshop.getMapSupport sourceMesh sourceChannel or not meshop.getMapSupport resultMesh resultChannel) do return false
	for faceIndex in 1 to sourceMesh.numfaces do (
		local sourceFace = meshop.getMapFace sourceMesh sourceChannel faceIndex
		local resultFace = meshop.getMapFace resultMesh resultChannel faceIndex
		for cornerIndex in 1 to 3 do (
			local sourceUV = meshop.getMapVert sourceMesh sourceChannel sourceFace[cornerIndex]
			local resultUV = meshop.getMapVert resultMesh resultChannel resultFace[cornerIndex]
			if (distance sourceUV resultUV > 0.00001) do return false
		)
	)
	return true
)

fn GCMatterportValidatePackedUVs sourceMesh resultMesh selectedIDs = (
	if (not GCMatterportUVChannelsMatch sourceMesh 1 resultMesh 1) do return "Source UV channel 1 changed."
	if (not meshop.getMapSupport resultMesh 2) do return "Result UV channel 2 is missing."
	local uvBounds = for materialID in selectedIDs collect #(1e9, 1e9, -1e9, -1e9, 0)
	for faceIndex in 1 to resultMesh.numfaces do (
		local materialID = getFaceMatID resultMesh faceIndex
		if (getFaceMatID sourceMesh faceIndex != materialID) do return "Face material IDs changed."
		local idIndex = findItem selectedIDs materialID
		local sourceFace = meshop.getMapFace sourceMesh 1 faceIndex
		local resultFace = meshop.getMapFace resultMesh 2 faceIndex
		for cornerIndex in 1 to 3 do (
			local resultUV = meshop.getMapVert resultMesh 2 resultFace[cornerIndex]
			if (idIndex == 0) then (
				local sourceUV = meshop.getMapVert sourceMesh 1 sourceFace[cornerIndex]
				if (distance sourceUV resultUV > 0.00001) do return "An unselected material ID was repacked."
			) else (
				local idBounds = uvBounds[idIndex]
				idBounds[1] = amin idBounds[1] resultUV.x
				idBounds[2] = amin idBounds[2] resultUV.y
				idBounds[3] = amax idBounds[3] resultUV.x
				idBounds[4] = amax idBounds[4] resultUV.y
				idBounds[5] += 1
			)
		)
	)
	for idIndex in 1 to selectedIDs.count do (
		local idBounds = uvBounds[idIndex]
		if (idBounds[5] == 0 or idBounds[1] < -0.0001 or idBounds[2] < -0.0001 or idBounds[3] > 1.0001 or idBounds[4] > 1.0001) do return ("ID " + (selectedIDs[idIndex] as string) + " did not pack into 0..1.")
	)
	return undefined
)

fn GCMatterportSaveAOOptions materialEntry aoOptions = (
	if (not GCMatterportIsCurrentMaterialEntry materialEntry) do return false
	local propertyKey = GCMatterportAOKey materialEntry
	GCMatterportSceneProperties.setValue (propertyKey + "enabled") aoOptions.useCoronaAO
	GCMatterportSceneProperties.setValue (propertyKey + "passes") aoOptions.passes
	GCMatterportSceneProperties.setValue (propertyKey + "sizeCM") aoOptions.sizeCM
	GCMatterportSceneProperties.setValue (propertyKey + "denoise") aoOptions.useVRayDenoiser
	GCMatterportSceneProperties.setValue (propertyKey + "override") aoOptions.customResolution
	GCMatterportSceneProperties.setValue (propertyKey + "manualResolution") aoOptions.manualResolution
	return true
)

fn GCMatterportGetMaterials selectedLayerNames = (
	local materialEntries = #()
	if (glTFMaterial == undefined) do return materialEntries
	for selectedLayerName in selectedLayerNames do (
		local lodLayer = LayerManager.getLayerFromName selectedLayerName
		local layerNodes = #()
		if (lodLayer != undefined) do lodLayer.nodes &layerNodes
		if (layerNodes.count == 1) do (
			local sceneNode = layerNodes[1]
			local parentMaterial = sceneNode.material
			if (parentMaterial != undefined and classOf parentMaterial == MultiMaterial) do (
				for slotIndex in 1 to parentMaterial.materialList.count do (
					local subMaterial = parentMaterial.materialList[slotIndex]
					if (slotIndex <= parentMaterial.materialIDList.count and subMaterial != undefined and classOf subMaterial == glTFMaterial) do (
						local actualMaterialID = parentMaterial.materialIDList[slotIndex]
						local rowText = (actualMaterialID as string) + ": " + subMaterial.name
						local materialEntry = GCMatterportMaterialEntry layerName: selectedLayerName nodeRef: sceneNode materialRef: subMaterial slotIndex: slotIndex materialID: actualMaterialID materialName: subMaterial.name displayText: rowText
						materialEntry.displayText = GCMatterportFormatMaterialRow materialEntry
						append materialEntries materialEntry
					)
				)
			)
		)
	)
	return materialEntries
)


fn GCMatterportLODHasAO layerName = (
	local materialEntries = GCMatterportGetMaterials #(layerName)
	if (materialEntries.count == 0) do return false
	if (materialEntries.count != materialEntries[1].nodeRef.material.materialList.count) do return false
	local requiredCount = 0
	local seenIDs = #()
	for materialEntry in materialEntries do (
		if (not GCMatterportIsCurrentMaterialEntry materialEntry or materialEntry.materialID < 1 or (findItem seenIDs materialEntry.materialID) != 0) do return false
		append seenIDs materialEntry.materialID
		local isEnabled = GCMatterportSceneProperties.getValue ((GCMatterportAOKey materialEntry) + "enabled") true
		if (classOf isEnabled != BooleanClass) do return false
		if (isEnabled) do (
			requiredCount += 1
			if (not GCMatterportHasAOMap materialEntry.materialRef) do return false
		)
	)
	return (requiredCount > 0)
)

fn GCMatterportExportFileName layerName = (
	local fileName = layerName
	for invalidCharacter in #("\\", "/", ":", "*", "?", "\"", "<", ">", "|") do fileName = substituteString fileName invalidCharacter "_"
	return (trimRight fileName " .") + ".glb"
)

fn GCMatterportLODHasGLB layerName = (
	if (maxFilePath == "" or maxFileName == "") do return false
	local filePath = maxFilePath + "export\\" + (GCMatterportExportFileName layerName)
	-- Presence only; this does not assert that the file matches the latest scene edits.
	return (doesFileExist filePath and getFileSize filePath > 0)
)

fn GCMatterportGetData = (
	local lodLayerNames = #()
	for layerIndex in 0 to (LayerManager.count - 1) do (
		local sceneLayerName = (LayerManager.getLayer layerIndex).name
		if ((findString (toLower sceneLayerName) "_lod") != undefined) do append lodLayerNames sceneLayerName
	)
	sort lodLayerNames
	return for sceneLayerName in lodLayerNames collect (
		local lodLayer = LayerManager.getLayerFromName sceneLayerName
		local layerNodes = #()
		if (lodLayer != undefined) do lodLayer.nodes &layerNodes
		local isLayerReady = GCMatterportIsLODReady layerNodes
		local displayPrefix = ""
		if (layerNodes.count > 1) then (
			displayPrefix = "[ERROR: More than one object] "
		) else if (isLayerReady) then (
			displayPrefix = "[" + ((dotNetClass "System.Char").ConvertFromUtf32 10003) + "] "
		) else if (layerNodes.count == 1) do (
			displayPrefix = "[Only Object] "
		)
		local glbPrefix = if (GCMatterportLODHasGLB sceneLayerName) then "[GLB] " else ""
		local aoPrefix = if (isLayerReady and GCMatterportLODHasAO sceneLayerName) then "[AO] " else ""
		GCMatterportLODEntry layerName: sceneLayerName displayText: (glbPrefix + aoPrefix + displayPrefix + sceneLayerName) objectCount: layerNodes.count isReady: isLayerReady
	)
)

fn GCMatterportLODsReady = (
	local lodEntries = GCMatterportGetData()
	if (lodEntries.count == 0) do return false
	for lodEntry in lodEntries do (
		if (not lodEntry.isReady) do return false
	)
	return true
)

global GCMatterportConfirmationContext = #("", "OK")

fn GCMatterportConfirmTyped messageContent expectedText: "OK" = (
	if (expectedText == "") do return false
	GCMatterportConfirmationContext = #(messageContent, expectedText)
	rollout typedConfirmation "Confirm LOD transfer" (
		local promptContent = ""
		local requiredText = "OK"
		local wasConfirmed = false

		label lblPrompt "" width: 380 height: 18 align: #left
		label lblInstruction "" width: 380 align: #left
		edittext edtConfirmation "" width: 380
		button btnConfirm "Confirm" width: 120 across: 2 enabled: false
		button btnCancel "Cancel" width: 120

		fn hasExpectedInput = (
			local typedText = trimLeft (trimRight edtConfirmation.text " \t\r\n") " \t\r\n"
			return (dotNetClass "System.String").Equals typedText requiredText (dotNetClass "System.StringComparison").Ordinal
		)

		fn wrapPrompt promptText = (
			local wrappedText = ""
			local currentLine = ""
			for characterIndex in 1 to promptText.count do (
				local nextCharacter = substring promptText characterIndex 1
				if (nextCharacter == "\n") then (
					wrappedText += currentLine + "\n"
					currentLine = ""
				) else (
					local measuredSize = getTextExtent (currentLine + nextCharacter)
					if (measuredSize.x > 360 and currentLine != "") do (
						wrappedText += currentLine + "\n"
						currentLine = ""
					)
					currentLine += nextCharacter
				)
			)
			return wrappedText + currentLine
		)

		on typedConfirmation open do (
			promptContent = GCMatterportConfirmationContext[1]
			requiredText = GCMatterportConfirmationContext[2]
			wasConfirmed = false
			lblPrompt.text = wrapPrompt promptContent
			local promptLines = filterString lblPrompt.text "\n" splitEmptyTokens: true
			local fontExtent = getTextExtent "Ag"
			local promptHeight = promptLines.count * (fontExtent.y + 2)
			-- Position controls below measured text, including wrapped layer names.
			lblPrompt.pos = [15, 12]
			lblPrompt.height = promptHeight
			lblInstruction.pos = [15, 12 + promptHeight + 8]
			edtConfirmation.pos = [15, 12 + promptHeight + 30]
			btnConfirm.pos = [79, 12 + promptHeight + 60]
			btnCancel.pos = [211, 12 + promptHeight + 60]
			setDialogSize typedConfirmation [410, 12 + promptHeight + 94]
			lblInstruction.text = "Type " + requiredText + " to confirm."
			edtConfirmation.text = ""
			btnConfirm.enabled = false
			setFocus edtConfirmation
		)
		on edtConfirmation changed typedText do (
			btnConfirm.enabled = hasExpectedInput()
		)
		on btnConfirm pressed do (
			if (hasExpectedInput()) do (
				wasConfirmed = true
				destroyDialog typedConfirmation
			)
		)
		on btnCancel pressed do destroyDialog typedConfirmation
	)
	GCMatterportConfirmationContext = #(messageContent, expectedText)
	createDialog typedConfirmation width: 410 modal: true escapeEnable: false
	GCMatterportConfirmationContext = #("", "OK")
	return typedConfirmation.wasConfirmed
)

global _rExportGCMatterportGLBConverter


rcmenu GCMatterportMaterialContextMenu (
	submenu "Use Corona AO" (
		menuItem aoEnable "Enable"
		menuItem aoDisable "Disable"
	)
	submenu "Passes" (
		menuItem passes1 "1"
		menuItem passes5 "5"
		menuItem passes15 "15"
		menuItem passes30 "30"
		menuItem passes60 "60"
		menuItem passes100 "100"
		menuItem passes150 "150"
	)
	submenu "Override Resolution" (
		menuItem resolution512 "512"
		menuItem resolution1024 "1024"
		menuItem resolution2048 "2048"
		menuItem resolution4096 "4096"
	)
	submenu "Size (cm)" (
		menuItem size5 "5"
		menuItem size15 "15"
		menuItem size30 "30"
		menuItem size60 "60"
		menuItem size100 "100"
	)
	submenu "V-Ray Denoiser" (
		menuItem denoiserEnable "Enable"
		menuItem denoiserDisable "Disable"
	)
	on aoEnable picked do _rExportGCMatterportGLBConverter.batchAOSetting #enabled true
	on aoDisable picked do _rExportGCMatterportGLBConverter.batchAOSetting #enabled false
	on passes1 picked do _rExportGCMatterportGLBConverter.batchAOSetting #passes 1
	on passes5 picked do _rExportGCMatterportGLBConverter.batchAOSetting #passes 5
	on passes15 picked do _rExportGCMatterportGLBConverter.batchAOSetting #passes 15
	on passes30 picked do _rExportGCMatterportGLBConverter.batchAOSetting #passes 30
	on passes60 picked do _rExportGCMatterportGLBConverter.batchAOSetting #passes 60
	on passes100 picked do _rExportGCMatterportGLBConverter.batchAOSetting #passes 100
	on passes150 picked do _rExportGCMatterportGLBConverter.batchAOSetting #passes 150
	on resolution512 picked do _rExportGCMatterportGLBConverter.batchAOSetting #resolution 512
	on resolution1024 picked do _rExportGCMatterportGLBConverter.batchAOSetting #resolution 1024
	on resolution2048 picked do _rExportGCMatterportGLBConverter.batchAOSetting #resolution 2048
	on resolution4096 picked do _rExportGCMatterportGLBConverter.batchAOSetting #resolution 4096
	on size5 picked do _rExportGCMatterportGLBConverter.batchAOSetting #sizeCM 5.0
	on size15 picked do _rExportGCMatterportGLBConverter.batchAOSetting #sizeCM 15.0
	on size30 picked do _rExportGCMatterportGLBConverter.batchAOSetting #sizeCM 30.0
	on size60 picked do _rExportGCMatterportGLBConverter.batchAOSetting #sizeCM 60.0
	on size100 picked do _rExportGCMatterportGLBConverter.batchAOSetting #sizeCM 100.0
	on denoiserEnable picked do _rExportGCMatterportGLBConverter.batchAOSetting #denoise true
	on denoiserDisable picked do _rExportGCMatterportGLBConverter.batchAOSetting #denoise false
)


struct GCMatterportExportJob (layerName, nodeRef, fileName, textureLimit, exportMaterial)


fn GCMatterportBuildExportMaterial sceneNode = (
	local sourceParent = sceneNode.material
	local exportParent = copy sourceParent
	for slotIndex in 1 to sourceParent.materialList.count do (
		local sourceMaterial = sourceParent.materialList[slotIndex]
		local materialID = sourceParent.materialIDList[slotIndex]
		local sourceEntry = GCMatterportMaterialEntry layerName: sceneNode.layer.name nodeRef: sceneNode materialRef: sourceMaterial slotIndex: slotIndex materialID: materialID
		local aoEnabled = GCMatterportSceneProperties.getValue ((GCMatterportAOKey sourceEntry) + "enabled") true
		-- Each slot gets its own instance, even when source slots share one material.
		local exportMaterial = copy sourceMaterial
		if (aoEnabled == false) do exportMaterial.ambientOcclusionMap = undefined
		exportParent.materialList[slotIndex] = exportMaterial
	)
	return exportParent
)

fn GCMatterportExportPreflight layerNames = (
	local exportJobs = #()
	local issues = #()
	if (maxFilePath == "" or maxFileName == "") do append issues "Save the MAX scene first. Output belongs in the scene's export folder."
	if (GLTF_Export == undefined or (findItem exporterPlugin.classes GLTF_Export) == 0) do append issues "The native glTF exporter is unavailable. Install or enable the 3ds Max glTF exporter."
	for fileName in #("gltfpack.exe", "gltfpack_webgl.bat") where (not doesFileExist (GCMatterportRuntimeFolder + fileName)) do append issues ("Missing runtime file: " + fileName + ". Restore it beside the converter script.")
	for folderPath in #(maxFilePath, GCMatterportRuntimeFolder) do (
		for forbiddenPart in #("%", ";", "\r", "\n") where (findString folderPath forbiddenPart != undefined) do append issues "The WebGL batch pipeline requires scene/script paths without %, semicolons or line breaks."
	)
	local referenceIDs = undefined
	local referenceLayer = ""
	local outputNames = #()
	for layerName in layerNames do (
		local lodLayer = LayerManager.getLayerFromName layerName
		local layerNodes = #()
		if (lodLayer != undefined) do lodLayer.nodes &layerNodes
		local limitPixels = GCMatterportAutomaticAOResolution layerName
		if (limitPixels == undefined) do append issues (layerName + ": use a LOD0, LOD1, LOD2 or LOD3 suffix so the texture limit is known.")
		local fileName = GCMatterportExportFileName layerName
		if ((findItem outputNames (toLower fileName)) != 0) do append issues (layerName + ": its export filename conflicts with another selected LOD. Rename one layer.")
		append outputNames (toLower fileName)
		for forbiddenPart in #("%", ";", "\r", "\n") where (findString fileName forbiddenPart != undefined) do append issues (layerName + ": remove %, semicolons or line breaks from the layer name.")
		if (layerNodes.count != 1) then (
			append issues (layerName + ": expected exactly one object; found " + (layerNodes.count as string) + ". Move the intended object into this layer and remove extra objects.")
		) else (
			local sceneNode = layerNodes[1]
			local entryCaption = layerName + " / " + sceneNode.name
			local materialIDs = #()
			local parentMaterial = sceneNode.material
			local validSlots = true
			local exportMaterial = undefined
			if (parentMaterial == undefined or classOf parentMaterial != MultiMaterial) then (
				validSlots = false
				append issues (entryCaption + ": assign a Multi/Sub-Object material containing glTF materials.")
			) else (
				local slotCount = parentMaterial.materialList.count
				if (slotCount == 0 or slotCount != parentMaterial.materialIDList.count) do (
					validSlots = false
					append issues (entryCaption + ": the Multi/Sub-Object material needs at least one slot and one actual Material ID per slot.")
				)
				for slotIndex in 1 to slotCount do (
					local subMaterial = parentMaterial.materialList[slotIndex]
					if (subMaterial == undefined or classOf subMaterial != glTFMaterial) do (
						validSlots = false
						append issues (entryCaption + " / slot " + (slotIndex as string) + ": assign a glTF material; empty, nested Multi and other material types cannot be exported.")
					)
					if (slotIndex <= parentMaterial.materialIDList.count) do (
						local materialID = parentMaterial.materialIDList[slotIndex]
						if (materialID < 1 or materialID > 65535 or (findItem materialIDs materialID) != 0) do (
							validSlots = false
							append issues (entryCaption + " / ID " + (materialID as string) + ": assign a unique Material ID between 1 and 65535.")
						)
						append materialIDs materialID
					)
				)
				sort materialIDs
				if (validSlots) do (
					if (referenceIDs == undefined) then (
						referenceIDs = materialIDs
						referenceLayer = layerName
					) else if ((materialIDs as string) != (referenceIDs as string)) do append issues (entryCaption + ": the slot count and actual Material ID set must match " + referenceLayer + " " + (referenceIDs as string) + "; found " + (materialIDs as string) + ". Match the selected LOD materials before exporting.")
				)
				if (validSlots) do (
					exportMaterial = GCMatterportBuildExportMaterial sceneNode
					-- Excluded AO maps are already absent, so missing excluded AO files do not block export.
					for bitmapMap in (getClassInstances Bitmaptexture target: exportMaterial) do (
						local texturePath = mapPaths.getFullFilePath bitmapMap.filename
						if (texturePath == undefined or texturePath == "" or not doesFileExist texturePath) do append issues (entryCaption + ": missing exported texture '" + bitmapMap.filename + "'. Relink the image before exporting.")
					)
				)
			)
			local sourceMesh = undefined
			try (
				if (superClassOf sceneNode != GeometryClass) do throw "Not geometry"
				sourceMesh = snapshotAsMesh sceneNode
				if (sourceMesh.numfaces == 0) do throw "No mesh faces"
				if (parentMaterial != undefined and classOf parentMaterial == MultiMaterial) do (
					local missingIDs = #()
					for faceIndex in 1 to sourceMesh.numfaces do (
						local faceID = getFaceMatID sourceMesh faceIndex
						if ((findItem materialIDs faceID) == 0) do appendIfUnique missingIDs faceID
					)
					if (missingIDs.count > 0) do append issues (entryCaption + ": faces use Material IDs without matching glTF slots " + (missingIDs as string) + ". Correct the face IDs or add matching glTF slots.")
				)
			) catch (
				append issues (entryCaption + ": export requires geometry that evaluates to a non-empty mesh. Check the object and its modifiers.")
			)
			if (sourceMesh != undefined) do delete sourceMesh
			append exportJobs (GCMatterportExportJob layerName: layerName nodeRef: sceneNode fileName: fileName textureLimit: limitPixels exportMaterial: exportMaterial)
		)
	)
	return #(exportJobs, issues)
)

fn GCMatterportValidateGLB filePath = (
	if (not doesFileExist filePath or getFileSize filePath <= 0) do throw "WebGL packing did not produce a non-empty GLB file."
	return true
)

fn GCMatterportExportOneLOD exportJob exportFolder = (
	local originalSelection = selection as array
	local originalPanelMode = getCommandPanelTaskMode()
	local originalStackObject = modPanel.getCurrentObject()
	local originalSubObjectLevel = subObjectLevel
	local temporaryNode = undefined
	local temporaryLayer = undefined
	local failureReason = undefined
	local runToken = ((dotNetClass "System.Guid").NewGuid()).ToString "N"
	local stagingFolder = exportFolder + "._gclod_" + runToken + "\\"
	local stagedGLB = stagingFolder + exportJob.fileName
	local finalGLB = exportFolder + exportJob.fileName
	try (
		if (not isValidNode exportJob.nodeRef or exportJob.nodeRef.layer.name != exportJob.layerName) do throw "The LOD object changed. Refresh the list before exporting."
		if (not makeDir stagingFolder all: true) do throw "Cannot create the export folder. Check folder permissions."
		subObjectLevel = 0
		setCommandPanelTaskMode mode: #create
		with undo off (
			temporaryLayer = LayerManager.newLayerFromName ("GC_Export_" + runToken)
			if (temporaryLayer == undefined) do throw "Cannot create the temporary export layer."
			temporaryNode = copy exportJob.nodeRef
			local worldTransform = temporaryNode.transform
			temporaryNode.parent = undefined
			temporaryNode.transform = worldTransform
			temporaryLayer.addNode temporaryNode
			temporaryNode.isHidden = false
			temporaryNode.isFrozen = false
			convertToMesh temporaryNode
			temporaryNode.material = exportJob.exportMaterial
			-- All bitmap filenames point to owned copies before the native exporter is called.
			local mapsFolder = stagingFolder + "maps\\"
			makeDir mapsFolder all: true
			local bitmapMaps = getClassInstances Bitmaptexture target: temporaryNode.material
			for mapIndex in 1 to bitmapMaps.count do (
				local bitmapMap = bitmapMaps[mapIndex]
				local sourceImage = mapPaths.getFullFilePath bitmapMap.filename
				local copiedImage = mapsFolder + (mapIndex as string) + (getFilenameType sourceImage)
				if (not copyFile sourceImage copiedImage) do throw ("Cannot copy the referenced texture: " + sourceImage)
				bitmapMap.filename = copiedImage
			)
			select temporaryNode
			local intermediateGLTF = stagingFolder + "scene.gltf"
			if (not exportFile intermediateGLTF #noPrompt selectedOnly: true using: GLTF_Export) do throw "Native glTF export failed or was cancelled."
			if (not doesFileExist intermediateGLTF) do throw "Native glTF export produced no file."
			local batchPath = GCMatterportRuntimeFolder + "gltfpack_webgl.bat"
			local commandLine = "/d /v:off /s /c \"\"" + batchPath + "\" \"" + intermediateGLTF + ";" + stagedGLB + ";" + (exportJob.textureLimit as string) + "\"\""
			local commandExecutable = (dotNetClass "System.Environment").SystemDirectory + "\\cmd.exe"
			GCMatterportRunAOProcess commandExecutable commandLine GCMatterportRuntimeFolder operationLabel: "WebGL export"
		)
		GCMatterportValidateGLB stagedGLB
		-- Publish only a validated GLB. A failed export never deletes an existing result.
		if (doesFileExist finalGLB) then (
			(dotNetClass "System.IO.File").Replace stagedGLB finalGLB (stagingFolder + "previous.glb")
		) else (
			(dotNetClass "System.IO.File").Move stagedGLB finalGLB
		)
	) catch (failureReason = getCurrentException() as string)
	with undo off (
		try (
			if (isValidNode temporaryNode) do delete temporaryNode
			if (temporaryLayer != undefined) do LayerManager.deleteLayerByName temporaryLayer.name
		) catch (failureReason = "Could not remove temporary export geometry: " + (getCurrentException() as string))
		try (
			select (for sceneNode in originalSelection where (isValidNode sceneNode) collect sceneNode)
			setCommandPanelTaskMode mode: originalPanelMode
			if (originalPanelMode == #modify and originalStackObject != undefined) do modPanel.setCurrentObject originalStackObject
			subObjectLevel = originalSubObjectLevel
		) catch (failureReason = "Could not fully restore the original selection/panel: " + (getCurrentException() as string))
	)
	try (
		local pathClass = dotNetClass "System.IO.Path"
		local resolvedFolder = pathClass.GetFullPath stagingFolder
		local expectedFolder = pathClass.GetFullPath (exportFolder + "._gclod_" + runToken + "\\")
		local resolvedRoot = pathClass.GetFullPath exportFolder
		if (resolvedFolder != expectedFolder or not (dotNetObject "System.String" resolvedFolder).StartsWith resolvedRoot (dotNetClass "System.StringComparison").OrdinalIgnoreCase) do throw "Refusing cleanup outside the owned export staging folder."
		if (doesDirectoryExist resolvedFolder) do (dotNetClass "System.IO.Directory").Delete resolvedFolder true
	) catch (
		format "Export staging cleanup: %\n" (getCurrentException())
	)
	return failureReason
)


global GCMatterportPreviewProcess
global GCMatterportPreviewPort
global GCMatterportPreviewRoot
global GCMatterportPreviewToken

fn GCMatterportStopPreviewServer = (
	if (GCMatterportPreviewProcess != undefined) do (
		try (
			if (not GCMatterportPreviewProcess.HasExited) do GCMatterportPreviewProcess.Kill()
			GCMatterportPreviewProcess.Dispose()
		) catch (format "Preview server cleanup: %\n" (getCurrentException()))
	)
	GCMatterportPreviewProcess = undefined
	GCMatterportPreviewPort = undefined
	return true
)

fn GCMatterportPreviewServerReady portNumber expectedToken = (
	local response = undefined
	local reader = undefined
	local isReady = false
	try (
		local request = (dotNetClass "System.Net.WebRequest").Create ("http://127.0.0.1:" + (portNumber as string) + "/viewer-ready.txt")
		request.Timeout = 300
		request.ReadWriteTimeout = 300
		request.Proxy = undefined
		response = request.GetResponse()
		reader = dotNetObject "System.IO.StreamReader" (response.GetResponseStream())
		isReady = ((reader.ReadToEnd()) == expectedToken)
	) catch (isReady = false)
	if (reader != undefined) do reader.Dispose()
	if (response != undefined) do response.Dispose()
	return isReady
)

fn GCMatterportEnsurePreviewServer viewerFolder = (
	if (GCMatterportPreviewProcess != undefined) do (
		if (not GCMatterportPreviewProcess.HasExited and GCMatterportPreviewRoot == viewerFolder) do (
			if (GCMatterportPreviewServerReady GCMatterportPreviewPort GCMatterportPreviewToken) do return GCMatterportPreviewPort
		)
		GCMatterportStopPreviewServer()
	)
	local serverExecutable = viewerFolder + "localhost.exe"
	GCMatterportPreviewRoot = viewerFolder
	GCMatterportPreviewToken = ((dotNetClass "System.Guid").NewGuid()).ToString "N"
	(dotNetClass "System.IO.File").WriteAllText (viewerFolder + "viewer-ready.txt") GCMatterportPreviewToken
	-- Choose a free port; retry if another process takes it between reservation and launch.
	for attemptIndex in 1 to 3 do (
		local listener = dotNetObject "System.Net.Sockets.TcpListener" (dotNetClass "System.Net.IPAddress").Loopback 0
		listener.Start()
		local localEndpoint = listener.LocalEndpoint
		local portNumber = localEndpoint.Port
		listener.Stop()
		local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
		startInfo.FileName = serverExecutable
		startInfo.Arguments = "\"" + (trimRight viewerFolder "\\/") + "\" " + (portNumber as string) + " 127.0.0.1"
		startInfo.WorkingDirectory = viewerFolder
		startInfo.UseShellExecute = false
		startInfo.CreateNoWindow = true
		startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden
		GCMatterportPreviewProcess = (dotNetClass "System.Diagnostics.Process").Start startInfo
		for waitIndex in 1 to 15 while (not GCMatterportPreviewProcess.HasExited) do (
			if (GCMatterportPreviewServerReady portNumber GCMatterportPreviewToken) do (
				GCMatterportPreviewPort = portNumber
				callbacks.removeScripts id: #GCMatterportPreviewShutdown
				callbacks.addScript #preSystemShutdown "GCMatterportStopPreviewServer()" id: #GCMatterportPreviewShutdown
				return portNumber
			)
			sleep 0.1
		)
		GCMatterportStopPreviewServer()
	)
	throw "The local Model Viewer server could not start. Check that localhost.exe is allowed to listen on the loopback interface."
)


fn GCMatterportViewerFiles = (
	return #("index.html", "js\\engine.js", "js\\basis\\basis_transcoder.js", "js\\basis\\basis_transcoder.wasm", "hdri\\studio.hdr", "localhost.exe", "mime.types", "favicon-16x16.png")
)

fn GCMatterportViewerIsInstalled viewerFolder = (
	for relativeFile in GCMatterportViewerFiles() do (
		local fileInfo = dotNetObject "System.IO.FileInfo" (viewerFolder + relativeFile)
		if (not fileInfo.Exists or fileInfo.Length == 0) do return false
	)
	return true
)


fn GCMatterportDownloadFile sourceURL destination = (
	local client = dotNetObject "System.Net.WebClient"
	local downloadError = undefined
	try (
		client.DownloadFile sourceURL destination
		local downloadedFile = dotNetObject "System.IO.FileInfo" destination
		if (not downloadedFile.Exists or downloadedFile.Length == 0) do throw "The downloaded file is empty."
	) catch (downloadError = getCurrentException() as string)
	client.Dispose()
	if (downloadError != undefined) do throw downloadError
	return true
)

fn GCMatterportPrepareViewer stageRoot = (
	local engineText = (dotNetClass "System.IO.File").ReadAllText (stageRoot + "\\js\\engine.js")
	local decoderMatch = (dotNetClass "System.Text.RegularExpressions.Regex").Match engineText "https://www[.]gstatic[.]com/basis-universal/versioned/[A-Za-z0-9_-]+/"
	if (not decoderMatch.Success) do throw "The viewer engine does not specify a supported Basis decoder version."
	makeDir (stageRoot + "\\js\\basis") all:true
	for decoderName in #("basis_transcoder.js", "basis_transcoder.wasm") do (
		GCMatterportDownloadFile (decoderMatch.Value + decoderName) (stageRoot + "\\js\\basis\\" + decoderName)
	)
	local utf8 = dotNetObject "System.Text.UTF8Encoding" false
	(dotNetClass "System.IO.File").WriteAllText (stageRoot + "\\index.html") "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"UTF-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n<title>Model Viewer</title>\n<link rel=\"icon\" type=\"image/png\" sizes=\"16x16\" href=\"/favicon-16x16.png\">\n<style>\nhtml, body { padding: 0; margin: 0; background: #f7f7f7; }\nmodel-viewer { width: 100vw; height: 100vh; }\n#error { position: fixed; top: 16px; left: 16px; right: 16px; padding: 12px; background: white; color: #900; font: 14px sans-serif; }\n</style>\n</head>\n<body>\n<model-viewer alt=\"\" shadow-intensity=\"1\" camera-controls\n environment-image=\"hdri/studio.hdr\" camera-orbit=\"-36deg 72deg\" field-of-view=\"30deg\"\n exposure=\"0.4\" tone-mapping=\"aces\" min-field-of-view=\"50deg\"\n max-field-of-view=\"50deg\" touch-action=\"pan-y\"></model-viewer>\n<div id=\"error\" hidden></div>\n<script type=\"module\">\nconst errorBox = document.querySelector('#error');\nconst reportError = message => { errorBox.textContent = message; errorBox.hidden = false; };\ntry {\n    const engineResponse = await fetch('/js/engine.js');\n    if (!engineResponse.ok) throw new Error('Cannot load Model Viewer engine: ' + engineResponse.status);\n    const engineURL = URL.createObjectURL(new Blob([await engineResponse.text()], { type: 'application/javascript' }));\n    try { await import(engineURL); } finally { URL.revokeObjectURL(engineURL); }\n    const viewerClass = customElements.get('model-viewer');\n    viewerClass.ktx2TranscoderLocation = '/js/basis/';\n    const parameters = new URLSearchParams(location.search);\n    const model = parameters.get('model');\n    if (!model || !/^[a-f0-9]{64}$/.test(model)) throw new Error('A valid exported LOD is required.');\n    const viewer = document.querySelector('model-viewer');\n    document.title = parameters.get('title') || 'Model Viewer';\n    viewer.alt = document.title;\n    window.devicePixelRatio = 2;\n    viewer.addEventListener('error', () => reportError('The exported GLB could not be loaded.'));\n    viewer.src = '/models/' + encodeURIComponent(model) + '.glb?v=' + encodeURIComponent(parameters.get('v') || '');\n} catch (error) {\n    reportError(error.message || 'Model Viewer could not start.');\n}\n</script>\n</body>\n</html>\n" utf8
	(dotNetClass "System.IO.File").WriteAllText (stageRoot + "\\mime.types") "application/javascript js\napplication/wasm wasm\nmodel/gltf-binary glb\nimage/vnd.radiance hdr\ntext/html html\ntext/plain txt\nimage/png png\n" utf8
	return true
)

fn GCMatterportInstallViewerArchive archivePath prepareOriginal:false normalizedArchive:undefined = (
	local installRoot = GCMatterportRuntimeFolder + "model-viewer"
	local stageRoot = GCMatterportRuntimeFolder + "._viewer_" + ((dotNetClass "System.Guid").NewGuid()).ToString("N")
	local backupRoot = stageRoot + "_previous"
	local archive = undefined
	local installFailure = undefined
	local replacedOld = false
	try (
		dotNet.loadAssembly "System.IO.Compression"
		dotNet.loadAssembly "System.IO.Compression.FileSystem"
		makeDir stageRoot all:true
		archive = (dotNetClass "System.IO.Compression.ZipFile").OpenRead archivePath
		-- Extract only the known runtime paths; archive paths never determine destinations.
		for relativeFile in GCMatterportViewerFiles() where (not prepareOriginal or (findItem #("js\\basis\\basis_transcoder.js", "js\\basis\\basis_transcoder.wasm") relativeFile) == 0) do (
			local entry = archive.GetEntry (substituteString relativeFile "\\" "/")
			if (entry == undefined or entry.Length == 0) do throw ("Viewer archive is missing: " + relativeFile)
			local destination = stageRoot + "\\" + relativeFile
			makeDir (getFilenamePath destination) all:true
			(dotNetClass "System.IO.Compression.ZipFileExtensions").ExtractToFile entry destination false
		)
		archive.Dispose()
		archive = undefined
		if (prepareOriginal) do GCMatterportPrepareViewer stageRoot
		if (not GCMatterportViewerIsInstalled (stageRoot + "\\")) do throw "The extracted viewer is incomplete."
		if (normalizedArchive != undefined) do (dotNetClass "System.IO.Compression.ZipFile").CreateFromDirectory stageRoot normalizedArchive
		GCMatterportStopPreviewServer()
		if (doesDirectoryExist installRoot) do (
			(dotNetClass "System.IO.Directory").Move installRoot backupRoot
			replacedOld = true
		)
		(dotNetClass "System.IO.Directory").Move stageRoot installRoot
	) catch (installFailure = getCurrentException() as string)
	if (archive != undefined) do archive.Dispose()
	if (installFailure != undefined and replacedOld and not doesDirectoryExist installRoot) do (
		(dotNetClass "System.IO.Directory").Move backupRoot installRoot
		replacedOld = false
	)
	-- These paths are generated for this invocation directly beneath the runtime root.
	if (doesDirectoryExist stageRoot) do try ((dotNetClass "System.IO.Directory").Delete stageRoot true) catch (format "Viewer staging cleanup: %\n" (getCurrentException()))
	if (installFailure == undefined and replacedOld) do try ((dotNetClass "System.IO.Directory").Delete backupRoot true) catch (format "Previous viewer cleanup: %\n" (getCurrentException()))
	if (installFailure != undefined) do throw installFailure
	return true
)


fn GCMatterportUpdateViewer = (
	local token = ((dotNetClass "System.Guid").NewGuid()).ToString("N")
	local downloadedArchive = GCMatterportRuntimeFolder + "._viewer_" + token + ".download.zip"
	local readyArchive = GCMatterportRuntimeFolder + "._viewer_" + token + ".ready.zip"
	local backupArchive = GCMatterportRuntimeFolder + "._viewer_" + token + ".previous.zip"
	local archivePath = GCMatterportRuntimeFolder + "model-viewer.zip"
	local updateFailure = undefined
	try (
		GCMatterportDownloadFile "https://raw.githubusercontent.com/MastaArt/GC-Tools/main/model-viewer.zip" downloadedArchive
		GCMatterportInstallViewerArchive downloadedArchive prepareOriginal:true normalizedArchive:readyArchive
		if (doesFileExist archivePath) then (
			(dotNetClass "System.IO.File").Replace readyArchive archivePath backupArchive
		) else (
			(dotNetClass "System.IO.File").Move readyArchive archivePath
		)
	) catch (updateFailure = getCurrentException() as string)
	for temporaryFile in #(downloadedArchive, readyArchive, backupArchive) where (doesFileExist temporaryFile) do (
		try (deleteFile temporaryFile) catch (format "Viewer archive cleanup: %\n" (getCurrentException()))
	)
	if (updateFailure != undefined) do throw updateFailure
	return true
)

fn GCMatterportEnsureViewerInstalled = (
	local viewerFolder = GCMatterportRuntimeFolder + "model-viewer\\"
	if (GCMatterportViewerIsInstalled viewerFolder) do return true
	local archivePath = GCMatterportRuntimeFolder + "model-viewer.zip"
	if (not doesFileExist archivePath) do return GCMatterportUpdateViewer()
	return GCMatterportInstallViewerArchive archivePath
)

fn GCMatterportPreviewLOD layerName = (
	if (not GCMatterportLODHasGLB layerName) do throw "Export this LOD to GLB before opening its preview."
	GCMatterportEnsureViewerInstalled()
	local viewerFolder = GCMatterportRuntimeFolder + "model-viewer\\"
	for relativeFile in #("index.html", "js\\engine.js", "js\\basis\\basis_transcoder.js", "js\\basis\\basis_transcoder.wasm", "hdri\\studio.hdr", "localhost.exe", "mime.types") do (
		if (not doesFileExist (viewerFolder + relativeFile)) do throw ("Model Viewer runtime file is missing: " + relativeFile)
	)
	local sourceFile = maxFilePath + "export\\" + (GCMatterportExportFileName layerName)
	local modelsFolder = viewerFolder + "models\\"
	makeDir modelsFolder all: true
	-- ASCII filenames avoid old TinyWeb filename encoding limits; the title remains Unicode.
	local modelKey = GCMatterportFileKey ((dotNetClass "System.IO.Path").GetFullPath sourceFile)
	local destinationFile = modelsFolder + modelKey + ".glb"
	local stagedFile = modelsFolder + modelKey + ".tmp"
	local backupFile = modelsFolder + modelKey + ".previous"
	local previewFailure = undefined
	try (
		(dotNetClass "System.IO.File").Copy sourceFile stagedFile true
		if (doesFileExist destinationFile) then (
			(dotNetClass "System.IO.File").Replace stagedFile destinationFile backupFile
			if (doesFileExist backupFile) do deleteFile backupFile
		) else (
			(dotNetClass "System.IO.File").Move stagedFile destinationFile
		)
		local portNumber = GCMatterportEnsurePreviewServer viewerFolder
		local titleValue = (dotNetClass "System.Uri").EscapeDataString layerName
		local cacheVersion = ((dotNetClass "System.DateTime").UtcNow.Ticks as string)
		local previewURL = "http://127.0.0.1:" + (portNumber as string) + "/?model=" + modelKey + "&title=" + titleValue + "&v=" + cacheVersion
		ShellLaunch previewURL ""
	) catch (
		previewFailure = getCurrentException() as string
		if (doesFileExist stagedFile) do deleteFile stagedFile
	)
	if (previewFailure != undefined) do throw previewFailure
	return true
)

struct GCMatterportAOClipboardEntry (
	materialID, useCoronaAO, passes, sizeCM, useVRayDenoiser, customResolution, manualResolution
)
global GCMatterportAOClipboard

rcmenu GCMatterportLODContextMenu (
	menuItem previewLODItem "Preview in Model Viewer"
	separator previewSeparator
	menuItem copyPropertiesItem "Copy Material Properties"
	menuItem pastePropertiesItem "Paste Material Properties"
	separator propertiesSeparator
	menuItem deleteLODsItem "Delete LODs"
	on GCMatterportLODContextMenu open do (
		previewLODItem.enabled = _rExportGCMatterportGLBConverter.canPreviewLOD()
		copyPropertiesItem.enabled = _rExportGCMatterportGLBConverter.canCopyLODProperties()
		pastePropertiesItem.enabled = _rExportGCMatterportGLBConverter.canPasteLODProperties()
	)
	on previewLODItem picked do _rExportGCMatterportGLBConverter.previewSelectedLOD()
	on copyPropertiesItem picked do _rExportGCMatterportGLBConverter.copyLODProperties()
	on pastePropertiesItem picked do _rExportGCMatterportGLBConverter.pasteLODProperties()
	on deleteLODsItem picked do _rExportGCMatterportGLBConverter.deleteSelectedLODs()
)

rollout _rBoilerplateGCMatterportGLBConverter "Boilerplate" category: 2 (
	group "Create Layers" (
		label lblPrefix "GC-" across: 4 align: #left 
		edittext edtLayerName "" align: #left bold: true offset: [-60, -1]
		label lblPostfix "_LOD" align: #left offset: [-55, 0]
		button btnCreateLayers "Create Layers" offset: [-90, -4]
	)
	
	fn createLODLayerNames layerBaseName = (
		local trimmedLayerName = trimLeft (trimRight layerBaseName " \t\r\n") " \t\r\n"
		if (trimmedLayerName == "") do return #()
		return for lodIndex in 0 to 3 collect ("GC-" + trimmedLayerName + "_LOD" + (lodIndex as string))
	)

	fn getLODBaseName sceneLayerName = (
		if (sceneLayerName.count <= 8) do return undefined
		if ((substring sceneLayerName 1 3) != "GC-") do return undefined
		local lodSuffix = substring sceneLayerName (sceneLayerName.count - 4) 5
		if ((findItem #("_LOD0", "_LOD1", "_LOD2", "_LOD3") lodSuffix) == 0) do return undefined
		return substring sceneLayerName 4 (sceneLayerName.count - 8)
	)

	fn createLODLayers = (
		local lodLayerNames = createLODLayerNames edtLayerName.text
		if (lodLayerNames.count == 0) do (
			messageBox "Enter a name for the LOD layers." title: "Create Layers" beep: false
			setFocus edtLayerName
			return false
		)

		local existingLODEntries = GCMatterportGetData()
		local existingBaseName = undefined
		for lodEntry in existingLODEntries do (
			local layerBaseName = getLODBaseName lodEntry.layerName
			if (layerBaseName == undefined) do (
				messageBox ("Cannot determine the LOD set name from layer: " + lodEntry.layerName + "\nExpected GC-<name>_LOD0 through GC-<name>_LOD3.") title: "Create Layers" beep: false
				return false
			)
			if (existingBaseName == undefined) then (
				existingBaseName = layerBaseName
			) else if (existingBaseName != layerBaseName) do (
				messageBox "The scene contains LOD layers from different sets. Keep one set before creating missing layers." title: "Create Layers" beep: false
				return false
			)
		)
		local requestedBaseName = trimLeft (trimRight edtLayerName.text " \t\r\n") " \t\r\n"
		if (existingBaseName != undefined and existingBaseName != requestedBaseName) do (
			messageBox ("A LOD set already exists. Use the existing name: " + existingBaseName + "\nOnly missing layers of that set can be created.") title: "Create Layers" beep: false
			return false
		)

		try (
			undo "Create Matterport LOD layers" on (
				for layerName in lodLayerNames do (
					if (LayerManager.getLayerFromName layerName == undefined) do (
						if (LayerManager.newLayerFromName layerName == undefined) do (
							throw ("Could not create layer: " + layerName)
						)
					)
				)
			)
			_rExportGCMatterportGLBConverter.refreshLODs()
		) catch (
			messageBox ("Could not create LOD layers.\n" + (getCurrentException() as string)) title: "Create Layers" beep: false
			return false
		)
		return true
	)

	fn assignDefaultMaterials lodEntries = (
		if (lodEntries.count == 0) do (
			messageBox "Select one or more LOD layers in the list." title: "Assign Default Materials" beep: false
			return false
		)
		if (glTFMaterial == undefined) do (
			messageBox "glTFMaterial is not available in this version of 3ds Max. No materials were assigned." title: "Assign Default Materials" beep: false
			return false
		)

		local assignedCount = 0
		local skippedReasons = #()
		undo "Assign Matterport LOD materials" on (
			for lodEntry in lodEntries do (
				local lodLayer = LayerManager.getLayerFromName lodEntry.layerName
				local layerNodes = #()
				if (lodLayer != undefined) do lodLayer.nodes &layerNodes
				if (lodLayer == undefined) then (
					append skippedReasons (lodEntry.layerName + ": layer no longer exists.")
				) else if (layerNodes.count != 1) then (
					append skippedReasons (lodEntry.layerName + ": expected exactly one object, found " + (layerNodes.count as string) + ".")
				) else (
					local targetNode = layerNodes[1]
					local hasGLTFSubMaterial = false
					if (targetNode.material != undefined and classOf targetNode.material == MultiMaterial) do (
						for subMaterial in targetNode.material.materialList do (
							if (subMaterial != undefined and classOf subMaterial == glTFMaterial) do hasGLTFSubMaterial = true
						)
					)
					if (targetNode.material != undefined and targetNode.material.name == lodEntry.layerName) then (
						append skippedReasons (lodEntry.layerName + ": the object already has a material with this name.")
					) else if (hasGLTFSubMaterial) then (
						append skippedReasons (lodEntry.layerName + ": the existing MultiMaterial already contains a glTFMaterial; preserved.")
					) else (
						try (
							if ((getLODBaseName lodEntry.layerName) == undefined) do throw "Expected a layer named GC-<name>_LOD0 through GC-<name>_LOD3."
							local lodSuffix = substring lodEntry.layerName (lodEntry.layerName.count - 3) 4
							local subMaterialNames = for slotIndex in 1 to 6 collect ("ID" + (slotIndex as string) + "_" + lodSuffix)
							local subMaterials = for subMaterialName in subMaterialNames collect (glTFMaterial name: subMaterialName)
							local lodMaterial = MultiMaterial numsubs: 6 name: lodEntry.layerName
							lodMaterial.materialIDList = #(1, 2, 3, 4, 5, 6)
							lodMaterial.materialList = subMaterials
							lodMaterial.names = subMaterialNames
							targetNode.material = lodMaterial
							assignedCount += 1
						) catch (
							append skippedReasons (lodEntry.layerName + ": " + (getCurrentException() as string))
						)
					)
				)
			)
		)
		_rExportGCMatterportGLBConverter.refreshLODs()
		local assignmentSummary = "Materials assigned to " + (assignedCount as string) + " of " + (lodEntries.count as string) + " LOD layers."
		if (skippedReasons.count > 0) do (
			assignmentSummary += "\n\nNot all layers were assigned:\n"
			for skippedReason in skippedReasons do assignmentSummary += skippedReason + "\n"
		)
		messageBox assignmentSummary title: "Assign Default Materials" beep: false
		return (skippedReasons.count == 0)
	)

	on btnCreateLayers pressed do createLODLayers()
)

rollout _rExportGCMatterportGLBConverter "Exporter" category: 2 (	
	group "LODs" (
		multiListbox lbxLODs "" items: #() height: 4 offset: [-2, 0] width: 326
		
		button btnRefresList "Refresh List" width: 150 across: 2
		button btnAddToLOD "Add to LOD" width: 150
		button btnAssignDefaultMaterials "Assign Default Materials" width: 310 align: #center
	)
	
	group "Materials" (
		multiListbox lbxMaterials "" items: #() height: 6 offset: [-2, 0] width: 326
		button btnTransferUV "Transfer UV Channel from 1 -> 2" width: 310 align: #center
	)

	group "Corona AO Settings" (
		checkbox cbxUseCoronaAO "Use Corona AO" width: 115 align: #left across: 2 checked: true enabled: false
		label lblAOSelection "Select one material." align: #right width: 188
		checkbox cbxAOOverride "Override Resolution" enabled: false across: 2 align: #left
		dropdownlist ddlAOResolution "" items: #("512", "1024", "2048", "4096") selection: 2 width: 100 enabled: false align: #right
		spinner spnAOPasses "Passes: " range: [1, 9999, 15] type: #integer fieldWidth: 42 width: 84 align: #left across: 3 enabled: false
		spinner spnAOSize "Size (cm): " range: [0.01, 9999.0, 5.0] type: #float fieldWidth: 46 width: 99 align: #left enabled: false
		checkbox cbxAODenoise "V-Ray Denoiser" toolTip: "Use V-Ray Denoiser" width: 108 align: #left checked: true enabled: false
	)

	button btnRenderAO "Render AO for Selected IDs (0)" width: 310 align: #center enabled: false

	button btnBatchExport "Batch Export LODs (0)" width: 310 height: 36 offset: [0, 8] align: #center enabled: false

	local isExportingLODs = false
	local isRenderingAO = false
	local refreshMaterials
	local refreshLODs
	local aoDisplaySignature = undefined
	local aoDisplayedKey = undefined
	local isLoadingAO = false
	local lodEntries = #()
	local materialEntries = #()
	local previousSceneSelection = undefined

	timer tmrLODRefresh interval: 500 active: false

	fn getListHandle listControl = (
		for controlHandle in listControl.hwnd do (
			if ((UIAccessor.GetWindowClassName controlHandle) == "ListBox") do return controlHandle
		)
		return 0
	)

	fn sameMaterialEntry firstEntry secondEntry = (
		return (firstEntry.layerName == secondEntry.layerName and firstEntry.nodeRef == secondEntry.nodeRef and firstEntry.materialRef == secondEntry.materialRef and firstEntry.slotIndex == secondEntry.slotIndex)
	)


	fn selectedAOEntry = (
		local selectedRows = lbxMaterials.selection as array
		if (selectedRows.count != 1) do return undefined
		local rowIndex = selectedRows[1]
		if (rowIndex < 1 or rowIndex > materialEntries.count) do return undefined
		local materialEntry = materialEntries[rowIndex]
		if (not GCMatterportIsCurrentMaterialEntry materialEntry) do return undefined
		return materialEntry
	)

	fn refreshAOSettings = (
		local selectedCount = lbxMaterials.selection.numberSet
		btnRenderAO.text = "Render AO for Selected IDs (" + (selectedCount as string) + ")"
		btnRenderAO.enabled = (selectedCount > 0 and not isRenderingAO and not isExportingLODs)
		local lodCount = lbxLODs.selection.numberSet
		btnBatchExport.text = "Batch Export LODs (" + (lodCount as string) + ")"
		btnBatchExport.enabled = (lodCount > 0 and not isRenderingAO and not isExportingLODs)
		local materialEntry = selectedAOEntry()
		local aoOptions = GCMatterportGetEffectiveAOOptions materialEntry
		local propertyKey = GCMatterportAOKey materialEntry
		local displaySignature = if (aoOptions == undefined) then "disabled" else (propertyKey + materialEntry.layerName + materialEntry.materialRef.name + (aoOptions as string))
		if (displaySignature == aoDisplaySignature) do return true
		aoDisplaySignature = displaySignature
		aoDisplayedKey = if (aoOptions == undefined) then undefined else propertyKey
		isLoadingAO = true
		local canEdit = (aoOptions != undefined)
		cbxUseCoronaAO.enabled = canEdit
		local canEditAO = (canEdit and aoOptions.useCoronaAO)
		spnAOPasses.enabled = canEditAO
		spnAOSize.enabled = canEditAO
		cbxAOOverride.enabled = canEditAO
		cbxAODenoise.enabled = canEditAO
		ddlAOResolution.enabled = (canEditAO and aoOptions.customResolution)
		if canEdit then (
			local materialCaption = "Material ID " + (materialEntry.materialID as string) + ": " + materialEntry.materialRef.name
			lblAOSelection.toolTip = materialCaption
			local shortCaption = materialCaption
			while ((getTextExtent shortCaption).x > 180 and shortCaption.count > 4) do shortCaption = substring shortCaption 1 (shortCaption.count - 1)
			lblAOSelection.text = if (shortCaption == materialCaption) then materialCaption else ((substring shortCaption 1 (amax 1 (shortCaption.count - 3))) + "...")
			cbxUseCoronaAO.checked = aoOptions.useCoronaAO
			spnAOPasses.value = aoOptions.passes
			spnAOSize.value = aoOptions.sizeCM
			cbxAOOverride.checked = aoOptions.customResolution
			cbxAODenoise.checked = aoOptions.useVRayDenoiser
			ddlAOResolution.selection = findItem #(512, 1024, 2048, 4096) aoOptions.resolution
		) else (
			lblAOSelection.text = if (materialEntry == undefined) then "Select one material." else "AO settings unavailable."
			lblAOSelection.toolTip = if (materialEntry == undefined) then "Select exactly one material to edit its AO settings." else "AO settings invalid or LOD suffix unsupported."
			spnAOPasses.value = 15
			spnAOSize.value = 5.0
			ddlAOResolution.selection = 2
			cbxUseCoronaAO.checked = true
			cbxAOOverride.checked = false
			cbxAODenoise.checked = true
		)
		isLoadingAO = false
		return canEdit
	)

	fn saveAOSettings changedField = (
		if isLoadingAO do return false
		local materialEntry = selectedAOEntry()
		if (materialEntry == undefined or (GCMatterportAOKey materialEntry) != aoDisplayedKey) do (
			refreshAOSettings()
			return false
		)
		local aoOptions = GCMatterportGetEffectiveAOOptions materialEntry
		if (aoOptions == undefined) do return false
		aoOptions.useCoronaAO = cbxUseCoronaAO.checked
		aoOptions.passes = spnAOPasses.value
		aoOptions.sizeCM = spnAOSize.value
		aoOptions.useVRayDenoiser = cbxAODenoise.checked
		aoOptions.customResolution = cbxAOOverride.checked
		-- Keep the manual value while automatic resolution is displayed.
		if (changedField == #resolution and aoOptions.customResolution and ddlAOResolution.selection > 0) do aoOptions.manualResolution = #(512, 1024, 2048, 4096)[ddlAOResolution.selection]
		local didSave = GCMatterportSaveAOOptions materialEntry aoOptions
		aoDisplaySignature = undefined
		refreshMaterials()
		refreshAOSettings()
		return didSave
	)

	on cbxUseCoronaAO changed checkedState do saveAOSettings #enabled
	on spnAOPasses changed spinnerValue do saveAOSettings #passes
	on spnAOSize changed spinnerValue do saveAOSettings #size
	on cbxAODenoise changed checkedState do saveAOSettings #denoise
	on cbxAOOverride changed checkedState do saveAOSettings #override
	on ddlAOResolution selected itemIndex do saveAOSettings #resolution
	on lbxMaterials selectionEnd do refreshAOSettings()

	fn refreshMaterials = (
		local selectedLayerNames = for rowIndex in (lbxLODs.selection as array) where (rowIndex >= 1 and rowIndex <= lodEntries.count) collect lodEntries[rowIndex].layerName
		local freshEntries = GCMatterportGetMaterials selectedLayerNames
		local hasDisplayChanges = (freshEntries.count != materialEntries.count)
		if (not hasDisplayChanges) do (
			for rowIndex in 1 to freshEntries.count do (
				if (freshEntries[rowIndex].displayText != materialEntries[rowIndex].displayText) do hasDisplayChanges = true
			)
		)
		if (not hasDisplayChanges) do (
			materialEntries = freshEntries
			refreshAOSettings()
			return materialEntries
		)
		local selectedEntries = for rowIndex in (lbxMaterials.selection as array) where (rowIndex >= 1 and rowIndex <= materialEntries.count) collect materialEntries[rowIndex]
		local listHandle = getListHandle lbxMaterials
		local topRowIndex = 0
		local topEntry = undefined
		if (listHandle != 0) do (
			topRowIndex = windows.sendMessage listHandle 0x018E 0 0
			if (topRowIndex >= 0 and topRowIndex < materialEntries.count) do topEntry = materialEntries[topRowIndex + 1]
		)
		materialEntries = freshEntries
		lbxMaterials.items = for materialEntry in materialEntries collect materialEntry.displayText
		local selectedRows = #{}
		for rowIndex in 1 to materialEntries.count do (
			for selectedEntry in selectedEntries do (
				if (sameMaterialEntry materialEntries[rowIndex] selectedEntry) do selectedRows[rowIndex] = true
			)
			if (topEntry != undefined and sameMaterialEntry materialEntries[rowIndex] topEntry) do topRowIndex = rowIndex - 1
		)
		lbxMaterials.selection = selectedRows
		if (listHandle != 0 and materialEntries.count > 0) do (
			topRowIndex = amax 0 (amin topRowIndex (materialEntries.count - 1))
			windows.sendMessage listHandle 0x0197 topRowIndex 0
		)
		refreshAOSettings()
		return materialEntries
	)

	fn batchAOSetting settingField settingValue = (
		if (isRenderingAO) do return false
		local failures = #()
		for rowIndex in (lbxMaterials.selection as array) do (
			if (rowIndex >= 1 and rowIndex <= materialEntries.count) do (
				local materialEntry = materialEntries[rowIndex]
				if (GCMatterportIsCurrentMaterialEntry materialEntry) then (
					local propertyKey = GCMatterportAOKey materialEntry
					-- Write only the requested fields; disabled AO entries are editable here.
					case settingField of (
						#resolution: (
							GCMatterportSceneProperties.setValue (propertyKey + "override") true
							GCMatterportSceneProperties.setValue (propertyKey + "manualResolution") settingValue
						)
						#passes: GCMatterportSceneProperties.setValue (propertyKey + "passes") settingValue
						#sizeCM: GCMatterportSceneProperties.setValue (propertyKey + "sizeCM") settingValue
						#denoise: GCMatterportSceneProperties.setValue (propertyKey + "denoise") settingValue
						#enabled: GCMatterportSceneProperties.setValue (propertyKey + "enabled") settingValue
					)
				) else append failures materialEntry.displayText
			)
		)
		aoDisplaySignature = undefined
		refreshLODs()
		if (failures.count > 0) do messageBox "Some material assignments changed. Those entries were skipped; select them again." title: "Materials" beep: false
		return (failures.count == 0)
	)

	on lbxMaterials rightClick do (
		if (not isRenderingAO) do (
			local listHandle = getListHandle lbxMaterials
			if (listHandle != 0 and materialEntries.count > 0) do (
				local cursorPoint = windows.screenToClient listHandle mouse.screenpos applyUIScaling: false
				local rowHeight = windows.sendMessage listHandle 0x01A1 0 0
				local topIndex = windows.sendMessage listHandle 0x018E 0 0
				local packedPoint = (bit.and (cursorPoint.x as integer) 65535) + (bit.shift (bit.and (cursorPoint.y as integer) 65535) 16)
				local hitResult = windows.sendMessage listHandle 0x01A9 0 packedPoint
				local rowIndex = if (rowHeight > 0) then (topIndex + (floor (cursorPoint.y / rowHeight) as integer) + 1) else 0
				if (cursorPoint.y >= 0 and (bit.shift hitResult -16) == 0 and rowIndex >= 1 and rowIndex <= materialEntries.count) do (
					if (not lbxMaterials.selection[rowIndex]) do lbxMaterials.selection = #{rowIndex}
					refreshAOSettings()
					local wasTimerActive = tmrLODRefresh.active
					tmrLODRefresh.active = false
					try (popUpMenu GCMatterportMaterialContextMenu) catch (format "Materials menu: %\n" (getCurrentException()))
					tmrLODRefresh.active = wasTimerActive
				)
			)
		)
	)

	fn renderSelectedAO = (
		if (isRenderingAO or isExportingLODs) do return false
		local selectedEntries = for rowIndex in (lbxMaterials.selection as array) where (rowIndex >= 1 and rowIndex <= materialEntries.count) collect materialEntries[rowIndex]
		if (selectedEntries.count == 0) do return false
		if (maxFilePath == "" or maxFileName == "") do (
			messageBox "Save the MAX scene before rendering AO. Images are saved beside the scene in export\\_maps." title: "Render AO" beep: false
			return false
		)
		local outputFolder = maxFilePath + "export\\_maps\\"
		local denoiserPath = GCMatterportDenoiserPath()
		local completedCount = 0
		local skippedCount = 0
		local reportLines = #()
		local previousTimerActive = tmrLODRefresh.active
		local originalLODSelection = lbxLODs.selection
		local originalMaterialSelection = lbxMaterials.selection
		local controlStates = for uiControl in #(lbxLODs, lbxMaterials, btnRefresList, btnAddToLOD, btnAssignDefaultMaterials, btnTransferUV, cbxUseCoronaAO, cbxAOOverride, ddlAOResolution, spnAOPasses, spnAOSize, cbxAODenoise) collect #(uiControl, uiControl.enabled)
		isRenderingAO = true
		tmrLODRefresh.active = false
		refreshAOSettings()
		-- Disable this rollout while native render/denoiser messages are being processed.
		for controlState in controlStates do controlState[1].enabled = false
		try (
			for materialEntry in selectedEntries do (
				local entryCaption = materialEntry.layerName + " / ID " + (materialEntry.materialID as string)
				local aoOptions = GCMatterportGetEffectiveAOOptions materialEntry
				if (aoOptions == undefined) then (
					append reportLines (entryCaption + ": invalid or stale material settings.")
				) else if (not aoOptions.useCoronaAO) then (
					skippedCount += 1
					append reportLines (entryCaption + ": skipped (Use Corona AO disabled).")
				) else (
					local bakeResult = GCMatterportBakeAO materialEntry aoOptions outputFolder denoiserPath
					if (bakeResult.errorMessage == undefined and bakeResult.filePath != undefined) then (
						try (
							GCMatterportAssignAO materialEntry bakeResult.filePath
							completedCount += 1
						) catch (append reportLines (entryCaption + ": " + (getCurrentException() as string)))
					) else (
						append reportLines (entryCaption + ": " + bakeResult.errorMessage)
					)
					if (bakeResult.cancelled) do exit
				)
			)
		) catch (append reportLines (getCurrentException() as string))
		for controlState in controlStates do controlState[1].enabled = controlState[2]
		isRenderingAO = false
		lbxLODs.selection = originalLODSelection
		lbxMaterials.selection = originalMaterialSelection
		aoDisplaySignature = undefined
		refreshLODs()
		tmrLODRefresh.active = previousTimerActive
		redrawViews()
		local summaryText = "AO rendered and assigned: " + (completedCount as string) + " of " + (selectedEntries.count as string) + ". Skipped: " + (skippedCount as string) + "."
		if (completedCount > 0) do summaryText += "\nImages: " + outputFolder
		for reportLine in reportLines do summaryText += "\n" + reportLine
		messageBox summaryText title: "Render AO" beep: false
		return (completedCount + skippedCount == selectedEntries.count)
	)

	on btnRenderAO pressed do renderSelectedAO()


	fn batchExportLODs = (
		if (isRenderingAO or isExportingLODs) do return false
		local selectedLayerNames = for rowIndex in (lbxLODs.selection as array) where (rowIndex >= 1 and rowIndex <= lodEntries.count) collect lodEntries[rowIndex].layerName
		if (selectedLayerNames.count == 0) do return false
		local preflightResult = GCMatterportExportPreflight selectedLayerNames
		if (preflightResult[2].count > 0) do (
			local messageContent = "Nothing was exported. Fix these issues in the selected LODs:\n"
			for issue in preflightResult[2] do messageContent += "\n" + issue
			messageBox messageContent title: "Batch Export LODs" beep: false
			return false
		)
		local exportJobs = preflightResult[1]
		local exportFolder = maxFilePath + "export\\"
		local completedCount = 0
		local reportLines = #()
		local previousTimerActive = tmrLODRefresh.active
		local controlStates = for uiControl in #(lbxLODs, lbxMaterials, btnRefresList, btnAddToLOD, btnAssignDefaultMaterials, btnTransferUV, cbxUseCoronaAO, cbxAOOverride, ddlAOResolution, spnAOPasses, spnAOSize, cbxAODenoise) collect #(uiControl, uiControl.enabled)
		isExportingLODs = true
		tmrLODRefresh.active = false
		refreshAOSettings()
		for controlState in controlStates do controlState[1].enabled = false
		try (
			for exportJob in exportJobs do (
				local failureReason = GCMatterportExportOneLOD exportJob exportFolder
				if (failureReason == undefined) then (
					completedCount += 1
				) else (
					append reportLines (exportJob.layerName + ": " + failureReason)
					-- Stop on operational failure/cancellation; preflight already checked the whole set.
					exit
				)
			)
		) catch (append reportLines (getCurrentException() as string))
		for controlState in controlStates do controlState[1].enabled = controlState[2]
		isExportingLODs = false
		aoDisplaySignature = undefined
		refreshLODs()
		tmrLODRefresh.active = previousTimerActive
		redrawViews()
		local summaryText = "WebGL GLB exported: " + (completedCount as string) + " of " + (exportJobs.count as string) + "."
		if (completedCount > 0) do summaryText += "\nOutput: " + exportFolder
		for reportLine in reportLines do summaryText += "\n" + reportLine
		messageBox summaryText title: "Batch Export LODs" beep: false
		return (completedCount == exportJobs.count)
	)

	on btnBatchExport pressed do batchExportLODs()


	fn refreshLODs selectedLayerNames: undefined = (
		local freshEntries = GCMatterportGetData()
		local hasDisplayChanges = (freshEntries.count != lodEntries.count)
		if (not hasDisplayChanges) do (
			for rowIndex in 1 to freshEntries.count do (
				if (freshEntries[rowIndex].layerName != lodEntries[rowIndex].layerName or freshEntries[rowIndex].displayText != lodEntries[rowIndex].displayText) do hasDisplayChanges = true
			)
		)
		local hasExplicitSelection = (selectedLayerNames != undefined)
		if (not hasDisplayChanges and not hasExplicitSelection) do (
			lodEntries = freshEntries
			refreshMaterials()
			return lodEntries
		)
		if (selectedLayerNames == undefined) do (
			selectedLayerNames = for rowIndex in (lbxLODs.selection as array) where (rowIndex >= 1 and rowIndex <= lodEntries.count) collect lodEntries[rowIndex].layerName
		)
		local listHandle = getListHandle lbxLODs
		local topRowIndex = 0
		local topLayerName = undefined
		if (listHandle != 0) do (
			-- LB_GETTOPINDEX returns a zero-based row index.
			topRowIndex = windows.sendMessage listHandle 0x018E 0 0
			if (topRowIndex >= 0 and topRowIndex < lodEntries.count) do topLayerName = lodEntries[topRowIndex + 1].layerName
		)
		lodEntries = freshEntries
		if (hasDisplayChanges) do lbxLODs.items = for lodEntry in lodEntries collect lodEntry.displayText
		lbxLODs.selection = (for rowIndex in 1 to lodEntries.count where ((findItem selectedLayerNames lodEntries[rowIndex].layerName) > 0) collect rowIndex) as bitarray
		if (listHandle != 0 and lodEntries.count > 0) do (
			for rowIndex in 1 to lodEntries.count where (lodEntries[rowIndex].layerName == topLayerName) do topRowIndex = rowIndex - 1
			topRowIndex = amax 0 (amin topRowIndex (lodEntries.count - 1))
			-- LB_SETTOPINDEX restores the same logical top layer when it still exists.
			windows.sendMessage listHandle 0x0197 topRowIndex 0
		)
		refreshMaterials()
		return lodEntries
	)

	fn syncSceneSelection = (
		local selectedHandles = for sceneNode in selection where (isValidNode sceneNode) collect sceneNode.handle
		sort selectedHandles
		local currentSignature = #()
		for nodeHandle in selectedHandles do (
			local sceneNode = maxOps.getNodeByHandle nodeHandle
			if (isValidNode sceneNode) do append currentSignature #(nodeHandle, sceneNode.layer.name)
		)
		local hasSelectionChanges = (previousSceneSelection == undefined)
		if (not hasSelectionChanges) do (
			hasSelectionChanges = (currentSignature.count != previousSceneSelection.count)
			if (not hasSelectionChanges) do (
				for entryIndex in 1 to currentSignature.count do (
					if (currentSignature[entryIndex][1] != previousSceneSelection[entryIndex][1] or currentSignature[entryIndex][2] != previousSceneSelection[entryIndex][2]) do hasSelectionChanges = true
				)
			)
		)
		if (not hasSelectionChanges) do return false
		previousSceneSelection = currentSignature
		local selectedLayerNames = #()
		for selectionEntry in currentSignature do (
			local sceneLayerName = selectionEntry[2]
			if ((findString (toLower sceneLayerName) "_lod") != undefined and (findItem selectedLayerNames sceneLayerName) == 0) do append selectedLayerNames sceneLayerName
		)
		refreshLODs selectedLayerNames: selectedLayerNames
		local selectedRows = lbxLODs.selection as array
		if (selectedRows.count > 0) do (
			local listHandle = getListHandle lbxLODs
			if (listHandle != 0) do (
				-- LB_SETCARETINDEX scrolls only when this selected row is not visible.
				windows.sendMessage listHandle 0x019E (selectedRows[1] - 1) 0
			)
		)
		return true
	)

	fn deleteSelectedLODs = (
		local selectedRows = lbxLODs.selection as array
		if (selectedRows.count == 0) do (
			messageBox "Select one or more LOD layers to delete." title: "Delete LODs" beep: false
			return false
		)
		local deletedCount = 0
		local skippedReasons = #()
		undo "Delete empty Matterport LOD layers" on (
			for rowIndex in selectedRows do (
				if (rowIndex < 1 or rowIndex > lodEntries.count) then (
					append skippedReasons ("Row " + (rowIndex as string) + ": the list is out of date.")
				) else (
					local selectedLayerName = lodEntries[rowIndex].layerName
					local selectedLayer = LayerManager.getLayerFromName selectedLayerName
					if (selectedLayer == undefined) then (
						append skippedReasons (selectedLayerName + ": layer no longer exists.")
					) else (
						local layerNodes = #()
						selectedLayer.nodes &layerNodes
						if (layerNodes.count > 0) then (
							append skippedReasons (selectedLayerName + ": contains " + (layerNodes.count as string) + " object(s); not deleted.")
						) else (
							try (
								if (LayerManager.deleteLayerByName selectedLayerName) then (
									deletedCount += 1
								) else (
									append skippedReasons (selectedLayerName + ": 3ds Max could not delete this empty layer.")
								)
							) catch (
								append skippedReasons (selectedLayerName + ": " + (getCurrentException() as string))
							)
						)
					)
				)
			)
		)
		refreshLODs()
		local deletionSummary = "Deleted " + (deletedCount as string) + " of " + (selectedRows.count as string) + " selected LOD layers."
		if (skippedReasons.count > 0) do (
			deletionSummary += "\n\nSkipped:\n"
			for skippedReason in skippedReasons do deletionSummary += skippedReason + "\n"
		)
		messageBox deletionSummary title: "Delete LODs" beep: false
		return (skippedReasons.count == 0)
	)


	fn getLODPropertyEntries layerName = (
		local lodLayer = LayerManager.getLayerFromName layerName
		local layerNodes = #()
		if (lodLayer != undefined) do lodLayer.nodes &layerNodes
		if (not GCMatterportIsLODReady layerNodes) do return undefined
		local entries = GCMatterportGetMaterials #(layerName)
		if (entries.count == 0 or entries.count != layerNodes[1].material.materialList.count) do return undefined
		return entries
	)

	fn canPreviewLOD = (
		if (isRenderingAO or isExportingLODs or lbxLODs.selection.numberSet != 1) do return false
		local rowIndex = (lbxLODs.selection as array)[1]
		if (rowIndex < 1 or rowIndex > lodEntries.count) do return false
		local layerName = lodEntries[rowIndex].layerName
		return ((getLODPropertyEntries layerName) != undefined and (GCMatterportLODHasGLB layerName))
	)

	fn previewSelectedLOD = (
		if (not canPreviewLOD()) do return false
		local rowIndex = (lbxLODs.selection as array)[1]
		try (
			GCMatterportPreviewLOD lodEntries[rowIndex].layerName
		) catch (
			messageBox ("Cannot open Model Viewer.\n" + (getCurrentException() as string)) title: "Preview in Model Viewer" beep: false
			return false
		)
		return true
	)


	fn copyableLODEntries = (
		if (isRenderingAO or lbxLODs.selection.numberSet != 1) do return undefined
		local rowIndex = (lbxLODs.selection as array)[1]
		if (rowIndex < 1 or rowIndex > lodEntries.count) do return undefined
		local entries = getLODPropertyEntries lodEntries[rowIndex].layerName
		if (entries == undefined) do return undefined
		local seenIDs = #()
		for materialEntry in entries do (
			if (materialEntry.materialID < 1 or (findItem seenIDs materialEntry.materialID) != 0 or GCMatterportGetEffectiveAOOptions materialEntry == undefined) do return undefined
			append seenIDs materialEntry.materialID
		)
		return entries
	)

	fn canCopyLODProperties = (
		return (copyableLODEntries() != undefined)
	)

	fn canPasteLODProperties = (
		return (not isRenderingAO and GCMatterportAOClipboard != undefined and GCMatterportAOClipboard.count > 0 and lbxLODs.selection.numberSet > 0)
	)

	fn copyLODProperties = (
		local entries = copyableLODEntries()
		if (entries == undefined) do (
			messageBox "Select exactly one valid LOD with glTF materials and unique Material IDs to copy its AO settings." title: "Copy Material Properties" beep: false
			return false
		)
		local clipboardEntries = #()
		for materialEntry in entries do (
			local aoOptions = GCMatterportGetEffectiveAOOptions materialEntry
			-- Scalar values only: no node/material/option references or computed resolution.
			append clipboardEntries (GCMatterportAOClipboardEntry materialID: materialEntry.materialID useCoronaAO: aoOptions.useCoronaAO passes: aoOptions.passes sizeCM: aoOptions.sizeCM useVRayDenoiser: aoOptions.useVRayDenoiser customResolution: aoOptions.customResolution manualResolution: aoOptions.manualResolution)
		)
		GCMatterportAOClipboard = clipboardEntries
		return true
	)

	fn pasteLODProperties = (
		if (not canPasteLODProperties()) do return false
		local targetLayerNames = for rowIndex in (lbxLODs.selection as array) where (rowIndex >= 1 and rowIndex <= lodEntries.count) collect lodEntries[rowIndex].layerName
		local reportLines = #()
		local pastedCount = 0
		for layerName in targetLayerNames do (
			local entries = getLODPropertyEntries layerName
			if (entries == undefined) then (
				append reportLines (layerName + ": skipped; expected one object with a valid glTF MultiMaterial.")
			) else (
				local matchedIDs = #()
				for materialEntry in entries do (
					local idCount = 0
					for otherEntry in entries where (otherEntry.materialID == materialEntry.materialID) do idCount += 1
					local sourceSettings = undefined
					for clipboardEntry in GCMatterportAOClipboard where (clipboardEntry.materialID == materialEntry.materialID) do sourceSettings = clipboardEntry
					local entryCaption = layerName + " / ID " + (materialEntry.materialID as string)
					if (materialEntry.materialID < 1 or idCount != 1 or not GCMatterportIsCurrentMaterialEntry materialEntry) then (
						append reportLines (entryCaption + ": skipped; invalid, duplicate or changed Material ID.")
					) else if (sourceSettings == undefined) then (
						append reportLines (entryCaption + ": unchanged; no matching ID in the copied settings.")
					) else (
						append matchedIDs materialEntry.materialID
						local aoOptions = GCMatterportAOOptions useCoronaAO: sourceSettings.useCoronaAO passes: sourceSettings.passes sizeCM: sourceSettings.sizeCM useVRayDenoiser: sourceSettings.useVRayDenoiser customResolution: sourceSettings.customResolution manualResolution: sourceSettings.manualResolution
						-- Save writes the target node/ID key; auto resolution is recomputed for its LOD.
						try (
							if (GCMatterportSaveAOOptions materialEntry aoOptions) then pastedCount += 1 else append reportLines (entryCaption + ": skipped; the material assignment changed.")
						) catch (
							append reportLines (entryCaption + ": could not save AO settings. " + (getCurrentException() as string))
						)
					)
				)
				for clipboardEntry in GCMatterportAOClipboard where ((findItem matchedIDs clipboardEntry.materialID) == 0) do append reportLines (layerName + ": no valid target for copied ID " + (clipboardEntry.materialID as string) + ".")
			)
		)
		aoDisplaySignature = undefined
		refreshLODs()
		local summaryText = "AO settings pasted to " + (pastedCount as string) + " Material ID(s)."
		for reportLine in reportLines do summaryText += "\n" + reportLine
		messageBox summaryText title: "Paste Material Properties" beep: false
		return (reportLines.count == 0)
	)


	on lbxLODs rightClick do (
		local listHandle = getListHandle lbxLODs
		if (listHandle != 0 and lodEntries.count > 0) do (
			local cursorPoint = windows.screenToClient listHandle mouse.screenpos applyUIScaling: false
			local rowHeight = windows.sendMessage listHandle 0x01A1 0 0
			local topIndex = windows.sendMessage listHandle 0x018E 0 0
			local packedPoint = (bit.and (cursorPoint.x as integer) 65535) + (bit.shift (bit.and (cursorPoint.y as integer) 65535) 16)
			local hitResult = windows.sendMessage listHandle 0x01A9 0 packedPoint
			-- ITEMFROMPOINT returns the nearest row even below the last item.
			local rowIndex = if (rowHeight > 0) then (topIndex + (floor (cursorPoint.y / rowHeight) as integer) + 1) else 0
			if (cursorPoint.y >= 0 and (bit.shift hitResult -16) == 0 and rowIndex >= 1 and rowIndex <= lodEntries.count) do (
				if (not lbxLODs.selection[rowIndex]) do lbxLODs.selection = #{rowIndex}
				refreshMaterials()
				local wasTimerActive = tmrLODRefresh.active
				tmrLODRefresh.active = false
				try (popUpMenu GCMatterportLODContextMenu) catch (format "LOD menu failed: %\n" (getCurrentException()))
				tmrLODRefresh.active = wasTimerActive
			)
		)
	)


	fn addSelectedObjectToLOD = (
		local selectedRows = lbxLODs.selection as array
		local selectedNodes = selection as array
		if (selectedRows.count != 1 or selectedNodes.count != 1) do (
			messageBox "Select exactly one scene object and one LOD layer in the list." title: "Add to LOD" beep: false
			return false
		)
		local rowIndex = selectedRows[1]
		if (rowIndex < 1 or rowIndex > lodEntries.count) do (
			refreshLODs()
			messageBox "The LOD list is out of date. Select the layer again." title: "Add to LOD" beep: false
			return false
		)
		local selectedLayerName = lodEntries[rowIndex].layerName
		local targetLayer = LayerManager.getLayerFromName selectedLayerName
		if (targetLayer == undefined) do (
			refreshLODs()
			messageBox ("Layer no longer exists: " + selectedLayerName) title: "Add to LOD" beep: false
			return false
		)
		local targetNode = selectedNodes[1]
		local sourceLayer = targetNode.layer
		local sourceLayerName = sourceLayer.name
		if (sourceLayer == targetLayer) do (
			messageBox ("The object is already assigned to " + selectedLayerName + ".") title: "Add to LOD" beep: false
			return false
		)
		local layerNodes = #()
		targetLayer.nodes &layerNodes
		if (layerNodes.count > 0) do (
			messageBox (selectedLayerName + ": already contains another object. Each LOD layer must contain exactly one object.") title: "Add to LOD" beep: false
			return false
		)
		if ((findString (toLower sourceLayerName) "_lod") != undefined) do (
			local transferMessage = "Move the selected object to another LOD layer.\nSource: " + sourceLayerName + "\nTarget: " + selectedLayerName
			if (not GCMatterportConfirmTyped transferMessage expectedText: "OK") do return false
		)
		-- The modal dialog may allow scene callbacks to run; revalidate captured references.
		if (not isValidNode targetNode) do (
			refreshLODs()
			messageBox "The object no longer exists. Nothing was moved." title: "Add to LOD" beep: false
			return false
		)
		local currentSourceLayer = LayerManager.getLayerFromName sourceLayerName
		local currentTargetLayer = LayerManager.getLayerFromName selectedLayerName
		if (currentSourceLayer == undefined or currentTargetLayer == undefined or currentSourceLayer != sourceLayer or currentTargetLayer != targetLayer or targetNode.layer != sourceLayer) do (
			refreshLODs()
			messageBox "The object or its layers changed while confirming. Nothing was moved; select the object and LOD again." title: "Add to LOD" beep: false
			return false
		)
		layerNodes = #()
		currentTargetLayer.nodes &layerNodes
		if (layerNodes.count > 0) do (
			refreshLODs()
			messageBox (selectedLayerName + ": the target layer is no longer empty. Nothing was moved.") title: "Add to LOD" beep: false
			return false
		)
		try (
			undo "Move selected object to Matterport LOD layer" on (
				targetLayer.addNode targetNode
			)
			if (targetNode.layer.name != selectedLayerName) do throw "3ds Max did not move the object to the selected layer."
		) catch (
			messageBox ("Could not add object to " + selectedLayerName + ": " + (getCurrentException() as string)) title: "Add to LOD" beep: false
			return false
		)
		refreshLODs selectedLayerNames: #(selectedLayerName)
		return true
	)

	fn assignSelectedLODMaterials = (
		local selectedRows = lbxLODs.selection as array
		if (selectedRows.count == 0) do (
			messageBox "Select one or more LOD layers in the list." title: "Assign Default Materials" beep: false
			return false
		)
		local selectedEntries = #()
		for rowIndex in selectedRows do (
			if (rowIndex < 1 or rowIndex > lodEntries.count) do (
				refreshLODs()
				messageBox "The LOD list is out of date. Select the layers again." title: "Assign Default Materials" beep: false
				return false
			)
			append selectedEntries lodEntries[rowIndex]
		)
		return _rBoilerplateGCMatterportGLBConverter.assignDefaultMaterials selectedEntries
	)

	on btnAssignDefaultMaterials pressed do assignSelectedLODMaterials()

	on btnAddToLOD pressed do addSelectedObjectToLOD()


	fn transferSelectedMaterialUVs = (
		local selectedRows = lbxMaterials.selection as array
		if (selectedRows.count == 0) do (
			messageBox "Select one or more material IDs in Materials." title: "Transfer UV Channel" beep: false
			return false
		)
		local targetNodes = #()
		local nodeMaterialIDs = #()
		for rowIndex in selectedRows do (
			if (rowIndex < 1 or rowIndex > materialEntries.count or not GCMatterportIsCurrentMaterialEntry materialEntries[rowIndex]) do (
				refreshMaterials()
				messageBox "The material selection is out of date. Select the IDs again." title: "Transfer UV Channel" beep: false
				return false
			)
			local materialEntry = materialEntries[rowIndex]
			local targetIndex = findItem targetNodes materialEntry.nodeRef
			if (targetIndex == 0) do (
				append targetNodes materialEntry.nodeRef
				append nodeMaterialIDs #()
				targetIndex = targetNodes.count
			)
			appendIfUnique nodeMaterialIDs[targetIndex] materialEntry.materialID
		)
		local previousSelection = selection as array
		local previousPanelMode = getCommandPanelTaskMode()
		local previousStackObject = modPanel.getCurrentObject()
		local previousSubObjectLevel = subObjectLevel
		local previousTimerActive = tmrLODRefresh.active
		local originalLODSelection = lbxLODs.selection
		local reportLines = #()
		local completedCount = 0
		local completedNodes = #()
		tmrLODRefresh.active = false
		undo "Transfer UV 1 to 2 and pack selected material IDs" on (
			for targetIndex in 1 to targetNodes.count do (
				local targetNode = targetNodes[targetIndex]
				local originalModifiers = for existingModifier in targetNode.modifiers collect existingModifier
				local sourceMesh = undefined
				local operationStage = "Validate source UVs"
				try (
					if (superClassOf targetNode != GeometryClass) do throw "Not a geometry object."
					sourceMesh = snapshotAsMesh targetNode
					if (sourceMesh.numfaces == 0 or not meshop.getMapSupport sourceMesh 1 or meshop.getNumMapVerts sourceMesh 1 == 0) do throw "UV channel 1 is missing or empty."
					local validIDs = #()
					for materialID in nodeMaterialIDs[targetIndex] do (
						local hasFaces = false
						for faceIndex in 1 to sourceMesh.numfaces while (not hasFaces) do hasFaces = (getFaceMatID sourceMesh faceIndex == materialID)
						if hasFaces then append validIDs materialID else append reportLines (targetNode.name + ": ID " + (materialID as string) + " has no faces; skipped.")
					)
					if (validIDs.count == 0) do throw "No selected material IDs have faces."
					-- Leave lower stack editing before creating a topology-dependent modifier.
					subObjectLevel = 0
					setCommandPanelTaskMode mode: #create
					operationStage = "Copy channel 1 to channel 2"
					-- Copy once per object. Paste adds a modifier above the original stack.
					ChannelInfo.CopyChannel targetNode 3 1
					ChannelInfo.PasteChannel targetNode 3 2
					-- Evaluate Paste before Unwrap initializes its local UV data.
					local copiedMesh = snapshotAsMesh targetNode
					local isExactCopy = GCMatterportUVChannelsMatch sourceMesh 1 copiedMesh 2
					delete copiedMesh
					if (not isExactCopy) do throw "Channel 2 does not match source channel 1 after paste."
					local unwrapModifier = Unwrap_UVW()
					unwrapModifier.name = "Material ID UV packing (channel 2)"
					unwrapModifier.unwrap.setMapChannel 2
					operationStage = "Add channel 2 Unwrap at top of stack"
					addModifier targetNode unwrapModifier before: 0
					if (targetNode.modifiers[1] != unwrapModifier) do throw "Unwrap must be above the channel paste modifier."
					select targetNode
					setCommandPanelTaskMode mode: #modify
					modPanel.setCurrentObject unwrapModifier
					subObjectLevel = 3
					unwrapModifier.unwrap2.setTVSubObjectMode 3
					unwrapModifier.unwrap2.setTVElementMode false
					unwrapModifier.unwrap2.setEnableSoftSelection false
					unwrapModifier.unwrap6.SetPackRescaleCluster false
					for materialID in validIDs do (
						operationStage = "Pack material ID " + (materialID as string)
						unwrapModifier.unwrap6.selectFacesByNode #{} targetNode
						unwrapModifier.unwrap2.selectByMatID materialID
						local selectedFaces = unwrapModifier.unwrap6.getSelectedFacesByNode targetNode
						if (selectedFaces.numberSet == 0) do throw ("Unwrap could not select faces for ID " + (materialID as string) + ".")
						-- Face-mode Break separates this ID at its boundary, retaining its internal islands.
						unwrapModifier.unwrap.breakSelected()
						unwrapModifier.unwrap6.selectFacesByNode selectedFaces targetNode
						-- Pack Custom is exposed as unwrap2.pack in Max 2027; no packCustom method exists.
						unwrapModifier.unwrap2.pack 3 0.004 true true true
					)
					unwrapModifier.unwrap6.selectFacesByNode #{} targetNode
					operationStage = "Validate packed channel 2 bounds"
					local packedMesh = snapshotAsMesh targetNode
					local validationError = GCMatterportValidatePackedUVs sourceMesh packedMesh validIDs
					delete packedMesh
					if (validationError != undefined) do throw validationError
					delete sourceMesh
					sourceMesh = undefined
					operationStage = "Convert completed UV result to Editable Poly"
					subObjectLevel = 0
					setCommandPanelTaskMode mode: #create
					-- Bake the evaluated result only after every selected ID packed successfully.
					convertToPoly targetNode
					completedCount += 1
					append completedNodes targetNode
				) catch (
					local failureReason = getCurrentException() as string
					if (sourceMesh != undefined) do delete sourceMesh
					subObjectLevel = 0
					setCommandPanelTaskMode mode: #create
					-- Remove dependents first: Unwrap above Paste. Never delete an input below a live Unwrap.
					local modifierIndex = 1
					while (modifierIndex <= targetNode.modifiers.count) do (
						if ((findItem originalModifiers targetNode.modifiers[modifierIndex]) == 0) then (
							deleteModifier targetNode modifierIndex
						) else (
							modifierIndex += 1
						)
					)
					append reportLines (targetNode.name + " [" + operationStage + "]: " + failureReason)
				)
			)
		)
		try (
			subObjectLevel = 0
			select (for sceneNode in previousSelection where (isValidNode sceneNode) collect sceneNode)
			local hasConvertedNodes = false
			for sceneNode in previousSelection where ((findItem completedNodes sceneNode) > 0) do hasConvertedNodes = true
			setCommandPanelTaskMode mode: previousPanelMode
			if (previousPanelMode == #modify) do (
				if hasConvertedNodes then (
					-- Collapse invalidates old stack references. Use the surviving node's current base.
					if (selection.count == 1) do modPanel.setCurrentObject selection[1].baseObject
					subObjectLevel = 0
				) else (
					if (previousStackObject != undefined) do modPanel.setCurrentObject previousStackObject
					subObjectLevel = previousSubObjectLevel
				)
			)
		) catch (
			append reportLines ("Could not fully restore the Modify panel: " + (getCurrentException() as string))
		)
		-- The scene selection was restored; keep the manual LOD/material selection intact.
		lbxLODs.selection = originalLODSelection
		refreshMaterials()
		tmrLODRefresh.active = previousTimerActive
		redrawViews()
		local resultMessage = "UV channel 1 copied to 2, selected IDs packed, and converted to Editable Poly on " + (completedCount as string) + " object(s)."
		for reportLine in reportLines do resultMessage += "\n" + reportLine
		messageBox resultMessage title: "Transfer UV Channel" beep: false
		return (reportLines.count == 0)
	)

	on btnTransferUV pressed do transferSelectedMaterialUVs()

	fn openMaterialInSlate rowIndex = (
		if (rowIndex < 1 or rowIndex > materialEntries.count) do (
			refreshMaterials()
			messageBox "This material row is out of date. Select it again." title: "Materials" beep: false
			return false
		)
		local clickedEntry = materialEntries[rowIndex]
		local freshEntries = GCMatterportGetMaterials #(clickedEntry.layerName)
		local isCurrentEntry = false
		for freshEntry in freshEntries do (
			if (sameMaterialEntry clickedEntry freshEntry) do isCurrentEntry = true
		)
		if (not isCurrentEntry) do (
			refreshMaterials()
			messageBox "This glTF material is no longer assigned to that LOD slot. The list has been refreshed." title: "Materials" beep: false
			return false
		)
		local parentMaterial = clickedEntry.nodeRef.material
		if (parentMaterial == undefined or classOf parentMaterial != MultiMaterial or clickedEntry.slotIndex > parentMaterial.materialList.count or parentMaterial.materialList[clickedEntry.slotIndex] != clickedEntry.materialRef) do (
			refreshMaterials()
			messageBox "The parent material changed. Select the material again." title: "Materials" beep: false
			return false
		)
		try (
			sme.Open()
			local activeViewIndex = sme.activeView
			if (sme.GetNumViews() == 0) then (
				activeViewIndex = sme.CreateView "LOD Materials"
			) else if (activeViewIndex < 1 or activeViewIndex > sme.GetNumViews()) do (
				activeViewIndex = 1
			)
			sme.activeView = activeViewIndex
			local materialView = sme.GetView activeViewIndex
			local materialNode = materialView.GetNodeByRef clickedEntry.materialRef
			if (materialNode == undefined) do (
				local nodePosition = [0, 0]
				for nodeIndex in 1 to materialView.GetNumNodes() do (
					local existingNode = materialView.GetNode nodeIndex
					local existingPosition = existingNode.position
					nodePosition.x = amax nodePosition.x (existingPosition.x + 300)
				)
				local parentNode = materialView.GetNodeByRef parentMaterial
				if (parentNode == undefined) do parentNode = materialView.CreateNode parentMaterial &nodePosition
				if (parentNode == undefined) do throw "Slate could not create the MultiMaterial graph."
				-- Restore missing children by reference; existing graph nodes are reused.
				local pendingMaterials = #(parentMaterial)
				local visitedMaterials = #()
				local graphIndex = 1
				while (graphIndex <= pendingMaterials.count) do (
					local graphMaterial = pendingMaterials[graphIndex]
					graphIndex += 1
					if (graphMaterial != undefined and (findItem visitedMaterials graphMaterial) == 0) do (
						append visitedMaterials graphMaterial
						if ((materialView.GetNodeByRef graphMaterial) == undefined) do (
							nodePosition += [-300, 160]
							materialView.CreateNode graphMaterial &nodePosition
						)
						for subIndex in 1 to (getNumSubMtls graphMaterial) do append pendingMaterials (getSubMtl graphMaterial subIndex)
						for mapIndex in 1 to (getNumSubTexmaps graphMaterial) do append pendingMaterials (getSubTexmap graphMaterial mapIndex)
					)
				)
				materialNode = materialView.GetNodeByRef clickedEntry.materialRef
				if (materialNode == undefined) do throw "Slate could not show the selected glTF material in the MultiMaterial graph."
			)
			materialView.SetSelectedNodes #(clickedEntry.materialRef)
			sme.SetMtlInParamEditor clickedEntry.materialRef
			materialView.ZoomExtents type: #selected
			materialView.SetFocus()
		) catch (
			refreshMaterials()
			messageBox ("Could not open the glTF material in Slate.\n" + (getCurrentException() as string)) title: "Materials" beep: false
			return false
		)
		return true
	)

	on lbxMaterials doubleClicked rowIndex do openMaterialInSlate rowIndex


	fn showClickedLOD rowIndex = (
		if (rowIndex < 1 or rowIndex > lodEntries.count) do (
			refreshLODs()
			messageBox "This LOD row is out of date. Select it again." title: "Show LOD" beep: false
			return false
		)
		local clickedLayerName = lodEntries[rowIndex].layerName
		local clickedLayer = LayerManager.getLayerFromName clickedLayerName
		if (clickedLayer == undefined) do (
			refreshLODs()
			messageBox "This LOD layer no longer exists. The list has been refreshed." title: "Show LOD" beep: false
			return false
		)
		local allLODEntries = GCMatterportGetData()
		local lodLayers = for lodEntry in allLODEntries collect (LayerManager.getLayerFromName lodEntry.layerName)
		if ((findItem lodLayers undefined) != 0 or (findItem lodLayers clickedLayer) == 0) do (
			refreshLODs()
			messageBox "The LOD layers changed. Select the layer again." title: "Show LOD" beep: false
			return false
		)
		try (
			undo "Show clicked Matterport LOD" on (
				for lodLayer in lodLayers do lodLayer.isHidden = (lodLayer != clickedLayer)
				local targetNodes = #()
				clickedLayer.nodes &targetNodes
				for targetNode in targetNodes where (isValidNode targetNode) do targetNode.isHidden = false
			)
			redrawViews()
			max tool zoomextents all
		) catch (
			messageBox ("Could not show the LOD layer.\n" + (getCurrentException() as string)) title: "Show LOD" beep: false
			return false
		)
		return true
	)

	on lbxLODs doubleClicked rowIndex do showClickedLOD rowIndex

	on lbxLODs selected rowIndex do refreshMaterials()

	on btnRefresList pressed do refreshLODs()
	on tmrLODRefresh tick do (
		try (
			if (not syncSceneSelection()) do refreshLODs()
		) catch (
			tmrLODRefresh.active = false
			format "LOD list auto-refresh stopped: %\n" (getCurrentException())
		)
	)

	on _rExportGCMatterportGLBConverter open do (
		-- Spinner.pos is its arrow position, not the start of its caption.
		local passesPosition = spnAOPasses.pos
		spnAOSize.pos = passesPosition + [113, 0]
		cbxAODenoise.pos = [225, passesPosition.y]
		ddlAOResolution.pos = cbxAOOverride.pos + [127, 0]
		previousSceneSelection = undefined
		syncSceneSelection()
		tmrLODRefresh.active = true
	)

	on _rExportGCMatterportGLBConverter close do (
		tmrLODRefresh.active = false
		previousSceneSelection = undefined
	)
)


rollout _rTransformationGCMatterportGLBConverter "Transformation" category: 3 (
	group "Set Pivot" (
		button btnPivotBottom "Bottom" width: 100 across: 3
		button btnPivotCenter "Center" width: 100
		button btnPivotTop "Top" width: 100
	)
	button btnMoveToCenter "Move to Center Scene" width: 310 align: #center

	fn transformSelectedObjects operationMode = (
		local selectedNodes = for sceneNode in selection where (isValidNode sceneNode) collect sceneNode
		if (selectedNodes.count == 0) do (
			messageBox "Select one or more scene objects first." title: "Transformation" beep: false
			return false
		)
		local hierarchyEntries = for sceneNode in selectedNodes collect (
			local nodeDepth = 0
			local ancestorNode = sceneNode.parent
			while (ancestorNode != undefined) do (
				nodeDepth += 1
				ancestorNode = ancestorNode.parent
			)
			#(nodeDepth, sceneNode)
		)
		fn compareDepth firstEntry secondEntry = (
			return firstEntry[1] - secondEntry[1]
		)
		qsort hierarchyEntries compareDepth
		selectedNodes = for hierarchyEntry in hierarchyEntries collect hierarchyEntry[2]
		-- Capture world targets before moving parents, then apply parents before children.
		local targetPoints = for sceneNode in selectedNodes collect (
			local worldBounds = nodeGetBoundingBox sceneNode (matrix3 1)
			local boundsCenter = (worldBounds[1] + worldBounds[2]) * 0.5
			case operationMode of (
				#bottom: [boundsCenter.x, boundsCenter.y, worldBounds[1].z]
				#top: [boundsCenter.x, boundsCenter.y, worldBounds[2].z]
				#center: boundsCenter
				#move: ((in coordsys world sceneNode.pos) + [-boundsCenter.x, -boundsCenter.y, -worldBounds[1].z])
			)
		)
		undo "Transform Matterport selection" on (
			for nodeIndex in 1 to selectedNodes.count do (
				local sceneNode = selectedNodes[nodeIndex]
				if (operationMode == #move) then (
					in coordsys world sceneNode.pos = targetPoints[nodeIndex]
				) else (
					in coordsys world sceneNode.pivot = targetPoints[nodeIndex]
				)
			)
		)
		redrawViews()
		return true
	)

	on btnPivotBottom pressed do transformSelectedObjects #bottom
	on btnPivotCenter pressed do transformSelectedObjects #center
	on btnPivotTop pressed do transformSelectedObjects #top
	on btnMoveToCenter pressed do transformSelectedObjects #move
)

rollout _rAboutGCMatterportGLBConverter "About" category: 999 (
	group "Description" (
		dotNetControl edtDescription "System.Windows.Forms.Textbox" align:#center height: 60
	)
	
	label lblDummy1 ""
    
	label lblName "" 
	label lblVer ""
	label lblClient ""
	
	label lblDummy2 ""
	
	label lblAuthor ""
	hyperlink lblCopy ""  align: #center
	
	label lblDummy3 ""
	button btnUpdateViewer "Download / Update Model Viewer" width:270 height:26
	
	timer tmrRestart "" active: false interval: 300
	    

	fn bgUpdate = (
		-- Keep the existing project endpoint; an unavailable/private repository fails without replacing files.
		local url = "https://raw.githubusercontent.com/MastaArt/GC-Matterport-GLB-Converter/main/"
		local currentScript = GCMatterportRuntimeFolder + "GC-Matterport-GLB-Converter.ms"
		local stage = GCMatterportRuntimeFolder + "._update_" + ((dotNetClass "System.Guid").NewGuid()).ToString("N") + "\\"
		local replacedFiles = #()
		local updateFailure = undefined
		local hasNewVersion = false
		local rollbackFailed = false
		try (
			makeDir stage all:true
			local downloadedScript = stage + "GC-Matterport-GLB-Converter.ms"
			GCMatterportDownloadFile (url + "GC-Matterport-GLB-Converter.ms") downloadedScript
			if ((getIniSetting downloadedScript "INFO" "NAME") != (getIniSetting currentScript "INFO" "NAME")) do throw "The update belongs to a different script."
			local remoteVersion = dotNetObject "System.Version" (getIniSetting downloadedScript "INFO" "VERSION")
			local localVersion = dotNetObject "System.Version" (getIniSetting currentScript "INFO" "VERSION")
			hasNewVersion = ((remoteVersion.CompareTo localVersion) > 0)
			if (hasNewVersion) do (
				local updateFiles = #("denoise.bat", "vdenoise.xml", "jpegoptim.exe", "gltfpack.exe", "gltfpack_webgl.bat", "model-viewer.zip", "GC-Matterport-GLB-Converter.ms")
				for fileName in updateFiles where (fileName != "GC-Matterport-GLB-Converter.ms") do GCMatterportDownloadFile (url + fileName) (stage + fileName)
				if (_rExportGCMatterportGLBConverter.isRenderingAO or _rExportGCMatterportGLBConverter.isExportingLODs) do throw "An AO render or GLB export is active. Retry the update when it finishes."
				for fileName in updateFiles do (
					local destination = GCMatterportRuntimeFolder + fileName
					local hadPrevious = doesFileExist destination
					if (hadPrevious) then (
						(dotNetClass "System.IO.File").Replace (stage + fileName) destination (stage + fileName + ".previous")
					) else (
						(dotNetClass "System.IO.File").Move (stage + fileName) destination
					)
					append replacedFiles #(fileName, hadPrevious)
				)
				GCMatterportInstallViewerArchive (GCMatterportRuntimeFolder + "model-viewer.zip")
				tmrRestart.active = true
			)
		) catch (updateFailure = getCurrentException() as string)
		if (updateFailure != undefined) do (
			for fileIndex in replacedFiles.count to 1 by -1 do (
				local item = replacedFiles[fileIndex]
				local destination = GCMatterportRuntimeFolder + item[1]
				try (
					if (item[2]) then (
						(dotNetClass "System.IO.File").Replace (stage + item[1] + ".previous") destination undefined
					) else deleteFile destination
				) catch (
					rollbackFailed = true
					format "Update rollback failed for %; backups retained in %: %\n" item[1] stage (getCurrentException())
				)
			)
			format "Converter update unavailable; local version retained. %\n" updateFailure
		)
		-- The staging directory belongs only to this update invocation.
		if (not rollbackFailed and doesDirectoryExist stage) do try ((dotNetClass "System.IO.Directory").Delete stage true) catch (format "Update staging cleanup: %\n" (getCurrentException()))
		return (updateFailure == undefined)
	)

	fn updateWorker = (
		m = dotnetobject "CSharpUtilities.SynchronizingBackgroundWorker"
		m.WorkerSupportsCancellation = true 
		m.CancelAsync() 
		dotNet.addEventHandler m "DoWork" bgUpdate
		m.RunWorkerAsync()	
	)
	
    fn getScriptInfo s releaseInfo: "" =  (
        if(releaseInfo != "") do (
            local r = getINISetting s releaseInfo
            return r
        )
		
        local v = getINISetting s "INFO" "VERSION"
        local a = getINISetting s "INFO" "AUTHOR"
        local n = getINISetting s "INFO" "NAME"
        local o = ""
		for i in (getINISetting s "ABOUT") do o += i + "\r\n"
        local d = getINISetting s "INFO" "DEV"
        local h = getINISetting s "INFO" "HELP"
        local c = getINISetting s "INFO" "CLIENT"
        
		struct data (version, author, name, description, developer, client, help, releases)
		
        local r = for i in (getINISetting s) where (i != "ABOUT" and i != "SCRIPT" and i != "COPY") collect i
		
		return (data version: v author: a name: n description: o developer: d client: c help: h releases: r)
    )
	
	on btnUpdateViewer pressed do (
		if (_rExportGCMatterportGLBConverter.isRenderingAO or _rExportGCMatterportGLBConverter.isExportingLODs) do return false
		btnUpdateViewer.enabled = false
		try (
			GCMatterportUpdateViewer()
			messageBox "Model Viewer was downloaded and installed." title:"Model Viewer" beep:false
		) catch (messageBox ("Model Viewer update failed.\n" + (getCurrentException() as string)) title:"Model Viewer" beep:false)
		btnUpdateViewer.enabled = true
	)

	on tmrRestart tick do (
		this = getThisScriptFileName()
		try(fileIn this) catch()
		vo = getIniSetting this "INFO" "VERSION"
		m = ("Script updated to version " + vo + "!\n\n\n")
		for c in (getIniSetting this vo) do (
			m += c + "\n"
		)
		
		--messageBox m title: "Success!" beep: false
		print "---UPDATED---"
		print m
		tmrRestart.active = false
	)

    on _rAboutGCMatterportGLBConverter open do (
		edtDescription.MultiLine = true
		edtDescription.WordWrap = true
		edtDescription.ReadOnly = true
		edtDescription.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle
		
		
        local i = getScriptInfo (getThisScriptFilename())
		
        lblName.caption = i.name
        lblAuthor.caption = i.author
        lblVer.caption = i.version
        lblCopy.address = lblCopy.caption = i.developer
        lblClient.caption = i.client
		edtDescription.text = i.description
		
		try (floaterGCMatterportGLBConverter.title = i.name + " " + i.version) catch()
		
		updateWorker()
			
		local t = '*'.get "TAB"
		tab = 1
		if (t != "") do (
			try (tab = t as integer) catch(1)
		)  

		local x = '*'.get "x"
		local y = '*'.get "y"
		
		if (x != "" and y != "") do (
			x = x as integer
			y = y as integer
			floaterGCMatterportGLBConverter.pos = [x, y] 
		)		
    )

	on _rAboutGCMatterportGLBConverter close do (
		local p = floaterGCMatterportGLBConverter.pos
		
		'*'.add "x" p.x
		'*'.add "y" p.y
	)	
)

(
local hasLODsAtStartup = ((GCMatterportGetData()).count > 0)
addRollout _rBoilerplateGCMatterportGLBConverter floaterGCMatterportGLBConverter rolledUp: hasLODsAtStartup
addRollout _rExportGCMatterportGLBConverter floaterGCMatterportGLBConverter rolledUp: (not hasLODsAtStartup)
addRollout _rTransformationGCMatterportGLBConverter floaterGCMatterportGLBConverter rolledUp: true
addRollout _rAboutGCMatterportGLBConverter floaterGCMatterportGLBConverter rolledUp: true 
)

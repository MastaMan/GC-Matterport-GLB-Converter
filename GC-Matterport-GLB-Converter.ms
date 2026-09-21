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


try(destroyDialog GCMatterportLiveRollout) catch()
try(closeRolloutFloater floaterGCMatterportGLBConverter) catch()
global floaterGCMatterportGLBConverter = newRolloutFloater "Matterport Converter" 360 580

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
	validationError,
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
	if (materialEntry != undefined and (materialEntry.materialRef == undefined or classOf materialEntry.materialRef != glTFMaterial or materialEntry.validationError != undefined)) do return undefined
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
	local uvInstruction = "Cannot bake AO for this ID: UV channel 2 is missing or unusable on its faces. Select this ID and run Transfer All IDs: Channel 1 -> 2."
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
				if (not (uvPoint.x >= -0.0001 and uvPoint.y >= -0.0001 and uvPoint.x <= 1.0001 and uvPoint.y <= 1.0001)) do return ("Cannot bake AO for this ID: its UV channel 2 coordinates are outside 0..1 or invalid. Run Transfer All IDs: Channel 1 -> 2 for this ID.")
				append uvCorners uvPoint
			)
			local edgeA = uvCorners[2] - uvCorners[1]
			local edgeB = uvCorners[3] - uvCorners[1]
			local uvAreaTwice = abs (edgeA.x * edgeB.y - edgeA.y * edgeB.x)
			if (uvAreaTwice <= 1e-12) do return ("Cannot bake AO for this ID: UV channel 2 contains collapsed faces with no usable UV area. Run Transfer All IDs: Channel 1 -> 2 for this ID.")
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


struct GCMatterportAOOutputState (conversion, colorSpace, display, viewTransform)

fn GCMatterportCaptureAOOutput = (
	local outputSpace = ""
	local outputDisplay = ""
	local outputView = ""
	local conversionType = ColorPipelineMgr.GetDefaultOutputConversion colorSpace: &outputSpace display: &outputDisplay viewTransform: &outputView fileType: #GammaEncoded
	return GCMatterportAOOutputState conversion: conversionType colorSpace: outputSpace display: outputDisplay viewTransform: outputView
)

fn GCMatterportRestoreAOOutput outputState = (
	local outputSpace = outputState.colorSpace
	local outputDisplay = outputState.display
	local outputView = outputState.viewTransform
	if (not ColorPipelineMgr.SetDefaultOutputConversion outputState.conversion colorSpace: &outputSpace display: &outputDisplay viewTransform: &outputView fileType: #GammaEncoded) do throw "Could not restore the original JPEG output color conversion."
	local restoredState = GCMatterportCaptureAOOutput()
	if (restoredState.conversion != outputState.conversion or restoredState.colorSpace != outputState.colorSpace or restoredState.display != outputState.display or restoredState.viewTransform != outputState.viewTransform) do throw "JPEG output color conversion did not restore to its original settings."
	return true
)

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
	local originalAOOutput = undefined
	local restoreAOOutput = false
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
		-- Native Corona RTT uses the default JPEG output transform, as in GC Configurator.
		originalAOOutput = GCMatterportCaptureAOOutput()
		restoreAOOutput = true
		if (not ColorPipelineMgr.SetDefaultOutputConversion #NoConversion fileType: #GammaEncoded) do throw "Could not disable the JPEG output display transform for AO."
		if ((GCMatterportCaptureAOOutput()).conversion != #NoConversion) do throw "AO requires JPEG output without a display transform."
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
			-- Set after attachment: adding an element can reset its output bitmap settings.
			ElementSetCustomGamma bakeElement 1.0
			if (ElementSetOutputColorConversion != undefined) do (
				ElementSetOutputColorConversion bakeElement #noConversion
				if (ElementGetOutputColorConversion bakeElement != #noConversion) do throw "Could not disable the display transform for AO output."
			)
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
		GCMatterportRestoreAOOutput originalAOOutput
		restoreAOOutput = false
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
	-- Also restore after setup failure, render exception or cancellation.
	if (restoreAOOutput and originalAOOutput != undefined) do (
		try (GCMatterportRestoreAOOutput originalAOOutput) catch (
			local restoreError = getCurrentException() as string
			bakeResult.errorMessage = (if bakeResult.errorMessage == undefined then "" else bakeResult.errorMessage + "\n") + restoreError
		)
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
			if (originalPanelMode == #modify) do (
				-- No sub-object level exists outside a compatible Modify context.
				if (originalSubObjectLevel != undefined) then subObjectLevel = originalSubObjectLevel
				else if (subObjectLevel != undefined) do subObjectLevel = 0
			)
		) catch (bakeResult.errorMessage = (if bakeResult.errorMessage == undefined then "" else bakeResult.errorMessage + "\n") + "Could not restore the original selection/panel: " + (getCurrentException() as string))
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
	local aoMap = Bitmaptexture name: "AO"
	-- AO stores scalar data: bypass image input rules and refresh an overwritten file.
	local aoBitmap = if (ColorPipelineMgr != undefined and ColorPipelineMgr.DataColorSpace != "") then (openBitmap filePath colorSpace: ColorPipelineMgr.DataColorSpace) else (openBitmap filePath gamma: 1.0)
	if (aoBitmap == undefined) do throw "Could not open the completed AO bitmap."
	forceReloadBitmapFile aoBitmap
	aoMap.bitmap = aoBitmap
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
	if materialEntry.validationError != undefined do return ((materialEntry.materialID as string) + ": Error: " + materialEntry.validationError)
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

-- Shared map validation: no render/bake during UI refresh.
fn GCMatterportMapIssue textureMap slotPath visited: #() = (
	if textureMap == undefined do return undefined
	if (findItem visited textureMap) != 0 do return (slotPath + ": cyclic texture graph")
	append visited textureMap
	if (classOf textureMap != Bitmaptexture) do return ((classOf textureMap as string) + " in " + slotPath + "; use Bitmap")
	for mapIndex in 1 to getNumSubTexmaps textureMap do (
		local mapIssue = GCMatterportMapIssue (getSubTexmap textureMap mapIndex) (slotPath + "/" + getSubTexmapSlotName textureMap mapIndex) visited: visited
		if mapIssue != undefined do return mapIssue
	)
	return undefined
)

fn GCMatterportMaterialIssue materialRef = (
	if (materialRef == undefined) do return "missing glTF material"
	if (classOf materialRef != glTFMaterial) do return ("material is " + (classOf materialRef as string) + ", not glTF")
	for mapIndex in 1 to getNumSubTexmaps materialRef do (
		local textureMap = getSubTexmap materialRef mapIndex
		local slotCaption = getSubTexmapSlotName materialRef mapIndex
		local mapIssue = GCMatterportMapIssue textureMap slotCaption
		if mapIssue != undefined do return mapIssue
	)
	return undefined
)

fn GCMatterportAssertExportMaps exportMaterial objectCaption = (
	if (classOf exportMaterial != MultiMaterial) do throw (objectCaption + ": Multi/Sub-Object required.")
	for slotIndex in 1 to exportMaterial.materialList.count do (
		local materialIssue = GCMatterportMaterialIssue exportMaterial.materialList[slotIndex]
		if materialIssue != undefined do throw (objectCaption + " / ID " + (exportMaterial.materialIDList[slotIndex] as string) + ": " + materialIssue)
	)
	return true
)

global GCMatterportGeometrySummaryCache = #()
fn GCMatterportGeometrySummary sceneNode = (
	-- Geometry is recomputed on explicit Refresh; map/class checks remain live.
	local sampleTime = timeStamp()
	local cachedIndex = 0
	for summaryIndex in 1 to GCMatterportGeometrySummaryCache.count where (GCMatterportGeometrySummaryCache[summaryIndex][1] == sceneNode) do cachedIndex = summaryIndex
	if cachedIndex > 0 do (
		local cached = GCMatterportGeometrySummaryCache[cachedIndex]
		return cached[3]
	)
	local resultData = #(0, "Polys", #(), undefined)
	local evaluatedMesh = undefined
	try (
		if (not isValidNode sceneNode or superclassOf sceneNode != GeometryClass) do throw "geometry unavailable"
		if (classOf sceneNode == Editable_Poly or classOf sceneNode == PolyMeshObject) then (
			resultData[1] = polyop.getNumFaces sceneNode
			for faceIndex in 1 to resultData[1] do appendIfUnique resultData[3] (polyop.getFaceMatID sceneNode faceIndex)
		) else (
			evaluatedMesh = snapshotAsMesh sceneNode
			resultData[1] = evaluatedMesh.numfaces
			resultData[2] = "Tris"
			for faceIndex in 1 to evaluatedMesh.numfaces do appendIfUnique resultData[3] (getFaceMatID evaluatedMesh faceIndex)
		)
	) catch (resultData[4] = getCurrentException() as string)
	if evaluatedMesh != undefined do delete evaluatedMesh
	local cacheRecord = #(sceneNode,sampleTime,resultData)
	if cachedIndex == 0 then append GCMatterportGeometrySummaryCache cacheRecord else GCMatterportGeometrySummaryCache[cachedIndex] = cacheRecord
	return resultData
)

fn GCMatterportGetMaterials selectedLayerNames = (
	local materialEntries = #()
	if (glTFMaterial == undefined) do return materialEntries
	for selectedLayerName in selectedLayerNames do (
		local lodLayer = LayerManager.getLayerFromName selectedLayerName
		local layerNodes = #()
		if lodLayer != undefined do lodLayer.nodes &layerNodes
		for sceneNode in layerNodes do (
			local parentMaterial = sceneNode.material
			if (parentMaterial == undefined or classOf parentMaterial != MultiMaterial) then (
				append materialEntries (GCMatterportMaterialEntry layerName: selectedLayerName nodeRef: sceneNode materialID: 0 slotIndex: 0 validationError: "Multi/Sub-Object required" displayText: (sceneNode.name + " - Error: Multi/Sub-Object required"))
			) else (
				local allIDs = #()
				for materialID in parentMaterial.materialIDList do appendIfUnique allIDs materialID
				local geometrySummary = GCMatterportGeometrySummary sceneNode
				for materialID in geometrySummary[3] do appendIfUnique allIDs materialID
				sort allIDs
				for materialID in allIDs do (
					local slotIndex = findItem parentMaterial.materialIDList materialID
					local subMaterial = if (slotIndex > 0 and slotIndex <= parentMaterial.materialList.count) then parentMaterial.materialList[slotIndex] else undefined
					local materialIssue = GCMatterportMaterialIssue subMaterial
					local matchingIDs = for assignedID in parentMaterial.materialIDList where assignedID == materialID collect assignedID
					if matchingIDs.count > 1 do materialIssue = "duplicate Material ID"
					local materialEntry = GCMatterportMaterialEntry layerName: selectedLayerName nodeRef: sceneNode materialRef: subMaterial slotIndex: slotIndex materialID: materialID validationError: materialIssue
					materialEntry.displayText = GCMatterportFormatMaterialRow materialEntry
					append materialEntries materialEntry
				)
				if allIDs.count == 0 do append materialEntries (GCMatterportMaterialEntry layerName: selectedLayerName nodeRef: sceneNode materialID: 0 slotIndex: 0 validationError: "empty Multi/Sub-Object" displayText: (sceneNode.name + " - Error: empty Multi/Sub-Object"))
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
		if isLayerReady do (
			for materialEntry in (GCMatterportGetMaterials #(sceneLayerName)) where materialEntry.validationError != undefined do isLayerReady = false
		)
		local countCaption = ""
		if isLayerReady do (
			local summaryData = GCMatterportGeometrySummary layerNodes[1]
			if summaryData[4] == undefined do (
				local formattedCount = (dotNetClass "System.String").Format (dotNetClass "System.Globalization.CultureInfo").InvariantCulture "{0:N0}" (dotNetObject "System.Int32" summaryData[1])
				countCaption = " (" + summaryData[2] + ": " + (substituteString formattedCount "," " ") + ")"
			)
		)
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
		GCMatterportLODEntry layerName: sceneLayerName displayText: (glbPrefix + aoPrefix + displayPrefix + sceneLayerName + countCaption) objectCount: layerNodes.count isReady: isLayerReady
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


global GCMatterportMaterialContextEntry

fn GCMatterportPreviewUnwrapChannel2 materialEntry = (
	if (not GCMatterportIsCurrentMaterialEntry materialEntry) do throw "The object or material assignment changed. Refresh Materials and select the ID again."
	local targetNode = materialEntry.nodeRef
	local sourceMesh = undefined
	local failureReason = undefined
	try (
		sourceMesh = snapshotAsMesh targetNode
		local hasFaces = false
		for faceIndex in 1 to sourceMesh.numfaces while not hasFaces do hasFaces = (getFaceMatID sourceMesh faceIndex == materialEntry.materialID)
		if (not hasFaces) do throw "No faces use this Material ID."
		if (not meshop.getMapSupport sourceMesh 2) do throw "UV channel 2 is missing. Preview does not create or unwrap UVs."
		if (meshop.getNumMapVerts sourceMesh 2 == 0) do throw "UV channel 2 is empty."
	) catch (failureReason = getCurrentException() as string)
	if (sourceMesh != undefined) do delete sourceMesh
	if (failureReason != undefined) do throw failureReason
	local previewName = "GC Preview Unwrap Channel 2"
	local previewModifier = undefined
	for candidate in targetNode.modifiers where (classOf candidate == Unwrap_UVW and candidate.name == previewName) do (
		if (previewModifier != undefined) do throw "Several preview modifiers exist. Keep one at the top of the stack."
		previewModifier = candidate
	)
	if (previewModifier != undefined) do (
		if (targetNode.modifiers[1] != previewModifier) do throw "Move GC Preview Unwrap Channel 2 to the top of the stack before previewing."
		if (previewModifier.unwrap.getMapChannel() != 2) do throw "The preview modifier channel was changed. Restore channel 2 or remove that modifier."
		if ((refs.dependentNodes previewModifier).count != 1) do throw "The preview modifier is instanced. Make it unique before previewing."
	)
	undo "Preview Unwrap Channel 2" on (
		select targetNode
		max modify mode
		if (previewModifier == undefined) do (
			previewModifier = Unwrap_UVW name: previewName
			previewModifier.unwrap.setMapChannel 2
			addModifier targetNode previewModifier before: 0
		)
		modPanel.setCurrentObject previewModifier
		subObjectLevel = 3
		previewModifier.unwrap2.setTVSubObjectMode 3
		previewModifier.unwrap2.setTVElementMode false
		previewModifier.unwrap2.setEnableSoftSelection false
		previewModifier.unwrap2.setFilterSelected false
		previewModifier.unwrap6.selectFacesByNode #{} targetNode
		previewModifier.unwrap2.selectByMatID materialEntry.materialID
		if ((previewModifier.unwrap6.getSelectedFacesByNode targetNode).numberSet == 0) do throw "Unwrap could not select this Material ID."
		previewModifier.unwrap2.setFilterSelected true
		previewModifier.unwrap.edit()
	)
	return true
)

rcmenu GCMatterportMaterialContextMenu (
	menuItem previewUnwrapItem "Preview Unwrap Channel 2"
	menuItem renderSelectedAOItem "Render AO for Selected IDs"
	separator previewSeparator
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
	on GCMatterportMaterialContextMenu open do (
		previewUnwrapItem.enabled = (GCMatterportMaterialContextEntry != undefined and not _rExportGCMatterportGLBConverter.isRenderingAO and not _rExportGCMatterportGLBConverter.isExportingLODs)
		renderSelectedAOItem.enabled = _rExportGCMatterportGLBConverter.btnRenderAO.enabled
	)
	on previewUnwrapItem picked do (
		try (GCMatterportPreviewUnwrapChannel2 GCMatterportMaterialContextEntry) catch (messageBox (getCurrentException() as string) title: "Preview Unwrap Channel 2" beep: false)
	)
	on renderSelectedAOItem picked do _rExportGCMatterportGLBConverter.renderSelectedAO()
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
					try (GCMatterportAssertExportMaps parentMaterial entryCaption) catch (append issues (getCurrentException() as string))
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
			GCMatterportAssertExportMaps temporaryNode.material exportJob.nodeRef.name
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
		) catch (failureReason = (if failureReason == undefined then "" else failureReason + "\n") + "Could not remove temporary export geometry: " + (getCurrentException() as string))
		try (
			select (for sceneNode in originalSelection where (isValidNode sceneNode) collect sceneNode)
			setCommandPanelTaskMode mode: originalPanelMode
			if (originalPanelMode == #modify and originalStackObject != undefined) do modPanel.setCurrentObject originalStackObject
			if (originalPanelMode == #modify) do (
				-- No sub-object level exists outside a compatible Modify context.
				if (originalSubObjectLevel != undefined) then subObjectLevel = originalSubObjectLevel
				else if (subObjectLevel != undefined) do subObjectLevel = 0
			)
		) catch (failureReason = (if failureReason == undefined then "" else failureReason + "\n") + "Could not fully restore the original selection/panel: " + (getCurrentException() as string))
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

global GCMatterportPCPreviewProcess
global GCMatterportPCPreviewPort
global GCMatterportPCPreviewRoot
global GCMatterportPCPreviewToken
global GCMatterportLiveSession
global GCMatterportLiveStop
global GCMatterportPreviewServerReady
global GCMatterportPreviewStartBusy = false
global GCMatterportPreviewLastProbeError = ""

-- Stop only localhost binaries belonging to this converter installation.
-- Enumerating by path also recovers processes left behind after script reloads.
fn GCMatterportStopAllPreviewServers = (
	local pathClass = dotNetClass "System.IO.Path"
	local ownedExecutables = for relativeFolder in #("model-viewer\\", "playcanvas-viewer\\") collect (toLower (pathClass.GetFullPath (GCMatterportRuntimeFolder + relativeFolder + "localhost.exe")))
	local failureReason = undefined
	for serverProcess in ((dotNetClass "System.Diagnostics.Process").GetProcessesByName "localhost") do (
		local executablePath = undefined
		try (
			if (not serverProcess.HasExited) do executablePath = toLower (pathClass.GetFullPath (serverProcess.MainModule.FileName as string))
		) catch (format "Preview ownership could not be inspected for PID %: %\n" serverProcess.Id (getCurrentException()))
		if (executablePath != undefined and (findItem ownedExecutables executablePath) > 0) do (
			try (
				if (not serverProcess.HasExited) do (
					serverProcess.Kill()
					if (not serverProcess.WaitForExit 3000) do throw "The previous converter viewer server did not exit within 3 seconds."
				)
			) catch (
				failureReason = (if failureReason == undefined then "" else failureReason + "\n") + "Could not stop converter viewer PID " + (serverProcess.Id as string) + ": " + (getCurrentException() as string)
			)
		)
		serverProcess.Dispose()
	)
	if (failureReason != undefined) do throw failureReason
	for storedProcess in #(GCMatterportPreviewProcess, GCMatterportPCPreviewProcess) where (storedProcess != undefined) do storedProcess.Dispose()
	GCMatterportPreviewProcess = undefined
	GCMatterportPreviewPort = undefined
	GCMatterportPCPreviewProcess = undefined
	GCMatterportPCPreviewPort = undefined
	return true
)

fn GCMatterportStartPreviewServer viewerFolder = (
	if GCMatterportPreviewStartBusy do throw "A Model Viewer server is already starting."
	GCMatterportPreviewStartBusy = true
	local startedServer = undefined
	local resultData = undefined
	local failureReason = undefined
	try (
		local serverExecutable = viewerFolder + "localhost.exe"
		if (not doesFileExist serverExecutable) do throw ("Missing Model Viewer server: " + serverExecutable)
		-- The bundled server exits immediately when another instance owns its folder.
		GCMatterportStopAllPreviewServers()
		local readyToken = ((dotNetClass "System.Guid").NewGuid()).ToString "N"
		(dotNetClass "System.IO.File").WriteAllText (viewerFolder + "viewer-ready.txt") readyToken
		local attemptReport = ""
		for attemptIndex in 1 to 3 while (resultData == undefined) do (
			local listener = dotNetObject "System.Net.Sockets.TcpListener" (dotNetClass "System.Net.IPAddress").Loopback 0
			listener.Start()
			local portNumber = listener.LocalEndpoint.Port
			listener.Stop()
			local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
			startInfo.FileName = serverExecutable
			startInfo.Arguments = "\"" + (trimRight viewerFolder "\\/") + "\" " + (portNumber as string) + " 127.0.0.1"
			startInfo.WorkingDirectory = viewerFolder
			startInfo.UseShellExecute = false
			startInfo.CreateNoWindow = true
			startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden
			startInfo.RedirectStandardError = true
			startInfo.RedirectStandardOutput = true
			startedServer = (dotNetClass "System.Diagnostics.Process").Start startInfo
			local stderrTask = startedServer.StandardError.ReadToEndAsync()
			local stdoutTask = startedServer.StandardOutput.ReadToEndAsync()
			for waitIndex in 1 to 30 while (resultData == undefined and not startedServer.HasExited) do (
				if (GCMatterportPreviewServerReady portNumber readyToken) then (
					resultData = #(startedServer, portNumber, readyToken)
				) else sleep 0.1
			)
			if (resultData == undefined) do (
				local attemptReason = if startedServer.HasExited then ("process exited with code " + (startedServer.ExitCode as string)) else ("HTTP readiness failed: " + GCMatterportPreviewLastProbeError)
				if (not startedServer.HasExited) do startedServer.Kill()
				if (not startedServer.WaitForExit 3000) do throw "The failed viewer server did not exit within 3 seconds."
				if stderrTask.IsCompleted do (
					local errorText = stderrTask.Result as string
					if (errorText != "") do attemptReason += "\n" + (substring errorText 1 (amin errorText.count 1200))
				)
				attemptReport += "\nAttempt " + (attemptIndex as string) + ", 127.0.0.1:" + (portNumber as string) + ": " + attemptReason
				startedServer.Dispose()
				startedServer = undefined
			)
		)
		if (resultData == undefined) do throw ("The local Model Viewer server could not start.\nExecutable: " + serverExecutable + "\nFolder: " + viewerFolder + attemptReport)
		callbacks.removeScripts id: #GCMatterportPreviewShutdown
		callbacks.removeScripts id: #GCMatterportPCPreviewShutdown
		callbacks.addScript #preSystemShutdown "GCMatterportStopAllPreviewServers()" id: #GCMatterportPreviewShutdown
	) catch (failureReason = getCurrentException() as string)
	if (failureReason != undefined and startedServer != undefined) do (
		try (
			if (not startedServer.HasExited) do startedServer.Kill()
			startedServer.WaitForExit 3000
			startedServer.Dispose()
		) catch (failureReason += "\nServer cleanup: " + (getCurrentException() as string))
	)
	GCMatterportPreviewStartBusy = false
	if (failureReason != undefined) do throw failureReason
	return resultData
)

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
		if (not isReady) do GCMatterportPreviewLastProbeError = "readiness token mismatch"
	) catch (isReady = false; GCMatterportPreviewLastProbeError = getCurrentException() as string)
	if (reader != undefined) do reader.Dispose()
	if (response != undefined) do response.Dispose()
	return isReady
)

fn GCMatterportEnsurePreviewServer viewerFolder = (
	local serverData = GCMatterportStartPreviewServer viewerFolder
	GCMatterportPreviewProcess = serverData[1]
	GCMatterportPreviewPort = serverData[2]
	GCMatterportPreviewToken = serverData[3]
	GCMatterportPreviewRoot = viewerFolder
	return serverData[2]
)



fn GCMatterportLiveBrowserScript = (
 return "(() => {\n const token=new URLSearchParams(location.search).get('live');\n if(!token || !/^[a-f0-9]{32}$/.test(token)) return;\n const viewer=document.querySelector('model-viewer'), root=new URL('/live/'+token+'/',location.href);\n const status=document.createElement('div'); status.id='gc-live-status';\n Object.assign(status.style,{position:'fixed',bottom:'12px',left:'12px',zIndex:10,padding:'9px 13px',background:'#20252de8',color:'#fff',font:'13px sans-serif',maxWidth:'85vw',pointerEvents:'none'});\n status.textContent='Google Live Preview: loading…';document.body.append(status);\n let revision=0, appliedTimestamp=null, busy=false, state={}, templates=null, retryAt=0, applyCount=0, closed=false;\n const instances=new Map(), imageCache=new Map(), textureCache=new Map();\n const privateValue=(object,description)=>{\n  for(let prototype=object;prototype;prototype=Object.getPrototypeOf(prototype)) {\n   const symbol=Object.getOwnPropertySymbols(prototype).find(symbol=>symbol.description===description);\n   if(symbol) return object[symbol];\n  }\n };\n const show=(message,error=false)=>{status.textContent=message;status.style.color=error?'#ffb4a9':'#fff';};\n const bindKey=mesh=>{for(let node=mesh;node;node=node.parent) if(/^GC_Live_ID_\\d+$/.test(node.name)) return node.name;return null;};\n const descriptorKey=descriptor=>JSON.stringify(descriptor);\n const transformKey=descriptor=>descriptor?JSON.stringify([descriptor.uv,descriptor.tiling,descriptor.offset,descriptor.rotation,descriptor.wrap]):'none';\n function localURL(relative) {\n  const url=new URL(relative,root);\n  if(url.origin!==location.origin || !url.pathname.startsWith(root.pathname)) throw new Error('Invalid local texture URL.');\n  return url.href;\n }\n async function imageData(descriptor) {\n  const url=localURL(descriptor.url);\n  if(!imageCache.has(url)) imageCache.set(url,(async()=>{\n   const wrapped=await viewer.createTexture(url);\n   const raw=[...(privateValue(wrapped,'correlatedObjects')||[])].find(texture=>texture.isTexture);\n   if(!raw) throw new Error('The installed Google texture API is incompatible. Restore the bundled viewer.');\n   const source=raw.image, canvas=document.createElement('canvas');canvas.width=source.width;canvas.height=source.height;\n   const context=canvas.getContext('2d',{willReadFrequently:true});context.drawImage(source,0,0);\n   return {raw,canvas,pixels:context.getImageData(0,0,canvas.width,canvas.height)};\n  })());\n  try{return await imageCache.get(url);}catch(error){imageCache.delete(url);throw error;}\n }\n function configure(texture,descriptor,data) {\n  texture.colorSpace=data?'':'srgb';texture.flipY=false;\n  texture.channel=descriptor.uv;\n  const angle=descriptor.rotation*Math.PI/180, [u,v]=descriptor.tiling,[x,y]=descriptor.offset;\n  texture.offset.set(x+.5-.5*(u*Math.cos(angle)+v*Math.sin(angle)),-y+.5-.5*(v*Math.cos(angle)-u*Math.sin(angle)));\n  texture.repeat.set(u,v);texture.center.set(0,0);texture.rotation=angle;\n  texture.wrapS=descriptor.wrap[0];texture.wrapT=descriptor.wrap[1];texture.updateMatrix();texture.needsUpdate=true;\n  return texture;\n }\n async function textureFor(descriptor,role,used) {\n  if(!descriptor) return null;\n  const key=role+':'+descriptorKey(descriptor);used.add(key);\n  if(!textureCache.has(key)) {\n   const image=await imageData(descriptor);let texture=image.raw.clone();texture.source=new image.raw.source.constructor(image.raw.image);\n   if(role==='scalar') {\n    const canvas=document.createElement('canvas');canvas.width=image.canvas.width;canvas.height=image.canvas.height;\n    const context=canvas.getContext('2d'), pixels=new ImageData(new Uint8ClampedArray(image.pixels.data),canvas.width,canvas.height);\n    for(let i=0;i<pixels.data.length;i+=4){const value=Math.max(pixels.data[i],pixels.data[i+1],pixels.data[i+2]);pixels.data[i]=pixels.data[i+1]=pixels.data[i+2]=pixels.data[i+3]=value;}\n    context.putImageData(pixels,0,0);texture.image=canvas;\n   }\n   textureCache.set(key,configure(texture,descriptor,role!=='color'));\n  }\n  return textureCache.get(key);\n }\n async function metallicRoughness(rough,metal,used) {\n  if(!rough&&!metal) return [null,null];\n  // Distinct UV transforms cannot share a packed texture. Google's Three material\n  // supports separate roughnessMap / metalnessMap, preserving both exactly.\n  if(rough&&metal&&transformKey(rough)!==transformKey(metal)) return [await textureFor(rough,'scalar',used),await textureFor(metal,'scalar',used)];\n  const key='mr:'+descriptorKey([rough,metal]);used.add(key);\n  if(!textureCache.has(key)) {\n   const roughImage=rough?await imageData(rough):null, metalImage=metal?await imageData(metal):null;\n   const width=Math.max(roughImage?.canvas.width||1,metalImage?.canvas.width||1),height=Math.max(roughImage?.canvas.height||1,metalImage?.canvas.height||1);\n   const read=image=>{\n    if(!image)return null;\n    if(image.canvas.width===width&&image.canvas.height===height)return image.pixels.data;\n    const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;\n    const context=canvas.getContext('2d',{willReadFrequently:true});context.drawImage(image.canvas,0,0,width,height);return context.getImageData(0,0,width,height).data;\n   };\n   const r=read(roughImage),m=read(metalImage),canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;\n   const context=canvas.getContext('2d'), pixels=context.createImageData(width,height);\n   for(let i=0;i<pixels.data.length;i+=4){pixels.data[i]=255;pixels.data[i+1]=r?Math.max(r[i],r[i+1],r[i+2]):255;pixels.data[i+2]=m?Math.max(m[i],m[i+1],m[i+2]):255;pixels.data[i+3]=255;}\n   context.putImageData(pixels,0,0);\n   const basis=(roughImage||metalImage).raw;const texture=basis.clone();texture.source=new basis.source.constructor(canvas);\n   textureCache.set(key,configure(texture,rough||metal,true));\n  }\n  const texture=textureCache.get(key);return [rough?texture:null,metal?texture:null];\n }\n const mapSlots={basecolormap:['map','color'],alphamap:['alphaMap','scalar'],normalmap:['normalMap','normal'],ambientocclusionmap:['aoMap','scalar'],emissionmap:['emissiveMap','color'],clearcoatmap:['clearcoatMap','scalar'],clearcoatroughnessmap:['clearcoatRoughnessMap','scalar'],clearcoatnormalmap:['clearcoatNormalMap','normal'],sheencolormap:['sheenColorMap','color'],sheenroughnessmap:['sheenRoughnessMap','scalar'],specularmap:['specularIntensityMap','scalar'],specularcolormap:['specularColorMap','color'],transmissionmap:['transmissionMap','scalar'],volumethicknessmap:['thicknessMap','scalar']};\n const setColor=(target,rgb)=>target?.setRGB(...rgb);\n async function prepareMaterial(key,data,used) {\n  const maps={};\n  for(const [field,[property,role]] of Object.entries(mapSlots)) maps[property]=await textureFor(data[field],role,used);\n  const [roughnessMap,metalnessMap]=await metallicRoughness(data.roughnessmap,data.metalnessmap,used);maps.roughnessMap=roughnessMap;maps.metalnessMap=metalnessMap;\n  let pair=instances.get(key);\n  if(!pair){pair={lit:templates[0].clone(),unlit:templates[1].clone()};instances.set(key,pair);}\n  const material=data.unlit?pair.unlit:pair.lit;\n  return {material,maps,apply(){\n   setColor(material.color,data.basecolor);setColor(material.emissive,data.emissioncolor);\n   material.metalness=data.metalness;material.roughness=data.roughness;\n   material.normalScale?.set(data.normal,data.normal);material.aoMapIntensity=data.ambientocclusion;\n   material.side=data.doublesided?2:0;material.transparent=data.alphamode===3;material.depthWrite=!material.transparent;material.alphaTest=data.alphamode===2?data.alphacutoff:0;material.opacity=1;\n   material.clearcoat=data.enableclearcoat?data.clearcoat:0;material.clearcoatRoughness=data.clearcoatroughness;material.clearcoatNormalScale?.set(data.clearcoatnormal,data.clearcoatnormal);\n   material.sheen=data.enablesheen?1:0;setColor(material.sheenColor,data.sheencolor);material.sheenRoughness=data.sheenroughness;\n   material.specularIntensity=data.enablespecular?data.specular:1;setColor(material.specularColor,data.enablespecular?data.specularcolor:[1,1,1]);\n   material.transmission=data.enabletransmission?data.transmission:0;material.ior=data.enableindexofrefraction?data.indexofrefraction:1.5;\n   material.thickness=data.enablevolume?data.volumethickness:0;material.attenuationDistance=data.enablevolume&&data.volumedistance>0?data.volumedistance:Infinity;setColor(material.attenuationColor,data.enablevolume?data.volumecolor:[1,1,1]);\n   Object.assign(material,maps);if(!data.aoEnabled)material.aoMap=null;material.needsUpdate=true;\n  }};\n }\n async function readJSON(relative) {const response=await fetch(new URL(relative,root),{cache:'no-store'});if(!response.ok)throw new Error('Local sync file unavailable: '+relative);return response.json();}\n async function poll() {\n  if(closed||busy||!viewer?.loaded||performance.now()<retryAt)return;\n  busy=true;\n  try {\n   const manifest=await readJSON('manifest.json');\n   if(manifest.session!==token)throw new Error('Preview session mismatch.');\n   if(manifest.closed){closed=true;show('Google Live Preview: sync stopped. Reopen from Max to start a new session.');return;}\n   if(manifest.timestamp===appliedTimestamp)return;\n   const scene=privateValue(viewer,'scene'),renderer=privateValue(viewer,'renderer'),loader=privateValue(renderer?.loader,'loader');\n   if(!scene?.model?.traverse||!scene.queueRender||!loader?.parse)throw new Error('Google Live Preview adapter is incompatible with this viewer build.');\n   if(!templates) {\n    const gltf={asset:{version:'2.0'},nodes:[],scenes:[{nodes:[]}],scene:0,materials:[{extensions:{KHR_materials_clearcoat:{clearcoatFactor:0}}},{extensions:{KHR_materials_unlit:{}}}],extensionsUsed:['KHR_materials_clearcoat','KHR_materials_unlit']};\n    const parsed=await new Promise((resolve,reject)=>loader.parse(gltf,root.href,resolve,reject));templates=await parsed.parser.getDependencies('material');\n   }\n   let nextState=structuredClone(state),nextRevision=manifest.revision,nextTimestamp=manifest.timestamp;\n   if(revision===0){const initial=await readJSON('state.json');nextState=initial.materials;nextRevision=initial.revision;nextTimestamp=initial.timestamp;}\n   else for(let r=revision+1;r<=manifest.revision;r++){const patch=await readJSON('updates/'+r+'.json');for(const [key,changes] of Object.entries(patch.changes))Object.assign(nextState[key],changes);}\n   const targets=[];scene.model.traverse(mesh=>{\n    if(!mesh.isMesh)return;const key=bindKey(mesh);if(!nextState[key])throw new Error('Source Material ID binding changed. Reopen Live Preview.');\n    for(const descriptor of Object.values(nextState[key]))if(descriptor?.url){const attribute=descriptor.uv===0?'uv':'uv'+descriptor.uv;if(!mesh.geometry.attributes[attribute])throw new Error('Required UV channel is absent. Reopen after adding UVs.');}\n    targets.push({mesh,key});\n   });\n   if(new Set(targets.map(target=>target.key)).size!==Object.keys(nextState).length)throw new Error('Source ID layout changed. Reopen Live Preview.');\n   const used=new Set(),prepared=new Map();\n   for(const [key,data] of Object.entries(nextState))prepared.set(key,await prepareMaterial(key,data,used));\n   // Never let an older asynchronous texture merge overwrite a newer change.\n   const latest=await readJSON('manifest.json');if(latest.timestamp!==nextTimestamp){\n    const activeTextures=new Set([...instances.values()].flatMap(pair=>[pair.lit,pair.unlit]).flatMap(material=>Object.values(material).filter(value=>value?.isTexture)));\n    for(const [key,texture] of textureCache)if(!used.has(key)&&!activeTextures.has(texture)){texture.dispose();textureCache.delete(key);}\n    return;\n   }\n   const before=JSON.stringify([viewer.getCameraOrbit(),viewer.getCameraTarget()]),geometries=targets.map(target=>target.mesh.geometry);\n   for(const preparedMaterial of prepared.values())preparedMaterial.apply();\n   for(const target of targets){const material=prepared.get(target.key).material;material.envMap=target.mesh.material.envMap;material.vertexColors=target.mesh.material.vertexColors;target.mesh.material=material;}\n   scene.queueShadowRender();scene.queueRender();revision=nextRevision;appliedTimestamp=nextTimestamp;state=nextState;applyCount++;\n   for(const [key,texture] of textureCache)if(!used.has(key)){texture.dispose();textureCache.delete(key);}\n   const activeURLs=new Set(Object.values(state).flatMap(material=>Object.values(material).filter(value=>value?.url).map(value=>localURL(value.url))));\n   for(const [url,promise] of imageCache)if(!activeURLs.has(url)){promise.then(image=>image.raw.dispose());imageCache.delete(url);}\n   status.dataset.check=JSON.stringify({revision,timestamp:appliedTimestamp,applyCount,viewer:'google-model-viewer',cameraPreserved:before===JSON.stringify([viewer.getCameraOrbit(),viewer.getCameraTarget()]),geometryPreserved:targets.every((target,index)=>target.mesh.geometry===geometries[index]),bindings:targets.map(target=>({key:target.key,geometry:target.mesh.geometry.uuid,color:target.mesh.material.color.toArray(),roughness:target.mesh.material.roughness,metalness:target.mesh.material.metalness,thickness:target.mesh.material.thickness,attenuationDistance:target.mesh.material.attenuationDistance,attenuationColor:target.mesh.material.attenuationColor?.toArray(),thicknessMap:!!target.mesh.material.thicknessMap,ao:!!target.mesh.material.aoMap,roughMap:!!target.mesh.material.roughnessMap,metalMap:!!target.mesh.material.metalnessMap,packed:!!target.mesh.material.roughnessMap&&target.mesh.material.roughnessMap===target.mesh.material.metalnessMap,metalPixel:target.mesh.material.metalnessMap?.image?.getContext?Array.from(target.mesh.material.metalnessMap.image.getContext('2d').getImageData(0,0,1,1).data):null,mrPixel:target.mesh.material.roughnessMap?.image?.getContext?Array.from(target.mesh.material.roughnessMap.image.getContext('2d').getImageData(0,0,1,1).data):null}))});\n   show('Google Live Preview · auto sync · revision '+revision);\n  } catch(error){if(error.message.includes('updates/')||error.message.includes('texture'))revision=0;show('Live Preview: '+error.message,true);retryAt=performance.now()+1500;}\n  finally{busy=false;}\n }\n setInterval(poll,150);poll();\n})();"
)

fn GCMatterportGoogleViewerHTML = (
 return "<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"UTF-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n<title>Google Model Viewer</title><link rel=\"icon\" href=\"/favicon-16x16.png\">\n<style>html,body{padding:0;margin:0;background:#f7f7f7}model-viewer{width:100vw;height:100vh}#error{position:fixed;top:16px;left:16px;right:16px;padding:12px;background:white;color:#900;font:14px sans-serif}</style>\n</head><body>\n<model-viewer alt=\"\" shadow-intensity=\"1\" camera-controls environment-image=\"hdri/studio.hdr\" camera-orbit=\"-36deg 72deg\" field-of-view=\"30deg\" exposure=\"0.4\" tone-mapping=\"aces\" min-field-of-view=\"50deg\" max-field-of-view=\"50deg\" touch-action=\"pan-y\"></model-viewer>\n<div id=\"error\" hidden></div>\n<script type=\"module\">\nconst errorBox=document.querySelector('#error');\nconst reportError=message=>{errorBox.textContent=message;errorBox.hidden=false;};\ntry {\n const response=await fetch('/js/engine.js');\n if(!response.ok) throw new Error('Cannot load Model Viewer engine: '+response.status);\n const engineURL=URL.createObjectURL(new Blob([await response.text()],{type:'application/javascript'}));\n try {await import(engineURL);} finally {URL.revokeObjectURL(engineURL);}\n customElements.get('model-viewer').ktx2TranscoderLocation='/js/basis/';\n const parameters=new URLSearchParams(location.search), model=parameters.get('model'), live=parameters.get('live');\n const viewer=document.querySelector('model-viewer');\n document.title=(parameters.get('title')||'Model Viewer')+' - Google Model Viewer';\n viewer.alt=document.title;window.devicePixelRatio=2;\n viewer.addEventListener('error',()=>reportError('The exported GLB could not be loaded.'));\n if(live && /^[a-f0-9]{32}$/.test(live)) {viewer.minCameraOrbit='auto auto 1%';viewer.src='/live/'+live+'/geometry/scene.glb';}\n else if(model && /^[a-f0-9]{64}$/.test(model)) viewer.src='/models/'+model+'.glb?v='+encodeURIComponent(parameters.get('v')||'');\n else throw new Error('A valid exported LOD or Live Preview session is required.');\n} catch(error) {reportError(error.message||'Model Viewer could not start.');}\n</script><script src=\"/js/live-sync.js\"></script>\n</body></html>\n"
)

fn GCMatterportViewerFiles = (
	return #("js\\live-sync.js", "index.html", "js\\engine.js", "js\\basis\\basis_transcoder.js", "js\\basis\\basis_transcoder.wasm", "hdri\\studio.hdr", "localhost.exe", "mime.types", "favicon-16x16.png")
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
	(dotNetClass "System.IO.File").WriteAllText (stageRoot + "\\index.html") (GCMatterportGoogleViewerHTML()) utf8
	(dotNetClass "System.IO.File").WriteAllText (stageRoot + "\\js\\live-sync.js") (GCMatterportLiveBrowserScript()) utf8
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
		for relativeFile in GCMatterportViewerFiles() where (not prepareOriginal or (findItem #("js\\live-sync.js", "js\\basis\\basis_transcoder.js", "js\\basis\\basis_transcoder.wasm") relativeFile) == 0) do (
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
	if (GCMatterportLiveSession != undefined) do GCMatterportLiveStop()
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

global GCMatterportPCPreviewProcess
global GCMatterportPCPreviewPort
global GCMatterportPCPreviewRoot
global GCMatterportPCPreviewToken

fn GCMatterportStopPCPreviewServer = (
	if (GCMatterportPCPreviewProcess != undefined) do (
		try (
			if (not GCMatterportPCPreviewProcess.HasExited) do GCMatterportPCPreviewProcess.Kill()
			GCMatterportPCPreviewProcess.Dispose()
		) catch (format "Preview server cleanup: %\n" (getCurrentException()))
	)
	GCMatterportPCPreviewProcess = undefined
	GCMatterportPCPreviewPort = undefined
	return true
)

fn GCMatterportPCPreviewServerReady portNumber expectedToken = (
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
		if (not isReady) do GCMatterportPreviewLastProbeError = "readiness token mismatch"
	) catch (isReady = false; GCMatterportPreviewLastProbeError = getCurrentException() as string)
	if (reader != undefined) do reader.Dispose()
	if (response != undefined) do response.Dispose()
	return isReady
)

fn GCMatterportEnsurePCPreviewServer viewerFolder = (
	local serverData = GCMatterportStartPreviewServer viewerFolder
	GCMatterportPCPreviewProcess = serverData[1]
	GCMatterportPCPreviewPort = serverData[2]
	GCMatterportPCPreviewToken = serverData[3]
	GCMatterportPCPreviewRoot = viewerFolder
	return serverData[2]
)



fn GCMatterportPCViewerFiles = (
	return #("LICENSE-engine.txt", "LICENSE-pcui.txt", "LICENSE-observer.txt", "LICENSE-react.txt", "LICENSE-meshoptimizer.txt", "LICENSE-basis.txt", "LICENSE-draco.txt", "index.html", "index.js", "style.css", "localhost.exe", "mime.types", "LICENSE.txt", "LOCAL-CHANGES.txt", "static\\playcanvas-logo.png", "static\\icons\\fly-mode.svg", "static\\icons\\orbit-mode.svg", "static\\lib\\basis\\basis.js", "static\\lib\\basis\\basis.wasm.js", "static\\lib\\basis\\basis.wasm.wasm", "static\\lib\\draco\\draco.js", "static\\lib\\draco\\draco.wasm.js", "static\\lib\\draco\\draco.wasm.wasm", "static\\lib\\lodepng\\lodepng.js", "static\\lib\\lodepng\\lodepng.wasm", "static\\skybox\\artist_workshop_2k.hdr")
)

fn GCMatterportEnsurePCViewerInstalled = (
	local viewerFolder = GCMatterportRuntimeFolder + "playcanvas-viewer\\"
	local isInstalled = true
	for relativeFile in GCMatterportPCViewerFiles() do (
		if (not doesFileExist (viewerFolder + relativeFile)) do isInstalled = false
	)
	if (isInstalled) do return true
	local archivePath = GCMatterportRuntimeFolder + "playcanvas-viewer.zip"
	if (not doesFileExist archivePath) do throw "playcanvas-viewer.zip is missing beside the converter script."
	local stageRoot = GCMatterportRuntimeFolder + "._pcviewer_" + ((dotNetClass "System.Guid").NewGuid()).ToString("N")
	local backupRoot = stageRoot + "_previous"
	local installRoot = trimRight viewerFolder "\\"
	local archive = undefined
	local installFailure = undefined
	local replacedOld = false
	try (
		dotNet.loadAssembly "System.IO.Compression.FileSystem"
		makeDir stageRoot all: true
		archive = (dotNetClass "System.IO.Compression.ZipFile").OpenRead archivePath
		for relativeFile in GCMatterportPCViewerFiles() do (
			local entry = archive.GetEntry (substituteString relativeFile "\\" "/")
			if (entry == undefined or entry.Length == 0) do throw ("PlayCanvas archive is missing: " + relativeFile)
			local destination = stageRoot + "\\" + relativeFile
			makeDir (getFilenamePath destination) all: true
			(dotNetClass "System.IO.Compression.ZipFileExtensions").ExtractToFile entry destination false
		)
		archive.Dispose()
		archive = undefined
		GCMatterportStopPCPreviewServer()
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
	if (doesDirectoryExist stageRoot) do try ((dotNetClass "System.IO.Directory").Delete stageRoot true) catch (format "PlayCanvas staging cleanup: %\n" (getCurrentException()))
	if (installFailure == undefined and replacedOld) do try ((dotNetClass "System.IO.Directory").Delete backupRoot true) catch (format "Previous PlayCanvas cleanup: %\n" (getCurrentException()))
	if (installFailure != undefined) do throw installFailure
	return true
)
fn GCMatterportPreviewPCLOD layerName openBrowser: true = (
	if (GCMatterportLiveSession != undefined) do GCMatterportLiveStop()
	if (not GCMatterportLODHasGLB layerName) do throw "Export this LOD to GLB before opening its preview."
	GCMatterportEnsurePCViewerInstalled()
	local viewerFolder = GCMatterportRuntimeFolder + "playcanvas-viewer\\"
	local sourceFile = maxFilePath + "export\\" + (GCMatterportExportFileName layerName)
	local modelsFolder = viewerFolder + "models\\"
	makeDir modelsFolder all: true
	-- ASCII filenames avoid old TinyWeb filename encoding limits; the title remains Unicode.
	local modelKey = GCMatterportFileKey ((dotNetClass "System.IO.Path").GetFullPath sourceFile)
	local destinationFile = modelsFolder + modelKey + ".glb"
	local stagedFile = modelsFolder + modelKey + ".tmp"
	local backupFile = modelsFolder + modelKey + ".previous"
	local previewFailure = undefined
	local previewURL = undefined
	try (
		(dotNetClass "System.IO.File").Copy sourceFile stagedFile true
		if (doesFileExist destinationFile) then (
			(dotNetClass "System.IO.File").Replace stagedFile destinationFile backupFile
			if (doesFileExist backupFile) do deleteFile backupFile
		) else (
			(dotNetClass "System.IO.File").Move stagedFile destinationFile
		)
		local portNumber = GCMatterportEnsurePCPreviewServer viewerFolder
		local titleValue = (dotNetClass "System.Uri").EscapeDataString layerName
		local cacheVersion = ((dotNetClass "System.DateTime").UtcNow.Ticks as string)
		previewURL = "http://127.0.0.1:" + (portNumber as string) + "/?default&load=" + ((dotNetClass "System.Uri").EscapeDataString ("models/" + modelKey + ".glb?v=" + cacheVersion)) + "&title=" + titleValue
		if (openBrowser) do ShellLaunch previewURL ""
	) catch (
		previewFailure = getCurrentException() as string
		if (doesFileExist stagedFile) do deleteFile stagedFile
	)
	if (previewFailure != undefined) do throw previewFailure
	return previewURL
)



-- Manual material preview. Native glTF serializes materials; geometry is loaded once.
struct GCMatterportLiveSessionData (token, layerName, nodeRef, geometrySignature, materialIDs, folderPath, materialLayout, textureCache = #(), lastState = #(), lastTextureCheck = 0, revision = 0)
struct GCMatterportLiveTextureData (sourcePath, stamp, observedStamp, url)
global GCMatterportLiveObserved
global GCMatterportLivePendingAt
global GCMatterportLiveBusy = false
global GCMatterportLiveGeometryDirty = false
global GCMatterportLiveSession

fn GCMatterportLiveJSONQuote stringValue = (
 local escaped = substituteString (stringValue as string) "\\" "\\\\"
 escaped = substituteString escaped "\"" "\\\""
 escaped = substituteString escaped "\r" "\\r"
 escaped = substituteString escaped "\n" "\\n"
 escaped = substituteString escaped "\t" "\\t"
 return ("\"" + escaped + "\"")
)

fn GCMatterportLiveWrite filePath content = (
 (dotNetClass "System.IO.File").WriteAllText filePath content (dotNetObject "System.Text.UTF8Encoding" false)
 return true
)

fn GCMatterportLiveHashFile filePath = (
 local inputStream = (dotNetClass "System.IO.File").OpenRead filePath
 local hasher = (dotNetClass "System.Security.Cryptography.SHA256").Create()
 local checksum = undefined
 try (checksum = hasher.ComputeHash inputStream) catch (
  inputStream.Dispose()
  hasher.Dispose()
  throw()
 )
 inputStream.Dispose()
 hasher.Dispose()
 return toLower (substituteString ((dotNetClass "System.BitConverter").ToString checksum) "-" "")
)

fn GCMatterportLivePointBits pointValue = (
 return ((bit.floatAsInt pointValue.x) as string) + "," + ((bit.floatAsInt pointValue.y) as string) + "," + ((bit.floatAsInt pointValue.z) as string)
)

fn GCMatterportLiveGeometrySignature sceneNode = (
 local sourceMesh = snapshotAsMesh sceneNode
 local fingerprint = stringStream ""
 try (
  format "%|%|%|" sceneNode.handle sourceMesh.numverts sourceMesh.numfaces to: fingerprint
  for rowIndex in 1 to 4 do format "%;" (GCMatterportLivePointBits sceneNode.transform[rowIndex]) to: fingerprint
  for vertexIndex in 1 to sourceMesh.numverts do format "%:%;" (GCMatterportLivePointBits (getVert sourceMesh vertexIndex)) (GCMatterportLivePointBits (getNormal sourceMesh vertexIndex)) to: fingerprint
  for faceIndex in 1 to sourceMesh.numfaces do format "%:%:%;" (getFace sourceMesh faceIndex) (getFaceMatID sourceMesh faceIndex) (getFaceSmoothGroup sourceMesh faceIndex) to: fingerprint
  for channelIndex in #(1, 2) do (
   local supported = (channelIndex < meshop.getNumMaps sourceMesh and meshop.getMapSupport sourceMesh channelIndex)
   format "|%:%|" channelIndex supported to: fingerprint
   if supported do (
    for vertexIndex in 1 to (meshop.getNumMapVerts sourceMesh channelIndex) do format "%;" (GCMatterportLivePointBits (meshop.getMapVert sourceMesh channelIndex vertexIndex)) to: fingerprint
    for faceIndex in 1 to (meshop.getNumMapFaces sourceMesh channelIndex) do format "%;" (meshop.getMapFace sourceMesh channelIndex faceIndex) to: fingerprint
   )
  )
 ) catch (delete sourceMesh; close fingerprint; throw())
 delete sourceMesh
 local result = GCMatterportFileKey (fingerprint as string)
 close fingerprint
 return result
)

fn GCMatterportLiveEntries layerName = (
 local entries = GCMatterportGetMaterials #(layerName)
 if (entries.count == 0) do throw "Select one LOD with glTF materials."
 local sourceNode = entries[1].nodeRef
 local sourceMesh = snapshotAsMesh sourceNode
 local usedIDs = #()
 for faceIndex in 1 to sourceMesh.numfaces do appendIfUnique usedIDs (getFaceMatID sourceMesh faceIndex)
 delete sourceMesh
 local activeEntries = #()
 for materialID in usedIDs do (
  local matches = for entry in entries where entry.materialID == materialID collect entry
  if (matches.count != 1 or not GCMatterportIsCurrentMaterialEntry matches[1]) do throw "Every used face ID must have exactly one current glTF material."
  append activeEntries matches[1]
 )
 if (activeEntries.count == 0) do throw "The selected LOD contains no faces."
 return activeEntries
)

fn GCMatterportLiveCheckMaps materialRef = (
 for propertyName in getPropNames materialRef where (matchPattern (propertyName as string) pattern: "*Map" ignoreCase: true) do (
  local textureMap = getProperty materialRef propertyName
  if (textureMap != undefined) do (
   if (classOf textureMap != Bitmaptexture) do throw ("Live Preview supports file Bitmap maps only: " + (propertyName as string) + ". Bake procedural maps explicitly first.")
   if (textureMap.coords.mappingType != 0 or textureMap.coords.realWorldScale or textureMap.coords.Noise_On) do throw ("Live Preview requires explicit UV mapping without Real-World Scale or UV noise: " + (propertyName as string))
   if ((findItem #(1, 2) textureMap.coords.mapChannel) == 0) do throw "Live Preview supports UV channels 1 and 2. Other channels require a new preview implementation."
   local resolved = mapPaths.getFullFilePath textureMap.filename
   if (resolved == undefined or resolved == "" or not doesFileExist resolved) do throw ("Missing Live Preview texture: " + textureMap.filename)
  )
 )
 return true
)

fn GCMatterportLiveExportGeometry sessionData entries outputFolder = (
 local originalSelection = selection as array
 local originalPanel = getCommandPanelTaskMode()
 local originalStack = modPanel.getCurrentObject()
 local originalLevel = subObjectLevel
 local temporaryNodes = #()
 local temporaryLayer = undefined
 local failureReason = undefined
 local gltfPath = outputFolder + "scene.gltf"
 makeDir (outputFolder + "maps\\") all: true
 try (
  subObjectLevel = 0
  setCommandPanelTaskMode mode: #create
  with undo off (
   temporaryLayer = LayerManager.newLayerFromName ("GC_Live_" + ((dotNetClass "System.Guid").NewGuid()).ToString("N"))
   for entry in entries do (
    local copyMaterial = copy entry.materialRef
    local aoEnabled = GCMatterportSceneProperties.getValue ((GCMatterportAOKey entry) + "enabled") true
    if (not aoEnabled) do copyMaterial.ambientOcclusionMap = undefined
    GCMatterportLiveCheckMaps copyMaterial
    local previewNode = undefined
    (
     previewNode = copy entry.nodeRef
     append temporaryNodes previewNode
     local worldTransform = previewNode.transform
     previewNode.parent = undefined
     previewNode.transform = worldTransform
     convertToMesh previewNode
     local discardFaces = #{}
     for faceIndex in 1 to previewNode.numfaces where (getFaceMatID previewNode faceIndex != entry.materialID) do discardFaces[faceIndex] = true
     meshop.deleteFaces previewNode discardFaces delIsoVerts: true
     -- Keep both available UV streams even when the starting material does not use them.
     if (copyMaterial.baseColorMap == undefined and meshop.getMapSupport previewNode 1) do (
      copyMaterial.baseColorMap = Bitmaptexture filename: (sessionData.folderPath + "white.png")
      copyMaterial.baseColorMap.coords.mapChannel = 1
     )
     if (copyMaterial.ambientOcclusionMap == undefined and meshop.getNumMaps previewNode > 2 and meshop.getMapSupport previewNode 2) do (
      copyMaterial.ambientOcclusionMap = Bitmaptexture filename: (sessionData.folderPath + "white.png")
      copyMaterial.ambientOcclusionMap.coords.mapChannel = 2
     )
    )
    previewNode.name = "GC_Live_ID_" + (entry.materialID as string)
    copyMaterial.name = previewNode.name
    for faceIndex in 1 to previewNode.numfaces do setFaceMatID previewNode faceIndex 1
    previewNode.material = copyMaterial
    temporaryLayer.addNode previewNode
    previewNode.isHidden = false
    previewNode.isFrozen = false
    local bitmapMaps = getClassInstances Bitmaptexture target: copyMaterial
    for mapIndex in 1 to bitmapMaps.count do (
     local sourceMap = bitmapMaps[mapIndex]
     local sourceImage = mapPaths.getFullFilePath sourceMap.filename
     local destination = outputFolder + "maps\\" + (entry.materialID as string) + "_" + (mapIndex as string) + (getFilenameType sourceImage)
     if (not copyFile sourceImage destination) do throw ("Could not stage Live Preview image: " + sourceImage)
     sourceMap.filename = destination
    )
   )
   select temporaryNodes
   if (not exportFile gltfPath #noPrompt selectedOnly: true using: GLTF_Export) do throw "Live Preview native material export failed."
  )
 ) catch (failureReason = getCurrentException() as string)
 with undo off (
  for previewNode in temporaryNodes where isValidNode previewNode do delete previewNode
  if temporaryLayer != undefined do LayerManager.deleteLayerByName temporaryLayer.name
  select (for originalNode in originalSelection where isValidNode originalNode collect originalNode)
  setCommandPanelTaskMode mode: originalPanel
  if (originalPanel == #modify and originalStack != undefined) do modPanel.setCurrentObject originalStack
  subObjectLevel = originalLevel
 )
 if failureReason != undefined do throw failureReason
 return gltfPath
)


fn GCMatterportLiveNumber numericValue = (
 return substituteString (formattedPrint (numericValue as float) format: ".9g") "," "."
)

fn GCMatterportLiveColor colorValue = (
 return "[" + (GCMatterportLiveNumber (colorValue.r / 255.0)) + "," + (GCMatterportLiveNumber (colorValue.g / 255.0)) + "," + (GCMatterportLiveNumber (colorValue.b / 255.0)) + "]"
)

fn GCMatterportLiveTexture sessionData textureMap forceCheck: false stageTextures: true = (
 if textureMap == undefined do return "null"
 if classOf textureMap != Bitmaptexture do throw "Live Preview supports file Bitmap maps only. Bake procedural maps explicitly first."
 local outputSettings = textureMap.output
 if (outputSettings.invert or outputSettings.enableColorMap or outputSettings.RGB_Level != 1 or outputSettings.output_amount != 1 or outputSettings.RGB_Offset != 0 or textureMap.rgbOutput != 0) do throw "Live Preview requires Bitmap maps without Output color adjustments. Bake these adjustments explicitly first."
 local coords = textureMap.coords
 if (coords.mappingType != 0 or coords.realWorldScale or coords.Noise_On or coords.U_Angle != 0 or coords.V_Angle != 0) do throw "Live Preview supports ordinary UV tiling, offset and W rotation; Real-World Scale, UV noise and tilted UVs are unsupported."
 if findItem #(1, 2) coords.mapChannel == 0 do throw "Live Preview supports existing UV channels 1 and 2."
 local resolved = mapPaths.getFullFilePath textureMap.filename
 if (resolved == undefined or resolved == "" or not doesFileExist resolved) do throw ("Missing texture: " + textureMap.filename)
 local extension = toLower (getFilenameType resolved)
 if findItem #(".png", ".jpg", ".jpeg", ".webp") extension == 0 do throw ("Live Preview requires PNG, JPEG or WebP textures: " + textureMap.filename)
 local cacheEntry = undefined
 for cached in sessionData.textureCache where cached.sourcePath == resolved do cacheEntry = cached
 if cacheEntry == undefined do (
  cacheEntry = GCMatterportLiveTextureData sourcePath: resolved
  append sessionData.textureCache cacheEntry
 )
 local inspectFile = (forceCheck or cacheEntry.observedStamp == undefined or timeStamp() - sessionData.lastTextureCheck >= 1000)
 if inspectFile do (
  local fileInfo = dotNetObject "System.IO.FileInfo" resolved
  if fileInfo.Length == 0 do throw ("Texture is empty or being saved: " + resolved)
  local stamp = (fileInfo.Length as string) + ":" + (fileInfo.LastWriteTimeUtc.Ticks as string)
  cacheEntry.observedStamp = stamp
 )
 if (stageTextures and (cacheEntry.url == undefined or cacheEntry.stamp != cacheEntry.observedStamp or forceCheck)) do (
   local digest = GCMatterportLiveHashFile resolved
   local fileName = digest + extension
   local targetFile = sessionData.folderPath + "textures\\" + fileName
   if not doesFileExist targetFile do (
    if not copyFile resolved targetFile do throw ("Could not cache texture: " + resolved)
   )
   if cacheEntry == undefined then (
    cacheEntry = GCMatterportLiveTextureData sourcePath: resolved
    append sessionData.textureCache cacheEntry
   )
   cacheEntry.stamp = cacheEntry.observedStamp
   cacheEntry.url = "textures/" + fileName
 )
 local wrapU = if coords.U_Mirror then 1002 else if coords.U_Tile then 1000 else 1001
 local wrapV = if coords.V_Mirror then 1002 else if coords.V_Tile then 1000 else 1001
 return "{\"url\":" + (GCMatterportLiveJSONQuote (if stageTextures then cacheEntry.url else resolved + "|" + cacheEntry.observedStamp)) + ",\"uv\":" + ((coords.mapChannel - 1) as string) + ",\"tiling\":[" + (GCMatterportLiveNumber coords.U_Tiling) + "," + (GCMatterportLiveNumber coords.V_Tiling) + "],\"offset\":[" + (GCMatterportLiveNumber coords.U_Offset) + "," + (GCMatterportLiveNumber coords.V_Offset) + "],\"rotation\":" + (GCMatterportLiveNumber coords.W_Angle) + ",\"wrap\":[" + (wrapU as string) + "," + (wrapV as string) + "]}"
)

fn GCMatterportLiveCapture sessionData forceCheck: false stageTextures: true = (
 local sourceNode = sessionData.nodeRef
 if (not isValidNode sourceNode or sourceNode.layer.name != sessionData.layerName) do throw "The source LOD changed. Reopen Live Preview."
 local parentMaterial = sourceNode.material
 if (parentMaterial == undefined or classOf parentMaterial != MultiMaterial or (parentMaterial.materialIDList as string) != sessionData.materialLayout) do throw "The material ID layout changed. Reopen Live Preview."
 local stateRows = #()
 for actualID in sessionData.materialIDs do (
  local slotIndex = findItem parentMaterial.materialIDList actualID
  local materialRef = parentMaterial.materialList[slotIndex]
  if (materialRef == undefined or classOf materialRef != glTFMaterial) do throw "Live Preview requires glTF materials."
  local sourceEntry = GCMatterportMaterialEntry nodeRef: sourceNode materialID: actualID
  local aoEnabled = GCMatterportSceneProperties.getValue ((GCMatterportAOKey sourceEntry) + "enabled") true
  local fields = #()
  for propertyName in #(#baseColor, #emissionColor, #sheenColor, #specularColor, #volumeColor) do append fields #((toLower (propertyName as string)), GCMatterportLiveColor (getProperty materialRef propertyName))
  for propertyName in #(#metalness, #roughness, #normal, #ambientOcclusion, #alphaMode, #alphaCutoff, #clearcoat, #clearcoatRoughness, #clearcoatNormal, #sheenRoughness, #specular, #transmission, #indexOfRefraction, #volumeThickness, #volumeDistance) do append fields #((toLower (propertyName as string)), GCMatterportLiveNumber (getProperty materialRef propertyName))
  for propertyName in #(#DoubleSided, #unlit, #enableClearCoat, #enableSheen, #enableSpecular, #enableTransmission, #enableIndexOfRefraction, #enableVolume) do append fields #((toLower (propertyName as string)), ((getProperty materialRef propertyName) as string))
  append fields #("aoEnabled", aoEnabled as string)
  for propertyName in #(#baseColorMap, #AlphaMap, #roughnessMap, #metalnessMap, #normalMap, #ambientOcclusionMap, #emissionMap, #clearcoatMap, #clearcoatRoughnessMap, #clearcoatNormalMap, #sheenColorMap, #sheenRoughnessMap, #specularMap, #specularColorMap, #transmissionMap, #volumeThicknessMap) do (
   local textureMap = getProperty materialRef propertyName
   local slotName = toLower (propertyName as string)
   if (matchPattern slotName pattern: "clearcoat*" and not materialRef.enableClearCoat) do textureMap = undefined
   if (matchPattern slotName pattern: "sheen*" and not materialRef.enableSheen) do textureMap = undefined
   if (matchPattern slotName pattern: "specular*" and not materialRef.enableSpecular) do textureMap = undefined
   if (propertyName == #transmissionMap and not materialRef.enableTransmission) do textureMap = undefined
   if (propertyName == #volumeThicknessMap and not materialRef.enableVolume) do textureMap = undefined
   if propertyName == #ambientOcclusionMap and not aoEnabled do textureMap = undefined
   append fields #((toLower (propertyName as string)), GCMatterportLiveTexture sessionData textureMap forceCheck: forceCheck stageTextures: stageTextures)
  )
  append stateRows #("GC_Live_ID_" + (actualID as string), fields)
 )
 if (forceCheck or timeStamp() - sessionData.lastTextureCheck >= 1000) do sessionData.lastTextureCheck = timeStamp()
 return stateRows
)

fn GCMatterportLiveStateJSON stateRows previousRows: #() = (
 local content = "{"
 local written = 0
 for rowIndex in 1 to stateRows.count do (
  local fields = stateRows[rowIndex][2]
  local previousFields = if rowIndex <= previousRows.count then previousRows[rowIndex][2] else #()
  local fieldContent = ""
  local fieldCount = 0
  for fieldIndex in 1 to fields.count do (
   if (fieldIndex > previousFields.count or fields[fieldIndex][2] != previousFields[fieldIndex][2]) do (
    if fieldCount > 0 do fieldContent += ","
    fieldContent += (GCMatterportLiveJSONQuote fields[fieldIndex][1]) + ":" + fields[fieldIndex][2]
    fieldCount += 1
   )
  )
  if fieldCount > 0 do (
   if written > 0 do content += ","
   content += (GCMatterportLiveJSONQuote stateRows[rowIndex][1]) + ":{" + fieldContent + "}"
   written += 1
  )
 )
 return content + "}"
)

fn GCMatterportLivePublishAtomic targetFile content = (
 local staged = targetFile + ".next"
 local backup = targetFile + ".previous"
 GCMatterportLiveWrite staged content
 if doesFileExist targetFile then (dotNetClass "System.IO.File").Replace staged targetFile backup else (dotNetClass "System.IO.File").Move staged targetFile
 if doesFileExist backup do deleteFile backup
 return true
)


fn GCMatterportLiveOwnedFolder folderPath = (
 local rootPath = (dotNetClass "System.IO.Path").GetFullPath (GCMatterportRuntimeFolder + "model-viewer\\live\\")
 local fullPath = (dotNetClass "System.IO.Path").GetFullPath folderPath
 local directoryInfo = dotNetObject "System.IO.DirectoryInfo" fullPath
 if not directoryInfo.Exists do return false
 if (bit.and (directoryInfo.Attributes.value__ as integer) 1024) != 0 do return false
 local parentPath = directoryInfo.Parent.FullName + "\\"
 if (toLower parentPath != toLower rootPath) do return false
 if not (dotNetClass "System.Text.RegularExpressions.Regex").IsMatch directoryInfo.Name "^[a-f0-9]{32}$" do return false
 local marker = fullPath + "\\.gc-live-owned"
 if not doesFileExist marker do return false
 return matchPattern ((dotNetClass "System.IO.File").ReadAllText marker) pattern: "GC-Matterport-Live-v1|*"
)

fn GCMatterportLiveSweepSessions = (
 local rootPath = GCMatterportRuntimeFolder + "model-viewer\\live\\"
 local closedFolders = #()
 for folderPath in getDirectories (rootPath + "*") where GCMatterportLiveOwnedFolder folderPath do (
  local marker = (dotNetClass "System.IO.File").ReadAllText (folderPath + ".gc-live-owned")
  local markerParts = filterString marker "|"
  local ownerAlive = false
  if markerParts.count == 2 do try (
   local ownerProcess = (dotNetClass "System.Diagnostics.Process").GetProcessById (markerParts[2] as integer)
   ownerAlive = not ownerProcess.HasExited
   ownerProcess.Dispose()
  ) catch (ownerAlive = false)
  if not ownerAlive then (
   (dotNetClass "System.IO.Directory").Delete folderPath true
  ) else if (markerParts[2] == (((dotNetClass "System.Diagnostics.Process").GetCurrentProcess()).Id as string) and doesFileExist (folderPath + ".closed")) do append closedFolders folderPath
 )
 -- Keep at most the newest two closed sessions for in-flight browser reads.
 while closedFolders.count > 2 do (
  local oldestIndex = 1
  for itemIndex in 2 to closedFolders.count do (
   local candidate = dotNetObject "System.IO.FileInfo" (closedFolders[itemIndex] + ".closed")
   local oldest = dotNetObject "System.IO.FileInfo" (closedFolders[oldestIndex] + ".closed")
   if candidate.LastWriteTimeUtc.Ticks < oldest.LastWriteTimeUtc.Ticks do oldestIndex = itemIndex
  )
  if GCMatterportLiveOwnedFolder closedFolders[oldestIndex] do (dotNetClass "System.IO.Directory").Delete closedFolders[oldestIndex] true
  deleteItem closedFolders oldestIndex
 )
 return true
)

fn GCMatterportLivePrune sessionData stateRows previousRows = (
 if not GCMatterportLiveOwnedFolder sessionData.folderPath do return false
 local retained = (GCMatterportLiveStateJSON stateRows) + (GCMatterportLiveStateJSON previousRows)
 for filePath in getFiles (sessionData.folderPath + "textures\\*") do (
  local fileName = filenameFromPath filePath
  if ((dotNetClass "System.Text.RegularExpressions.Regex").IsMatch fileName "^[a-f0-9]{64}[.](png|jpg|jpeg|webp)$" and findString retained ("textures/" + fileName) == undefined) do deleteFile filePath
 )
 sessionData.textureCache = for cached in sessionData.textureCache where (cached.url != undefined and doesFileExist (sessionData.folderPath + substituteString cached.url "/" "\\")) collect cached
 for filePath in getFiles (sessionData.folderPath + "updates\\*.json") do (
  local oldRevision = try ((getFilenameFile filePath) as integer) catch (sessionData.revision)
  if oldRevision < sessionData.revision - 7 do deleteFile filePath
 )
 return true
)


fn GCMatterportLiveUpdate forceCheck: false = (
 local sessionData = GCMatterportLiveSession
 if sessionData == undefined do throw "Open Live Preview first."
 if (_rExportGCMatterportGLBConverter.isRenderingAO or _rExportGCMatterportGLBConverter.isExportingLODs or GCMatterportLiveBusy) do return sessionData.revision
 GCMatterportLiveBusy = true
 local failureReason = undefined
 try (
  if GCMatterportLiveGeometryDirty do (
   if GCMatterportLiveGeometrySignature sessionData.nodeRef != sessionData.geometrySignature do throw "Geometry, UVs or face Material IDs changed. Reopen Live Preview."
   GCMatterportLiveGeometryDirty = false
  )
  local stateRows = GCMatterportLiveCapture sessionData forceCheck: forceCheck
  local delta = GCMatterportLiveStateJSON stateRows previousRows: sessionData.lastState
  if delta != "{}" do (
   local revision = sessionData.revision + 1
   local tickText = trimRight (((dotNetClass "System.DateTime").UtcNow.Ticks) as string) "L"
   local header = "{\"session\":" + (GCMatterportLiveJSONQuote sessionData.token) + ",\"timestamp\":" + (GCMatterportLiveJSONQuote (tickText + "-" + (revision as string))) + ",\"revision\":" + (revision as string)
   GCMatterportLiveWrite (sessionData.folderPath + "updates\\" + (revision as string) + ".json") (header + ",\"changes\":" + delta + "}")
   GCMatterportLivePublishAtomic (sessionData.folderPath + "state.json") (header + ",\"materials\":" + (GCMatterportLiveStateJSON stateRows) + "}")
   GCMatterportLivePublishAtomic (sessionData.folderPath + "manifest.json") (header + "}")
   local previousRows = sessionData.lastState
   sessionData.lastState = stateRows
   sessionData.revision = revision
   GCMatterportLivePrune sessionData stateRows previousRows
  )
 ) catch (failureReason = getCurrentException() as string)
 GCMatterportLiveBusy = false
 if failureReason != undefined do throw failureReason
 return sessionData.revision
)

fn GCMatterportLiveObserve = (
 if GCMatterportLiveSession == undefined or GCMatterportLiveBusy or _rExportGCMatterportGLBConverter.isRenderingAO or _rExportGCMatterportGLBConverter.isExportingLODs do return undefined
 if GCMatterportLiveGeometryDirty do (
  if GCMatterportLiveGeometrySignature GCMatterportLiveSession.nodeRef != GCMatterportLiveSession.geometrySignature do throw "Geometry or UVs changed. Reopen Live Preview."
  GCMatterportLiveGeometryDirty = false
 )
 local observed = GCMatterportLiveStateJSON (GCMatterportLiveCapture GCMatterportLiveSession stageTextures: false)
 if observed != GCMatterportLiveObserved then (
  GCMatterportLiveObserved = observed
  GCMatterportLivePendingAt = timeStamp()
 ) else if (GCMatterportLivePendingAt != undefined and timeStamp() - GCMatterportLivePendingAt >= 200) do (
  GCMatterportLiveUpdate()
  GCMatterportLivePendingAt = undefined
 )
 return GCMatterportLiveSession.revision
)

fn GCMatterportLiveStop = (
 try (GCMatterportLiveRollout.tmrLive.active = false) catch()
 deleteAllChangeHandlers id: #GCMatterportLiveGeometry
 if (GCMatterportLiveSession != undefined and GCMatterportLiveOwnedFolder GCMatterportLiveSession.folderPath) do (
  GCMatterportLiveWrite (GCMatterportLiveSession.folderPath + ".closed") "closed"
  GCMatterportLivePublishAtomic (GCMatterportLiveSession.folderPath + "manifest.json") ("{\"session\":" + (GCMatterportLiveJSONQuote GCMatterportLiveSession.token) + ",\"closed\":true}")
 )
 GCMatterportLiveSession = undefined
 GCMatterportLiveObserved = undefined
 GCMatterportLivePendingAt = undefined
 GCMatterportLiveBusy = false
 GCMatterportLiveSweepSessions()
 return true
)

fn GCMatterportLiveOpen layerName openBrowser: true = (
 if (_rExportGCMatterportGLBConverter.isRenderingAO or _rExportGCMatterportGLBConverter.isExportingLODs or GCMatterportLiveBusy) do throw "Another render/export/preview operation is active."
 GCMatterportLiveStop()
 GCMatterportEnsureViewerInstalled()
 GCMatterportLiveSweepSessions()
 local entries = GCMatterportLiveEntries layerName
 local sourceNode = entries[1].nodeRef
 local token = ((dotNetClass "System.Guid").NewGuid()).ToString("N")
 local viewerFolder = GCMatterportRuntimeFolder + "model-viewer\\"
 local folderPath = viewerFolder + "live\\" + token + "\\"
 for relative in #("geometry\\", "textures\\", "updates\\") do makeDir (folderPath + relative) all: true
 GCMatterportLiveWrite (folderPath + ".gc-live-owned") ("GC-Matterport-Live-v1|" + (((dotNetClass "System.Diagnostics.Process").GetCurrentProcess()).Id as string))
 GCMatterportLiveWrite (folderPath + ".closed") "pending"
 local whiteImage = dotNetObject "System.Drawing.Bitmap" 1 1
 whiteImage.SetPixel 0 0 ((dotNetClass "System.Drawing.Color").FromArgb 255 255 255 255)
 whiteImage.Save (folderPath + "white.png") (dotNetClass "System.Drawing.Imaging.ImageFormat").Png
 whiteImage.Dispose()
 local sessionData = GCMatterportLiveSessionData token: token layerName: layerName nodeRef: sourceNode geometrySignature: (GCMatterportLiveGeometrySignature sourceNode) materialIDs: (for entry in entries collect entry.materialID) folderPath: folderPath materialLayout: (sourceNode.material.materialIDList as string) textureCache: #() lastState: #()
 -- Validate and stage materials before the one-time geometry export.
 GCMatterportLiveCapture sessionData forceCheck: true
 local timerActive = _rExportGCMatterportGLBConverter.tmrLODRefresh.active
 local originalLODs = _rExportGCMatterportGLBConverter.lbxLODs.selection
 local failureReason = undefined
 _rExportGCMatterportGLBConverter.tmrLODRefresh.active = false
 _rExportGCMatterportGLBConverter.isExportingLODs = true
 try (
  local geometryGLTF = GCMatterportLiveExportGeometry sessionData entries (folderPath + "geometry\\")
  GCMatterportRunAOProcess (GCMatterportRuntimeFolder + "gltfpack.exe") ("-noq -km -kn -i \"" + geometryGLTF + "\" -o \"" + folderPath + "geometry/scene.glb\"") GCMatterportRuntimeFolder operationLabel: "Live Preview initial geometry"
 ) catch (failureReason = getCurrentException() as string)
 _rExportGCMatterportGLBConverter.isExportingLODs = false
 _rExportGCMatterportGLBConverter.lbxLODs.selection = originalLODs
 _rExportGCMatterportGLBConverter.tmrLODRefresh.active = timerActive
 if failureReason != undefined do throw failureReason
 if GCMatterportLiveOwnedFolder folderPath do (
  for filePath in getFiles (folderPath + "geometry\\*") where (filenameFromPath filePath != "scene.glb") do deleteFile filePath
  for directoryPath in getDirectories (folderPath + "geometry\\*") do (dotNetClass "System.IO.Directory").Delete directoryPath true
  deleteFile (folderPath + "white.png")
 )
 deleteFile (folderPath + ".closed")
 GCMatterportLiveSession = sessionData
 GCMatterportLiveGeometryDirty = false
 GCMatterportLiveUpdate forceCheck: true
 GCMatterportLiveObserved = GCMatterportLiveStateJSON (GCMatterportLiveCapture sessionData stageTextures: false)
 GCMatterportLivePendingAt = undefined
 when geometry sourceNode changes id: #GCMatterportLiveGeometry do (GCMatterportLiveGeometryDirty = true)
 when topology sourceNode changes id: #GCMatterportLiveGeometry do (GCMatterportLiveGeometryDirty = true)
 when transform sourceNode changes id: #GCMatterportLiveGeometry do (GCMatterportLiveGeometryDirty = true)
 try (GCMatterportLiveRollout.tmrLive.active = true) catch()
 local portNumber = GCMatterportEnsurePreviewServer viewerFolder
 local previewURL = "http://127.0.0.1:" + (portNumber as string) + "/?live=" + token + "&title=" + ((dotNetClass "System.Uri").EscapeDataString layerName)
 if openBrowser do ShellLaunch previewURL ""
 return previewURL
)

rollout GCMatterportLiveRollout "Live Preview Materials" (
 label lblLiveInfo "Select one LOD and open it.\nMaterial edits sync automatically." width: 320 height: 28
 button btnOpenLive "Open Live Preview" width: 156 across: 2
 button btnUpdateLive "Refresh Textures" width: 156
 label lblLiveStatus "Geometry loads once.\nKeep this window open to sync." width: 320 height: 28
 timer tmrLive interval: 50 active: false
 on btnOpenLive pressed do (
  try (
   local rows = _rExportGCMatterportGLBConverter.lbxLODs.selection as array
   local allLODs = GCMatterportGetData()
   if rows.count != 1 do throw "Select exactly one LOD."
   GCMatterportLiveOpen allLODs[rows[1]].layerName
   lblLiveStatus.text = "Auto sync active. Edit glTF materials in the Material Editor."
  ) catch (messageBox (getCurrentException() as string) title: "Google Live Preview")
 )
 on tmrLive tick do (
  if GCMatterportLiveSession != undefined do (
   try (
    local revision = GCMatterportLiveObserve()
    lblLiveStatus.text = "Auto sync active - revision " + revision as string
   ) catch (lblLiveStatus.text = getCurrentException() as string)
  )
 )
 on btnUpdateLive pressed do (
  try (GCMatterportLiveUpdate forceCheck: true) catch (messageBox (getCurrentException() as string) title: "Refresh Textures")
 )
 on GCMatterportLiveRollout open do setDialogSize GCMatterportLiveRollout [344, (lblLiveStatus.pos.y + lblLiveStatus.height + 8)]
 on GCMatterportLiveRollout close do GCMatterportLiveStop()
)


struct GCMatterportAOClipboardEntry (
	materialID, useCoronaAO, passes, sizeCM, useVRayDenoiser, customResolution, manualResolution
)
global GCMatterportAOClipboard

rcmenu GCMatterportLODContextMenu (
	menuItem previewLODItem "Preview in Google Model Viewer"
	menuItem previewPCLODItem "Preview in PlayCanvas Viewer"
	menuItem liveMaterialsItem "Live Preview Materials..."
	separator previewSeparator
	menuItem copyPropertiesItem "Copy Material Properties"
	menuItem pastePropertiesItem "Paste Material Properties"
	separator propertiesSeparator
	menuItem deleteLODsItem "Delete LODs"
	on GCMatterportLODContextMenu open do (
		previewLODItem.enabled = _rExportGCMatterportGLBConverter.canPreviewLOD()
		previewPCLODItem.enabled = previewLODItem.enabled
		copyPropertiesItem.enabled = _rExportGCMatterportGLBConverter.canCopyLODProperties()
		pastePropertiesItem.enabled = _rExportGCMatterportGLBConverter.canPasteLODProperties()
	)
	on previewLODItem picked do _rExportGCMatterportGLBConverter.previewSelectedLOD()
	on previewPCLODItem picked do _rExportGCMatterportGLBConverter.previewSelectedLOD usePlayCanvas: true
	on liveMaterialsItem picked do (try (destroyDialog GCMatterportLiveRollout) catch(); createDialog GCMatterportLiveRollout 344 110)
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

	fn assignDefaultMaterials lodEntries materialCount: 6 = (
        if (classOf materialCount != Integer or materialCount < 1 or materialCount > 1000) do throw "Material ID count must be an integer from 1 to 1000."
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
							local subMaterialNames = for slotIndex in 1 to materialCount collect ("ID" + (slotIndex as string) + "_" + lodSuffix)
							local subMaterials = for subMaterialName in subMaterialNames collect (glTFMaterial name: subMaterialName)
							local lodMaterial = MultiMaterial numsubs: materialCount name: lodEntry.layerName
							lodMaterial.materialIDList = for materialID in 1 to materialCount collect materialID
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

	on btnCreateLayers pressed do (
		if (createLODLayers()) do (
			_rBoilerplateGCMatterportGLBConverter.open = false
			_rExportGCMatterportGLBConverter.open = true
		)
	)
)

rollout _rExportGCMatterportGLBConverter "Exporter" category: 2 (	
	label lblCompleteStatus "Complete status: [GLB] [AO]" align: #left width: 326 toolTip: "GLB: exported file exists. AO: all enabled material IDs have AO maps. Check: one object with valid glTF materials."
	group "LODs" (
		multiListbox lbxLODs "" items: #() height: 4 offset: [-2, 0] width: 326
		
		button btnRefresList "Refresh List" width: 150 across: 2
		button btnAddToLOD "Add to LOD" width: 150
		button btnAssignDefaultMaterials "Assign Default Materials" width: 232 align: #left across: 2
        spinner spnDefaultMaterialCount "IDs cnt.: " range: [1,256,6] offset: [0, 2] type: #integer fieldWidth: 42 width: 86 align: #right toolTip: "Number of glTF material IDs to create (1-1000)."
	)
	
	group "Materials" (
		multiListbox lbxMaterials "" items: #() height: 6 offset: [-2, 0] width: 326
		button btnTransferUV "Transfer All IDs: Channel 1 -> 2" width: 310 align: #center
	)

	group "Corona AO Settings" (
		checkbox cbxUseCoronaAO "Use Corona AO" width: 115 align: #left across: 2 checked: true enabled: false
		label lblAOSelection "Select one material." align: #right width: 188
		checkbox cbxAOOverride "Override Resolution" width: 125 enabled: false across: 3 align: #left
		dropdownlist ddlAOResolution "" items: #("512", "1024", "2048", "4096") selection: 2 width: 64 enabled: false align: #left
		label lblDefaultAOResolution "" width: 104 align: #left visible: false
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
			local defaultResolution = GCMatterportAutomaticAOResolution materialEntry.layerName
			lblDefaultAOResolution.text = "Default: " + (if defaultResolution == undefined then "N/A" else defaultResolution as string)
			lblDefaultAOResolution.visible = cbxAOOverride.checked
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
			lblDefaultAOResolution.visible = false
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
					GCMatterportMaterialContextEntry = materialEntries[rowIndex]
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
		local controlStates = for uiControl in #(lbxLODs, lbxMaterials, btnRefresList, btnAddToLOD, btnAssignDefaultMaterials, spnDefaultMaterialCount, btnTransferUV, cbxUseCoronaAO, cbxAOOverride, ddlAOResolution, spnAOPasses, spnAOSize, cbxAODenoise) collect #(uiControl, uiControl.enabled)
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
		local controlStates = for uiControl in #(lbxLODs, lbxMaterials, btnRefresList, btnAddToLOD, btnAssignDefaultMaterials, spnDefaultMaterialCount, btnTransferUV, cbxUseCoronaAO, cbxAOOverride, ddlAOResolution, spnAOPasses, spnAOSize, cbxAODenoise) collect #(uiControl, uiControl.enabled)
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
		local allCompleted = (completedCount == exportJobs.count and reportLines.count == 0)
		local summaryText = if allCompleted then "Batch export completed." else "Batch export stopped before completion."
		summaryText += "\nWebGL GLB exported: " + (completedCount as string) + " of " + (exportJobs.count as string) + "."
		if (reportLines.count > 0) do (
			summaryText += "\nFailed or cancelled: " + (reportLines.count as string) + "."
			local notAttemptedCount = amax 0 (exportJobs.count - completedCount - reportLines.count)
			if (notAttemptedCount > 0) do summaryText += " Not attempted: " + (notAttemptedCount as string) + "."
		)
		if (completedCount > 0) do summaryText += "\n\nOutput: " + exportFolder
		for reportLine in reportLines do summaryText += "\n" + reportLine
		if (completedCount > 0) then (
			if (queryBox (summaryText + "\n\nOpen this folder?") title: "Batch Export LODs" beep: false defaultButton: 2) do (
				try (
					if (not doesDirectoryExist exportFolder) do throw "The export folder no longer exists."
					ShellLaunch "explorer.exe" ("\"" + (trimRight exportFolder "\\") + "\"")
				) catch (messageBox ("Could not open the export folder.\n" + (getCurrentException() as string)) title: "Batch Export LODs" beep: false)
			)
		) else (
			messageBox summaryText title: "Batch Export LODs" beep: false
		)
		return allCompleted
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

	fn previewSelectedLOD usePlayCanvas: false = (
		if (not canPreviewLOD()) do return false
		local rowIndex = (lbxLODs.selection as array)[1]
		try (
			if (usePlayCanvas) then GCMatterportPreviewPCLOD lodEntries[rowIndex].layerName else GCMatterportPreviewLOD lodEntries[rowIndex].layerName
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
		return _rBoilerplateGCMatterportGLBConverter.assignDefaultMaterials selectedEntries materialCount: spnDefaultMaterialCount.value
	)

	on btnAssignDefaultMaterials pressed do assignSelectedLODMaterials()

	on btnAddToLOD pressed do addSelectedObjectToLOD()


	fn transferAllMaterialUVs showSummary: true = (
		if (isRenderingAO or isExportingLODs) do return false
		local selectedRows = lbxLODs.selection as array
		if (selectedRows.count == 0) do (
			messageBox "Select one or more target LODs." title: "Transfer All IDs" beep: false
			return false
		)
		local targetNodes = #()
		for rowIndex in selectedRows do (
			if (rowIndex < 1 or rowIndex > lodEntries.count) do throw "The LOD list is out of date. Refresh it."
			local lodLayer = LayerManager.getLayerFromName lodEntries[rowIndex].layerName
			local layerNodes = #()
			if (lodLayer != undefined) do lodLayer.nodes &layerNodes
			if (layerNodes.count != 1 or not isValidNode layerNodes[1]) do (
				messageBox "Each selected LOD must contain exactly one object." title: "Transfer All IDs" beep: false
				return false
			)
			appendIfUnique targetNodes layerNodes[1]
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
		undo "Transfer UV 1 to 2 and pack all material IDs" on (
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
					for faceIndex in 1 to sourceMesh.numfaces do appendIfUnique validIDs (getFaceMatID sourceMesh faceIndex)
					sort validIDs
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
					unwrapModifier.unwrap2.setAlwaysEdit false
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
					if (previousSubObjectLevel != undefined) then subObjectLevel = previousSubObjectLevel
					else if (subObjectLevel != undefined) do subObjectLevel = 0
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
		local resultMessage = "UV channel 1 copied to 2, all IDs packed, and converted to Editable Poly on " + (completedCount as string) + " object(s)."
		for reportLine in reportLines do resultMessage += "\n" + reportLine
		if showSummary do messageBox resultMessage title: "Transfer All IDs" beep: false
		return (reportLines.count == 0)
	)

	on btnTransferUV pressed do (
		if (queryBox "Transfer UV Channel 1 to Channel 2 for all material IDs?\n\nThis operation may take some time. Please wait until it finishes and do not interact with 3ds Max." title: "Transfer All IDs" beep: false defaultButton: 2) do transferAllMaterialUVs()
	)

	fn openMaterialInSlate rowIndex = (
		if (rowIndex < 1 or rowIndex > materialEntries.count) do (
			refreshMaterials()
			messageBox "This material row is out of date. Select it again." title: "Materials" beep: false
			return false
		)
		local clickedEntry = materialEntries[rowIndex]
		if (clickedEntry.slotIndex < 1 or clickedEntry.materialRef == undefined) do (messageBox clickedEntry.displayText title: "Materials" beep: false; return false)
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

	on btnRefresList pressed do (GCMatterportGeometrySummaryCache = #(); refreshLODs())
	on tmrLODRefresh tick do (
		try (
			if (not syncSceneSelection()) do refreshLODs()
		) catch (
			tmrLODRefresh.active = false
			format "LOD list auto-refresh stopped: %\n" (getCurrentException())
		)
	)

	on _rExportGCMatterportGLBConverter open do (
		lblCompleteStatus.text = "Complete status: [GLB] [AO] [" + (dotNetClass "System.Char").ConvertFromUtf32 10003 + "]"
		-- Spinner.pos is its arrow position, not the start of its caption.
		local passesPosition = spnAOPasses.pos
		spnAOSize.pos = passesPosition + [113, 0]
		cbxAODenoise.pos = [225, passesPosition.y]
		ddlAOResolution.pos = cbxAOOverride.pos + [127, 0]
		lblDefaultAOResolution.pos = ddlAOResolution.pos + [70, 3]
		previousSceneSelection = undefined
		syncSceneSelection()
		tmrLODRefresh.active = true
	)

	on _rExportGCMatterportGLBConverter close do (
		if GCMatterportLiveRollout != undefined do (
			try (destroyDialog GCMatterportLiveRollout) catch (format "Live Preview window cleanup: %\n" (getCurrentException()))
		)
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
	hyperlink lblCopy "" address: "https://3dground.net" align: #center
	
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
				local updateFiles = #("denoise.bat", "vdenoise.xml", "jpegoptim.exe", "gltfpack.exe", "gltfpack_webgl.bat", "model-viewer.zip", "playcanvas-viewer.zip", "GC-Matterport-GLB-Converter.ms")
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
		
		
        local infoFilePath = (dotNetClass "System.IO.Path").GetFullPath (GCMatterportRuntimeFolder + "GC-Matterport-GLB-Converter.ms")
        local i = getScriptInfo infoFilePath
		
        lblName.caption = i.name
        lblAuthor.caption = i.author
        lblVer.caption = i.version
        -- A hyperlink requires a web URI, never an empty value or a local file path.
        local developerAddress = trimLeft (trimRight i.developer " \t\r\n") " \t\r\n"
        local isWebAddress = (dotNetClass "System.Uri").IsWellFormedUriString developerAddress (dotNetClass "System.UriKind").Absolute
        if isWebAddress do (
            local developerURI = dotNetObject "System.Uri" developerAddress (dotNetClass "System.UriKind").Absolute
            isWebAddress = ((findItem #("http", "https") (developerURI.Scheme as string)) > 0)
        )
        lblCopy.enabled = isWebAddress
        if isWebAddress then (
            lblCopy.address = developerAddress
            lblCopy.caption = developerAddress
        ) else (
            lblCopy.caption = "Developer link unavailable"
            format "About: INFO/DEV must be an absolute HTTP(S) URL in %.\n" infoFilePath
        )
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

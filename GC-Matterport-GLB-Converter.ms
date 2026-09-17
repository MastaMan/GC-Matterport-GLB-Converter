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
global floaterGCMatterportGLBConverter = newRolloutFloater "Matterport Converter" 360 500

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
		GCMatterportLODEntry layerName: sceneLayerName displayText: (displayPrefix + sceneLayerName) objectCount: layerNodes.count isReady: isLayerReady
	)
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


fn GCMatterportFormatMaterialRow materialEntry = (
	local aoOptions = GCMatterportGetEffectiveAOOptions materialEntry
	local propertyKey = GCMatterportAOKey materialEntry
	local isEnabled = GCMatterportSceneProperties.getValue (propertyKey + "enabled") true
	local statusGlyph = (dotNetClass "System.Char").ConvertFromUtf32 (if isEnabled then 10003 else 9675)
	local rowText = "[" + statusGlyph + "] " + (materialEntry.materialID as string) + ": " + materialEntry.materialRef.name
	local differences = #()
	if (aoOptions != undefined) do (
		if (aoOptions.resolution != GCMatterportAutomaticAOResolution materialEntry.layerName) do append differences (aoOptions.resolution as string)
		if (aoOptions.passes != 15) do append differences ("Passes " + (aoOptions.passes as string))
		if (abs (aoOptions.sizeCM - 5.0) > 0.0001) do (
			local sizeCaption = trimRight (trimRight (substituteString (formattedPrint aoOptions.sizeCM format: ".4f") "," ".") "0") "."
			append differences ("Size " + sizeCaption + " cm")
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

rcmenu GCMatterportLODContextMenu (
	menuItem deleteLODsItem "Delete LODs"
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

	local refreshMaterials
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
	
	timer tmrRestart "" active: false interval: 300
	    
	fn downloadFile url dl = (
		deleteFile dl
		w = dotNetObject "System.Net.WebClient"			
		try(
			spm = dotNetClass "System.Net.ServicePointManager"
			spm.SecurityProtocol = spm.SecurityProtocol.TLS12				
			w.DownloadFile (url + "?time=" + timestamp() as string) dl				
		) catch(
			return false
		)
		
		return true
	)
	
	fn bgUpdate = (
		local url = "https://raw.githubusercontent.com/MastaArt/GC-Matterport-GLB-Converter/main/"
		local main = url + "GC-Matterport-GLB-Converter.ms"
		
		local additionalFiles = #(
			"INSTALL.mcr", 
			"jpegoptim.exe", 
			"convert.exe",
			"model-viewer.zip",
			"7za.exe",
			"extract.bat",
			"gltfpack.exe",
			"gltfpack.bat",
			"gltfpack_webgl.bat",
			"denoise.bat",
			"vdenoise.xml",
			"xnormal.bat",
			"xnormal.xml"
		)
		
		local this = getThisScriptFileName()
		local p = getFileNamePath (getThisScriptFileName())
		local dl = this + ".tmp"
		local r = downloadFile main dl
		if(not r or not doesFileExist dl) do return print "Can't download updates!"
		local vn = getIniSetting dl "INFO" "VERSION"
		local vo = getIniSetting this "INFO" "VERSION"
		
		if(vn > vo) do (
			deleteFile this
			renameFile dl this
			
			for n in additionalFiles do (
				downloadFile (url + n) (p + n)
			)
			
			tmrRestart.active = true
		)
		
		deleteFile dl
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

Device info:emulator
Build info:emulator 6.0.0.129(DEVC00E129R4P11)
Fingerprint:42da6680a65ac409558e0f3ff051a757f4357dd93e9d50159c7316da241bbe5b
Timestamp:2026-01-25 02:22:22.183
Module name:com.example.nwpucampus
Version:1.0.0
VersionCode:1000000
PreInstalled:No
Foreground:Yes
Pid:8960
Uid:20020059
Process life time:346s
Process Memory(kB): 132608(Rss)
Device Memory(kB): Total 4025360, Free 1987144, Available 2646592
Page switch history:
  02:22:21.723 :enters foreground
Reason:TypeError
Error name:TypeError
Error message:@Component '@Component 'MapCanvas'[7]': Illegal variable value error with decorated variable @Prop 'onTap': failed validation: 'undefined, null, number, boolean, string, or Object but not function, not V2 @ObservedV2 / @Trace class, and makeObserved return value either, attempt to assign value type: 'function', value: 'undefined'!
Stacktrace:
    at varValueCheckFailed (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:2315:1)
    at checkIsSupportedValue (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:6488:1)
    at SynchedPropertyOneWayPU (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:6994:1)
    at SynchedPropertyObjectOneWayPU (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:7351:1)
    at MapCanvas entry (entry/src/main/ets/components/MapCanvas.ets:14:1)
    at anonymous entry (entry/src/main/ets/pages/Index.ets:556:7)
    at updateFunc (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:8720:1)
    at observeComponentCreation2 (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:8747:1)
    at initialRender entry (entry/src/main/ets/pages/Index.ets:576:23)
    at initialRenderView (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:8251:1)

HiLog:
01-25 02:22:20.592  8960  8960 I C02c11/APPSPAWN: AppSpawnChild id 28 flags:0xc
01-25 02:22:20.592  8960  8960 I C02c02/PARAM: ResetParamSecurityLabel Fd:18
01-25 02:22:20.593  8960  8960 I C02d33/HitraceOption: FilterAppTrace com.example.nwpucampus 8960
01-25 02:22:20.597  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /system/app/ArkWebCoreLegacy to /mnt/sandbox/100/com.example.nwpucampus/system/app/ArkWebCoreLegacy
01-25 02:22:20.597  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /system/data to /mnt/sandbox/100/com.example.nwpucampus/system/data
01-25 02:22:20.598  8960  8960 W C02c11/APPSPAWN: mount /system/bin time 10000 us
01-25 02:22:20.598  8960  8960 I C02c11/APPSPAWN: file /mnt/sandbox/100/com.example.nwpucampus/data/service/el1/public/hosts_user/hosts already exist
01-25 02:22:20.598  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /system/etc/hosts to /mnt/sandbox/100/com.example.nwpucampus/data/service/el1/public/hosts_user/hosts
01-25 02:22:20.598  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /vendor/lib to /mnt/sandbox/100/com.example.nwpucampus/vendor/lib
01-25 02:22:20.598  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /vendor/etc/hiai to /mnt/sandbox/100/com.example.nwpucampus/vendor/etc/hiai
01-25 02:22:20.598  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /data/data/hiai to /mnt/sandbox/100/com.example.nwpucampus/data/data/hiai
01-25 02:22:20.600  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /data/app/el1/public/aot_compiler/ark_cache/com.example.nwpucampus to /mnt/sandbox/100/com.example.nwpucampus/data/storage/ark-cache
01-25 02:22:20.600  8960  8960 W C02c11/APPSPAWN: check dir /data/app/el1/public/aot_compiler/ark_cache/com.example.nwpucampus failed,strerror:No such file or directory
01-25 02:22:20.600  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /data/app/el1/public/shader_cache/cloud/com.example.nwpucampus to /mnt/sandbox/100/com.example.nwpucampus/data/storage/shader_cache/cloud
01-25 02:22:20.600  8960  8960 W C02c11/APPSPAWN: check dir /data/app/el1/public/shader_cache/cloud/com.example.nwpucampus failed,strerror:No such file or directory
01-25 02:22:20.601  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /data/service/el1/public/themes/100/a/app to /mnt/sandbox/100/com.example.nwpucampus/data/themes/a/app
01-25 02:22:20.601  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /data/service/el1/public/themes/100/b/app to /mnt/sandbox/100/com.example.nwpucampus/data/themes/b/app
01-25 02:22:20.602  8960  8960 W C02c11/APPSPAWN: errno:13 private mount to /mnt/sandbox/100/com.example.nwpucampus/data/service/el0/public/for-all-app '524288' failed
01-25 02:22:20.603  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /chip_prod/etc/passthrough to /mnt/sandbox/100/com.example.nwpucampus/chip_prod/etc/passthrough
01-25 02:22:20.603  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /vendor/etc/vulkan to /mnt/sandbox/100/com.example.nwpucampus/vendor/etc/vulkan
01-25 02:22:20.603  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /mnt/hmdfs/100/cloud/data/com.example.nwpucampus to /mnt/sandbox/100/com.example.nwpucampus/data/storage/el2/cloud
01-25 02:22:20.603  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /vendor/etc/silk to /mnt/sandbox/100/com.example.nwpucampus/vendor/etc/silk
01-25 02:22:20.604  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /system/asan/lib64 to /mnt/sandbox/100/com.example.nwpucampus/system/asan/lib64
01-25 02:22:20.604  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /vendor/asan/lib64 to /mnt/sandbox/100/com.example.nwpucampus/vendor/asan/lib64
01-25 02:22:20.604  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /chip_prod/lib64/passthrough to /mnt/sandbox/100/com.example.nwpucampus/chip_prod/lib64/passthrough
01-25 02:22:20.604  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /data/app/el1/bundle/public/com.huawei.hmos.arkwebcorelegacy to /mnt/sandbox/100/com.example.nwpucampus/data/storage/el1/bundle/arkwebcorelegacy
01-25 02:22:20.604  8960  8960 W C02c11/APPSPAWN: check dir /data/app/el1/bundle/public/com.huawei.hmos.arkwebcorelegacy failed,strerror:No such file or directory
01-25 02:22:20.605  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /system/app/ohos.global.systemres to /mnt/sandbox/100/com.example.nwpucampus/data/global/systemResources
01-25 02:22:20.616  8960  8960 W C02c11/APPSPAWN: mount /mnt/sandbox/100/com.example.nwpucampus/mnt/storage/Users time 16000 us
01-25 02:22:20.637  8960  8960 W C02c11/APPSPAWN: mount /mnt/sandbox/100/com.example.nwpucampus/mnt/storage/external time 15000 us
01-25 02:22:20.647  8960  8960 W C02c11/APPSPAWN: mount /mnt/sandbox/100/com.example.nwpucampus/mnt/storage/userExternal time 15000 us
01-25 02:22:20.657  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /data/preload/app to /mnt/sandbox/100/com.example.nwpucampus/data/preload/app
01-25 02:22:20.657  8960  8960 W C02c11/APPSPAWN: errno:2 bind mount /mnt/data/ANCO_APP_DATA to /mnt/sandbox/100/com.example.nwpucampus/mnt/storage/ANCO_APP_DATA
01-25 02:22:20.666  8960  8960 W C02c11/APPSPAWN: mount /mnt/sandbox/100/com.example.nwpucampus/mnt/storage/ANCO_APP_DATA time 16000 us
01-25 02:22:20.669  8960  8960 E C02c11/APPSPAWN: [sandbox_dec.c:179]open dec file fail.
01-25 02:22:20.683  8960  8960 I C05a05/SecCompEnhanceClient: [RegisterCheckCallback]Register secComp: sessionId=4173293436, seqNum=******143.
01-25 02:22:20.686  8960  8960 I C02d0b/HICHECKER: hichecker param is empty.
01-25 02:22:20.687  8960  8960 I C04500/webview: SelectWebcoreBeforeProcessRun: SelectWebcoreBeforeProcessRun for app com.example.nwpucampus.
01-25 02:22:20.687  8960  8960 I C04500/webview: CalculateActiveWebEngineVersion: CalculateActiveWebEngineVersion, enforce EVERGREEN
01-25 02:22:20.687  8960  8960 I C02c11/APPSPAWN: ClearEnvAndReturnSuccess 4
01-25 02:22:20.688  8960  8960 I C01317/AppKit: [MAINTHD3066]mainthread start, pid:8960
01-25 02:22:20.699  8960  8960 I C01719/ffrt: 2:QueueMonitor:46 timeout:30000000 us
01-25 02:22:20.704  8960  8960 I C01317/AppKit: [MAINTHD425]attach
01-25 02:22:20.715  8960 12971 I C01317/AppKit: [MAINTHD819]ScheduleLaunchAbility called, ability EntryAbility, type is 1.
01-25 02:22:20.733  8960  8960 I C03900/ACE_UIContent: [69]AceForwardCompatibility [com.example.nwpucampus] force:1 newpipe:1
01-25 02:22:20.735  8960  8960 I C01317/AppKit: [MAINTHD250]NativeLibPath empty
01-25 02:22:20.741  8960  8960 I C01317/AppKit: [MAINTHD1751]SmartGC: process is start. enable warm startup SmartGC: 0
01-25 02:22:20.750  8960 12983 W C01719/ffrt: 3:operator():110 [-385668320] set priority warn ret[1] eno[0]
01-25 02:22:20.761  8960  8960 I C03f00/ArkCompiler: [ecmascript] asmint: 1, aot: 0, jit: 1, baseline jit: 0, bundle name: com.example.nwpucampus
01-25 02:22:20.768  8960  8960 I C03f00/ArkCompiler: [ecmascript] multi-thread check enabled: 0
01-25 02:22:20.769  8960  8960 I C03f00/ArkCompiler: [pgo] reset pgo profiler, pgo profiler is disabled
01-25 02:22:20.780  8960  8960 E C01707/CONCUR: [Interface] task 12984 apply qos failed, errno = 4
01-25 02:22:20.780  8960  8960 I C03301/LIBUV: init:5296
01-25 02:22:20.780  8960  8960 I C03301/LIBUV: init:5296, backend_fd:24
01-25 02:22:20.780  8960  8960 I C03301/LIBUV: open:5296, pipefd[0]:27
01-25 02:22:20.782  8960  8960 I C03f00/ArkCompiler: [ecmascript] can not find aot file
01-25 02:22:20.783  8960  8960 E C01305/Base: [zip_file.cpp(ExtractToBufByName:957)]GetEntry from pkgContextInfo.json err
01-25 02:22:20.812  8960  8960 I C03f00/ArkCompiler: StartServer, componentName = <private>
01-25 02:22:20.813  8960  8960 W C01321/JsRuntime: [CSM162]not Connected
01-25 02:22:20.813  8960  8960 I C03f00/ArkCompiler: [ecmascript] JSNApi::NotifyDebugMode, tid = 8960, debugApp = 1, isDebugMode = 0, instanceId = 0
01-25 02:22:20.825  8960  8960 I C03f00/ArkCompiler: [compiler] __jit_debug_register_code() is called.
01-25 02:22:20.826  8960  8960 I C03f00/ArkCompiler: [compiler] success to register stub.an to debugger.
01-25 02:22:20.847  8960 12993 I C02c03/PARAM_WATCHER: Add watcher keyPrefix persist.hdc.jdwp remoteWatcherId 50 success
01-25 02:22:20.853  8960 12982 I C01317/AppKit: [DRH395]File existed. dir: /data/storage/el2/base/cache/rawheap
01-25 02:22:20.859  8960  8960 W C01e00/ResourceManager: update userId, currentUserId_= 0, userId= 100
01-25 02:22:20.859  8960  8960 E C01e00/ResourceManager: LoadThemesRes failed, userId = 100, bundleName = com.example.nwpucampus
01-25 02:22:20.860  8960 12982 I C01317/AppKit: [DRH375]success to AclSetAccess, path: /data/storage/el2/base/cache/rawheap
01-25 02:22:20.867  8960 12995 W C01653/NativePreferences: LoadFromDisk: The settingXml /***/el1/***/i18*** load failed.
01-25 02:22:20.897  8960  8960 E C01301/CompatiblePolicyDeviceType: [calculateResourceType:81]deviceType is empty.
01-25 02:22:20.900  8960  8960 W C01301/Ability: [resource_config_helper183]invalid source:
01-25 02:22:20.900  8960  8960 W C01301/Ability: [resource_config_helper183]invalid source:
01-25 02:22:20.904  8960  8960 I C01317/AppKit: [application_cleaner94]ClearTempData
01-25 02:22:20.905  8960  8960 I C02d06/XCollie: Application is in starting period.
01-25 02:22:20.961  8960  8960 I C01317/AppKit: [js_ability_stage190]AbilityStage::LoadModule
01-25 02:22:20.961  8960  8960 W C01317/AppKit: [js_ability_stage935]null stage
01-25 02:22:20.961  8960  8960 W C01317/AppKit: [js_ability_stage233]Not found AbilityStage.js
01-25 02:22:20.966  8960  8960 I C01332/UIAbility: [JUA348]called
01-25 02:22:20.967  8960  8960 I C03f00/ArkCompiler: [ecmascript] start to execute module buffer with secure memory: /data/storage/el1/bundle/entry/ets/entryability/EntryAbility.abc
01-25 02:22:20.967  8960 12985 I C03f00/ArkCompiler: [pgo] will save profiler to file /data/storage/ark-profile/rt_entry.ap
01-25 02:22:20.968  8960  8960 E C03f00/ArkCompiler: [common] Can not open xpm proc file, do not check secure memory anymore.
01-25 02:22:20.981  8960  8960 E C01707/CONCUR: [Interface] task 12985 apply qos failed, errno = 4
01-25 02:22:20.996  8960  8960 E C01707/CONCUR: [Interface] task 12986 apply qos failed, errno = 4
01-25 02:22:21.012  8960  8960 E C01707/CONCUR: [Interface] task 12987 apply qos failed, errno = 4
01-25 02:22:21.043  8960  8960 E C01707/CONCUR: [Interface] task 12985 apply qos failed, errno = 4
01-25 02:22:21.113  8960  8960 E C01707/CONCUR: [Interface] task 12986 apply qos failed, errno = 4
01-25 02:22:21.133  8960  8960 E C01707/CONCUR: [Interface] task 12987 apply qos failed, errno = 4
01-25 02:22:21.140  8960  8960 I C01320/JsEnv: [js_environment290]timing: 172
01-25 02:22:21.141  8960  8960 I C01320/JSENV: Callee constructor is OK string
01-25 02:22:21.141  8960  8960 I C01320/JSENV: Ability::constructor callee is object [object Object]
01-25 02:22:21.242  8960  8960 I C01332/UIAbility: [JUA393]End
01-25 02:22:21.242  8960  8960 I C01332/UIAbility: [ui_ability_thread169]Lifecycle:Attach
01-25 02:22:21.282  8960  8960 I C02d06/XCollie: Application is in starting period.
01-25 02:22:21.284  8960  8960 I C01317/AppKit: [MAINTHD2710]called
01-25 02:22:21.285  8960  8960 I C03f00/ArkCompiler: [gc] app is not inBackground
01-25 02:22:21.304  8960  8960 E C01707/CONCUR: [Interface] task 12985 apply qos failed, errno = 4
01-25 02:22:21.313  8960  8960 E C01707/CONCUR: [Interface] task 12986 apply qos failed, errno = 4
01-25 02:22:21.355  8960  8960 E C01707/CONCUR: [Interface] task 12987 apply qos failed, errno = 4
01-25 02:22:21.359  8960 12971 I C01332/UIAbility: [ui_ability_thread317]name:EntryAbility,targeState:5,isNewWant:0
01-25 02:22:21.359  8960  8960 I C01332/UIAbility: [ui_ability_thread236]Lifecycle:name EntryAbility
01-25 02:22:21.360  8960  8960 I C04201/DMS: AddDisplayIdFromAms: abilityToken and display[0] has been added.
01-25 02:22:21.407  8960  8960 I C01332/UIAbility: [JUA1854]JsUIAbility call js, name: onCreate
01-25 02:22:21.415  8960  8960 I C01317/AppKit: [ohos_application1111]current 2, pre 0
01-25 02:22:21.415  8960  8960 W C01317/AppKit: [ohos_application1140]fontSize empty
01-25 02:22:21.415  8960  8960 I C01317/AppKit: [ohos_application1171]current 2, pre 0
01-25 02:22:21.415  8960  8960 W C01317/AppKit: [ohos_application1175]language empty
01-25 02:22:21.415  8960  8960 W C01317/AppKit: [ohos_application1194]language and locale empty
01-25 02:22:21.416  8960  8960 I C01317/AppKit: [ohos_application287]configuration_: {"0#const.build.characteristics":"phone","0#input.pointer.device":"true","0#ohos.app.fontSizeScale":"nonFollowSystem","0#ohos.application.densitydpi":"xxxldpi","0#ohos.application.direction":"vertical","0#ohos.application.displayid":"0","0#ohos.system.colorMode":"light","0#ohos.system.colorMode.isSetByApp":"isSetByApp","0#ohos.system.fontSizeScale":"1.0","0#ohos.system.fontWeightScale":"1.0","0#ohos.system.hour":"false","0#ohos.system.language":"zh-Hans-CN","0#ohos.system.locale":"zh-Hans-CN"}, config: {"0#ohos.system.colorMode":"light","0#ohos.system.colorMode.isSetByApp":"isSetByApp"}
01-25 02:22:21.416  8960  8960 E C04217/WMSAttribute: UpdateConfigurationSyncForAll: root is null
01-25 02:22:21.417  8960  8960 I C01332/UIAbility: [JUA1854]JsUIAbility call js, name: onConfigurationUpdated
01-25 02:22:21.417  8960  8960 I C01332/UIAbility: [JUA1899]end, name: onConfigurationUpdated, time: 0
01-25 02:22:21.417  8960  8960 I C01332/UIAbility: [JUA1854]JsUIAbility call js, name: onConfigurationUpdate
01-25 02:22:21.418  8960  8960 I C01332/UIAbility: [JUA1899]end, name: onConfigurationUpdate, time: 0
01-25 02:22:21.418  8960  8960 W C01317/AppKit: [js_ability_stage822]Not found AbilityStage.js
01-25 02:22:21.419  8960  8960 W C01317/AppKit: [js_ability_stage822]Not found AbilityStage.js
01-25 02:22:21.419  8960  8960 I C01317/AppKit: [ohos_application311]ignoreWindowContext size 0
01-25 02:22:21.419  8960  8960 E C04217/WMSAttribute: UpdateConfigurationForAll: root is null
01-25 02:22:21.419  8960  8960 I A00000/testTag: Ability onCreate
01-25 02:22:21.419  8960  8960 I C01332/UIAbility: [JUA1899]end, name: onCreate, time: 12
01-25 02:22:21.420  8960  8960 E C01332/UIAbility: [ui_ability_impl305]hasSaveData_: false
01-25 02:22:21.422  8960  8960 W C01332/UIAbility: [JUA1088]formatRegex: []
01-25 02:22:21.423  8960  8960 I C04202/WMSMain: Init: WindowScene with window session!
01-25 02:22:21.423  8960  8960 I C04202/WMSMain: Init: set isModuleAbilityHookEnd
01-25 02:22:21.424  8960  8960 I C04204/WMSScb: RS multi-instance enabled: 1, deviceType phone
01-25 02:22:21.426  8960  8960 I C01406/OHOS::RS: multi-instance, create RSUIContextManager, isMultiInstanceOpen_ 1
01-25 02:22:21.427  8960  8960 I C04204/WMSScb: InitRSUIDirector: Create RSUIDirector: RSUIDirector's RSUIContext [token: 38482906972161, tid: 8960], rsUIContext: RSUIContext is null
01-25 02:22:21.464  8960  8960 I C01406/OHOS::RS: RSLogManager init log flag: 0x0(0)
01-25 02:22:21.464  8960  8960 I C01406/OHOS::RS: RSFrameRateLinker::Create id: 38482906972160
01-25 02:22:21.465  8960  8960 I C04202/WMSMain: VsyncStation: id 38482906972162 created
01-25 02:22:21.465  8960  8960 I C04200/WindowSceneSessionImpl: WindowSceneSessionImpl: [WMSCom] Constructor nwpucampus0
01-25 02:22:21.465  8960  8960 E C04200/WMS: SetWindowType: permission denied!
01-25 02:22:21.465  8960  8960 I C0420a/WMSLife: Create: Window Create name:nwpucampus0, state:0, mode:0
01-25 02:22:21.474  8960  8960 I C0420a/WMSLife: Create: SetIsAbilityHookOff 0
01-25 02:22:21.474  8960  8960 W C0420a/WMSLife: IsWindowSessionInvalid: already destroyed or not created! id: 0 state_: 0
01-25 02:22:21.474  8960  8960 W C04200/WindowSceneSessionImpl: AdjustWindowAnimationFlag: session invalid!
01-25 02:22:21.476  8960  8960 I C04200/WindowSceneSessionImpl: Remove window flag WINDOW_FLAG_SHOW_WHEN_LOCKED
01-25 02:22:21.478  8960  8960 I C0420a/WMSLife: Connect: in
01-25 02:22:21.481  8960 12971 I C04208/WMSLayout: NotifyAppHookWindowInfoUpdated: in
01-25 02:22:21.491  8960 12971 I C04208/WMSLayout: SetAppHookWindowInfo: Id:0, preHookWindowInfo:[enableHookWindow: false, widthHookRatio: 1.000000], newHookWindowInfo:[enableHookWindow: false, widthHookRatio: 1.000000]
01-25 02:22:21.491  8960 12971 I C0421d/WMSRotation: SetCurrentRotation: currentRotation: 0
01-25 02:22:21.492  8960 12971 I C04208/WMSLayout: UpdateRect: id:0 name:nwpucampus0 rect:[0 0 0 0]->[0 0 1320 2856] reason:23 displayId:0
01-25 02:22:21.492  8960 12971 W C04208/WMSLayout: NotifySingleHandTransformChange: id:0, uiContent is nullptr
01-25 02:22:21.497  8960  8960 I C04208/WMSLayout: Connect: updateRect when connect.preRect:[0,0,1320,2856]rect:[0,0,1320,2856]
01-25 02:22:21.497  8960  8960 I C0420a/WMSLife: Connect: Window Connect [name:nwpucampus0, id:34, type:1], ret:0
01-25 02:22:21.509  8960  8960 I C04208/WMSLayout: NotifyWindowStatusChange: id:34, windowMode:1, windowStatus:1, lastWindowStatus:0, skipRedundantWindowStatusNotifications:0
01-25 02:22:21.511  8960  8960 I C04208/WMSLayout: SetConfigWindowLimitsVP: id:34, windowLimits:[0 0 0 0 0.000000 0.000000 1.000000 1]
01-25 02:22:21.513  8960  8960 I C04208/WMSLayout: GetSystemSizeLimits: px[6720,6720,1120,840], vp[1920,1920,320,240], configMax:1920, vpr:3.500000, winType:1
01-25 02:22:21.515  8960  8960 I C0421a/WMSLayoutPc: GetSupportedWindowModesConfiguration: winId: 34, windowModeSupportType: 15
01-25 02:22:21.545  8960  8960 I C0420f/WMSRecover: RegisterSessionRecoverCallbackFunc: persistentId=34
01-25 02:22:21.545  8960  8960 I C04217/WMSAttribute: UpdateDefaultStatusBarColor: win=34, appColor=light
01-25 02:22:21.545  8960  8960 I C04209/WMSImms: SetSpecificBarProperty: win [34 nwpucampus0] type 2108 1 ffffff ff000000 0 4
01-25 02:22:21.568  8960  8960 I C04200/WMS: IsMainHandlerAvailable: id:34, isAvailable:1
01-25 02:22:21.569  8960  8960 I C04200/WMS: IsMainHandlerAvailable: id:34, isAvailable:1
01-25 02:22:21.569  8960  8960 I C02800/InputManagerImpl: [][SetWindowInputEventConsumer:364] enter
01-25 02:22:21.580  8960  8960 I C02800/MMIClient: [][OnConnected:267] Connection to server succeeded, fd:39
01-25 02:22:21.580  8960  8960 I C02800/MMIClient: [][AddFdListener:166] Server was listening
01-25 02:22:21.580  8960  8960 I C02800/MMIClient: [][StartEventRunner:127] reuse current event handler, thread name:
01-25 02:22:21.580  8960  8960 I C02800/MMIClient: [][StartEventRunner:130] File fd is in listening
01-25 02:22:21.580  8960  8960 I C02800/InputManagerImpl: [][SetWindowInputEventConsumer] leave
01-25 02:22:21.580  8960  8960 I C0420c/WMSEvent: AddInputWindow: SetWindowInputEventConsumer success, wid:34
01-25 02:22:21.580  8960  8960 I C0420c/WMSEvent: LoadGameController: in
01-25 02:22:21.606  8960  8960 I C04732/GameController: [(RegisterEntryModule:24)]begin load gamecontroller_event
01-25 02:22:21.606  8960  8960 I C04732/GameController: [(StartInputToTouch:57)]Begin StartInputToTouch
01-25 02:22:21.607  8960  8960 I C0420c/WMSEvent: LoadGameController: dlopen GameController success
01-25 02:22:21.607  8960  8960 I C04217/WMSAttribute: ConnectServer: start connect
01-25 02:22:21.607  8960  8960 I C04217/WMSAttribute: ConnectServer: end connect
01-25 02:22:21.607  8960  8960 W C04217/WMSAttribute: RegisterGetWMSWindowListCallback: callback has registered
01-25 02:22:21.607  8960  8960 I C04217/WMSAttribute: RegisterGetWMSWindowListCallback: winId: 34
01-25 02:22:21.607  8960  8960 I C04217/WMSAttribute: UpdateColorMode: winId: 34, colorMode: light
01-25 02:22:21.608  8960  8960 I C04217/WMSAttribute: UpdateColorMode: winId: 34, colorMode: light, hasDarkRes: 1
01-25 02:22:21.608  8960  8960 I C0421c/WMSCompat: SetPcAppInpadSpecificSystemBarInvisible: isPcAppInpadSpecificSystemBarInvisible: 0
01-25 02:22:21.608  8960  8960 I C0421c/WMSCompat: SetPcAppInpadOrientationLandscape: isPcAppInpadOrientationLandscape: 0
01-25 02:22:21.608  8960  8960 E C04200/WMS: singleton_container.cpp GetSingleton: cant get OHOS::Rosen::WindowInfoReporter
01-25 02:22:21.613  8960 13027 I C04732/GameController: [(GetSelfBundleName:49)]The current bundleName [com.example.nwpucampus]. version [1.0.0]
01-25 02:22:21.614  8960 13027 I C04732/GameController: [(IsCommonApp:88)]The [com.example.nwpucampus] is a common app.
01-25 02:22:21.614  8960 13027 W C04732/GameController: [(ReadJsonFromFile:191)]realpath failed for [/data/service/el1/public/for-all-app/gamecontroller_server/game_support_key_mapping.json]
01-25 02:22:21.614  8960 13027 I C04732/GameController: [(DoAsyncTask:71)]The app does not support input-to-touch feature.
01-25 02:22:21.636  8960  8960 I C01332/UIAbility: [JUA1854]JsUIAbility call js, name: onWindowStageCreate
01-25 02:22:21.636  8960  8960 I A00000/testTag: Ability onWindowStageCreate
01-25 02:22:21.636  8960  8960 I C04200/JsWindowStage: LoadContent: [NAPI]
01-25 02:22:21.637  8960  8960 I C01332/UIAbility: [JUA1899]end, name: onWindowStageCreate, time: 1
01-25 02:22:21.638  8960  8960 I C01332/UIAbility: [JUA1854]JsUIAbility call js, name: onWillForeground
01-25 02:22:21.638  8960  8960 I C01332/UIAbility: [JUA1899]end, name: onWillForeground, time: 0
01-25 02:22:21.638  8960  8960 I C04202/WMSMain: GoForeground: reason: 4
01-25 02:22:21.638  8960  8960 I C0420a/WMSLife: Show: Window show [name: nwpucampus0, id: 34, type: 1], reason: 4, state:1, requestState:1
01-25 02:22:21.639  8960  8960 I C04208/WMSLayout: GetSystemSizeLimits: px[6720,6720,1120,840], vp[1920,1920,320,240], configMax:1920, vpr:3.500000, winType:1
01-25 02:22:21.640  8960  8960 I C04208/WMSLayout: UpdateNewSize: fullscreen or compatible mode could not update new size, Id: 34
01-25 02:22:21.640  8960  8960 I C04217/WMSAttribute: IsSystemDensityChanged: windowId: 34, lastDensity: -1.000000, currDensity: 3.500000
01-25 02:22:21.641  8960  8960 W C04200/WindowSessionImpl: UpdateViewportConfig: uiContent is null!
01-25 02:22:21.648  8960  8960 I C01332/UIAbility: [ui_ability_impl430]wnd call, AfterForeground
01-25 02:22:21.648  8960  8960 W C0420a/WMSLife: GetAttachStateSyncResult: lifecycleCallback is null
01-25 02:22:21.648  8960  8960 I C01406/OHOS::RS: RSFrameRateLinker::Create id: 38482906972161
01-25 02:22:21.659  8960 12970 I C04207/WMSFocus: UpdateFocusState: focus: 1, id: 34
01-25 02:22:21.660  8960 12970 I C04207/WMSFocus: NotifyHighlightChange: windowId: 34, isHighlight: 1,
01-25 02:22:21.668  8960 12971 W C04208/WMSLayout: NotifySingleHandTransformChange: id:34, uiContent is nullptr
01-25 02:22:21.721  8960  8960 I C01706/rtg_interface: rtg fOpen fail, errno = 2(No such file or directory)
01-25 02:22:21.721  8960  8960 I C01706/RsFrameReportExt: RsFrameReportExt:[LoadLibrary] load library success!
01-25 02:22:21.721  8960  8960 I C01706/RsFrameReportExt: RsFrameReportExt:[Init] dlopen libframe_ui_intf.so success!
01-25 02:22:21.721  8960  8960 E C01706/ueaClient-RmeCoreSched: [Init]: do not enabled!ret: -1
01-25 02:22:21.721  8960  8960 I C01706/ueaClient-FrameMsgMgr: [Init]:inited success!
01-25 02:22:21.722  8960  8960 I C01706/ueaClient-FrameUiIntf: [Init]:ret:1, inited:1
01-25 02:22:21.722  8960  8960 I C04217/WMSAttribute: InitWaterfallMode: winId: 34
01-25 02:22:21.722  8960  8960 I C04217/WMSAttribute: NotifyWaterfallModeChange: winId: 34, waterfall: 0, stat: 2
01-25 02:22:21.722  8960  8960 I C0420a/WMSLife: NotifyAfterDidForeground: reason: 4
01-25 02:22:21.722  8960  8960 I C04202/WMSMain: NotifyFreeMultiWindowModeResume: IsPcMode 0, isColdStart 1
01-25 02:22:21.722  8960  8960 I C0420a/WMSLife: Show: Window show success [name:nwpucampus0, id:34, type:1]
01-25 02:22:21.722  8960  8960 I C04208/WMSLayout: NotifyWindowStatusChange: id:34, windowMode:1, windowStatus:1, lastWindowStatus:1, skipRedundantWindowStatusNotifications:0
01-25 02:22:21.722  8960  8960 I C04208/WMSLayout: NotifyWindowStatusDidChange: Id:34, WindowMode:1, windowStatus:1, lastWindowStatus:0, listenerSize:0, rect:[0 0 1320 2856]
01-25 02:22:21.723  8960  8960 W C04201/DMS: OnDisplayInfoChange: data is not changed.
01-25 02:22:21.723  8960  8960 I C01332/UIAbility: [JUA1854]JsUIAbility call js, name: onForeground
01-25 02:22:21.723  8960  8960 I A00000/testTag: Ability onForeground
01-25 02:22:21.723  8960  8960 I C01332/UIAbility: [JUA1899]end, name: onForeground, time: 0
01-25 02:22:21.746  8960  8960 I C02d06/XCollie: Application is in starting period.
01-25 02:22:21.746  8960  8960 I C0420a/WMSLife: NotifyAfterDidForeground execute
01-25 02:22:21.746  8960  8960 I C01332/UIAbility: [JUA1854]JsUIAbility call js, name: onDidForeground
01-25 02:22:21.746  8960  8960 I C01332/UIAbility: [JUA1899]end, name: onDidForeground, time: 0
01-25 02:22:21.746  8960  8960 I C04202/WMSMain: GoResume: in
01-25 02:22:21.746  8960  8960 I C0420a/WMSLife: Resume: in, isColdStart: 1, isDidForeground: 0
01-25 02:22:21.746  8960  8960 I C0420a/WMSLife: NotifyAfterLifecycleResumed: in
01-25 02:22:21.746  8960  8960 I C0420a/WMSLife: SetUIContentInner: pages/Index, state:2, persistentId: 34
01-25 02:22:21.746  8960  8960 I C0420a/WMSLife: SetUIContentComplete: persistentId=34
01-25 02:22:21.747  8960  8960 I C03900/Ace: [(-1:-1:undefined)] CreateUIContent.
01-25 02:22:21.747  8960  8960 I C03934/AceUIEvent: [(-1:-1:undefined)] report ace loaded
01-25 02:22:21.748  8960  8960 I C04707/HaAceEngine: OnAceLoaded end
01-25 02:22:21.752  8960  8960 W C0391f/AceImage: [(-2:-1:undefined)] mkdir cache file path failed.
01-25 02:22:21.753  8960  8960 I C03900/Ace: [(-2:-1:undefined)] Create ace bg threads pool.
01-25 02:22:21.753  8960  8960 I C03900/Ace: [(-2:-1:undefined)] Init RenderService UniRender Type:0
01-25 02:22:21.754  8960  8960 I C03900/Ace: [(-2:-1:undefined)] [com.example.nwpucampus][entry][-1]: UIContent: apiCompatibleVersion: 40000010, apiTargetVersion: 60001021, and apiReleaseType: Beta1, useNewPipe: 1
01-25 02:22:21.756  8960 12982 W C04707/HaClient: =========Invalid Client=========
01-25 02:22:21.791  8960  8960 I C02c03/PARAM_WATCHER: Add watcher keyPrefix persist.sys.arkui.animationscale remoteWatcherId 50 success
01-25 02:22:21.804  8960  8960 E C03900/Ace: [(-2:-1:undefined)] ConfigXMLParserBase read system file failed
01-25 02:22:21.804  8960  8960 W C03900/Ace: [(-2:-1:undefined)] ArkUiFeatureParamManager failed to load xml file
01-25 02:22:21.805  8960  8960 E C03900/Ace: [(-2:-1:undefined)] ConfigXMLParserBase read system UI correction config file failed
01-25 02:22:21.805  8960  8960 W C03900/Ace: [(-2:-1:undefined)] ArkUiFeatureParamManager failed to load UI correction config file
01-25 02:22:21.808  8960  8960 I C03900/Ace: [(-2:-1:undefined)] SetLocale language tag: zh-CN, select language: zh-CN
01-25 02:22:21.809  8960  8960 I C03900/Ace: [(-2:-1:undefined)] [com.example.nwpucampus][entry][-1]: SetLanguage: zh, colorMode: light, deviceAccess: 1
01-25 02:22:21.809  8960  8960 I C03900/Ace: [(-2:-1:undefined)] [com.example.nwpucampus][entry][-1]: Initialize UIContent isModelJson:true
01-25 02:22:21.834  8960  8960 I C03922/AceNavigation: [(-2:-1:undefined)] subscribe hsp Update successfully
01-25 02:22:21.834  8960  8960 I C03900/Ace: [(100000:100000:scope)] SetHapPath, Use hap path to load resource
01-25 02:22:21.835  8960  8960 I C04217/WMSAttribute: RegisterWaterfallModeChangeListener: winId: 34
01-25 02:22:21.841  8960  8960 I C04200/WMS: GetSurfaceNode: name:nwpucampus0, id:34
01-25 02:22:21.841  8960  8960 I C04200/WMS: GetSurfaceNode: name:nwpucampus0, id:34
01-25 02:22:21.841  8960  8960 I C03900/Ace: [(100000:100000:scope)] SetRSSurfaceNode 38482906972162 with rs multi
01-25 02:22:21.851  8960  8960 W C03900/Ace: [(100000:100000:scope)] Invalid config:zh_CN-long-notround-vertical-light-phone-xxxhdpi
01-25 02:22:21.856  8960  8960 I C01406/OHOS::RS: RSSurfaceNode::SetAbilityState, surfaceNodeId:[38482906972162], ability state: background
01-25 02:22:21.860  8960  8960 I C03900/Ace: [(100000:100000:scope)] set translateManager to pipeline, instanceId:100000
01-25 02:22:21.864  8960  8960 I C0421d/WMSRotation: RegisterOrientationChangeListener: in
01-25 02:22:21.864  8960  8960 I C03900/Ace: [(100000:100000:scope)] AddPersistAfterLayoutTask size: 1
01-25 02:22:21.865  8960  8960 I C03919/AceInputTracking: [(100000:100000:scope)] Debug touch pass mode 0
01-25 02:22:21.866  8960  8960 E C03934/AceUIEvent: [(100000:100000:scope)] AceTransform load failed: Error loading shared library /system/lib64/libtransform_interaction_ext.z.so: No such file or directory
01-25 02:22:21.866  8960  8960 I C03937/AceResource: [(100000:100000:scope)] ResourceAdapter UpdateResConfig with colorMode light
01-25 02:22:21.867  8960  8960 W C03900/Ace: [(100000:100000:scope)] not found systemTheme in HapModuleInfo, loading default OHOS_THEME
01-25 02:22:21.867  8960  8960 I C03900/Ace: [(100000:100000:scope)] Cannot Get File List from resources/styles/
01-25 02:22:21.867  8960  8960 W C03900/Ace: [(100000:100000:scope)] GetAsset failed: resources/styles/default.json
01-25 02:22:21.932  8960  8960 I C01406/OHOS::RS: RSTransactionHandler::Begin syncId:0, transactionHandler:3557641567, remoteTransactionDataStack.size:0
01-25 02:22:21.933  8960  8960 I C01406/OHOS::RS: RSTransactionHandler::Commit transactionHandler:3557641567
01-25 02:22:21.939  8960  8960 I C03900/Ace: [(100000:100000:scope)] root node OnAttachToFrameNode, id:0
01-25 02:22:21.940  8960  8960 I C03900/Ace: [(100000:100000:scope)] Rosenwindow set root, rsId:38482906972163
01-25 02:22:21.940  8960  8960 I C01406/OHOS::RS: RSTransactionHandler::Begin syncId:0, transactionHandler:3557641567, remoteTransactionDataStack.size:0
01-25 02:22:21.940  8960  8960 I C01406/OHOS::RS: RSTransactionHandler::Commit transactionHandler:3557641567
01-25 02:22:21.943  8960  8960 I C02220/IntentionClient: in Connect, enter
01-25 02:22:21.945  8960  8960 I C02220/IntentionClient: in Connect, Connecting IntentionService success
01-25 02:22:21.945  8960  8960 I C02220/IntentionClient: in Connect, leave
01-25 02:22:21.950  8960  8960 E C01d02/accessibility_asacfwk: [(AccessibilitySystemAbilityClientImpl:57)]accessibility service is ready.
01-25 02:22:21.957  8960  8960 I C02c03/PARAM_WATCHER: Add watcher keyPrefix accessibility.config.ready remoteWatcherId 50 success
01-25 02:22:21.961  8960  8960 I C03900/Ace: [(100000:100000:scope)] focusWindowId: 0, realHostWindowId: 0
01-25 02:22:21.976  8960  8960 I C03900/Ace: [(100000:100000:scope)] [com.example.nwpucampus][entry][100000]: window focus
01-25 02:22:21.979  8960  8960 I C02c03/PARAM_WATCHER: Add watcher keyPrefix debug.graphic.frame remoteWatcherId 50 success
01-25 02:22:21.980  8960  8960 E C01719/ffrt: 4:Load:62 load so[lib_cpuboost.so] fail
01-25 02:22:21.981  8960  8960 E C03900/Ace: [(100000:100000:scope)] ERROR EACCES
01-25 02:22:21.981  8960  8960 E C03900/Ace: [(100000:100000:scope)] ERROR EACCES
01-25 02:22:21.981  8960  8960 I C03900/Ace: [(100000:100000:scope)] ArkUIInvisibleFreeze: 0
01-25 02:22:21.981  8960  8960 I C03900/Ace: [(100000:100000:scope)] [com.example.nwpucampus][entry][100000]: SetMinPlatformVersion is 40000010
01-25 02:22:21.982  8960  8960 I C04209/WMSImms: RegisterAvoidAreaChangeListener: win 34
01-25 02:22:21.991  8960  8960 E C04201/IMockSessionManager: Read result failed, code is: 3.
01-25 02:22:21.993  8960  8960 E C04201/IMockSessionManager: Read result failed, code is: 5.
01-25 02:22:22.006  8960 12971 I C04208/WMSLayout: UpdateRect: id:34 name:nwpucampus0 rect:[0 0 1320 2856]->[0 0 1320 2856] reason:23 displayId:0
01-25 02:22:22.008  8960  8960 I C04209/WMSImms: GetAvoidAreaByType: win [34 nwpucampus0] type 0 times 1 area top [0 0 1320 136] 
01-25 02:22:22.012  8960  8960 I C04209/WMSImms: GetAvoidAreaByType: win [34 nwpucampus0] type 1 times 2 area top [512 37 292 83] 
01-25 02:22:22.013  8960  8960 I C04209/WMSImms: GetAvoidAreaByType: win [34 nwpucampus0] type 4 times 3 area bottom [429 2758 462 98] 
01-25 02:22:22.013  8960  8960 I C03917/AceSafeArea: [(100000:100000:scope)] InitializeSafeArea systemInsets:SafeAreaInsets left_: [start: 0, end: 0], top_: [start: 0, end: 136], right_: [start: 0, end: 0], bottom_: [start: 0, end: 0], cutoutInsets:SafeAreaInsets left_: [start: 0, end: 0], top_: [start: 37, end: 120], right_: [start: 0, end: 0], bottom_: [start: 0, end: 0], navInsets:SafeAreaInsets left_: [start: 0, end: 0], top_: [start: 0, end: 0], right_: [start: 0, end: 0], bottom_: [start: 2758, end: 2856]
01-25 02:22:22.016  8960  8960 I C0394e/AceWindow: [(100000:100000:scope)] Initialize displayId: 0, availableRect: [0, 0, 1320, 2856]
01-25 02:22:22.018  8960  8960 I C03900/Ace: [(100000:100000:scope)] Failed to open libthp_extra_innerapi.z.so, reason: Error loading shared library /system/lib64/libthp_extra_innerapi.z.so: No such file or directory
01-25 02:22:22.018  8960  8960 I C03900/Ace: [(-2:100000:singleton)] [com.example.nwpucampus][entry][100000]: Initialize: pages/Index
01-25 02:22:22.018  8960  8960 I C03900/Ace: [(100000:100000:scope)] RunPage:pages/Index
01-25 02:22:22.019  8960  8960 W C03900/Ace: [(100000:100000:scope)] GetAsset failed: manifest.json
01-25 02:22:22.020  8960 13041 I C03951/InputKeyFlow: [(-1:100000:singleton)] Subscribe touch.events.pass.through Event
01-25 02:22:22.021  8960  8960 I C0421c/WMSCompat: RegisterNavigateCallbackForPageCompatibleModeIfNeed: content is nullptr or page is empty
01-25 02:22:22.021  8960  8960 I C04200/WMS: InitUIContent: [0, 0]
01-25 02:22:22.021  8960 13042 I C02c03/PARAM_WATCHER: Add watcher keyPrefix persist.ace.trace.layout.enabled remoteWatcherId 50 success
01-25 02:22:22.021  8960  8960 I C04208/WMSLayout: SetUIContentInner: single hand, id:34, posX:0, posY:0, scaleX:1.000000, scaleY:1.000000
01-25 02:22:22.023  8960 13042 I C02c03/PARAM_WATCHER: Add watcher keyPrefix persist.ace.trace.inputevent.enabled remoteWatcherId 50 success
01-25 02:22:22.023  8960  8960 I C04219/WMSDecor: UpdateDecorEnable: decorVisible:1, id: 34
01-25 02:22:22.023  8960  8960 I C03900/Ace: [(-2:100000:singleton)] [com.example.nwpucampus][entry][100000]: UpdateWindowVisible: 1, hasDecor: 0
01-25 02:22:22.023  8960  8960 I C03900/Ace: [(-2:100000:singleton)] [com.example.nwpucampus][entry][100000]: NotifyWindowMode mode = 1
01-25 02:22:22.024  8960 13042 I C02c03/PARAM_WATCHER: Add watcher keyPrefix const.security.developermode.state remoteWatcherId 50 success
01-25 02:22:22.025  8960 13042 I C02c03/PARAM_WATCHER: Add watcher keyPrefix persist.ace.debug.statemgr.enabled remoteWatcherId 50 success
01-25 02:22:22.027  8960 13042 I C02c03/PARAM_WATCHER: Add watcher keyPrefix persist.ace.debug.boundary.enabled remoteWatcherId 50 success
01-25 02:22:22.029  8960 13042 I C02c03/PARAM_WATCHER: Add watcher keyPrefix persist.ace.performance.monitor.enabled remoteWatcherId 50 success
01-25 02:22:22.032  8960  8960 I C03900/Ace: [(-2:100000:singleton)] [com.example.nwpucampus][entry][100000]: window foreground
01-25 02:22:22.033  8960  8960 I C03900/Ace: [(100000:100000:scope)] Update application state , state: ON_SHOW
01-25 02:22:22.033  8960  8960 I C01406/OHOS::RS: RSSurfaceNode::SetAbilityState, surfaceNodeId:[38482906972162], ability state: foreground
01-25 02:22:22.034  8960  8960 I C03900/Ace: [(100000:100000:scope)] ArkUI requests first Vsync.
01-25 02:22:22.034  8960  8960 I C04202/WMSMain: RequestVsync: First vsync has requested, nodeId: 38482906972162
01-25 02:22:22.035  8960  8960 I C04208/WMSLayout: UpdateViewportConfig: Id: 34, reason: 0, windowRect: [0 0 1320 2856], displayOrientation: 0, config[0, 0, 0, 3.500000]
01-25 02:22:22.035  8960  8960 I C03900/Ace: [(-2:100000:singleton)] [com.example.nwpucampus][entry][100000]: window focus
01-25 02:22:22.036  8960  8960 I C03900/Ace: [(-2:100000:singleton)] [com.example.nwpucampus][entry][100000]:window active
01-25 02:22:22.041  8960  8960 W C01320/JsEnv: [source_map145]the stack without line info
01-25 02:22:22.041  8960  8960 I A00000/testTag: Succeeded in loading the content.
01-25 02:22:22.042  8960  8960 I C04200/JsWindowStage: Window [34, nwpucampus0] load content end, ret=0
01-25 02:22:22.042  8960  8960 I C02d06/XCollie: Application is in starting period.
01-25 02:22:22.042  8960  8960 I C04209/WMSImms: NotifyAvoidAreaChange: win 34 api 21 type 0 area top [0 0 1320 136] 
01-25 02:22:22.042  8960  8960 I C04209/WMSImms: NotifyAvoidAreaChange: win 34 api 21 type 1 area top [512 37 292 83] 
01-25 02:22:22.042  8960  8960 I C04209/WMSImms: NotifyAvoidAreaChange: win 34 api 21 type 2 area empty
01-25 02:22:22.042  8960  8960 I C04209/WMSImms: NotifyAvoidAreaChange: win 34 api 21 type 3 area empty
01-25 02:22:22.042  8960  8960 I C04209/WMSImms: NotifyAvoidAreaChange: win 34 api 21 type 4 area bottom [429 2758 462 98] 
01-25 02:22:22.044  8960  8960 I C04208/WMSLayout: UpdateViewportConfig: Id: 34, reason: 23, windowRect: [0 0 1320 2856], displayOrientation: 0, config[0, 0, 0, 3.500000]
01-25 02:22:22.051  8960  8960 I C01356/Recovery: [app_recovery468]fileDir: /data/storage/el2/base/files
01-25 02:22:22.051  8960  8960 I C03900/Ace: [(100000:100000:scope)] Update application state , state: ON_ACTIVE
01-25 02:22:22.072  8960  8960 I C01d02/accessibility_asacfwk: [(SubscribeStateObserver:551)]Observer has subscribed!
01-25 02:22:22.073  8960  8960 I C01d02/accessibility_asacfwk: [(SubscribeStateObserver:551)]Observer has subscribed!
01-25 02:22:22.073  8960  8960 I C01d02/accessibility_asacfwk: [(SubscribeStateObserver:551)]Observer has subscribed!
01-25 02:22:22.073  8960  8960 I C0391c/AceFocus: [(100000:100000:scope)] Window: 34 get focus.
01-25 02:22:22.073  8960  8960 W C0391c/AceFocus: [(100000:100000:scope)] Current focus view can not found!
01-25 02:22:22.073  8960  8960 I C0391c/AceFocus: [(100000:100000:scope)] Request focus on rootFocusHub: root/0
01-25 02:22:22.075  8960  8960 I C04208/WMSLayout: UpdateViewportConfig: Id: 34, reason: 23, windowRect: [0 0 1320 2856], displayOrientation: 0, config[0, 0, 0, 3.500000]
01-25 02:22:22.075  8960  8960 I C03925/AceRouter: [(100000:100000:scope)] Page router manager is creating page[1]: url: pages/Index path: pages/Index.js, recoverable: yes, namedRouter: no
01-25 02:22:22.131  8960  8960 I C015b0/NETSTACK: [napi_utils.cpp:759] newId = 1, id = 2
01-25 02:22:22.143  8960  8960 I C015b0/NETSTACK: [http_module.cpp:64] IsAtomicService bundleName is com.example.nwpucampus, isAtomicService is 0
01-25 02:22:22.168  8960  8960 I C05a01/ATM: [ParseRequestPermissionFromUser:645]AsyncContext.uiAbilityFlag is: 1.
01-25 02:22:22.168  8960  8960 I C05a01/ATM: [ParseStringArray:136]Array size is 2
01-25 02:22:22.168  8960  8960 I C05a01/ATM: [ParseRequestPermissionFromUser:645]AsyncContext.uiAbilityFlag is: 1.
01-25 02:22:22.169  8960  8960 I C05a01/ATM: [ParseStringArray:136]Array size is 2
01-25 02:22:22.171  8960 13047 I C05a01/ATM: [IsDynamicRequest:435]TokenID: 537574366, bundle: com.huawei.hmos.security.privacycenter, uiExAbility: PermissionGrantAbility, serExAbility: PermissionServiceGrantAbility.
01-25 02:22:22.171  8960 13047 I C05a01/ATM: [IsDynamicRequest:439]Permission: ohos.permission.LOCATION: state: 1, errorReason: 0
01-25 02:22:22.171  8960 13047 I C05a01/ATM: [IsDynamicRequest:439]Permission: ohos.permission.APPROXIMATELY_LOCATION: state: 1, errorReason: 0
01-25 02:22:22.171  8960 13046 I C05a01/ATM: [IsDynamicRequest:435]TokenID: 537574366, bundle: com.huawei.hmos.security.privacycenter, uiExAbility: PermissionGrantAbility, serExAbility: PermissionServiceGrantAbility.
01-25 02:22:22.171  8960 13046 I C05a01/ATM: [IsDynamicRequest:439]Permission: ohos.permission.LOCATION: state: 1, errorReason: 0
01-25 02:22:22.171  8960 13046 I C05a01/ATM: [IsDynamicRequest:439]Permission: ohos.permission.APPROXIMATELY_LOCATION: state: 1, errorReason: 0
01-25 02:22:22.180  8960  8960 E C03947/AceStateMgmt: [(100000:100000:scope)] FIX THIS APPLICATION ERROR: @Component '@Component 'MapCanvas'[7]': Illegal variable value error with decorated variable @Prop 'onTap': failed validation: 'undefined, null, number, boolean, string, or Object but not function, not V2 @ObservedV2 / @Trace class, and makeObserved return value either, attempt to assign value type: 'function', value: 'undefined'!
01-25 02:22:22.181  8960  8960 E C03947/AceStateMgmt: [(100000:100000:scope)] FIX THIS APPLICATION ERROR: @Component 'Index'[4] has error in update func: @Component '@Component 'MapCanvas'[7]': Illegal variable value error with decorated variable @Prop 'onTap': failed validation: 'undefined, null, number, boolean, string, or Object but not function, not V2 @ObservedV2 / @Trace class, and makeObserved return value either, attempt to assign value type: 'function', value: 'undefined'!
01-25 02:22:22.182  8960  8960 W C03f00/ArkCompiler: [default] [Call] occur exception need return
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler: [ecmascript] Pending exception before ExecutePendingJob called, in line:5942, exception details as follows:
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler: TypeError: @Component '@Component 'MapCanvas'[7]': Illegal variable value error with decorated variable @Prop 'onTap': failed validation: 'undefined, null, number, boolean, string, or Object but not function, not V2 @ObservedV2 / @Trace class, and makeObserved return value either, attempt to assign value type: 'function', value: 'undefined'!
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at varValueCheckFailed (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:2315:1)
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at checkIsSupportedValue (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:6488:1)
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at SynchedPropertyOneWayPU (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:6994:1)
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at SynchedPropertyObjectOneWayPU (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:7351:1)
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at MapCanvas entry (entry/src/main/ets/components/MapCanvas.ets:14:1)
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at anonymous entry (entry/src/main/ets/pages/Index.ets:556:7)
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at updateFunc (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:8720:1)
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at observeComponentCreation2 (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:8747:1)
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at initialRender entry (entry/src/main/ets/pages/Index.ets:576:23)
01-25 02:22:22.182  8960  8960 E C03f00/ArkCompiler:     at initialRenderView (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:8251:1)
01-25 02:22:22.182  8960  8960 W C03900/Ace: [(100000:100000:scope)] after call jsFunction hasError, empty: 0, caught: 1
01-25 02:22:22.187  8960  8960 I C01356/Recovery: [app_recovery255]scheduleRecoverApp  begin
01-25 02:22:22.187  8960  8960 E C01317/AppKit: [MAINTHD2051]
01-25 02:22:22.187  8960  8960 E C01317/AppKit: com.example.nwpucampus is about to exit due to RuntimeError
01-25 02:22:22.187  8960  8960 E C01317/AppKit: Error type:TypeError
01-25 02:22:22.187  8960  8960 E C01317/AppKit: Error name:TypeError
01-25 02:22:22.187  8960  8960 E C01317/AppKit: Error message:@Component '@Component 'MapCanvas'[7]': Illegal variable value error with decorated variable @Prop 'onTap': failed validation: 'undefined, null, number, boolean, string, or Object but not function, not V2 @ObservedV2 / @Trace class, and makeObserved return value either, attempt to assign value type: 'function', value: 'undefined'!
01-25 02:22:22.187  8960  8960 E C01317/AppKit: Stacktrace:
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at varValueCheckFailed (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:2315:1)
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at checkIsSupportedValue (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:6488:1)
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at SynchedPropertyOneWayPU (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:6994:1)
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at SynchedPropertyObjectOneWayPU (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:7351:1)
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at MapCanvas entry (entry/src/main/ets/components/MapCanvas.ets:14:1)
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at anonymous entry (entry/src/main/ets/pages/Index.ets:556:7)
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at updateFunc (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:8720:1)
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at observeComponentCreation2 (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:8747:1)
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at initialRender entry (entry/src/main/ets/pages/Index.ets:576:23)
01-25 02:22:22.187  8960  8960 E C01317/AppKit:     at initialRenderView (/usr1/hmos_for_system/src/increment/sourcecode/out/generic_generic_x86_64only/all_all_phone_standard_emulator/obj/foundation/arkui/ace_engine/frameworks/bridge/declarative_frontend/stateMgmt.js:8251:1)
01-25 02:22:22.187  8960  8960 W C01317/AppKit: [MAINTHD2063]hisysevent write result=0, send event [FRAMEWORK,PROCESS_KILL], pid=8960, processName=com.example.nwpucampus, msg=Kill Reason:Js Error, foreground=1, isUncatchable=0

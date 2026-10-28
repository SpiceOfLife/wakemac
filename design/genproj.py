import hashlib, os, sys
root = sys.argv[1]
def uid(s): return hashlib.md5(s.encode()).hexdigest()[:24].upper()

ios_src = sorted(f for f in os.listdir(f"{root}/iOS") if f.endswith(".swift"))
mac_src = sorted(f for f in os.listdir(f"{root}/macOS") if f.endswith(".swift"))
shared = ["Protocol.swift"]

objs = []
def add(k, body): objs.append((k, body))

# file refs
refs = {}
for d, files in (("iOS", ios_src), ("macOS", mac_src), ("Shared", shared)):
    for f in files:
        k = uid(f"ref:{d}/{f}"); refs[(d,f)] = k
        add(k, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }}')
for d in ("iOS","macOS"):
    k = uid(f"ref:{d}/Assets.xcassets"); refs[(d,"Assets.xcassets")] = k
    add(k, f'{{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }}')
    k = uid(f"ref:{d}/Info.plist"); refs[(d,"Info.plist")] = k
    add(k, f'{{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }}')
ios_prod = uid("prod:ios"); mac_prod = uid("prod:mac")
add(ios_prod, '{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = WakeMac.app; sourceTree = BUILT_PRODUCTS_DIR; }')
add(mac_prod, '{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "WakeMac Agent.app"; sourceTree = BUILT_PRODUCTS_DIR; }')

# groups
def group(name, children, path=True):
    k = uid(f"grp:{name}")
    ch = ", ".join(children)
    p = f"path = {name}; " if path else ""
    add(k, f'{{isa = PBXGroup; children = ({ch}); {p}sourceTree = "<group>"; }}')
    return k
g_ios = group("iOS", [refs[("iOS",f)] for f in ios_src] + [refs[("iOS","Assets.xcassets")], refs[("iOS","Info.plist")]])
g_mac = group("macOS", [refs[("macOS",f)] for f in mac_src] + [refs[("macOS","Assets.xcassets")], refs[("macOS","Info.plist")]])
g_sh = group("Shared", [refs[("Shared",f)] for f in shared])
g_prod = uid("grp:Products")
add(g_prod, f'{{isa = PBXGroup; children = ({ios_prod}, {mac_prod}); name = Products; sourceTree = "<group>"; }}')
g_main = uid("grp:main")
add(g_main, f'{{isa = PBXGroup; children = ({g_ios}, {g_mac}, {g_sh}, {g_prod}); sourceTree = "<group>"; }}')

def target(name, tag, srcs, product, ptype_settings_debug, sdk, assets):
    bfs = []
    for d,f in srcs:
        bk = uid(f"bf:{tag}:{d}/{f}")
        add(bk, f'{{isa = PBXBuildFile; fileRef = {refs[(d,f)]}; }}')
        bfs.append(bk)
    src_phase = uid(f"srcphase:{tag}")
    add(src_phase, f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(bfs)}); runOnlyForDeploymentPostprocessing = 0; }}')
    fw = uid(f"fw:{tag}")
    add(fw, '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }')
    rb = uid(f"bf:{tag}:assets")
    add(rb, f'{{isa = PBXBuildFile; fileRef = {refs[assets]}; }}')
    res = uid(f"res:{tag}")
    add(res, f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({rb}); runOnlyForDeploymentPostprocessing = 0; }}')
    cfgs = []
    for c in ("Debug","Release"):
        k = uid(f"cfg:{tag}:{c}")
        s = "; ".join(f"{a} = {b}" for a,b in ptype_settings_debug.items())
        add(k, f'{{isa = XCBuildConfiguration; buildSettings = {{{s}; }}; name = {c}; }}')
        cfgs.append(k)
    cl = uid(f"cl:{tag}")
    add(cl, f'{{isa = XCConfigurationList; buildConfigurations = ({", ".join(cfgs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
    t = uid(f"target:{tag}")
    add(t, f'{{isa = PBXNativeTarget; buildConfigurationList = {cl}; buildPhases = ({src_phase}, {fw}, {res}); buildRules = (); dependencies = (); name = "{name}"; productName = "{name}"; productReference = {product}; productType = "com.apple.product-type.application"; }}')
    return t

common = {"SWIFT_VERSION":"5.0","MARKETING_VERSION":"1.0","CURRENT_PROJECT_VERSION":"1","CODE_SIGN_STYLE":"Automatic","GENERATE_INFOPLIST_FILE":"NO","ENABLE_PREVIEWS":"YES","ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon"}
ios_set = dict(common, **{"SDKROOT":"iphoneos","IPHONEOS_DEPLOYMENT_TARGET":"17.0","TARGETED_DEVICE_FAMILY":'"1,2"',
  "PRODUCT_BUNDLE_IDENTIFIER":"app.oursblanc.wakemac","PRODUCT_NAME":"WakeMac","INFOPLIST_FILE":"iOS/Info.plist","CODE_SIGN_ENTITLEMENTS":"iOS/WakeMac.entitlements",
  "LD_RUNPATH_SEARCH_PATHS":'"$(inherited) @executable_path/Frameworks"', "DEVELOPMENT_TEAM":"93YM59H7UW","INFOPLIST_KEY_LSApplicationCategoryType":"public.app-category.utilities"})
mac_set = dict(common, **{"SDKROOT":"macosx","MACOSX_DEPLOYMENT_TARGET":"13.0",
  "PRODUCT_BUNDLE_IDENTIFIER":"app.oursblanc.wakemac.agent","PRODUCT_NAME":'"WakeMac Agent"',"INFOPLIST_FILE":"macOS/Info.plist",
  "ENABLE_HARDENED_RUNTIME":"YES","CODE_SIGN_IDENTITY":'"-"',"COMBINE_HIDPI_IMAGES":"YES","INFOPLIST_KEY_LSApplicationCategoryType":"public.app-category.utilities",
  "LD_RUNPATH_SEARCH_PATHS":'"$(inherited) @executable_path/../Frameworks"'})
t_ios = target("WakeMac","ios",[("iOS",f) for f in ios_src]+[("Shared","Protocol.swift")], ios_prod, ios_set, "iphoneos", ("iOS","Assets.xcassets"))
t_mac = target("WakeMacAgent","mac",[("macOS",f) for f in mac_src]+[("Shared","Protocol.swift")], mac_prod, mac_set, "macosx", ("macOS","Assets.xcassets"))

pcfgs=[]
for c in ("Debug","Release"):
    k=uid(f"pcfg:{c}")
    extra = 'DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; GCC_OPTIMIZATION_LEVEL = 0; ONLY_ACTIVE_ARCH = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ' if c=="Debug" else 'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule; '
    add(k, f'{{isa = XCBuildConfiguration; buildSettings = {{ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; ENABLE_STRICT_OBJC_MSGSEND = YES; ENABLE_USER_SCRIPT_SANDBOXING = YES; {extra}}}; name = {c}; }}')
    pcfgs.append(k)
pcl=uid("pcl")
add(pcl, f'{{isa = XCConfigurationList; buildConfigurations = ({", ".join(pcfgs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
proj=uid("project")
add(proj, f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; }}; buildConfigurationList = {pcl}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja, en, Base); mainGroup = {g_main}; productRefGroup = {g_prod}; projectDirPath = ""; projectRoot = ""; targets = ({t_ios}, {t_mac}); }}')

out = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n"
for k,b in objs: out += f"\t\t{k} = {b};\n"
out += f"\t}};\n\trootObject = {proj};\n}}\n"
os.makedirs(f"{root}/WakeMac.xcodeproj", exist_ok=True)
open(f"{root}/WakeMac.xcodeproj/project.pbxproj","w").write(out)
print(len(objs), "objects")

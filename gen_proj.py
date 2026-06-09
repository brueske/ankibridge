#!/usr/bin/env python3
"""Generate AnkiBridge.xcodeproj/project.pbxproj (classic groups, objectVersion 56)."""
import os, hashlib

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = "AnkiBridge"

source_files = [
    "AnkiBridgeApp.swift", "AppState.swift", "AppSettings.swift", "Models.swift",
    "Attachment.swift", "OpenAIClient.swift", "AnkiConnectClient.swift", "CardParser.swift",
    "ContentView.swift", "SidebarView.swift", "ChatView.swift",
    "CardsPaneView.swift", "SettingsView.swift",
]
resource_files = ["Assets.xcassets"]
other_files = ["AnkiBridge.entitlements"]  # referenced, not in a build phase

def uid(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()

# Stable ids
PROJECT_ID = uid("project")
MAIN_GROUP = uid("maingroup")
APP_GROUP = uid("appgroup")
PRODUCTS_GROUP = uid("products")
TARGET_ID = uid("target")
PRODUCT_REF = uid("product.app")
SOURCES_PHASE = uid("phase.sources")
RESOURCES_PHASE = uid("phase.resources")
FRAMEWORKS_PHASE = uid("phase.frameworks")
PROJ_CFG_LIST = uid("cfglist.project")
TARGET_CFG_LIST = uid("cfglist.target")
PROJ_DEBUG = uid("cfg.project.debug")
PROJ_RELEASE = uid("cfg.project.release")
TARGET_DEBUG = uid("cfg.target.debug")
TARGET_RELEASE = uid("cfg.target.release")

def fileref(name):
    return uid("fileref." + name)
def buildfile(name):
    return uid("buildfile." + name)

lines = []
def w(s=""): lines.append(s)

w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {")
w("\t};")
w("\tobjectVersion = 56;")
w("\tobjects = {")

# PBXBuildFile
w("\n/* Begin PBXBuildFile section */")
for f in source_files:
    w(f"\t\t{buildfile(f)} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {fileref(f)} /* {f} */; }};")
for f in resource_files:
    w(f"\t\t{buildfile(f)} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {fileref(f)} /* {f} */; }};")
w("/* End PBXBuildFile section */")

# PBXFileReference
w("\n/* Begin PBXFileReference section */")
w(f'\t\t{PRODUCT_REF} /* {PROJ}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJ}.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
for f in source_files:
    w(f'\t\t{fileref(f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }};')
for f in resource_files:
    w(f'\t\t{fileref(f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {f}; sourceTree = "<group>"; }};')
for f in other_files:
    w(f'\t\t{fileref(f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {f}; sourceTree = "<group>"; }};')
w("/* End PBXFileReference section */")

# PBXFrameworksBuildPhase
w("\n/* Begin PBXFrameworksBuildPhase section */")
w(f"\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{")
w("\t\t\tisa = PBXFrameworksBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (\n\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */")

# PBXGroup
w("\n/* Begin PBXGroup section */")
w(f"\t\t{MAIN_GROUP} = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{APP_GROUP} /* {PROJ} */,")
w(f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,")
w("\t\t\t);")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")

w(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{PRODUCT_REF} /* {PROJ}.app */,")
w("\t\t\t);")
w("\t\t\tname = Products;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")

w(f"\t\t{APP_GROUP} /* {PROJ} */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for f in source_files + resource_files + other_files:
    w(f"\t\t\t\t{fileref(f)} /* {f} */,")
w("\t\t\t);")
w(f"\t\t\tpath = {PROJ};")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("/* End PBXGroup section */")

# PBXNativeTarget
w("\n/* Begin PBXNativeTarget section */")
w(f"\t\t{TARGET_ID} /* {PROJ} */ = {{")
w("\t\t\tisa = PBXNativeTarget;")
w(f"\t\t\tbuildConfigurationList = {TARGET_CFG_LIST} /* Build configuration list for PBXNativeTarget \"{PROJ}\" */;")
w("\t\t\tbuildPhases = (")
w(f"\t\t\t\t{SOURCES_PHASE} /* Sources */,")
w(f"\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,")
w(f"\t\t\t\t{RESOURCES_PHASE} /* Resources */,")
w("\t\t\t);")
w("\t\t\tbuildRules = (\n\t\t\t);")
w("\t\t\tdependencies = (\n\t\t\t);")
w(f"\t\t\tname = {PROJ};")
w(f"\t\t\tproductName = {PROJ};")
w(f"\t\t\tproductReference = {PRODUCT_REF} /* {PROJ}.app */;")
w("\t\t\tproductType = \"com.apple.product-type.application\";")
w("\t\t};")
w("/* End PBXNativeTarget section */")

# PBXProject
w("\n/* Begin PBXProject section */")
w(f"\t\t{PROJECT_ID} /* Project object */ = {{")
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
w("\t\t\t\tLastSwiftUpdateCheck = 1600;")
w("\t\t\t\tLastUpgradeCheck = 1600;")
w("\t\t\t\tTargetAttributes = {")
w(f"\t\t\t\t\t{TARGET_ID} = {{")
w("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
w("\t\t\t\t\t};")
w("\t\t\t\t};")
w("\t\t\t};")
w(f"\t\t\tbuildConfigurationList = {PROJ_CFG_LIST} /* Build configuration list for PBXProject \"{PROJ}\" */;")
w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
w("\t\t\tdevelopmentRegion = en;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);")
w(f"\t\t\tmainGroup = {MAIN_GROUP};")
w(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;")
w("\t\t\tprojectDirPath = \"\";")
w("\t\t\tprojectRoot = \"\";")
w("\t\t\ttargets = (")
w(f"\t\t\t\t{TARGET_ID} /* {PROJ} */,")
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */")

# PBXResourcesBuildPhase
w("\n/* Begin PBXResourcesBuildPhase section */")
w(f"\t\t{RESOURCES_PHASE} /* Resources */ = {{")
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for f in resource_files:
    w(f"\t\t\t\t{buildfile(f)} /* {f} in Resources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXResourcesBuildPhase section */")

# PBXSourcesBuildPhase
w("\n/* Begin PBXSourcesBuildPhase section */")
w(f"\t\t{SOURCES_PHASE} /* Sources */ = {{")
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for f in source_files:
    w(f"\t\t\t\t{buildfile(f)} /* {f} in Sources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXSourcesBuildPhase section */")

# XCBuildConfiguration
def project_common():
    return [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "CLANG_ANALYZER_NONNULL = YES;",
        "CLANG_ENABLE_MODULES = YES;",
        "CLANG_ENABLE_OBJC_ARC = YES;",
        "CLANG_ENABLE_OBJC_WEAK = YES;",
        "COPY_PHASE_STRIP = NO;",
        "ENABLE_STRICT_OBJC_MSGSEND = YES;",
        "GCC_C_LANGUAGE_STANDARD = gnu17;",
        "GCC_NO_COMMON_BLOCKS = YES;",
        "MACOSX_DEPLOYMENT_TARGET = 14.0;",
        "MTL_FAST_MATH = YES;",
        "SDKROOT = macosx;",
    ]

def target_common():
    return [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
        "CODE_SIGN_ENTITLEMENTS = AnkiBridge/AnkiBridge.entitlements;",
        'CODE_SIGN_IDENTITY = "-";',
        "CODE_SIGN_STYLE = Automatic;",
        "COMBINE_HIDPI_IMAGES = YES;",
        "CURRENT_PROJECT_VERSION = 1;",
        "ENABLE_HARDENED_RUNTIME = YES;",
        "ENABLE_PREVIEWS = YES;",
        "GENERATE_INFOPLIST_FILE = YES;",
        'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.education";',
        'INFOPLIST_KEY_NSHumanReadableCopyright = "";',
        'LD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/../Frameworks",\n\t\t\t\t);',
        "MARKETING_VERSION = 1.0;",
        'PRODUCT_BUNDLE_IDENTIFIER = com.ankibridge.app;',
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        "SWIFT_EMIT_LOC_STRINGS = YES;",
        "SWIFT_VERSION = 5.0;",
    ]

w("\n/* Begin XCBuildConfiguration section */")

def emit_cfg(cfg_id, name, settings):
    w(f"\t\t{cfg_id} /* {name} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    for s in settings:
        w(f"\t\t\t\t{s}")
    w("\t\t\t};")
    w(f"\t\t\tname = {name};")
    w("\t\t};")

emit_cfg(PROJ_DEBUG, "Debug", project_common() + [
    "DEBUG_INFORMATION_FORMAT = dwarf;",
    "ENABLE_TESTABILITY = YES;",
    "GCC_OPTIMIZATION_LEVEL = 0;",
    'GCC_PREPROCESSOR_DEFINITIONS = (\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t);',
    "ONLY_ACTIVE_ARCH = YES;",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
    "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
])
emit_cfg(PROJ_RELEASE, "Release", project_common() + [
    "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
    "ENABLE_NS_ASSERTIONS = NO;",
    "SWIFT_COMPILATION_MODE = wholemodule;",
])
emit_cfg(TARGET_DEBUG, "Debug", target_common())
emit_cfg(TARGET_RELEASE, "Release", target_common())
w("/* End XCBuildConfiguration section */")

# XCConfigurationList
w("\n/* Begin XCConfigurationList section */")
w(f"\t\t{PROJ_CFG_LIST} /* Build configuration list for PBXProject \"{PROJ}\" */ = {{")
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w(f"\t\t\t\t{PROJ_DEBUG} /* Debug */,")
w(f"\t\t\t\t{PROJ_RELEASE} /* Release */,")
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w(f"\t\t{TARGET_CFG_LIST} /* Build configuration list for PBXNativeTarget \"{PROJ}\" */ = {{")
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w(f"\t\t\t\t{TARGET_DEBUG} /* Debug */,")
w(f"\t\t\t\t{TARGET_RELEASE} /* Release */,")
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w("/* End XCConfigurationList section */")

w("\t};")
w(f"\trootObject = {PROJECT_ID} /* Project object */;")
w("}")

projdir = os.path.join(ROOT, f"{PROJ}.xcodeproj")
os.makedirs(projdir, exist_ok=True)
with open(os.path.join(projdir, "project.pbxproj"), "w") as f:
    f.write("\n".join(lines) + "\n")
print("Wrote", os.path.join(projdir, "project.pbxproj"))

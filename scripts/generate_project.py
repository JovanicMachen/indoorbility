"""Generate the native Xcode project with its local core and pinned Google SDKs."""
from pathlib import Path
import hashlib
import plistlib
import subprocess
import json

ROOT = Path(__file__).resolve().parent.parent
objects = {}
# Preserve the developer's device-signing team when regenerating source membership.
team = None
existing = ROOT/'Indoorbility.xcodeproj/project.pbxproj'
if existing.exists():
    try:
        previous = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(existing)]))
        team = next((v.get('buildSettings', {}).get('DEVELOPMENT_TEAM') for v in previous['objects'].values()
                     if v.get('buildSettings', {}).get('PRODUCT_BUNDLE_IDENTIFIER') == 'com.indoorbility.app'), None)
    except (ValueError, subprocess.CalledProcessError):
        pass

def key(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, value): objects[key(name)] = value; return key(name)
def quoted(value): return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
def seq(values): return '(' + ', '.join(values) + (',' if values else '') + ')'

files, builds, asset_builds = [], [], []
for path in sorted((ROOT/'App').glob('*.swift')):
    ref = add('file:'+path.name, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+quoted(path.name)+'; sourceTree = "<group>";}')
    files.append(ref)
    builds.append(add('build:'+path.name, '{isa = PBXBuildFile; fileRef = '+ref+';}'))
for path in sorted((ROOT/'App').glob('*.xcassets')):
    ref = add('asset:'+path.name, '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = '+quoted(path.name)+'; sourceTree = "<group>";}')
    files.append(ref)
    asset_builds.append(add('asset-build:'+path.name, '{isa = PBXBuildFile; fileRef = '+ref+';}'))
app_group = add('app-group', '{isa = PBXGroup; children = '+seq(files)+'; path = App; sourceTree = "<group>";}')
product = add('product', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = Indoorbility.app; sourceTree = BUILT_PRODUCTS_DIR;}')
products = add('products', '{isa = PBXGroup; children = '+seq([product])+'; name = Products; sourceTree = "<group>";}')
main = add('main', '{isa = PBXGroup; children = '+seq([app_group, products])+'; sourceTree = "<group>";}')
package = add('local-package', '{isa = XCLocalSwiftPackageReference; relativePath = .;}')
dep = add('package-product', '{isa = XCSwiftPackageProductDependency; package = '+package+'; productName = IndoorbilityCore;}')
framework_build = add('core-build', '{isa = PBXBuildFile; productRef = '+dep+';}')
google_navigation = add('google-navigation-package', '{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/googlemaps/ios-navigation-sdk"; requirement = {kind = exactVersion; version = 11.1.1;};}')
# Pin Maps too: a newer transitive release requires a higher deployment target.
google_maps = add('google-maps-package', '{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/googlemaps/ios-maps-sdk"; requirement = {kind = exactVersion; version = 11.1.1;};}')
google_product = add('google-navigation-product', '{isa = XCSwiftPackageProductDependency; package = '+google_navigation+'; productName = GoogleNavigation;}')
google_build = add('google-navigation-build', '{isa = PBXBuildFile; productRef = '+google_product+';}')
sources = add('sources', '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+seq(builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
frameworks = add('frameworks', '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = '+seq([framework_build,google_build])+'; runOnlyForDeploymentPostprocessing = 0;}')
resource_files = list(asset_builds)
for sound in sorted((ROOT/'App/Resources').glob('*.mp3')):
    ref = add('sound:'+sound.name, '{isa = PBXFileReference; lastKnownFileType = audio.mp3; path = '+quoted(str(sound.relative_to(ROOT)))+'; sourceTree = SOURCE_ROOT;}')
    resource_files.append(add('sound-build:'+sound.name, '{isa = PBXBuildFile; fileRef = '+ref+';}'))
if (ROOT/'LocalConfig/MapsConfig.plist').exists():
    config_ref = add('maps-config', '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "LocalConfig/MapsConfig.plist"; sourceTree = SOURCE_ROOT;}')
    resource_files.append(add('maps-config-build', '{isa = PBXBuildFile; fileRef = '+config_ref+';}'))
resources = add('resources', '{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+seq(resource_files)+'; runOnlyForDeploymentPostprocessing = 0;}')
project_configs=[]; app_configs=[]
for config in ['Debug', 'Release']:
    debug=config=='Debug'
    common = {'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if debug else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if debug else 'dwarf-with-dsym'}
    if debug:
        common['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        common['ONLY_ACTIVE_ARCH']='YES'
    settings=lambda d: '{'+' '.join(k+' = '+quoted(v)+';' for k,v in d.items())+'}'
    project_configs.append(add('project:'+config,'{isa = XCBuildConfiguration; buildSettings = '+settings(common)+'; name = '+config+';}'))
    app={'PRODUCT_BUNDLE_IDENTIFIER':'com.indoorbility.app','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_CFBundleDisplayName':'Indoorbility','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone':'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight','INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad':'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight','TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','INFOPLIST_KEY_NSCameraUsageDescription':'Indoorbility uses the camera to read signs, capture a space with LiDAR, locate you within your saved scans, and recognize optional facial gestures.','INFOPLIST_KEY_NSMicrophoneUsageDescription':'Indoorbility listens for a short command only when you tap Listen.','INFOPLIST_KEY_NSSpeechRecognitionUsageDescription':'Indoorbility recognizes your spoken navigation commands on supported devices.','MARKETING_VERSION':'0.3.0','CURRENT_PROJECT_VERSION':'1','CODE_SIGN_STYLE':'Automatic','SWIFT_EMIT_LOC_STRINGS':'YES'}
    app['INFOPLIST_KEY_NSLocationWhenInUseUsageDescription'] = 'Indoorbility uses your location for outdoor directions and to remember a confirmed entrance. GPS never establishes your indoor position.'
    if (ROOT/'App/Assets.xcassets/AppIcon.appiconset').exists():
        app['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
    if team: app['DEVELOPMENT_TEAM'] = team
    app_configs.append(add('app:'+config,'{isa = XCBuildConfiguration; buildSettings = '+settings(app)+'; name = '+config+';}'))
pconfigs=add('project-configs','{isa = XCConfigurationList; buildConfigurations = '+seq(project_configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
aconfigs=add('app-configs','{isa = XCConfigurationList; buildConfigurations = '+seq(app_configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
target=add('target','{isa = PBXNativeTarget; buildConfigurationList = '+aconfigs+'; buildPhases = '+seq([sources,frameworks,resources])+'; buildRules = (); dependencies = (); name = Indoorbility; packageProductDependencies = '+seq([dep,google_product])+'; productName = Indoorbility; productReference = '+product+'; productType = "com.apple.product-type.application";}')
test_file=add('ui-file', '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UITests/IndoorbilityUITests.swift; sourceTree = "<group>";}')
test_build=add('ui-build', '{isa = PBXBuildFile; fileRef = '+test_file+';}')
test_product=add('ui-product','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = IndoorbilityUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
objects[main]='{isa = PBXGroup; children = '+seq([app_group,test_file,products])+'; sourceTree = "<group>";}'
objects[products]='{isa = PBXGroup; children = '+seq([product,test_product])+'; name = Products; sourceTree = "<group>";}'
test_sources=add('ui-sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+seq([test_build])+'; runOnlyForDeploymentPostprocessing = 0;}')
test_frameworks=add('ui-frameworks','{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
test_configs=[]
for config in ['Debug','Release']:
    values={'PRODUCT_BUNDLE_IDENTIFIER':'com.indoorbility.app.uitests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad':'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight','TARGETED_DEVICE_FAMILY':'1,2','TEST_TARGET_NAME':'Indoorbility','CODE_SIGN_STYLE':'Automatic'}
    test_configs.append(add('ui-config:'+config,'{isa = XCBuildConfiguration; buildSettings = '+settings(values)+'; name = '+config+';}'))
test_config_list=add('ui-configs','{isa = XCConfigurationList; buildConfigurations = '+seq(test_configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
proxy=add('ui-proxy','{isa = PBXContainerItemProxy; containerPortal = '+key('project')+'; proxyType = 1; remoteGlobalIDString = '+target+'; remoteInfo = Indoorbility;}')
test_dependency=add('ui-dependency','{isa = PBXTargetDependency; target = '+target+'; targetProxy = '+proxy+';}')
test_target=add('ui-target','{isa = PBXNativeTarget; buildConfigurationList = '+test_config_list+'; buildPhases = '+seq([test_sources,test_frameworks])+'; buildRules = (); dependencies = '+seq([test_dependency])+'; name = IndoorbilityUITests; productName = IndoorbilityUITests; productReference = '+test_product+'; productType = "com.apple.product-type.bundle.ui-testing";}')
project=add('project','{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600;}; buildConfigurationList = '+pconfigs+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = '+main+'; packageReferences = '+seq([package,google_navigation,google_maps])+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+seq([target,test_target])+';}')
folder=ROOT/'Indoorbility.xcodeproj'; folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project+';}\n')
schemes=folder/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Indoorbility.app" BlueprintName="Indoorbility" ReferencedContainer="container:Indoorbility.xcodeproj"/>'
(schemes/'Indoorbility.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="IndoorbilityUITests.xctest" BlueprintName="IndoorbilityUITests" ReferencedContainer="container:Indoorbility.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(folder)

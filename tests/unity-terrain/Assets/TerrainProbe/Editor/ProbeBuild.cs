using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

namespace La64.TerrainProbe
{
    public static class ProbeBuild
    {
        private const string ResourcePath = "Assets/Resources/TerrainProbe";
        private const string ScenePath = "Assets/Generated/TerrainProbe.unity";

        private static string Argument(string key, string fallback)
        {
            string[] args = Environment.GetCommandLineArgs();
            int index = Array.IndexOf(args, key);
            return index >= 0 && index + 1 < args.Length ? args[index + 1] : fallback;
        }

        private static Material SaveMaterial(string name, string shaderName)
        {
            Shader shader = Shader.Find(shaderName);
            if (shader == null) throw new InvalidOperationException("Missing shader: " + shaderName);
            string path = ResourcePath + "/" + name + ".mat";
            AssetDatabase.DeleteAsset(path);
            var material = new Material(shader);
            material.enableInstancing = true;
            if (material.HasProperty("_Glossiness")) material.SetFloat("_Glossiness", 0f);
            AssetDatabase.CreateAsset(material, path);
            return material;
        }

        [MenuItem("Terrain Probe/Prepare scene")]
        public static void Prepare()
        {
            Directory.CreateDirectory(ResourcePath);
            Directory.CreateDirectory("Assets/Generated");
            AssetDatabase.Refresh();
            SaveMaterial("MeshUnlit", "TerrainProbe/MeshUnlit");
            SaveMaterial("MeshLit", "Standard");
            Material terrainMaterial = SaveMaterial("Terrain", "Nature/Terrain/Standard");
            foreach (string name in new[] { "flat-hash", "hills-hash" })
                File.Copy("Assets/TerrainProbe/" + name + ".txt", ResourcePath + "/" + name + ".txt", true);
            // A scene Terrain keeps built-in Terrain shader dependencies in the player.
            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var data = new TerrainData { heightmapResolution = 33, size = new Vector3(1f, 1f, 1f) };
            AssetDatabase.DeleteAsset("Assets/Generated/BuildTerrain.asset");
            AssetDatabase.CreateAsset(data, "Assets/Generated/BuildTerrain.asset");
            GameObject keep = Terrain.CreateTerrainGameObject(data);
            keep.name = "Shader retention terrain (outside camera)";
            keep.transform.position = new Vector3(10000f, 0f, 10000f);
            keep.GetComponent<Terrain>().drawInstanced = true;
            keep.GetComponent<Terrain>().materialTemplate = terrainMaterial;
            new GameObject("Terrain Probe").AddComponent<TerrainProbe>();
            GraphicsSettings.defaultRenderPipeline = null;
            for (int i = 0; i < QualitySettings.names.Length; i++) {
                QualitySettings.SetQualityLevel(i, false);
                QualitySettings.renderPipeline = null;
            }
            // InstancingStrippingMode.KeepAll in Unity 2022.3.
            var graphics = new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset")[0]);
            var stripping = graphics.FindProperty("m_InstancingStripping");
            if (stripping == null) throw new InvalidOperationException("Cannot configure instancing variant retention");
            stripping.intValue = 2;
            graphics.ApplyModifiedPropertiesWithoutUndo();
            EditorSceneManager.SaveScene(scene, ScenePath);
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
        }

        public static void Build()
        {
            string api = Argument("-terrainApi", "gles3");
            bool water = Argument("-probeSuite", "terrain") == "water";
            string platform = Argument("-terrainTarget", "android");
            string output = Argument("-terrainOutput", "Builds/terrain-" + api + ".apk");
            bool windows = platform == "windows";
            if (!windows && platform != "android") throw new ArgumentException("terrainTarget must be android or windows");
            if (!windows && api != "gles3" && api != "vulkan") throw new ArgumentException("terrainApi must be gles3 or vulkan");
            BuildTarget target = windows ? BuildTarget.StandaloneWindows64 : BuildTarget.Android;
            BuildTargetGroup group = windows ? BuildTargetGroup.Standalone : BuildTargetGroup.Android;
            if (!EditorUserBuildSettings.SwitchActiveBuildTarget(group, target))
                throw new InvalidOperationException("Cannot select build target: " + target);
            Prepare();
            if (water) {
                SaveMaterial("Water", "TerrainProbe/Water");
                SaveMaterial("WaterGrab", "TerrainProbe/WaterGrab");
                foreach (var probe in UnityEngine.Object.FindObjectsOfType<TerrainProbe>())
                    UnityEngine.Object.DestroyImmediate(probe.gameObject);
                foreach (var terrain in UnityEngine.Object.FindObjectsOfType<Terrain>())
                    UnityEngine.Object.DestroyImmediate(terrain.gameObject);
                new GameObject("Water Probe").AddComponent<WaterProbe>();
                EditorSceneManager.SaveScene(SceneManager.GetActiveScene(), ScenePath);
                var plugin = AssetImporter.GetAtPath("Assets/Plugins/Android/arm64-v8a/libwater_gl.so") as PluginImporter;
                if (plugin != null) {
                    plugin.SetCompatibleWithAnyPlatform(false);
                    plugin.SetCompatibleWithEditor(false);
                    plugin.SetCompatibleWithPlatform(BuildTarget.Android, true);
                    plugin.SetPlatformData(BuildTarget.Android, "CPU", "ARM64");
                    plugin.SaveAndReimport();
                }
                AssetDatabase.SaveAssets();
            }
            PlayerSettings.companyName = "La64Diagnostics";
            PlayerSettings.productName = water ? "WaterProbe" : "TerrainProbe";
            PlayerSettings.bundleVersion = "0.1.0";
            PlayerSettings.colorSpace = ColorSpace.Gamma;
            PlayerSettings.runInBackground = true;
            PlayerSettings.defaultScreenWidth = 960;
            PlayerSettings.defaultScreenHeight = 540;
            PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
            PlayerSettings.SetUseDefaultGraphicsAPIs(target, false);
            PlayerSettings.SetGraphicsAPIs(target, new[] { windows ? GraphicsDeviceType.Direct3D11 :
                api == "vulkan" ? GraphicsDeviceType.Vulkan : GraphicsDeviceType.OpenGLES3 });
            if (!windows) {
                PlayerSettings.SetApplicationIdentifier(group, "org.la64." + (water ? "waterprobe." : "terrainprobe.") + api);
                PlayerSettings.SetScriptingBackend(group, ScriptingImplementation.IL2CPP);
                PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
                PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel26;
                // Keep the test build independent of newer SDKs the Hub may add.
                PlayerSettings.Android.targetSdkVersion = AndroidSdkVersions.AndroidApiLevel34;
                PlayerSettings.Android.forceInternetPermission = false;
                PlayerSettings.Android.useCustomKeystore = false;
                PlayerSettings.Android.buildApkPerCpuArchitecture = false;
                PlayerSettings.SetManagedStrippingLevel(group, ManagedStrippingLevel.Low);
                EditorUserBuildSettings.buildAppBundle = false;
                EditorUserBuildSettings.androidBuildSystem = AndroidBuildSystem.Gradle;
            } else {
                PlayerSettings.SetScriptingBackend(group, ScriptingImplementation.Mono2x);
            }
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions {
                scenes = new[] { ScenePath }, locationPathName = output, target = target,
                options = BuildOptions.Development
            });
            Debug.Log("TERRAIN_PROBE_BUILD " + report.summary.result + " " + output);
            if (report.summary.result != BuildResult.Succeeded)
                throw new InvalidOperationException("Terrain probe build failed: " + report.summary.result);
        }
    }
}

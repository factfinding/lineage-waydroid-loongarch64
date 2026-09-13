using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.Rendering;

namespace La64.TerrainProbe
{
    public sealed class TerrainProbe : MonoBehaviour
    {
        private sealed class Case
        {
            public string name;
            public bool mesh, flat, instanced, twoLayers, lit;
            public float pixelError = 1f;
        }

        private static readonly Case[] Cases = {
            new Case { name = "00_mesh_flat_unlit", mesh = true, flat = true },
            new Case { name = "01_mesh_hills_unlit", mesh = true },
            new Case { name = "02_mesh_hills_lit", mesh = true, lit = true },
            new Case { name = "03_terrain_flat_single", flat = true },
            new Case { name = "04_terrain_hills_single" },
            new Case { name = "05_terrain_hills_single_instanced", instanced = true },
            new Case { name = "06_terrain_hills_blended", twoLayers = true },
            new Case { name = "07_terrain_hills_blended_instanced", twoLayers = true, instanced = true },
            new Case { name = "08_terrain_hills_lod20", twoLayers = true, pixelError = 20f },
            new Case { name = "09_terrain_hills_lod20_instanced", twoLayers = true, instanced = true, pixelError = 20f }
        };

        [Serializable] private sealed class CaseRecord
        {
            public string caseName, inputHeightSha256, readbackHeightSha256, shader;
            public float heightMaxError, alphaMaxError, pixelError;
            public bool inputMatchesReference, cpuReadbackPass, instanced, shaderSupported;
            public int heightResolution, textureLayers;
        }
        [Serializable] private sealed class EnvironmentRecord
        {
            public string utc, unity, device, os, gpu, graphicsApi, graphicsVersion, processor;
            public string backend, berberisMode, artJit, outputDirectory;
            public bool supportsInstancing;
            public int pointerSize;
        }

        private Camera probeCamera;
        private GameObject subject;
        private readonly List<UnityEngine.Object> owned = new List<UnityEngine.Object>();
        private string outputDirectory, status = "Starting";
        private int caseIndex;
        private bool busy, initialized, hideUi;
        private CaseRecord record;
        private int captureSequence;

        private void Start()
        {
            Application.targetFrameRate = 30;
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
            outputDirectory = Path.Combine(Application.persistentDataPath,
                "terrain-probe-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 6));
            Directory.CreateDirectory(outputDirectory);
            Application.logMessageReceived += SaveLog;
            QualitySettings.vSyncCount = 0;
            QualitySettings.antiAliasing = 0;
            QualitySettings.shadows = ShadowQuality.Disable;
            RenderSettings.fog = false;
            RenderSettings.skybox = null;
            RenderSettings.ambientMode = AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.45f, 0.45f, 0.45f);
            probeCamera = new GameObject("Fixed camera").AddComponent<Camera>();
            probeCamera.clearFlags = CameraClearFlags.SolidColor;
            probeCamera.backgroundColor = new Color(0.04f, 0.2f, 0.6f);
            probeCamera.orthographic = true;
            probeCamera.orthographicSize = 46f;
            probeCamera.nearClipPlane = 0.1f;
            probeCamera.farClipPlane = 300f;
            probeCamera.allowHDR = false;
            probeCamera.allowMSAA = false;
            probeCamera.useOcclusionCulling = false;
            probeCamera.transform.position = new Vector3(88f, 65f, -50f);
            probeCamera.transform.LookAt(new Vector3(32f, 3f, 32f));
            var light = new GameObject("Fixed directional light").AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 1f;
            light.shadows = LightShadows.None;
            light.transform.rotation = Quaternion.Euler(48f, -35f, 0f);
            var env = new EnvironmentRecord {
                utc = DateTime.UtcNow.ToString("o"), unity = Application.unityVersion,
                device = SystemInfo.deviceModel, os = SystemInfo.operatingSystem,
                gpu = SystemInfo.graphicsDeviceName, graphicsApi = SystemInfo.graphicsDeviceType.ToString(),
                graphicsVersion = SystemInfo.graphicsDeviceVersion, processor = SystemInfo.processorType,
                supportsInstancing = SystemInfo.supportsInstancing, pointerSize = IntPtr.Size,
                outputDirectory = outputDirectory, berberisMode = AndroidProperty("berberis.mode"),
                artJit = AndroidProperty("dalvik.vm.usejit"),
#if ENABLE_IL2CPP
                backend = "IL2CPP"
#else
                backend = "Mono/editor"
#endif
            };
            File.WriteAllText(Path.Combine(outputDirectory, "environment.json"), JsonUtility.ToJson(env, true));
            Debug.Log("TERRAIN_PROBE_OUTPUT=" + outputDirectory);
            initialized = true;
            ShowCase(0);
            if (AutoRequested()) StartCoroutine(RunAll());
        }

        private static string AndroidProperty(string key)
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            try {
                using (var properties = new AndroidJavaClass("android.os.SystemProperties"))
                    return properties.CallStatic<string>("get", key, "");
            } catch (Exception e) { return "unavailable: " + e.GetType().Name; }
#else
            return "not Android";
#endif
        }

        private static bool AutoRequested()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            using (var player = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
            using (var activity = player.GetStatic<AndroidJavaObject>("currentActivity"))
            using (var intent = activity.Call<AndroidJavaObject>("getIntent"))
                return intent.Call<bool>("getBooleanExtra", "probe_auto", false);
#else
            return Array.IndexOf(Environment.GetCommandLineArgs(), "--probe-auto") >= 0;
#endif
        }

        private T Own<T>(T value) where T : UnityEngine.Object { owned.Add(value); return value; }

        private void ShowCase(int index)
        {
            if (subject != null) { subject.SetActive(false); Destroy(subject); }
            foreach (var value in owned) Destroy(value);
            owned.Clear();
            caseIndex = (index + Cases.Length) % Cases.Length;
            Case test = Cases[caseIndex];
            float[,] heights = TerrainFixture.Heights(test.flat);
            string expected = Resources.Load<TextAsset>("TerrainProbe/" + (test.flat ? "flat-hash" : "hills-hash")).text.Trim();
            string actualHash = TerrainFixture.Hash(heights);
            record = new CaseRecord {
                caseName = test.name, inputHeightSha256 = actualHash,
                inputMatchesReference = actualHash == expected, heightResolution = TerrainFixture.Resolution,
                instanced = test.instanced, pixelError = test.pixelError, textureLayers = test.twoLayers ? 2 : 1
            };
            var first = Own(Checker(new Color32(32, 190, 64, 255), new Color32(140, 230, 50, 255)));
            if (test.mesh) MakeMesh(heights, first, test.lit);
            else MakeTerrain(heights, first, test);
            record.cpuReadbackPass = record.inputMatchesReference && record.heightMaxError <= 2f / 65535f
                && record.alphaMaxError <= 2f / 255f;
            status = record.cpuReadbackPass ? "CPU data OK; inspect rendered surface" : "CPU DATA MISMATCH";
            File.WriteAllText(Path.Combine(outputDirectory, test.name + "-data.json"), JsonUtility.ToJson(record, true));
            Debug.Log("TERRAIN_PROBE_CASE " + JsonUtility.ToJson(record));
        }

        private static Texture2D Checker(Color32 a, Color32 b)
        {
            var texture = new Texture2D(64, 64, TextureFormat.RGBA32, false);
            texture.name = "Uncompressed checker";
            texture.filterMode = FilterMode.Point;
            texture.wrapMode = TextureWrapMode.Repeat;
            var pixels = new Color32[64 * 64];
            for (int y = 0; y < 64; y++)
                for (int x = 0; x < 64; x++) pixels[y * 64 + x] = (x / 8 + y / 8) % 2 == 0 ? a : b;
            texture.SetPixels32(pixels);
            texture.Apply(false, false);
            return texture;
        }

        private void MakeMesh(float[,] heights, Texture2D texture, bool lit)
        {
            int n = TerrainFixture.Resolution;
            var vertices = new Vector3[n * n];
            var uv = new Vector2[n * n];
            for (int z = 0; z < n; z++)
                for (int x = 0; x < n; x++) {
                    vertices[z * n + x] = new Vector3(x * TerrainFixture.Width / (n - 1),
                        heights[z, x] * TerrainFixture.Height, z * TerrainFixture.Width / (n - 1));
                    uv[z * n + x] = new Vector2(x * 8f / (n - 1), z * 8f / (n - 1));
                }
            var mesh = Own(new Mesh { name = "Height-equivalent mesh" });
            mesh.vertices = vertices;
            mesh.uv = uv;
            mesh.triangles = TerrainFixture.Triangles();
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            var material = Own(new Material(Resources.Load<Material>("TerrainProbe/" + (lit ? "MeshLit" : "MeshUnlit"))));
            material.mainTexture = texture;
            record.shader = material.shader.name;
            record.shaderSupported = material.shader.isSupported;
            subject = new GameObject("Mesh control");
            subject.AddComponent<MeshFilter>().sharedMesh = mesh;
            subject.AddComponent<MeshRenderer>().sharedMaterial = material;
            var readback = new float[n, n];
            var actual = mesh.vertices;
            for (int z = 0; z < n; z++)
                for (int x = 0; x < n; x++) {
                    readback[z, x] = actual[z * n + x].y / TerrainFixture.Height;
                    record.heightMaxError = Mathf.Max(record.heightMaxError, Mathf.Abs(readback[z, x] - heights[z, x]));
                }
            record.readbackHeightSha256 = TerrainFixture.Hash(readback);
        }

        private void MakeTerrain(float[,] heights, Texture2D texture, Case test)
        {
            int n = TerrainFixture.Resolution;
            var data = Own(new TerrainData { heightmapResolution = n, alphamapResolution = 64,
                baseMapResolution = 64, size = new Vector3(TerrainFixture.Width, TerrainFixture.Height, TerrainFixture.Width) });
            var layers = new List<TerrainLayer>();
            layers.Add(Own(new TerrainLayer { diffuseTexture = texture, tileSize = new Vector2(8f, 8f), smoothness = 0f }));
            if (test.twoLayers) {
                var second = Own(Checker(new Color32(210, 70, 32, 255), new Color32(235, 180, 45, 255)));
                layers.Add(Own(new TerrainLayer { diffuseTexture = second, tileSize = new Vector2(8f, 8f), smoothness = 0f }));
            }
            data.terrainLayers = layers.ToArray();
            data.SetHeights(0, 0, heights);
            float[,,] alpha = TerrainFixture.Alphamaps(64, test.twoLayers);
            data.SetAlphamaps(0, 0, alpha);
            subject = Terrain.CreateTerrainGameObject(data);
            subject.name = test.name;
            var terrain = subject.GetComponent<Terrain>();
            var material = Own(new Material(Resources.Load<Material>("TerrainProbe/Terrain")));
            material.enableInstancing = test.instanced;
            terrain.materialTemplate = material;
            terrain.drawInstanced = test.instanced;
            terrain.heightmapPixelError = test.pixelError;
            terrain.basemapDistance = 1000f;
            terrain.drawTreesAndFoliage = false;
            terrain.shadowCastingMode = ShadowCastingMode.Off;
            terrain.Flush();
            record.shader = material.shader.name;
            record.shaderSupported = material.shader.isSupported;
            var readback = data.GetHeights(0, 0, n, n);
            record.readbackHeightSha256 = TerrainFixture.Hash(readback);
            for (int z = 0; z < n; z++)
                for (int x = 0; x < n; x++)
                    record.heightMaxError = Mathf.Max(record.heightMaxError, Mathf.Abs(readback[z, x] - heights[z, x]));
            var actualAlpha = data.GetAlphamaps(0, 0, 64, 64);
            for (int z = 0; z < 64; z++)
                for (int x = 0; x < 64; x++)
                    for (int l = 0; l < layers.Count; l++)
                        record.alphaMaxError = Mathf.Max(record.alphaMaxError, Mathf.Abs(actualAlpha[z, x, l] - alpha[z, x, l]));
        }

        private IEnumerator Capture()
        {
            hideUi = true;
            yield return new WaitForEndOfFrame();
            string prefix = Cases[caseIndex].name + "-" + (++captureSequence).ToString("D3");
            // Fixed-size camera render is independent of the window's aspect ratio.
            var rt = new RenderTexture(960, 540, 24, RenderTextureFormat.ARGB32);
            var previous = RenderTexture.active;
            var oldTarget = probeCamera.targetTexture;
            float oldAspect = probeCamera.aspect;
            Texture2D pixels = null;
            try {
                probeCamera.aspect = 960f / 540f;
                probeCamera.targetTexture = rt;
                probeCamera.Render();
                RenderTexture.active = rt;
                pixels = new Texture2D(960, 540, TextureFormat.RGB24, false);
                pixels.ReadPixels(new Rect(0, 0, 960, 540), 0, 0);
                pixels.Apply();
                File.WriteAllBytes(Path.Combine(outputDirectory, prefix + "-camera.png"), pixels.EncodeToPNG());
            } finally {
                probeCamera.targetTexture = oldTarget;
                probeCamera.aspect = oldAspect;
                RenderTexture.active = previous;
                if (pixels != null) Destroy(pixels);
                rt.Release();
                Destroy(rt);
            }
            yield return new WaitForEndOfFrame();
            var screen = ScreenCapture.CaptureScreenshotAsTexture();
            File.WriteAllBytes(Path.Combine(outputDirectory, prefix + "-screen.png"), screen.EncodeToPNG());
            Destroy(screen);
            hideUi = false;
            Debug.Log("TERRAIN_PROBE_CAPTURE " + prefix);
        }

        private IEnumerator CaptureOne()
        {
            busy = true;
            yield return Capture();
            busy = false;
        }

        private IEnumerator RunAll()
        {
            busy = true;
            for (int i = 0; i < Cases.Length; i++) {
                ShowCase(i);
                // Count real frames as well as seconds; slow translation must not
                // make us capture before the first shader/draw has been submitted.
                float start = Time.realtimeSinceStartup;
                for (int frame = 0; frame < 30 || Time.realtimeSinceStartup - start < 2f; frame++) yield return null;
                yield return Capture();
            }
            File.WriteAllText(Path.Combine(outputDirectory, "COMPLETE.txt"),
                "All cases captured. Completion is NOT a visual pass.\n");
            status = "All 10 cases saved; inspect screenshots";
            Debug.Log("TERRAIN_PROBE_COMPLETE " + outputDirectory);
            busy = false;
            if (Array.IndexOf(Environment.GetCommandLineArgs(), "--probe-quit") >= 0) Application.Quit();
        }

        private void SaveLog(string message, string stack, LogType type)
        {
            try { File.AppendAllText(Path.Combine(outputDirectory, "player.log"),
                DateTime.UtcNow.ToString("o") + " " + type + " " + message + "\n" + stack + "\n"); }
            catch (IOException) { /* Do not recursively log a logging failure. */ }
        }

        private void OnDestroy() { Application.logMessageReceived -= SaveLog; }

        private void OnGUI()
        {
            if (!initialized || hideUi) return;
            GUI.matrix = Matrix4x4.Scale(new Vector3(Screen.width / 1100f, Screen.width / 1100f, 1f));
            GUILayout.BeginArea(new Rect(10, 10, 760, 180), GUI.skin.box);
            GUILayout.Label("Terrain probe: " + Cases[caseIndex].name);
            GUILayout.Label(SystemInfo.graphicsDeviceType + " | " + status);
            GUI.enabled = !busy;
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("Previous", GUILayout.Height(44))) ShowCase(caseIndex - 1);
            if (GUILayout.Button("Next", GUILayout.Height(44))) ShowCase(caseIndex + 1);
            if (GUILayout.Button("Capture", GUILayout.Height(44))) StartCoroutine(CaptureOne());
            if (GUILayout.Button("Run all", GUILayout.Height(44))) StartCoroutine(RunAll());
            GUILayout.EndHorizontal();
            GUI.enabled = true;
            GUILayout.EndArea();
        }
    }
}

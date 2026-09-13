using System;
using System.Collections;
using System.IO;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Rendering;

namespace La64.TerrainProbe
{
    public sealed class WaterProbe : MonoBehaviour
    {
        private static readonly string[] Names = {
            "00_background", "01_opaque_water", "02_alpha_blend", "03_depth_visual",
            "04_depth_fade", "05_grab_copy", "06_grab_refraction", "07_reflection_argb32",
            "08_reflection_argbhalf", "09_reflection_argbfloat", "10_four_draws", "11_four_instanced"
        };
        [Serializable] private sealed class EnvironmentRecord {
            public string unity, graphicsApi, gpu, graphicsVersion, os, backend, suite = "water";
            public int expectedCases = Names.Length;
            public bool supportsInstancing, depth, argbHalf, argbFloat;
        }
        [Serializable] private sealed class Record {
            public string caseName, shader, requestedFormat, actualFormat, skipReason;
            public bool shaderSupported, cpuReadbackPass, targetCreated, skipped;
            public int meshVertices, meshIndices;
        }
        [DllImport("water_gl")] private static extern void WaterSetPath(string path);
        [DllImport("water_gl")] private static extern IntPtr WaterGetRenderEvent();
        private Camera cameraMain, reflectionCamera;
        private GameObject surface;
        private Mesh mesh;
        private Material material;
        private RenderTexture reflection;
        private CommandBuffer diagnostics;
        private IntPtr renderEvent;
        private readonly Matrix4x4[] tiles = new Matrix4x4[4];
        private string output, status;
        private int current;
        private bool hideUi, busy;
        private Record record;

        private IEnumerator Start()
        {
            output = Path.Combine(Application.persistentDataPath,
                "water-probe-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0,6));
            Directory.CreateDirectory(output);
            Application.logMessageReceived += Log;
            Debug.Log("TERRAIN_PROBE_OUTPUT=" + output);
            Application.targetFrameRate = 30;
            QualitySettings.vSyncCount = 0; QualitySettings.antiAliasing = 0;
            QualitySettings.shadows = ShadowQuality.Disable;
            RenderSettings.fog = false; RenderSettings.skybox = null;
            RenderSettings.ambientMode = AmbientMode.Flat; RenderSettings.ambientLight = Color.white;
            cameraMain = new GameObject("Water camera").AddComponent<Camera>();
            cameraMain.transform.position = new Vector3(7,7,-9);
            cameraMain.transform.LookAt(new Vector3(0,0,0));
            cameraMain.clearFlags = CameraClearFlags.SolidColor;
            cameraMain.backgroundColor = new Color(0.07f,0.12f,0.22f);
            cameraMain.nearClipPlane = 0.1f; cameraMain.farClipPlane = 80;
            cameraMain.fieldOfView = 48;
            cameraMain.allowHDR = false; cameraMain.allowMSAA = false;
            cameraMain.depthTextureMode = DepthTextureMode.Depth;
            cameraMain.useOcclusionCulling = false;
            var sun = new GameObject("Sun").AddComponent<Light>();
            sun.type = LightType.Directional; sun.transform.rotation = Quaternion.Euler(50,-30,0);
            sun.shadows = LightShadows.None;
            // Opaque Standard materials contribute to the camera depth texture.
            for (int z=0; z<6; z++) for (int x=0; x<6; x++) {
                var floor = GameObject.CreatePrimitive(PrimitiveType.Cube);
                floor.name = "Checker floor";
                floor.transform.position = new Vector3(x-2.5f,-1.6f + z*0.14f,z-2.5f);
                floor.transform.localScale = new Vector3(1,0.25f,1);
                var m = new Material(Resources.Load<Material>("TerrainProbe/MeshLit"));
                m.color = (x+z)%2 == 0 ? new Color(0.85f,0.65f,0.13f) : new Color(0.15f,0.2f,0.27f);
                floor.GetComponent<Renderer>().sharedMaterial = m;
            }
            for (int x=0; x<3; x++) {
                var pillar = GameObject.CreatePrimitive(PrimitiveType.Cube);
                pillar.name = "Depth and reflection landmark";
                pillar.transform.position = new Vector3(x*2-2,0.4f,1.5f);
                pillar.transform.localScale = new Vector3(0.45f,3.5f,0.45f);
                var m = new Material(Resources.Load<Material>("TerrainProbe/MeshLit"));
                m.color = x==0 ? Color.red : x==1 ? Color.green : Color.blue;
                pillar.GetComponent<Renderer>().sharedMaterial = m;
            }
            mesh = new Mesh { name = "Fixed water quad" };
            mesh.vertices = new[] {new Vector3(-3,0,-3),new Vector3(-3,0,3),new Vector3(3,0,3),new Vector3(3,0,-3)};
            mesh.uv = new[] {new Vector2(0,0),new Vector2(0,1),new Vector2(1,1),new Vector2(1,0)};
            mesh.triangles = new[] {0,1,2,0,2,3}; mesh.RecalculateNormals(); mesh.RecalculateBounds();
            surface = new GameObject("Water surface"); surface.layer = 4;
            surface.AddComponent<MeshFilter>().sharedMesh = mesh;
            surface.AddComponent<MeshRenderer>();
            int t=0;
            for(int z=0;z<2;z++) for(int x=0;x<2;x++)
                tiles[t++]=Matrix4x4.TRS(new Vector3(x*3-1.5f,0,z*3-1.5f),Quaternion.identity,new Vector3(0.5f,1,0.5f));
            reflectionCamera = new GameObject("Reflection camera").AddComponent<Camera>();
            reflectionCamera.enabled = false;
#if UNITY_ANDROID && !UNITY_EDITOR
            WaterSetPath(Path.Combine(output,"gles-diagnostics.txt"));
            renderEvent = WaterGetRenderEvent();
            GL.IssuePluginEvent(renderEvent,0);
#endif
            var env = new EnvironmentRecord {
                unity=Application.unityVersion, graphicsApi=SystemInfo.graphicsDeviceType.ToString(),
                gpu=SystemInfo.graphicsDeviceName, graphicsVersion=SystemInfo.graphicsDeviceVersion,
                os=SystemInfo.operatingSystem, supportsInstancing=SystemInfo.supportsInstancing,
                depth=SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.Depth),
                argbHalf=SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.ARGBHalf),
                argbFloat=SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.ARGBFloat),
#if ENABLE_IL2CPP
                backend="IL2CPP"
#else
                backend="Mono"
#endif
            };
            File.WriteAllText(Path.Combine(output,"environment.json"),JsonUtility.ToJson(env,true));
            Show(0);
            yield return null;
            bool auto = Array.IndexOf(Environment.GetCommandLineArgs(),"--probe-auto")>=0;
#if UNITY_ANDROID && !UNITY_EDITOR
            using(var player=new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
            using(var activity=player.GetStatic<AndroidJavaObject>("currentActivity"))
            using(var intent=activity.Call<AndroidJavaObject>("getIntent"))
                auto=intent.Call<bool>("getBooleanExtra","probe_auto",false);
#endif
            if(auto) yield return RunAll();
        }

        private void Show(int index)
        {
            current=(index+Names.Length)%Names.Length;
            if(diagnostics!=null) { cameraMain.RemoveCommandBuffer(CameraEvent.AfterEverything,diagnostics); diagnostics.Release(); diagnostics=null; }
            if(reflection!=null) { reflection.Release(); Destroy(reflection); reflection=null; }
            if(material!=null) Destroy(material);
            record=new Record {caseName=Names[current],meshVertices=mesh.vertexCount,meshIndices=mesh.triangles.Length};
            material=new Material(Resources.Load<Material>("TerrainProbe/"+(current==5||current==6?"WaterGrab":"Water")));
            record.shader=material.shader.name; record.shaderSupported=material.shader.isSupported;
            record.cpuReadbackPass=mesh.vertexCount==4 && mesh.triangles.Length==6;
            surface.GetComponent<Renderer>().sharedMaterial=material;
            surface.SetActive(current>0 && current<10);
            if(current==2 || current==4) {
                material.SetInt("_Src",(int)BlendMode.SrcAlpha); material.SetInt("_Dst",(int)BlendMode.OneMinusSrcAlpha); material.SetInt("_ZWrite",0);
            }
            if(current<=4) material.SetFloat("_Mode",Mathf.Max(0,current-1));
            if(current==5||current==6) material.SetFloat("_Distortion",current==6?0.025f:0);
            if(current>=7 && current<=9) {
                var format=current==7?RenderTextureFormat.ARGB32:current==8?RenderTextureFormat.ARGBHalf:RenderTextureFormat.ARGBFloat;
                record.requestedFormat=format.ToString();
                if(!SystemInfo.SupportsRenderTextureFormat(format)) { record.skipped=true; record.skipReason="RenderTexture format not supported"; }
                else {
                    reflection=new RenderTexture(960,540,24,format);
                    record.targetCreated=reflection.Create(); record.actualFormat=reflection.format.ToString();
                    if(!record.targetCreated || reflection.format!=format) { record.skipped=true; record.skipReason="RenderTexture allocation failed or substituted format"; }
                    reflectionCamera.CopyFrom(cameraMain); reflectionCamera.enabled=false;
                    reflectionCamera.depthTextureMode=DepthTextureMode.None;
                    reflectionCamera.cullingMask=~(1<<4); reflectionCamera.targetTexture=reflection;
                    reflectionCamera.aspect=960f/540f;
                    // Mirror the view about y=0; clip away submerged geometry.
                    Matrix4x4 mirror=Matrix4x4.Scale(new Vector3(1,-1,1));
                    reflectionCamera.worldToCameraMatrix=cameraMain.worldToCameraMatrix*mirror;
                    Vector3 point=reflectionCamera.worldToCameraMatrix.MultiplyPoint(new Vector3(0,0.01f,0));
                    Vector3 normal=reflectionCamera.worldToCameraMatrix.MultiplyVector(Vector3.up).normalized;
                    reflectionCamera.projectionMatrix=reflectionCamera.CalculateObliqueMatrix(new Vector4(normal.x,normal.y,normal.z,-Vector3.Dot(point,normal)));
                    var cb=new CommandBuffer {name="Reflection GL diagnostics"};
                    if(renderEvent!=IntPtr.Zero) cb.IssuePluginEvent(renderEvent,200+current);
                    reflectionCamera.AddCommandBuffer(CameraEvent.AfterEverything,cb);
                    bool old=GL.invertCulling;
                    try { GL.invertCulling=!old; reflectionCamera.Render(); }
                    finally { GL.invertCulling=old; reflectionCamera.RemoveCommandBuffer(CameraEvent.AfterEverything,cb); cb.Release(); }
                    material.SetFloat("_Mode",4); material.SetTexture("_Reflection",reflection);
                }
            }
            if(current>=10) {
                material.SetFloat("_Mode",1); material.SetInt("_Src",(int)BlendMode.SrcAlpha);
                material.SetInt("_Dst",(int)BlendMode.OneMinusSrcAlpha); material.SetInt("_ZWrite",0);
                material.enableInstancing=current==11;
                if(current==11&&!SystemInfo.supportsInstancing) { record.skipped=true; record.skipReason="Instancing unsupported"; }
            }
            if(renderEvent!=IntPtr.Zero) {
                diagnostics=new CommandBuffer {name="Water GL diagnostics"};
                diagnostics.IssuePluginEvent(renderEvent,100+current);
                cameraMain.AddCommandBuffer(CameraEvent.AfterEverything,diagnostics);
            }
            status=record.skipped?record.skipReason:"Inspect output; data checks alone are not a visual pass";
            File.WriteAllText(Path.Combine(output,Names[current]+"-data.json"),JsonUtility.ToJson(record,true));
        }

        private void Update()
        {
            if(material==null || record.skipped || current<10) return;
            if(current==11) Graphics.DrawMeshInstanced(mesh,0,material,tiles,4,null,ShadowCastingMode.Off,false,4);
            else foreach(var matrix in tiles) Graphics.DrawMesh(mesh,matrix,material,4,null,0,null,ShadowCastingMode.Off,false);
        }

        private IEnumerator Capture()
        {
            hideUi=true;
            yield return new WaitForEndOfFrame();
            var target=new RenderTexture(960,540,24,RenderTextureFormat.ARGB32);
            var oldTarget=cameraMain.targetTexture; var oldActive=RenderTexture.active; float aspect=cameraMain.aspect;
            try {
                cameraMain.targetTexture=target; cameraMain.aspect=960f/540f; cameraMain.Render();
                SaveTexture(target,Names[current]+"-camera.png");
                if(reflection!=null) SaveTexture(reflection,Names[current]+"-reflection.png");
            } finally {
                cameraMain.targetTexture=oldTarget; cameraMain.aspect=aspect; RenderTexture.active=oldActive;
                target.Release(); Destroy(target);
            }
            yield return new WaitForEndOfFrame();
            var screen=ScreenCapture.CaptureScreenshotAsTexture();
            File.WriteAllBytes(Path.Combine(output,Names[current]+"-screen.png"),screen.EncodeToPNG()); Destroy(screen);
            hideUi=false;
        }
        private void SaveTexture(RenderTexture target,string name)
        {
            RenderTexture.active=target;
            var pixels=new Texture2D(target.width,target.height,TextureFormat.RGB24,false);
            try { pixels.ReadPixels(new Rect(0,0,target.width,target.height),0,0); pixels.Apply();
                File.WriteAllBytes(Path.Combine(output,name),pixels.EncodeToPNG()); }
            finally { Destroy(pixels); }
        }
        private IEnumerator RunAll()
        {
            busy=true;
            for(int i=0;i<Names.Length;i++) {
                Show(i); float start=Time.realtimeSinceStartup;
                for(int frame=0;frame<30 || Time.realtimeSinceStartup-start<2;frame++) yield return null;
                yield return Capture();
            }
            File.WriteAllText(Path.Combine(output,"COMPLETE.txt"),"12 cases captured; inspect images, skips and diagnostics. This is not a visual pass.\n");
            Debug.Log("TERRAIN_PROBE_COMPLETE "+output); busy=false;
            if(Array.IndexOf(Environment.GetCommandLineArgs(),"--probe-quit")>=0) Application.Quit();
        }
        private void Log(string message,string stack,LogType type)
        {
            try { File.AppendAllText(Path.Combine(output,"player.log"),type+" "+message+"\n"+stack+"\n"); }
            catch(IOException) { }
        }
        private void OnDestroy() { Application.logMessageReceived-=Log; }
        private void OnGUI()
        {
            if(output==null||hideUi) return;
            GUILayout.BeginArea(new Rect(10,10,700,170),GUI.skin.box);
            GUILayout.Label("Water probe: "+Names[current]); GUILayout.Label(status);
            GUI.enabled=!busy;
            GUILayout.BeginHorizontal();
            if(GUILayout.Button("Previous",GUILayout.Height(44))) Show(current-1);
            if(GUILayout.Button("Next",GUILayout.Height(44))) Show(current+1);
            if(GUILayout.Button("Run all",GUILayout.Height(44))) StartCoroutine(RunAll());
            GUILayout.EndHorizontal(); GUI.enabled=true; GUILayout.EndArea();
        }
    }
}

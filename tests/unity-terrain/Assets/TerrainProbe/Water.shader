Shader "TerrainProbe/Water"
{
    Properties { _Mode("Mode", Float)=0 _Src("Source blend", Float)=1 _Dst("Destination blend", Float)=0 _ZWrite("Depth write", Float)=1 _Reflection("Reflection", 2D)="black" {} }
    SubShader {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Pass {
            Cull Off ZWrite [_ZWrite] Blend [_Src] [_Dst]
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"
            struct appdata { float4 vertex:POSITION; float2 uv:TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct v2f { float4 pos:SV_POSITION; float4 screen:TEXCOORD0; float2 uv:TEXCOORD1; float eye:TEXCOORD2; };
            UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);
            sampler2D _Reflection;
            float _Mode;
            v2f vert(appdata v) {
                UNITY_SETUP_INSTANCE_ID(v);
                v2f o; o.pos=UnityObjectToClipPos(v.vertex); o.screen=ComputeScreenPos(o.pos);
                o.uv=v.uv; o.eye=-UnityObjectToViewPos(v.vertex).z; return o;
            }
            float4 frag(v2f i):SV_Target {
                if (_Mode < 0.5) return float4(0.05,0.65,0.9,1);
                if (_Mode < 1.5) return float4(0.05,0.65,0.9,0.5);
                if (_Mode < 3.5) {
                    float raw=SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture,UNITY_PROJ_COORD(i.screen));
                    float gap=max(0,LinearEyeDepth(raw)-i.eye);
                    if (_Mode < 2.5) return float4(saturate(gap/5),saturate(gap/2),0.1,1);
                    return float4(0.03,0.5,0.8,saturate(gap/2)*0.8);
                }
                return tex2D(_Reflection,i.screen.xy/i.screen.w);
            }
            ENDCG
        }
    }
}

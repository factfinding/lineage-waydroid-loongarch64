Shader "TerrainProbe/WaterGrab"
{
    Properties { _Distortion("Distortion", Float)=0 }
    SubShader {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        GrabPass { "_WaterProbeGrab" }
        Pass {
            Cull Off ZWrite Off
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            struct v2f { float4 pos:SV_POSITION; float4 grab:TEXCOORD0; float2 uv:TEXCOORD1; };
            sampler2D _WaterProbeGrab; float _Distortion;
            v2f vert(appdata_base v) {
                v2f o; o.pos=UnityObjectToClipPos(v.vertex);
                o.grab=ComputeGrabScreenPos(o.pos); o.uv=v.texcoord.xy; return o;
            }
            float4 frag(v2f i):SV_Target {
                float2 offset=float2(sin(i.uv.y*35),cos(i.uv.x*27))*_Distortion;
                i.grab.xy+=offset*i.grab.w;
                return tex2Dproj(_WaterProbeGrab,UNITY_PROJ_COORD(i.grab));
            }
            ENDCG
        }
    }
}

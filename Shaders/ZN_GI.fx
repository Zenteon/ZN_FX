#include "ReShade.fxh"


//============================================================================================
#define rayL 3	//How many Lods are checked during sampling, pretty big performance impact
//============================================================================================

uniform float FarPlane <
	ui_type = "slider";
	ui_min = 1.1;
	ui_max = 3000.0;
	ui_label = "Far Plane";
	ui_tooltip = "Adjust max depth for depth buffer";
	ui_category = "Depth Buffer Settings";
> = 1000.0;

uniform float NearPlane <
	ui_type = "slider";
	ui_min = 1.1;
	ui_max = 1000.0;
	ui_label = "Near Plane";
	ui_tooltip = "Adjust min depth for depth buffer";
	ui_category = "Depth Buffer Settings";
> = 1.0;

uniform float Intensity <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Intensity";
	ui_tooltip = "Intensity of the effect";
	ui_category = "Display";
> = 0.2;

uniform float AmbientNeg <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 0.5;
	ui_label = "Ambient light offset";
	ui_tooltip = "Removes ambient light before applying GI";
	ui_category = "Display";
> = 0.06;

uniform float LightEx <
	ui_type = "slider";
	ui_min = 1.0;
	ui_max = 2.2;
	ui_label = "LightEx";
	ui_tooltip = "Converts lightmap to linear, lower slightly if you see extra banding when enabling the effect";
	ui_category = "Display";
> = 2.2;

uniform float distMask <
	ui_type = "slider";
	ui_label = "Distance Mask";
	ui_tooltip = "Prevents washing out of clouds, and reduces artifacts from fog";
	ui_category = "Display";
> = 0.0;

uniform bool useDirectionalLight <
	ui_label = "Directional Light";
	ui_tooltip = "More accurate calculation to improve visual quality || Heavy Performance Impact";
	ui_category = "Sampling";
> = 1;

uniform int sLod <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 2;
	ui_label = "Starting LOD";
	ui_tooltip = "Changes the starting LOD value, increases sample range at the cose of fine details \n"
"Aliasing artifacts can be very noticable || Moderate Performance impact";
	ui_category = "Sampling";
> = 0;

uniform int rayT <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 10;
	ui_label = "Ray step count";
	ui_tooltip = "Ray steps per LOD, Increases range without detail loss \n" 
"Recommended to change incrementally with 'Ray Range' when increasing || Very Heavy Performance impact";
	ui_category = "Sampling";
> = 0;

uniform float rayD <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 10.0;
	ui_label = "Brightness multiplier";
	ui_tooltip = "How bright light sources are. Different from intensity || No Performance impact";
	ui_category = "Sampling";
> = 5.0;

uniform float sampR <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 20.0;
	ui_label = "Ray Range";
	ui_tooltip = "Increases GI range without detail loss, may create noise at higher levels || Low Performance impact";
	ui_category = "Sampling";
> = 8.0;

uniform bool debug <
	ui_label = "Debug";
	ui_tooltip = "Displays GI";
> = 0;


//============================================================================================
//Textures and samplers
//============================================================================================
texture BlueNoiseTex < source = "ZNbluenoise512.png"; >
{
	Width  = 512.0;
	Height = 512.0;
	Format = RGBA8;
};
texture NorTex{Width = BUFFER_WIDTH / 1; Height = BUFFER_HEIGHT / 1; Format = RGBA8; MipLevels = 1;};
texture BufTex{Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = R16; MipLevels = 7;};
texture LumTex{Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA8; MipLevels = 7;};
texture HalfTex{Width = BUFFER_WIDTH / 1.; Height = BUFFER_HEIGHT / 1.; Format = RGBA8; MipLevels = 2;};
texture NorHalfTex{Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA8; MipLevels = 7;};



sampler NormalSam{Texture = NorTex;};
sampler BufferSam{Texture = BufTex;};
sampler LightSam{Texture = LumTex;};
sampler NoiseSam{Texture = BlueNoiseTex;};
sampler HalfSam{Texture = HalfTex;};
sampler NorHalfSam{Texture = NorHalfTex;};

//============================================================================================
//Buffer Definitions
//============================================================================================

//Saves LightMap and LODS
float4 LightMap(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float p = LightEx;
	float3 te = tex2D(ReShade::BackBuffer, texcoord).rgb;
	return float4(pow(te, p), 1.0);
}

//Saves DepthBuffer and LODS
float LinearBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float f = FarPlane;
	float n = NearPlane;
	float depth = ReShade::GetLinearizedDepth(texcoord);
	depth = lerp(n, f, depth);
	return depth / (f - n);
}

//Generates Normal Buffer from depth
float4 NormalBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 uvd = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float vc =  ReShade::GetLinearizedDepth(texcoord);
	 
	float vx;
	float vxl = vc - ReShade::GetLinearizedDepth(texcoord + float2(-1, 0) / uvd);	
	float vxl2 = vc - ReShade::GetLinearizedDepth(texcoord + float2(-2, 0) / uvd);
	float exlC = lerp(vxl2, vxl, 2.0);
	
	float vxr = vc - ReShade::GetLinearizedDepth(texcoord + float2(1, 0) / uvd);
	float vxr2 = vc - ReShade::GetLinearizedDepth(texcoord + float2(2, 0) / uvd);
	float exrC = lerp(vxr2, vxr, 2.0);
	
	if(abs(exlC - vc) > abs(exrC - vc)) {vx = -vxl;}
	else {vx = vxr;}
	
	float vy;
	float vyl = vc - ReShade::GetLinearizedDepth(texcoord + float2(0, -1) / uvd);
	float vyl2 = vc - ReShade::GetLinearizedDepth(texcoord + float2(0, -2) / uvd);
	float eylC = lerp(vyl2, vyl, 2.0);
	
	float vyr = vc - ReShade::GetLinearizedDepth(texcoord + float2(0, 1) / uvd);
	float vyr2 = vc - ReShade::GetLinearizedDepth(texcoord + float2(0, 2) / uvd);
	float eyrC = lerp(vyr2, vyr, 2.0);
	
	if(abs(eylC - vc) > abs(eyrC - vc)) {vy = -vyl;}
	else {vy = vyr;}
	
	return float4(0.5 + 0.5 * normalize(float3(vx, vy, vc / FarPlane)), 1.0);
}

//Saves Normal Buffer LODS
float4 NormalLods(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 normal = tex2D(NormalSam, texcoord).rgb;
	return float4(normal, 1.0);
}

//============================================================================================
//Lighting Calculations
//============================================================================================

float3 sampGI(float2 coord, float3 offset)
{
    float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	
	float3 dir[8]; //Clockwise from verticle
	dir[0] = normalize(float3(-1, -1, 0) + 1.0 * offset);
    dir[1] = normalize(float3(-1, 0, 0) + 1.0 * offset);
    dir[2] = normalize(float3(-1, 1, 0) + 1.0 * offset);
    dir[3] = normalize(float3(0, -1, 0) + 1.0 * offset);
    dir[4] = normalize(float3(0, 1, 0) + 1.0 * offset);
    dir[5] = normalize(float3(1, -1, 0) + 1.0 * offset);
    dir[6] = normalize(float3(1, 0, 0) + 1.0 * offset);
    dir[7] = normalize(float3(1, 1, 0) + 1.0 * offset);
    
    float rayS;
    float3 ac;
    float3 map;
 
    for(rayS = sLod; rayS <= (rayL + sLod); rayS++)
    {
        
		float depth = tex2D(BufferSam, coord).r;
		float trueDepth = ReShade::GetLinearizedDepth(coord);    
		float3 surfN = normalize(1.0 - 2.0 * tex2D(NormalSam, coord).rgb);
		float3 normal = surfN;
		
	        for(int i = 0; i < 8; i++)
	        {
	            
				
				
	            for(int ii = 0; ii <= rayT; ii++)
	            {   
					float3 moDir = float3(surfN.xy, 0) + float3(dir[i].x, dir[i].y, 0.0);
					
					float3 rayP = float3(coord, depth);
					rayP += (ii + 1.0) * sampR * (offset.r + 1.5) * pow(2.0, rayS) * (normalize(moDir)) / float3(res, 1.0);
	    			 
					depth = tex2Dlod(BufferSam, float4(rayP.xy, rayS, rayS)).r;           
					map = tex2Dlod(LightSam, float4(rayP.xy, rayS, rayS)).rgb;
					
					
					
					
			
					
					
	                float3 pAc = saturate(map);
	                pAc /= 1.0 + pow(1.0 * (FarPlane - NearPlane) * abs(rayP.z - depth), 2.0);
					
					
					if(useDirectionalLight == 1)//Weak SS Global Illumination algorith
					{
						
						float3 rayD = float3(coord, trueDepth) - rayP;
						rayD = normalize(rayD);
						normal = 1.0 - 2.0 * tex2Dlod(NorHalfSam, float4(rayP.xy, ceil(rayS /rayL), ceil(rayS / rayL))).rgb;
						
						float3 directionalDif = 0.5 * (1.0 + dot(surfN, rayD) * dot(surfN, normal));
						ac += directionalDif * pAc;
					}
					
					else //Strong ambient occlusion algorithm
					{
						float3 rayD = float3(coord, trueDepth) - rayP;
						rayD = normalize(rayD);
						
						float3 ambientDif = 0.5 * (1.0 + dot(surfN, rayD));
						ac += ambientDif * pAc;
					}
						
					
	            }	             
	        }
        
    }
    ac /= 8 * (rayL + sLod); //rayD * pow(2.0, rayS - sLod);
    ac *= rayD;
	return pow((ac * sqrt(rayL)) / (rayT + 1.0), 1.0 / 2.2);
}
//GI Texture
float4 GlobalPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 aspectPos= float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float3 noise = tex2D(NoiseSam, frac(texcoord * (aspectPos / 512))).rgb;
	float3 input = sampGI(texcoord, (noise - 0.5));
	return float4(clamp(input, 0.0, 1.0), 1.0);
}

float3 ZN_Stylize_FXmain(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 bxy= float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	
	float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;
	float3 noise = tex2D(NoiseSam, frac(0.5 + texcoord * (bxy / 512))).rgb;
	float3 light = tex2D(LightSam, texcoord).rgb;
	float depth = tex2D(BufferSam, texcoord).r;
	
	float lightG = light.r * 0.2126 + light.g * 0.7152 + light.b * 0.0722;
	
	float3 GI = tex2Dlod(HalfSam, float4(texcoord, 1, 1)).rgb;
	GI *= 1.0 - pow(depth, 1.0 - distMask);
	input = input * abs(debug - 1.0) + Intensity * (clamp(GI - noise * 0.05 - lightG, 0.0, 1.0) - AmbientNeg* abs(debug - 1.0));
	return input;
}

technique ZN_SDIL
<
    ui_label = "ZN_SDIL";
    ui_tooltip =        
        "             Zentient - Screen Space Directional Indirect Lighting             \n"
        "\n"
        "\n"
        "A relatively lightweight Screen Space Global Illumination implementation that samples LODS\n"
        "\n"
        "\n";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = LightMap;
		RenderTarget = LumTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = LinearBuffer;
		RenderTarget = BufTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = NormalBuffer;
		RenderTarget = NorTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = NormalLods;
		RenderTarget = NorHalfTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = GlobalPass;
		RenderTarget = HalfTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = ZN_Stylize_FXmain;
	}
}

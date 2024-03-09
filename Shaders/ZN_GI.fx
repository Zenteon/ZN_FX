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
> = 2000.0;

uniform float NearPlane <
	ui_type = "slider";
	ui_min = 1.1;
	ui_max = 1000.0;
	ui_label = "Near Plane";
	ui_tooltip = "Adjust min depth for depth buffer";
	ui_category = "Depth Buffer Settings";
> = 25.0;

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
	ui_max = 1.0;
	ui_label = "Ambient light offset";
	ui_tooltip = "Removes ambient light before applying GI";
	ui_category = "Display";
> = 0.1;

uniform float LightEx <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 5.0;
	ui_label = "LightEx";
	ui_tooltip = "Lightmap contrast";
	ui_category = "Display";
> = 2.2;

uniform float distMask <
	ui_type = "slider";
	ui_label = "Distance Mask";
	ui_tooltip = "Prevents washing out of clouds, and reduces artifacts from fog";
	ui_category = "Display";
> = 0.0;

uniform int sLod <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 4;
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
"Recommended to increase incrementally with 'Ray Range' || Heavy Performance impact";
	ui_category = "Sampling";
> = 0;

uniform float rayD <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 1.0;
	ui_label = "Light Dropoff";
	ui_tooltip = "How quickly light dissipates || No Performance impact";
	ui_category = "Sampling";
> = 0.9;

uniform float sampR <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 10.0;
	ui_label = "Ray Range";
	ui_tooltip = "Increases GI range without detail loss, may create noise at higher levels || Moderate-Heavy Performance impact";
	ui_category = "Sampling";
> = 3.0;



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
texture NorTex{Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; MipLevels = 1;};
texture BufTex{Width = BUFFER_WIDTH / 1; Height = BUFFER_HEIGHT / 1; Format = R16; MipLevels = 3;};
texture LumTex{Width = BUFFER_WIDTH / 1; Height = BUFFER_HEIGHT / 1; MipLevels = 3;};
texture HalfTex{Width = BUFFER_WIDTH / 1.; Height = BUFFER_HEIGHT / 1.; MipLevels = 2;};



sampler NormalSam{Texture = NorTex;};
sampler BufferSam{Texture = BufTex;};
sampler LightSam{Texture = LumTex;};
sampler NoiseSam{Texture = BlueNoiseTex;};
sampler HalfSam{Texture = HalfTex;};

//============================================================================================
//Buffer Definitions
//============================================================================================

//Saves LightMap and LODS
float3 LightMap(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float p = LightEx;
	float3 te = tex2D(ReShade::BackBuffer, texcoord).rgb;
	return pow(te, p);
}

//Saves DepthBuffer and LODS
float3 LinearBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float f = FarPlane;
	float n = NearPlane;
	float depth = ReShade::GetLinearizedDepth(texcoord);
	depth = lerp(n, f, depth);
	return depth / (f - n);
}

//Generates Normal Buffer from depth
float3 NormalBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
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
	
	return 0.5 + 0.5 * normalize(float3(vx, vy, vc / FarPlane));
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
 
    for(int i = 0; i < 8; i++)
    {
        
		float depth = tex2D(BufferSam, coord).r;
		float trueDepth = ReShade::GetLinearizedDepth(coord);
		float3 rayP = float3(coord, depth);           
		float3 surfN = tex2D(NormalSam, coord).rgb;
		int scn = 0;
	        for(int ii = 0; ii <= rayT; ii++)
	        {
	            
				
				
	            for(rayS = sLod; rayS <= (rayL + sLod); rayS++)
	            {   
					float3 moDir = float3(dir[i].x, dir[i].y, 0.0);
					rayP += sampR * (offset.r + 1.5) * pow(2.0, rayS) * (normalize(moDir)) / float3(res, 1.0);
	    			
					depth = tex2Dlod(BufferSam, float4(rayP.xy, (rayS), (rayS))).r;           
					map = tex2Dlod(LightSam, float4(rayP.xy, (rayS), (rayS))).rgb;
					
					float3 rayD = normalize((rayP - float3(coord, trueDepth) * depth) * FarPlane);
					float3 curN = dot(rayD, surfN);
					
	                float3 pAc = saturate(map);
	                pAc /= (1.0 + pow(0.1 * (FarPlane - NearPlane) * abs(rayP.z - depth), 2.0));//Power is higher than two to reduce depth artifacts
					ac += curN * pAc;
					
	            }	             
	        }
        
    }
    ac /= rayD * pow(2.0, rayS - sLod);
	return ac * sqrt(rayL);
}

float3 GlobalPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 aspectPos= float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float3 noise = tex2D(NoiseSam, frac(texcoord * (aspectPos / 512))).rgb;
	float3 input = sampGI(texcoord, (noise - 0.5));
	return clamp(input, 0.0, 1.0);
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
	input = input * abs(debug - 1.0) + Intensity * (clamp(pow(GI, 1.0 / LightEx) - noise * 0.05 - lightG, 0.0, 1.0) - AmbientNeg* abs(debug - 1.0));
	return input;
}

technique ZN_SDIL
<
    ui_label = "ZN_SDIL";
    ui_tooltip =        
        "             Zentient - Screen Space Directional Indirect Lighting             \n"
        "\n"
        "\n"
        "Diffuse directional occlusion that samples the backbuffer for indirect lighting\n"
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
		PixelShader = GlobalPass;
		RenderTarget = HalfTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = ZN_Stylize_FXmain;
	}
}

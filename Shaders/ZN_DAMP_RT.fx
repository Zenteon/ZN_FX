/*
ZN Depth Aware Mipmapped Ray Tracing (DAMP RT), by Zenteon 

Techniques used, papers inpiring, and information aquired:
https://atyuwen.github.io/posts/normal-reconstruction/


*/
#include "ReShade.fxh"

#ifndef ZNRY_SAMPLE_DIV
//============================================================================================
	#define ZNRY_SAMPLE_DIV 4 //Sample Texture Resolution Divider
//============================================================================================
#endif


#ifndef ZNRY_RENDER_SCL
//============================================================================================
	#if(BUFFER_HEIGHT <= 720)
		#define ZNRY_RENDER_SCL 100 //Render Scale (percent)
	#elif(BUFFER_HEIGHT <= 960)
		#define ZNRY_RENDER_SCL 89
	#elif(BUFFER_HEIGHT <= 1080)
		#define ZNRY_RENDER_SCL 80
	#elif(BUFFER_HEIGHT <= 1440)
		#define ZNRY_RENDER_SCL 67
	#elif(BUFFER_HEIGHT <= 2160)
		#define ZNRY_RENDER_SCL 50
	#else
		#define ZNRY_RENDER_SCL 40 
	#endif
//============================================================================================
#endif

#ifndef ZNRY_MAX_LODS
//============================================================================================
	#define ZNRY_MAX_LODS 6 //How many Lods are checked during sampling, moderate impact
//============================================================================================
#endif

uniform int ZN_DAMPRT <
	ui_label = " ";
	ui_text = "Zentient DAMP RT (Depth Aware Mipmapped Ray Tracing) is a shader built around\n"
			"sampling miplevels in order to approximate cone tracing in 2D space before\n"
			"extrapolating the data into 3D based on depth information. \n"
			"While not directly taken from any papers, it was heavily inspired after seeing\n"
			"Alexander Sannikov's approach to calculating GI with radiance cascasdes.\n";
	ui_type = "radio";
	ui_category = "ZN DAMP RT";
	ui_category_closed = true;
> = 1;  

uniform float BUFFER_SCALE <
	ui_type = "slider";
	ui_min = 0.5;
	ui_max = 5.0;
	ui_label = "Buffer Scale";
	ui_tooltip = "Adjustst the accuracy of the depth buffer for closer objects";
	ui_category = "Depth Buffer Settings";
	ui_category_closed = true;
> = 2.0;

uniform float NEAR_PLANE <
	ui_type = "slider";
	ui_min = -1.0;
	ui_max = 2.0;
	ui_label = "Near Plane";
	ui_tooltip = "Adjust min depth for depth buffer, increase slightly if dark lines or occlusion artifacts are visible";
	ui_category = "Depth Buffer Settings";
> = 0.0;

uniform float FOV <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 110.0;
	ui_label = "FOV";
	ui_tooltip = "Adjust to match ingame FOV";
	ui_category = "Depth Buffer Settings";
	ui_step = 1;
> = 70;

uniform float INTENSITY <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "GI Intensity";
	ui_tooltip = "Intensity of the effect";
	ui_category = "Display";
> = 0.5;

uniform int TONEMAPPER <
	ui_type = "combo";
	ui_items = "ZN Filmic\0Sony A7RIII\0ACES\0Reinhardt\0None\0Contrast\0";
	ui_label = "Tonemapper";
	ui_tooltip = "Tonemapper Selection, Select 'None' if image becomes too dark or saturated";
	ui_category = "Display";
> = 4;

uniform float AMBIENT_NEG <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 0.3;
	ui_label = "Ambient Reduction";
	ui_tooltip = "Removes ambient light before adding GI to the image";
	ui_category = "Display";
> = 0.05;

uniform float DEPTH_MASK <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Depth Mask";
	ui_tooltip = "Depth dropoff to allow compatibility with in game fog";
	ui_category = "Display";
> = 0.0;	

uniform int DO_DENOISING <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 2;
	ui_label = "Denoising";
	ui_tooltip = "Runs a denoising pass at '1' and an edge aware denoiser at '2' || Moderate Performance Impact"; 
	ui_category = "Sampling";
> = 1;

uniform bool SHADOW <
	ui_label = "Shadows";
	ui_tooltip = "Rejects some samples to cast soft shadows, essentially a pretty nice AO || No Performance Impact";
	ui_category = "Sampling";
> = 1;

uniform float SHADOW_BIAS <
	ui_type = "slider";
	ui_label = "Shadow Bias";
	ui_tooltip = "Reduces artifacts and intensity of shadows";
	ui_category = "Sampling";
	ui_min = -0.01;
	ui_max = 0.01;
> = 0.001;

uniform float DIRECT_BIAS <
	ui_type = "slider";
	ui_label = "Direct Bias";
	ui_tooltip = "Modifies light levels for sampling. 0.0 is more realistic, in most cases 1.0 looks better and is more stable.";
	ui_category = "Sampling";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.95;

uniform bool REMOVE_DIRECTL <
	ui_label = "Brightness Mask";
	ui_tooltip = "Prevents excessive illumination in already lit areas || No Performance Impact";
	ui_category = "Sampling";
> = 0;

uniform bool BLOCK_SCATTER <
	ui_label = "Block Scattering";
	//hidden = true;
	ui_tooltip = "Takes into account extra information about sampled surfaces || Low-Medium Performance Impact";
	ui_category = "Sampling";
> = 1;

uniform float RAY_LENGTH <
ui_type = "slider";
	ui_min = 0.1;
	ui_max = 10.0;
	ui_label = "Ray Step Length";
	ui_tooltip = "Changes the length of ray steps per Mip, reduces overall sample quality but increases shadow presence || Moderate Performance Impact"; 
	ui_category = "Sampling";
> = 2.0;

uniform float DISTANCE_SCALE <
ui_type = "slider";
	ui_min = 0.01;
	ui_max = 10.0;
	ui_label = "Distance Scale";
	ui_tooltip = "The scale at which brightness calculations are made"; 
	ui_category = "Sampling";
> = 2.0;

uniform int DEBUG <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 3;
> = 0;

uniform bool SHOW_MIPS <
	ui_label = "Display Mipmaps";
	ui_tooltip = "Just for fun, for anyone wanting to visualize how it works\n"
		"recommended to turn off denoising and use debug view 2";
> = 0;

uniform int PREPRO_SETTINGS <
	ui_type = "radio";
	ui_text = "Preprocessor Definition Guide:\n"
			"\n"
			"ZNRY_MAX_LODS - The maximum LOD sampled, has a direct performance impact, and an exponential impact on ray range. Max is 8\n"
			"\n"
			"ZNRY_RENDER_SCL - The resolution scale for GI, default is automatically selected based on resolution, changes may require reloading ReShade.\n"
			"\n"
			"ZNRY_SAMPLE_DIV - The resolution divider for sampled textures. (ex, 4 is 1/4 resolution, 2 is half resolution, 1 is full resolution\n"
			"This has a massive performance impact, with minimal quality drops, not recommended to increase past half resolution";
> = 1;

//============================================================================================
//Textures/Samplers
//=================================================================================

texture RYBlueNoiseTex < source = "ZNbluenoise512.png"; >
{
	Width  = 512.0;
	Height = 512.0;
	Format = RGBA8;
};
texture RYNorTex{Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 1;};
texture RYNorDivTex{Width = BUFFER_WIDTH / ZNRY_SAMPLE_DIV; Height = BUFFER_HEIGHT / ZNRY_SAMPLE_DIV; Format = RGBA8; MipLevels = 9;};
texture RYBufTex{Width = BUFFER_WIDTH / ZNRY_SAMPLE_DIV; Height = BUFFER_HEIGHT / ZNRY_SAMPLE_DIV; Format = R16; MipLevels = 9;};
texture RYLumTex{Width = BUFFER_WIDTH / ZNRY_SAMPLE_DIV; Height = BUFFER_HEIGHT / ZNRY_SAMPLE_DIV; Format = RGBA8; MipLevels = 9;};
texture RYGITex{Width = BUFFER_WIDTH * (ZNRY_RENDER_SCL / 100.0); Height = BUFFER_HEIGHT * (ZNRY_RENDER_SCL / 100.0); Format = RGBA8; MipLevels = 1;};
texture RYBlurTex1{Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 2;};
texture RYBlurTex2{Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 1;};


sampler NoiseSam{Texture = RYBlueNoiseTex;};
sampler NorSam{Texture = RYNorTex;};
sampler NorDivSam{Texture = RYNorDivTex;};
sampler DepSam{Texture = RYBufTex;};
sampler LumSam{Texture = RYLumTex;};
sampler BlurSam1{Texture = RYBlurTex1;};
sampler BlurSam2{Texture = RYBlurTex2;};
sampler GISam{Texture = RYGITex;};

//============================================================================================
//Tonemappers
//============================================================================================


float3 SONYA7RIII(float3 z) //This is a custom tonemapper, it doesn't look great, which is funny
{
    float a = 0.1;
    float b = 1.1;
    float c = 0.5;
    float3 d = float3(0.02, 0.01, 0.02);
    float e = 1.3;
    float f = 4.8;
    float g = 0.3;
    float h = 2.0;
    float i = 0.2;
    float j = 0.6;
    float k = 1.3;
    float l = 2.5;
    
    z *= 20.0;
    
    z = h*(c+pow(a*z,b)-d*(sin(e*z)-j)/((k*z-f)*(k*z-f)+g));
    z = pow(z, l);
    z = i*log(z);
    
    return saturate(z);
}


float3 ZNFilmic(float3 x)
{
	float a = 17.36;
	float b = 16.667;
	float c = 6.0;
	float d = 0.4;
	return saturate((a*x*x+d*x) / (b*x*x + c*x + 1.0));
}


float3 ACESFilm(float3 x)
{
float a = 2.51f;
float b = 0.03f;
float c = 2.43f;
float d = 0.59f;
float e = 0.14f;
return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

//============================================================================================
//Functions
//============================================================================================

float3 eyePos(float2 xy, float z, float2 pw)//takes screen coords (0-1) and depth (0-1) and converts to eyespace position
{
	float fn = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - 1.0;
	float2 nxy = 2.0 * xy - 1.0;
	float3 vv = normalize(float3(nxy, 1.0));
	//float3 eyp = float3(nxy * pw * z, fn * z);
	float3 eyp = float3(vv * (fn * z));
	return eyp;
}


float3 DAMPGI(float2 xy, float2 offset)
{
	float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float f = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
	float n = NEAR_PLANE;
	float2 PW = 2.0 * tan(FOV * 0.00875) * (f - n); //Dimensions of FarPlane
	PW.y *= res.x / res.y;
	
	
	int LODS = ZNRY_MAX_LODS;
	float2 dir[8]; //Clockwise from verticle
    dir[0] = float2(0.0, 1.0);
    dir[1] = float2(0.7071, 0.7071);
    dir[2] = float2(1.0, 0.0);
    dir[3] = float2(0.7071, -0.7071);
    dir[4] = float2(0.0, -1.0);
    dir[5] = float2(-0.7071, -0.7071);
    dir[6] = float2(-1.0, 0.0);
    dir[7] = float2(-0.7071, 0.7071);
    
    float trueD = ReShade::GetLinearizedDepth(xy);
    float3 surfN = normalize(2.0 * tex2D(NorSam, xy).rgb - 1.0);
    float d = trueD;
    float3 rp = float3(xy, d);
    float3 l;
    
    for(int i = 0; i < 8; i++){
    	
    	d =  trueD;
    	int iLOD = 0;
    	rp = float3(xy, d);
    	float3 minD  = rp;//float3(0.0, 0.0, 1.0);
    	float3 maxD = 0.0;
    	
 		for(int ii = 2; ii <= LODS; ii++)
    	{
    		
    		//Max shadow vector calculation
    		//if((minD - float3(xy, trueD)).z < (rp - float3(xy, trueD)).z) {minD = rp;}
    		float3 compVec0 = normalize(0.000000001 + rp - float3(xy, trueD));
    		float3 compVec1 = normalize(0.000000001 + minD - float3(xy, trueD));
    		//if(abs(compVec0.x) < abs(compVec1.x)) {minD = rp;}
    		//if(abs(compVec0.y) < abs(compVec1.y)) {minD = rp;}
    		if(compVec0.z <= compVec1.z) {minD = rp;}//d <= trueD && 
    		
    		compVec0 = rp - float3(xy, trueD);
    		compVec1 = minD - float3(xy, trueD);
    		
			//Ray vector and depth calculations
			float2 rd = offset.xy * abs(SHOW_MIPS - 1.0);   
    		rp.xy += (RAY_LENGTH * (dir[i] + rd) * pow(2, ii)) / res;
    		if(rp.x > 1.0 || rp.y > 1.0) {break;}
    		if(rp.x < 0 || rp.y < 0) {break;}
    		
    		//float3 rpq = round((rp.xy * res) / pow(2.0, iLOD + 1.0)) / (res / pow(2.0, iLOD + 1.0);
    		
			d = tex2Dlod(DepSam, float4(rp.xy, 0, iLOD)).r;
    		d = pow(d, BUFFER_SCALE);
    		rp.z = d;
    		
    		
    		//Occlusion calculations
   		 int sh;
   		 int sh2;
   		 if(SHADOW == 0) {sh = 1; sh2 = 1;}
   		 float3 eyeXY = eyePos(rp.xy, rp.z, PW);
			float3 texXY = eyePos(xy, trueD, PW);
   		 float3 shvMin = normalize(minD - float3(xy, trueD));
   		 float3 shvMax = normalize(float3(xy, trueD) - maxD);
   		 float shd = distance(rp, float3(xy, trueD));
   		 
   		 //if(rp.z < trueD && d < (trueD + shd * shvMin.z) + SHADOW_BIAS) {sh = 1;}
   		 if(d < (trueD + shd * shvMin.z) + SHADOW_BIAS) {sh = 1;}
			if(trueD < (d + shd * shvMax.z) + SHADOW_BIAS) {sh2 = 1;}
			//if(d > trueD) {sh2 = 1;}
			if(sh == 1)
			{
				float3 col = tex2Dlod(LumSam, float4(rp.xy, 0, iLOD)).rgb;
				float smb = 1.0;
				if(BLOCK_SCATTER == 1)
				{
					float3 nor = 2.0 * tex2Dlod(NorDivSam, float4(rp.xy, 0, iLOD)).rgb - 1.0;
					smb = 0.5 + 0.5 * dot(-surfN, nor);
					smb *= 4.0;
				}
				
				float ed = 1.0 + pow(DISTANCE_SCALE * distance(texXY, 0.0), 2.0) / f;
				//float pd = 1.0 + 1.0 * distance(rp.xy, xy);
				float cd = 1.0 + (pow(DISTANCE_SCALE * distance(eyeXY, texXY), 2.0)) / f;
				float amb = 0.5 + 0.5 * dot(surfN, normalize(rp - float3(xy, trueD)));
				
				col *= ed;
				l += (pow(4.0, iLOD) / 4.0) * smb * amb * (col / (ed * cd));
			}
			
			iLOD++;
    		
    	}}
    	
	l = pow(l / (2.0 * pow(2.0, LODS)), 1.0 / 2.2);
	return l;
}


float3 tonemap(float3 input)
{
	if(TONEMAPPER == 4) {return input;}
	input = pow(saturate(input), 2.2);
	input = clamp(-input / (input - 1.6), 0.0, 1.0);
	if(TONEMAPPER == 0) {input = ZNFilmic(input);}
	if(TONEMAPPER == 1){input = SONYA7RIII(input);}
	if(TONEMAPPER == 2){input = ACESFilm(input);}
	if(TONEMAPPER == 3){input = input / (input + 0.5);}
	if(TONEMAPPER == 5){input = pow(input, 0.5 * input + 1.0);}
	return pow(input, 1.0 / 2.2);
}


float3 BlendGI(float3 input, float3 GI, float depth)
{
	GI *= 1.0 - pow(depth, 1.0 - DEPTH_MASK * 0.5) * DEPTH_MASK;
	float3 ICol = lerp(normalize(input) / 0.577, input, 0.5 + 0.5 * DIRECT_BIAS);
	float ILum = (input.r + input.g + input.b) / 3.0;
	float GILum = (GI.r + GI.g + GI.b) / 3.0;
	
	if(REMOVE_DIRECTL == 0) {ILum = 0.0;}
	
	if(DEBUG == 1) {input = (GI- ILum) * ICol - (INTENSITY * AMBIENT_NEG);}
	else if(DEBUG == 2) {input = GI;}
	else if(DEBUG == 3) {input = pow(lerp(1.0, GI, GILum), 3.0);}
	else{input += (INTENSITY * (GI - ILum) * ICol) - (INTENSITY * AMBIENT_NEG);}
	
	return input;
}

float eyeDis(float2 xy, float2 pw)
{
	return eyePos(xy, ReShade::GetLinearizedDepth(xy), pw).z;
}


//============================================================================================
//Buffer Definitions
//============================================================================================

//Saves LightMap and LODS
float4 LightMap(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float p = 2.2;
	float3 te = tex2D(ReShade::BackBuffer, texcoord).rgb;
	te = pow(te, p);
	te = -te / (te - 1.1);
	te = lerp(te, normalize(te) / 0.577, DIRECT_BIAS);
	return saturate(float4(te, 1.0));
}

//Saves DepthBuffer and LODS
float LinearBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float f = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
	float n = NEAR_PLANE;
	float depth = ReShade::GetLinearizedDepth(texcoord);
	depth = lerp(n, f, depth);
	return pow(depth / (f - n), 1.0 / BUFFER_SCALE);
}



//Generates Normal Buffer from depth, as described here: https://atyuwen.github.io/posts/normal-reconstruction/
float4 NormalBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float FarPlane = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
	float2 aspectPos= float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float2 PW = 2.0 * tan(FOV * 0.00875) * (FarPlane - 1); //Dimensions of FarPlane
	PW.y *= aspectPos.x / aspectPos.y;
	
	float2 uvd = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float vc =  eyeDis(texcoord, PW);
	
	 
	float vx;
	float vxl = vc - eyeDis(texcoord + float2(-1, 0) / uvd, PW);	
	float vxl2 = vc - eyeDis(texcoord + float2(-2, 0) / uvd, PW);
	float exlC = lerp(vxl2, vxl, 2.0);
	
	float vxr = vc - eyeDis(texcoord + float2(1, 0) / uvd, PW);
	float vxr2 = vc - eyeDis(texcoord + float2(2, 0) / uvd, PW);
	float exrC = lerp(vxr2, vxr, 2.0);
	
	if(abs(exlC - vc) > abs(exrC - vc)) {vx = -vxl;}
	else {vx = vxr;}
	
	float vy;
	float vyl = vc - eyeDis(texcoord + float2(0, -1) / uvd, PW);
	float vyl2 = vc - eyeDis(texcoord + float2(0, -2) / uvd, PW);
	float eylC = lerp(vyl2, vyl, 2.0);
	
	float vyr = vc - eyeDis(texcoord + float2(0, 1) / uvd, PW);
	float vyr2 = vc - eyeDis(texcoord + float2(0, 2) / uvd, PW);
	float eyrC = lerp(vyr2, vyr, 2.0);
	
	if(abs(eylC - vc) > abs(eyrC - vc)) {vy = -vyl;}
	else {vy = vyr;}
	
	return float4(0.5 + 0.5 * normalize(float3(vx, vy, vc / FarPlane)), 1.0);
}
//Renders GI to a texture for resolution scaling and blending
float4 RawGI(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 bxy = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float3 noise = tex2D(NoiseSam, frac(0.5 + texcoord * (bxy / (512 / (ZNRY_RENDER_SCL / 100.0))))).rgb;
	return float4(DAMPGI(texcoord, 1.0 - 2.0 * noise.xy), 1.0);
}

float4 NormalDiv(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 nor = tex2D(NorSam, texcoord).rgb;
	return float4(nor, 1.0);

}

//5x5 gaussian blur
float4 Denoise(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	if(DO_DENOISING == 0) {return tex2D(GISam, texcoord).rgba;}    
	float f = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
	float n = NEAR_PLANE;
	
	int gaussianK[25] =
	{1,4,7,4,1,
    4,16,26,16,4,
    7,26,41,26,7,
    4,16,26,16,4,
    1,4,7,4,1};
    
    float fn = f - n;
    float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float4 col;
    float3 gd;
    float gaussCount = 273;
    if(DO_DENOISING == 2) {gd = tex2D(NorSam, texcoord).rgb;}
    for(int i = 0; i < 5; i++)
    {
        for(int ii = 0; ii < 5; ii++)
        {
            int s = (i) + (ii);
            float g = float(gaussianK[s]);
            float2 c = ((texcoord * res)-3.0 + float2(i, ii)) / res;
            
            float4 sam = g * tex2D(GISam, c).rgba;
            if(DO_DENOISING == 2)
			{
				float3 n = tex2D(NorSam, c).rgb;
				float comp = max(dot(n, gd), 0.0);
				sam *= comp;
				gaussCount -= g * (1.0 - comp);
			}
  		  col += sam;      
		}
    }
    return 1.5 * col / gaussCount;
}

//Second denoising pass samples first Miplevel to increase range
float4 Denoise2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	if(DO_DENOISING == 0) {return tex2D(BlurSam1, texcoord).rgba;}    
	float f = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
	float n = NEAR_PLANE;
	
	int gaussianK[25] =
	{1,4,7,4,1,
    4,16,26,16,4,
    7,26,41,26,7,
    4,16,26,16,4,
    1,4,7,4,1};
    
    float fn = f - n;
    float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float4 col;
    float3 gd;
    float gaussCount = 273;
    if(DO_DENOISING == 2) {gd = 2.0 * tex2D(NorSam, texcoord).rgb - 1.0;}
    for(int i = 0; i < 5; i++)
    {
        for(int ii = 0; ii < 5; ii++)
        {
            int s = (i) + (ii);
            float g = float(gaussianK[s]);
            float2 c = ((texcoord * res)-5.0 + 2.0 * float2(i, ii)) / res;
            
            float4 sam = tex2Dlod(BlurSam1, float4(c, 0, 1)).rgba;
            if(DO_DENOISING == 2)
			{
				float3 n = 2.0 * tex2Dlod(NorSam, float4(c, 0, 1)).rgb - 1.0;
				float comp = max(dot(n, gd), 0.0);
				gaussCount -= g * (1.0 - comp);
				sam *= comp;
			}
  		  col += g * sam / gaussCount;      
		}
    }
    return 1.5 * col;
}

//============================================================================================
//Main
//============================================================================================



float3 DAMPRT(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;
	float3 GI = tex2Dlod(BlurSam2, float4(texcoord, 0, 1)).rgb;
	float depth = ReShade::GetLinearizedDepth(texcoord);
	
	
	input = BlendGI(input, GI, depth);
	input = tonemap(input);
	
	
	return input;
}

technique ZN_DAMPRT <
    ui_label = "DAMP RT";
    ui_tooltip ="Zentient DAMP RT - by Zenteon\n" 
				"The sucessor to SDIL, a slightly more expensive, but much stronger base";
>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = LightMap;
		RenderTarget = RYLumTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = LinearBuffer;
		RenderTarget = RYBufTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = NormalBuffer;
		RenderTarget = RYNorTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = NormalDiv;
		RenderTarget = RYNorDivTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = RawGI;
		RenderTarget = RYGITex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = Denoise;
		RenderTarget = RYBlurTex1;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = Denoise2;
		RenderTarget = RYBlurTex2;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = DAMPRT;
	}
}

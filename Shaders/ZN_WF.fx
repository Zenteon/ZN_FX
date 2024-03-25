#include "ReShade.fxh"



uniform float FRAME_BOOST <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 30.0;
	ui_label = "Sensitivity";
	ui_tooltip = "Enhances small details in the wireframe";
> = 10.0;

uniform float3 FRAME_COLOR <
	ui_label = "Wireframe Color";
	ui_type = "color";
> = float3(0.2, 1.0, 0.0);

uniform bool OVERLAY_MODE <
	ui_label = "Overlay Frame";
	ui_tooltip = "Overlays outline on top of the image";
> = 0.0;


texture WFNormalTex {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 3;};


sampler NormalSam { Texture = WFNormalTex;};


float eyeDis(float2 xy, float2 pw)
{
	return ReShade::GetLinearizedDepth(xy);//eyePos(xy, ReShade::GetLinearizedDepth(xy), pw).z;
}


float4 NormalBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float FarPlane = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
	float2 aspectPos= float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float2 PW = 2.0 * tan(70.0 * 0.00875) * (FarPlane - 1); //Dimensions of FarPlane
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

float WireFrame(float2 xy)
{
	int gaussianK[9] = {1,2,1,2,4,2,1,2,1};  
	float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT);

	float3 norA = tex2D(NormalSam, xy).xyz;
	float3 norB;
	for(int i = 0; i < 3; i++){
		for(int ii = 0; ii < 3; ii++)
		{
			float g = gaussianK[ii + (i * 3)] / 1;
			float2 p = float2(i - 1.0, ii - 1.0) / res;
			norB += g * tex2D(NormalSam, xy + p).xyz;
			
		}}
		norB /= 16.0;
	float3 diff = abs(norA - norB);
	return (diff.r + diff.g + diff.b) / 3.0;

}




float3 ZN_WF_FX(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 bxy = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;
	float bri = saturate(FRAME_BOOST * WireFrame(texcoord));
	if(OVERLAY_MODE == 1){
		input = lerp(input, bri * FRAME_COLOR, bri);
		}
	else {return bri * FRAME_COLOR;}
	
	return input;//OVERLAY_MODE;
}

technique ZN_WireFrame
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = NormalBuffer;
		RenderTarget = WFNormalTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = ZN_WF_FX;
	}
}

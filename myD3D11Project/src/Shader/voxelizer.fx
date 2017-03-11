
#define PI 3.1415926

//-----------------------
//constant buffer
//---------------------

//todo register
cbuffer cbPerFrame : register(b0)
{
	float4x4 gView;
	float4x4 gProj;
	uint gRes;
	float3 gVoxelSize;
};

cbuffer cbPerObject : register(b1)
{
	float4x4 gWorld;
};

//--------------------------
//read write 3d texture
//---------------------------
RWTexture3D<float4> gTargetUAV;

//----------------------
//shader structure
//--------------------
struct VS_IN
{
	float3 posL  : POSITION;
	float3 normL  :NORMAL;
};

struct VS_OUT
{
	float4 posW  : TEXCOORD0;
	float4 posV  : SV_POSITION;
	float3 normW  : TEXCOORD2;
};

struct PS_IN
{
	float4 pos    : SV_POSITION;
	float3 normW  : TEXCOORD2;
	float3 svoPos :SVO;
};

//--------------------------------------------------------------------------------------
// Render States.
//--------------------------------------------------------------------------------------

// RasterizerState for disabling culling.
RasterizerState RS_CullDisabled
{
	CullMode = None;
};


// BlendState for disabling blending.
BlendState NoBlending
{
	AlphaToCoverageEnable = FALSE;
	BlendEnable[0] = FALSE;
};

// DepthStencilState for disabling depth writing.
DepthStencilState DisableDepth
{
	DepthEnable = FALSE;
	DepthWriteMask = 0;
};


//-----------------------------
//VERTEX SHADER
//-----------------------------
VS_OUT VS(VS_IN vin)
{
	VS_OUT vout;

	vout.posW=mul(float4(vin.posL,1.0f),gWorld);
	vout.posV=mul(vout.posW,gView);

	vout.normW=mul(float4(vin.normL,1.0f),gWorld).xyz;

	return vout;
}

//-----------------------------
//GEOMETRY SHADER
//-----------------------------
[maxvertexcount(3)]
void GS(triangle VS_OUT gin[3],inout TriangleStream<PS_IN> triStream)
{
	float3 facenormal=abs(normalize(cross(gin[1].posW.xyz-gin[0].posW.xyz,gin[2].posW.xyz-gin[0].posW.xyz)));
	float axis=max(facenormal.x,max(facenormal.y,facenormal.z));

	float3 VoxelSceneCenterPos=float3(0,0,0);
	float3 offset=mul((float3)VoxelSceneCenterPos, 1.0f / gVoxelSize);

	for( uint i = 0; i < 3; i++)
	{
		PS_IN output;
		// The position is in World space, transform to voxel space:
		output.pos = float4(gin[i].posW.xyz - offset , 1);

		// Projection matrix is unnecessary, just a swizzle is enough:
		if (axis == facenormal.x)
		{
			output.pos.xyz = output.pos.zyx;
		}
		else if (axis == facenormal.y)
		{
			output.pos.xyz = output.pos.xzy;
		}
		
		output.pos.xyz /= (float)gRes;

		uint x=output.pos.x*(gRes-1)+gRes/2;
		uint y=output.pos.y*(gRes-1)+gRes/2;
		uint z=output.pos.z*(gRes-1)+gRes/2;
		if (axis == facenormal.x)
		{
			output.svoPos=uint3(z,y,x);
		}
		else if (axis == facenormal.y)
		{
			output.svoPos=uint3(x,z,y);
		}
		else output.svoPos=uint3(x,y,z);

		//pos for rasterization
		output.pos.zw = 1;

		output.normW = gin[i].normW;

		triStream.Append(output);
	}
	triStream.RestartStrip();
}

//----------------------------
//PIXEL SHADER
//-------------------------
float4 PS(PS_IN pin) : SV_Target
{
	// Store voxels which are inside voxel-space boundary.
	if (all(pin.svoPos>= 0) && all(pin.svoPos < gRes)) 
	{
		// Transform normal data from -1~1 to 0~1 .
		float3 normal = (pin.normW + 1.f)*0.5f;	

		gTargetUAV[pin.svoPos] = float4(normal, 1.0f);

		//to make it easier to check the result.
		return float4(normal,0.0);
	}
	else return float4(0,0,0, 0);
}

technique11 VoxelizerTech
{
	pass VoxelizerPass
	{
		SetVertexShader(CompileShader(vs_5_0, VS()));
		SetGeometryShader(CompileShader(gs_5_0, GS()));
		SetPixelShader(CompileShader(ps_5_0, PS()));
		SetDepthStencilState(DisableDepth, 0);
		SetBlendState(NoBlending, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetRasterizerState(RS_CullDisabled);
	}
}
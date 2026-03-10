#define ROOT_SIG "CBV(b0), \
                  RootConstants(b1, num32bitconstants=3), \
                  SRV(t7), \
                  SRV(t0), \
                  SRV(t1), \
                  SRV(t2), \
                  SRV(t3), \
                  SRV(t4), \
                  SRV(t5), \
                  SRV(t6)"

#include "CommonStructs.h"

struct PushConstants
{
    uint ClustersStart;
    uint NumClusters;
    uint NumInstances;
};

struct VertexOutput
{
    /// Shader view position
    float4 svPosition : SV_POSITION;
    float3 worldPosition : POSITION0;
    float3 color : COLOR0;
    /// Vertex UV
    float2 uv : TEXCOORD0;
};

struct Cluster
{
	float3       Center;
	float        Radius;
	float        Error;

	uint32_t     VertexStart;
	uint32_t     VertexCount;
	uint32_t     TriangleStart;
	uint32_t     TriangleCount;

	uint32_t     GroupIndex;
	int32_t      RefinedGroup;
	uint32_t     Padding;
};

ConstantBuffer<Scene>          sceneBuffer : register(b0);
ConstantBuffer<PushConstants>   pushConstants : register(b1);
StructuredBuffer<Object>        objectBuffer : register(t7);

StructuredBuffer<float3>        vertices : register(t0);
StructuredBuffer<float3>        normals : register(t1);
StructuredBuffer<float3>        tangents : register(t2);
StructuredBuffer<float2>        uvs : register(t3);

StructuredBuffer<Cluster>       meshlets : register(t4);
StructuredBuffer<uint>          meshletVertexIndices : register(t5);
StructuredBuffer<uint>          meshletTriangleIndices : register(t6);

float DistToPlane(float3 planeNormal, float3 planePoint, float3 p)
{
    return dot(normalize(planeNormal), p - planePoint);
}

bool IsMeshletVisible(Cluster c, float4x4 world)
{
    float3 worldCenter = mul(world, float4(c.Center, 1)).xyz;

    bool isInFrustum = true;
    for (int i = 0; i < 6; ++i)
    {
        float d;
        if (sceneBuffer.useOldPlanes != 0)
            d = DistToPlane(sceneBuffer.oldPlanes[i].normal, sceneBuffer.oldPlanes[i].position, worldCenter);
        else
            d = DistToPlane(sceneBuffer.planes[i].normal, sceneBuffer.planes[i].position, worldCenter);

        if (d < -c.Radius)
        {
            isInFrustum = false;
            break;
        }
    }

    return isInFrustum;
}

struct Payload
{
    uint InstanceIndices[32];
    uint MeshletIndices[32];
};

groupshared Payload s_Payload;

[RootSignature(ROOT_SIG)]
[NumThreads(32, 1, 1)]
void mainAS(
    uint gtid : SV_GroupThreadID,
    uint dtid : SV_DispatchThreadID,
    uint gid  : SV_GroupID)
{
    uint instanceIndex = dtid / pushConstants.NumClusters;
    uint meshletIndex  = dtid % pushConstants.NumClusters;
    meshletIndex += pushConstants.ClustersStart;
    bool visibility = false;
    if (meshletIndex < pushConstants.NumClusters + pushConstants.ClustersStart && instanceIndex < pushConstants.NumInstances)
    {
        float4x4 world = objectBuffer[instanceIndex].transform;
        Cluster c = meshlets[meshletIndex];
        visibility = IsMeshletVisible(c, world);
    }
    // https://github.com/microsoft/directxshadercompiler/wiki/wave-intrinsics
    if (visibility)
    {
        uint exportIndex = WavePrefixCountBits(visibility);
        s_Payload.InstanceIndices[exportIndex] = instanceIndex;
        s_Payload.MeshletIndices[exportIndex] = meshletIndex;
    }

    uint visibilityCount = WaveActiveCountBits(visibility);


    DispatchMesh(visibilityCount, 1, 1, s_Payload);
}

// uint3 GetIndices(uint triangleInd)
// {
//     uint3 tri;
//     tri.x = meshletTriangleIndices[triangleInd] & 0xFF;
//     tri.y = (meshletTriangleIndices[triangleInd] >> 8) & 0xFF;
//     tri.z = (meshletTriangleIndices[triangleInd] >> 16) & 0xFF;
//     return tri;
// }

// https://www.shadertoy.com/view/XlGcRh
uint fmix(uint h)
{
    h ^= h >> 16;
    h *= 0x85ebca6bu;
    h ^= h >> 13;
    h *= 0xc2b2ae35u;
    h ^= h >> 16;
    return h;
}

float3 HashColor(uint id)
{
    uint hash = fmix(id);
    return float3((hash & 0xFF) / 255.0, ((hash >> 8) & 0xFF) / 255.0, ((hash >> 16) & 0xFF) / 255.0);
}

static const uint DEBUG_BOUND_VERT_COUNT = 6;
static const uint DEBUG_BOUND_TRI_COUNT = 8;

static const float3 kDebugBoundVerts[6] =
{
    float3(0.0,  1.0,  0.0),
    float3(1.0,  0.0,  0.0),
    float3(0.0,  0.0,  1.0),
    float3(-1.0,  0.0,  0.0),
    float3(0.0,  0.0, -1.0),
    float3(0.0, -1.0,  0.0)
};

static const uint3 kDebugBoundTris[8] =
{
    uint3(0, 1, 2),
    uint3(0, 2, 3),
    uint3(0, 3, 4),
    uint3(0, 4, 1),

    uint3(5, 2, 1),
    uint3(5, 3, 2),
    uint3(5, 4, 3),
    uint3(5, 1, 4)
};

[NumThreads(128, 1, 1)]
[outputtopology("triangle")]
void mainMS(
    uint3 gtid : SV_GroupThreadID,
    uint gid  : SV_GroupID,
    in  payload  Payload payload,
    out indices  uint3 tris[128],
    out vertices VertexOutput verts[128]
)
{
    uint instanceIndex = payload.InstanceIndices[gid];
    uint meshletIndex = payload.MeshletIndices[gid];

    Cluster c = meshlets[meshletIndex];
    float4x4 world = objectBuffer[instanceIndex].transform;

#if DEBUG_CLUSTER_BOUNDS

    SetMeshOutputCounts(DEBUG_BOUND_VERT_COUNT, DEBUG_BOUND_TRI_COUNT);

    if (gtid.x < DEBUG_BOUND_TRI_COUNT)
    {
        tris[gtid.x] = kDebugBoundTris[gtid.x];
    }

    if (gtid.x < DEBUG_BOUND_VERT_COUNT)
    {
        float3 localPos = c.Center + kDebugBoundVerts[gtid.x] * c.Radius;
        float4 worldPos = mul(world, float4(localPos, 1.0));

        verts[gtid.x].svPosition = mul(sceneBuffer.invViewProj, worldPos);
        verts[gtid.x].worldPosition = worldPos.xyz;
        verts[gtid.x].color = HashColor(meshletIndex);
        verts[gtid.x].uv = float2(0.0, 0.0);
    }

#else

    SetMeshOutputCounts(c.VertexCount, c.TriangleCount);

    if (gtid.x < c.TriangleCount)
    {
        uint triangleInd = c.TriangleStart + (gtid.x * 3);
        uint3 tri;
        tri.x = meshletTriangleIndices[triangleInd + 0];
        tri.y = meshletTriangleIndices[triangleInd + 1];
        tri.z = meshletTriangleIndices[triangleInd + 2];
        tris[gtid.x] = tri;
    }

    if (gtid.x < c.VertexCount)
    {
        uint vertexIndex = meshletVertexIndices[c.VertexStart + gtid.x];
        float4 worldPosition = mul(world, float4(vertices[vertexIndex], 1.0));

        verts[gtid.x].svPosition = mul(sceneBuffer.invViewProj, worldPosition);
        verts[gtid.x].worldPosition = worldPosition.xyz;
        uint colorId = sceneBuffer.debugGroups ? c.GroupIndex : meshletIndex;
        verts[gtid.x].color = HashColor(colorId);
        verts[gtid.x].uv = float2(0.0, 0.0);
    }

#endif
}

struct VertexInput : VertexOutput {};

struct PixelOutput
{
    float4 color  : SV_TARGET;
};

PixelOutput mainPS(VertexInput input)
{
    PixelOutput output;

#if DEBUG_CLUSTER_BOUNDS
    output.color = float4(input.color, .3);
#else
    output.color = float4(input.color, 1.0);
#endif
    return output;
}


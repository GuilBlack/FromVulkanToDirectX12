#define ROOT_SIG "CBV(b0), \
                  SRV(t0), \
                  SRV(t1), \
                  SRV(t2), \
                  SRV(t3), \
                  SRV(t4), \
                  SRV(t5), \
                  UAV(u0)"

#include "CommonStructs.h"
#include "CommonCluster.h"

struct VertexOutput
{
    /// Shader view position
    float4 svPosition : SV_POSITION;
    float3 worldPosition : POSITION0;
    float3 color : COLOR0;
    /// Vertex UV
    float2 uv : TEXCOORD0;
};

ConstantBuffer<Scene>           sceneBuffer : register(b0);
StructuredBuffer<Object>        objectBuffer : register(t0);

StructuredBuffer<float3>        vertices : register(t1);

StructuredBuffer<uint>          clusterVertexIndices : register(t2);
StructuredBuffer<uint>          clusterTriangleIndices : register(t3);

StructuredBuffer<Cluster>       clusters : register(t4);
StructuredBuffer<ClusterGroup>  clusterGroups : register(t5);

RWStructuredBuffer<TraversalInfo> selectedClusters : register(u0);

[RootSignature(ROOT_SIG)]
[NumThreads(128, 1, 1)]
[outputtopology("triangle")]
void mainMS(
    uint3 gtid : SV_GroupThreadID,
    uint gid  : SV_GroupID,
    out indices  uint3 tris[128],
    out vertices VertexOutput verts[128]
)
{
    uint instanceIndex = selectedClusters[gid].objectIdx;
    uint clusterIdx = selectedClusters[gid].nodeIdx;

    Cluster c = clusters[clusterIdx];
    float4x4 world = objectBuffer[instanceIndex].transform;

    SetMeshOutputCounts(c.VertexCount, c.TriangleCount);

    if (gtid.x < c.TriangleCount)
    {
        uint triangleInd = c.TriangleStart + (gtid.x * 3);
        uint3 tri;
        tri.x = clusterTriangleIndices[triangleInd + 0];
        tri.y = clusterTriangleIndices[triangleInd + 1];
        tri.z = clusterTriangleIndices[triangleInd + 2];
        tris[gtid.x] = tri;
    }

    if (gtid.x < c.VertexCount)
    {
        uint vertexIndex = clusterVertexIndices[c.VertexStart + gtid.x];
        float4 worldPosition = mul(world, float4(vertices[vertexIndex], 1.0));
        // float4x4 worldToNdc = mul(sceneBuffer.invViewProj, world);
        verts[gtid.x].svPosition = mul(sceneBuffer.invViewProj, worldPosition);
        verts[gtid.x].worldPosition = worldPosition.xyz;
        
        // debug error instead of color
        ClusterGroup group = clusterGroups[c.GroupIndex];
        uint colorId = sceneBuffer.debugGroups ? c.GroupIndex : clusterIdx;
        
        verts[gtid.x].color = HashColor(colorId);
        verts[gtid.x].uv = float2(0.0, 0.0);
    }
}

struct VertexInput : VertexOutput {};

struct PixelOutput
{
    float4 color  : SV_TARGET;
};

PixelOutput mainPS(VertexInput input)
{
    PixelOutput output;
    output.color = float4(input.color, 1.0);
    return output;
}

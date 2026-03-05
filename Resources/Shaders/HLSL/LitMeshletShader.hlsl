#define ROOT_SIG "CBV(b0), \
                  RootConstants(b1, num32bitconstants=2), \
                  SRV(t7), \
                  SRV(t0), \
                  SRV(t1), \
                  SRV(t2), \
                  SRV(t3), \
                  SRV(t4), \
                  SRV(t5), \
                  SRV(t6)"

struct PushConstants
{
    uint NumMeshlets;
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

struct Camera
{
    /// Camera transformation matrix.
    float4x4 view;

    /**
    *	Camera inverse view projection matrix.
    *	projection * inverseView.
    */
    float4x4 invViewProj;
    float3 position;
};

struct Object
{
    /// Object transformation matrix.
    float4x4 transform;
};

struct MeshletData
{
    uint            VertexOffset;
    uint            TriangleOffset;
    uint            VertexCount;
    uint            TriangleCount;

    float3          BoundsCenter;
    float           BoundsRadius;

    //uint            ConeInfo; // ConeAxis[3], ConeCutoff as int8_t
    float3          ConeAxis;
    float           ConeCutoff;
};

ConstantBuffer<Camera>          cameraBuffer : register(b0);
ConstantBuffer<PushConstants>   pushConstants : register(b1);
StructuredBuffer<Object>        objectBuffer : register(t7);

StructuredBuffer<float3>        vertices : register(t0);
StructuredBuffer<float3>        normals : register(t1);
StructuredBuffer<float3>        tangents : register(t2);
StructuredBuffer<float2>        uvs : register(t3);

StructuredBuffer<MeshletData>   meshlets : register(t4);
StructuredBuffer<uint>          meshletVertexIndices : register(t5);
StructuredBuffer<uint>          meshletTriangleIndices : register(t6);

// void GetConeData(MeshletData m, out float3 coneAxis, out float coneCutoff)
// {
//     uint coneInfo = m.ConeInfo;
//     coneAxis = float3(
//         int((coneInfo >> 0) & 0xFF) / 127.0,
//         int((coneInfo >> 8) & 0xFF) / 127.0,
//         int((coneInfo >> 16) & 0xFF) / 127.0);
//     coneCutoff = int((coneInfo >> 24) & 0xFF) / 127.0;
// }

bool IsMeshletVisible(MeshletData m, float4x4 world)
{
    float3 coneAxis = m.ConeAxis;
    float coneCutoff = m.ConeCutoff;
    // GetConeData(m, coneAxis, coneCutoff);
    float3 worldCenter = mul(world, float4(m.BoundsCenter, 1)).xyz;
    float3 worldConeAxis = normalize(mul(world, float4(coneAxis, 0))).xyz;

    bool shouldCull = dot(worldCenter - cameraBuffer.position, worldConeAxis) >= coneCutoff * length(worldCenter - cameraBuffer.position) + m.BoundsRadius;
    return !shouldCull;
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
    uint instanceIndex = dtid / pushConstants.NumMeshlets;
    uint meshletIndex  = dtid % pushConstants.NumMeshlets;
    bool visibility = false;
    if (meshletIndex < pushConstants.NumMeshlets && instanceIndex < pushConstants.NumInstances)
    {
        float4x4 world = objectBuffer[instanceIndex].transform;
        MeshletData m = meshlets[meshletIndex];
        visibility = IsMeshletVisible(m, world);
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

uint3 GetIndices(uint triangleInd)
{
    uint3 tri;
    tri.x = meshletTriangleIndices[triangleInd] & 0xFF;
    tri.y = (meshletTriangleIndices[triangleInd] >> 8) & 0xFF;
    tri.z = (meshletTriangleIndices[triangleInd] >> 16) & 0xFF;
    return tri;
}

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

[NumThreads(128, 1, 1)]
[outputtopology("triangle")]
void mainMS(
    uint3 gtid : SV_GroupThreadID,
    uint gid  : SV_GroupID,
    in  payload  Payload payload,
    out indices  uint3 tris[126],
    out vertices VertexOutput verts[64]
)
{
    uint instanceIndex = payload.InstanceIndices[gid];
    uint meshletIndex = payload.MeshletIndices[gid];

    MeshletData m = meshlets[meshletIndex];
    SetMeshOutputCounts(m.VertexCount, m.TriangleCount);

    if (gtid.x < m.TriangleCount)
        tris[gtid.x] = GetIndices(m.TriangleOffset + gtid.x);

    if (gtid.x < m.VertexCount)
    {
        uint vertexIndex = meshletVertexIndices[m.VertexOffset + gtid.x];
        float4 worldPosition = mul(objectBuffer[instanceIndex].transform, float4(vertices[vertexIndex], 1.0));
        verts[gtid.x].svPosition = mul(cameraBuffer.invViewProj, float4(worldPosition));
        verts[gtid.x].color = HashColor(meshletIndex);
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

#define ROOT_SIG "CBV(b0), \
                  SRV(t7), \
                  SRV(t0), \
                  SRV(t1), \
                  SRV(t2), \
                  SRV(t3), \
                  SRV(t4), \
                  SRV(t5), \
                  SRV(t6)"

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

    uint            ConeInfo; // ConeAxis[3], ConeCutoff in int8_t
};

ConstantBuffer<Camera>          cameraBuffer : register(b0);
StructuredBuffer<Object>        objectBuffer : register(t7);

StructuredBuffer<float3>        vertices : register(t0);
StructuredBuffer<float3>        normals : register(t1);
StructuredBuffer<float3>        tangents : register(t2);
StructuredBuffer<float2>        uvs : register(t3);

StructuredBuffer<MeshletData>   meshlets : register(t4);
StructuredBuffer<uint>          meshletVertexIndices : register(t5);
StructuredBuffer<uint>          meshletTriangleIndices : register(t6);

uint3 GetIndices(uint triangleInd)
{
    uint3 tri;
    tri.x = meshletTriangleIndices[triangleInd] & 0xFF;
    tri.y = (meshletTriangleIndices[triangleInd] >> 8) & 0xFF;
    tri.z = (meshletTriangleIndices[triangleInd] >> 16) & 0xFF;
    return tri;
}

[RootSignature(ROOT_SIG)]
[NumThreads(128, 1, 1)]
[outputtopology("triangle")]
void mainMS(
    uint3 gtid : SV_GroupThreadID,
    uint3 gid : SV_GroupID,
    out indices uint3 tris[126],
    out vertices VertexOutput verts[64]
)
{
    MeshletData m = meshlets[gid.x];
    SetMeshOutputCounts(m.VertexCount, m.TriangleCount);

    if (gtid.x < m.TriangleCount)
    {
        tris[gtid.x] = GetIndices(m.TriangleOffset + gtid.x);
    }

    if (gtid.x < m.VertexCount)
    {
        uint vertexIndex = meshletVertexIndices[m.VertexOffset + gtid.x];
        // verts[gtid.x].worldPosition = mul(world, float4(vertices[vertexIndex], 1.0));
        float4 worldPosition = mul(objectBuffer[gid.y].transform, float4(vertices[vertexIndex], 1.0));
        //verts[gtid.x].viewPosition = float3(cameraBuffer.view._14, cameraBuffer.view._24, cameraBuffer.view._34);
        verts[gtid.x].svPosition = mul(cameraBuffer.invViewProj, float4(/*verts[gtid.x].*/worldPosition));
        //verts[gtid.x].uv = uvs[vertexIndex];
        verts[gtid.x].color = float3(float(gid.x & 1), float(gid.x & 3) / 4.0, float(gid.x & 7) / 8.0);
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

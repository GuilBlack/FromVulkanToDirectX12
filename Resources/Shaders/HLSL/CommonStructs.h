struct FrustumPlane
{
    float3 normal;
    float __pad0;
    float3 position;
    float __pad1;
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
    FrustumPlane planes[6];
    FrustumPlane oldPlanes[6];
    float3 position;
    uint useOldPlanes;
};

struct Object
{
    /// Object transformation matrix.
    float4x4 transform;
};

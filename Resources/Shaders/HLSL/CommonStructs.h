struct FrustumPlane
{
    float3 normal;
    float __pad0;
    float3 position;
    float __pad1;
};

struct Scene
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
    float3 camPosition;
    uint useOldPlanes;
    uint debugGroups;
};

struct Object
{
    /// Object transformation matrix.
    float4x4 transform;
};

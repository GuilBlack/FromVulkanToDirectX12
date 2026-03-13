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

    uint maxTraversalInfo;
    uint maxRenderClusters;
    float nearPlane;
    float farPlane;

    float errorOverDistance;
    uint  debugLodError;
    uint  totalNodes;
};

struct Object
{
    /// Object transformation matrix.
    float4x4 transform;
};

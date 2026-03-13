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

#define invalidRefinedGroup 0xFFFFFFFF

struct ClusterGroup
{
    float3      center;
    float       radius;
    float       error;

    uint32_t    clusterStart;
    uint32_t    clusterCount;

    int32_t     depth;
    uint32_t    levelIndex;
    float       padding[3];
};

struct ClusterNode
{
    float3      center;
    float       radius;
    float       error;

    uint32_t    firstChildOrGroup; // child node offset or grp idx depending on if it's a leaf or not.
    uint32_t    childCount;
    uint32_t    isLeaf; // 1 = leaf, 0 = internal
};

struct TraversalInfo
{
    uint objectIdx;
    uint nodeIdx;
};

#define invalidTraversalInfo (~0)
#define traversalInfoReadCounter 0 // read task pointer
#define traversalTaskCounter 1 // tasks in flight counter
#define traversalInfoWriteCounter 2 // write task pointer
#define renderClusterCounter 3

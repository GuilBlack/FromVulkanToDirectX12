#define ROOT_SIG "RootConstants(b0, num32bitconstants=1), \
                  CBV(b1), \
                  SRV(t0), \
                  SRV(t1), \
                  UAV(u0), \
                  UAV(u1)"

#include "CommonStructs.h"
#include "CommonCluster.h"

struct PushConstants
{
    uint NumInstances;
};

ConstantBuffer<PushConstants>   pushConstants : register(b0);
ConstantBuffer<Scene>           sceneBuffer : register(b1);

StructuredBuffer<Object>        objectBuffer : register(t0);
StructuredBuffer<ClusterNode>   meshletNodes : register(t1);

RWStructuredBuffer<uint>            counters : register(u0);
RWStructuredBuffer<TraversalInfo>   traversalInfos : register(u1);

[RootSignature(ROOT_SIG)]
[numthreads(1, 1, 1)]
void main()
{
    counters[traversalInfoReadCounter] = 0;
    counters[traversalTaskCounter] = 0;
    counters[traversalInfoWriteCounter] = 0;
    counters[renderClusterCounter] = 0;
    DeviceMemoryBarrier();
    for (uint i = 0; i < pushConstants.NumInstances; ++i)
    {
        uint traversalInfoOffset;
        InterlockedAdd(counters[traversalTaskCounter], 1, traversalInfoOffset);
        uint dummy;
        InterlockedAdd(counters[traversalInfoWriteCounter], 1, dummy);

        TraversalInfo info;
        info.objectIdx = i;
        info.nodeIdx = 0;
        traversalInfos[traversalInfoOffset] = info;
    }
}

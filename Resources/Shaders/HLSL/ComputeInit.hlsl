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

RWStructuredBuffer<uint>                            counters : register(u0);
RWStructuredBuffer<TraversalInfo>  traversalInfos : register(u1);

[RootSignature(ROOT_SIG)]
[WaveSize(32)]
[numthreads(32, 1, 1)]
void main(
    uint id : SV_DispatchThreadID,
    uint groupId : SV_GroupID
)
{
    if (id == 0)
    {
        counters[traversalTaskCounter] = pushConstants.NumInstances;
        counters[traversalInfoWriteCounter] = pushConstants.NumInstances;
    }
    if (id >= pushConstants.NumInstances)
        return;

    TraversalInfo info;
    info.objectIdx = id;
    info.nodeIdx = 0;
    traversalInfos[id] = info;
}

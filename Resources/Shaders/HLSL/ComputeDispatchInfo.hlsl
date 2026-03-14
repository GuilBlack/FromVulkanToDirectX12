#define ROOT_SIG "CBV(b0), \
                  UAV(u0), \
                  UAV(u1)"

#include "CommonStructs.h"
#include "CommonCluster.h"

ConstantBuffer<Scene>   sceneBuffer : register(b0);

RWStructuredBuffer<uint>                        counters : register(u0);
RWStructuredBuffer<DispatchMeshIndirectCommand> dispatchCommands : register(u1);

[RootSignature(ROOT_SIG)]
[numthreads(1, 1, 1)]
void main()
{
    uint numClusters = counters[renderClusterCounter];
    numClusters = max(numClusters, sceneBuffer.maxRenderClusters);

    dispatchCommands[0].threadGroupCountX = counters[renderClusterCounter];
    dispatchCommands[0].threadGroupCountY = 1;
    dispatchCommands[0].threadGroupCountZ = 1;
}

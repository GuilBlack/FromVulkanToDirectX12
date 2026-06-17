// Copyright 2026 Guillaume BLACKBURN
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the “Software”), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
// OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

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

// TODO: optimize this xD
[RootSignature(ROOT_SIG)]
[numthreads(1, 1, 1)]
void main()
{
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

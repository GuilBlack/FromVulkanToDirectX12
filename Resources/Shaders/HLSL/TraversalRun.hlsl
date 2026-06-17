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

#define ROOT_SIG "CBV(b0), \
                  SRV(t0), \
                  SRV(t1), \
                  SRV(t2), \
                  SRV(t3), \
                  UAV(u0), \
                  UAV(u1), \
                  UAV(u2), \
                  UAV(u3)"

// this shader is HEAVILY based on the one in nvidia's vk_lod_cluster
// check it out for a more complete implementation that handles a lot more
// things :thumbsup:

#include "CommonStructs.h"
#include "CommonCluster.h"

#define invalidLane (~0)

#define NUM_THREADS 32

ConstantBuffer<Scene>               sceneBuffer : register(b0);
StructuredBuffer<Object>            objectBuffer : register(t0);

StructuredBuffer<Cluster>           meshlets : register(t1);
StructuredBuffer<ClusterGroup>      meshletGroups : register(t2);
StructuredBuffer<ClusterNode>       meshletNodes : register(t3);

globallycoherent RWStructuredBuffer<uint>            counters : register(u0);
globallycoherent RWStructuredBuffer<TraversalInfo>   traversalInfos : register(u1);
globallycoherent RWStructuredBuffer<TraversalInfo>   renderClusters : register(u2);
globallycoherent RWStructuredBuffer<uint>            dump : register(u3);

groupshared uint s_taskIDs[NUM_THREADS];

uint setupTask(inout TraversalInfo traversalInfo, uint laneReadIndex, uint currentPass)
{
    ClusterNode node = meshletNodes[traversalInfo.nodeIdx];

    uint subCount = 0;
    subCount = node.isLeaf ? meshletGroups[node.firstChildOrGroup].clusterCount : node.childCount;
    return subCount;
}

bool testForTraversal(float4x4 instanceToEye, float3 center, float uniformScale, float radius, float error)
{
    float sphereDistance    = length(mul(instanceToEye, float4(center, 1.0)).xyz);
    float errorDistance     = max(sceneBuffer.nearPlane, sphereDistance - radius * uniformScale);
    float errorOverDistance = error * uniformScale / errorDistance;

    return errorOverDistance >= sceneBuffer.errorOverDistance;
}

float DistToPlane(float3 planeNormal, float3 planePoint, float3 p)
{
    return dot(normalize(planeNormal), p - planePoint);
}

bool isMeshletVisible(float3 center, float radius, float4x4 world)
{
    float3 worldCenter = mul(world, float4(center, 1)).xyz;

    bool isInFrustum = true;
    for (int i = 0; i < 6; ++i)
    {
        float d = sceneBuffer.useOldPlanes != 0 ?
                DistToPlane(sceneBuffer.oldPlanes[i].normal, sceneBuffer.oldPlanes[i].position, worldCenter) :
                DistToPlane(sceneBuffer.planes[i].normal, sceneBuffer.planes[i].position, worldCenter);

        if (d < -radius)
        {
            isInFrustum = false;
            break;
        }
    }

    return isInFrustum;
}

groupshared uint s_nodesOffsets[NUM_THREADS];
groupshared uint s_temp[NUM_THREADS];

void processSubtask(const TraversalInfo traversalInfo, uint taskID, uint taskSubID, bool taskValid, uint currentPass, uint currentRun)
{
    TraversalInfo subTraversalInfo;
    subTraversalInfo.objectIdx = WaveReadLaneAt(traversalInfo.objectIdx, taskID);
    subTraversalInfo.nodeIdx   = WaveReadLaneAt(traversalInfo.nodeIdx, taskID);

//     dump[(32 * currentRun + WaveGetLaneIndex()) * 21 + 18] = subTraversalInfo.objectIdx;
//     dump[(32 * currentRun + WaveGetLaneIndex()) * 21 + 19] = subTraversalInfo.nodeIdx;
    DeviceMemoryBarrier();

//     if (currentPass >= 1)
//         return;

    ClusterNode node    = meshletNodes[subTraversalInfo.nodeIdx];
    uint objIdx         = subTraversalInfo.objectIdx;
    bool forceCluster   = false;

    float3 center;
    float radius;
    float error;
    if (node.isLeaf == false)
    {
        uint childIdx           = node.firstChildOrGroup + taskSubID;
        ClusterNode childNode   = meshletNodes[childIdx];
        center                  = childNode.center;
        radius                  = childNode.radius;
        error                   = childNode.error;
        subTraversalInfo.nodeIdx   = childIdx;
    }
    else
    {
        ClusterGroup group  = meshletGroups[node.firstChildOrGroup];
        uint clusterIdx     = group.clusterStart + taskSubID;
        Cluster cluster     = meshlets[clusterIdx];
        if (cluster.RefinedGroup != invalidRefinedGroup)
        {
            ClusterGroup refinedGroup = meshletGroups[cluster.RefinedGroup];

            center = refinedGroup.center;
            radius = refinedGroup.radius;
            error  = refinedGroup.error;
        }
        else
        {
            center = group.center;
            radius = group.radius;
            error  = group.error;

            forceCluster = true;
        }
        subTraversalInfo.nodeIdx = clusterIdx; // prepared for render
    }

    float4x4 world      = objectBuffer[objIdx].transform;
    float uniformScale  = max(max(length(world[0].xyz), length(world[1].xyz)), length(world[2].xyz));
    float errorScale    = 1.0;

    // TODO: replace the 1.0 by the uniform scale later on.
    bool traverse      = testForTraversal(mul(sceneBuffer.view, world), center, uniformScale, radius, error);
    bool visible       = isMeshletVisible(center, radius * uniformScale, world);
    bool traverseNode  = taskValid && visible && node.isLeaf == false && traverse;
    bool renderCluster = taskValid && visible && node.isLeaf && (!traverse || forceCluster);

    uint4 voteNodes = WaveActiveBallot(traverseNode);
    uint nodesCount = WaveActiveCountBits(traverseNode);

    uint4 voteClusters = WaveActiveBallot(renderCluster);
    uint clustersCount = WaveActiveCountBits(renderCluster);

    uint offsetNodes    = 0;
    uint offsetClusters = 0;

    if (WaveIsFirstLane())
    {
        uint oldNodesCount;
         InterlockedAdd(counters[traversalTaskCounter], nodesCount, oldNodesCount);
         InterlockedAdd(counters[traversalInfoWriteCounter], nodesCount, offsetNodes);
         InterlockedAdd(counters[renderClusterCounter], clustersCount, offsetClusters);
    }
    DeviceMemoryBarrier();

    offsetNodes = WaveReadLaneFirst(offsetNodes);
    offsetNodes += WavePrefixCountBits(traverseNode);

    offsetClusters = WaveReadLaneFirst(offsetClusters);
    offsetClusters += WavePrefixCountBits(renderCluster);

    traverseNode = traverseNode && offsetNodes < sceneBuffer.maxTraversalInfo;
    renderCluster = renderCluster && offsetClusters < sceneBuffer.maxRenderClusters;

    bool doStore = traverseNode || renderCluster;

     if (traverseNode && subTraversalInfo.nodeIdx < sceneBuffer.totalNodes)
     {
         DeviceMemoryBarrier();
         traversalInfos[offsetNodes] = subTraversalInfo;
     }

     if (renderCluster)
         renderClusters[offsetClusters] = subTraversalInfo;
    DeviceMemoryBarrier();
}

// an in depth example of how this loop works is in the comments at the end of this file
void processSubtasks(inout TraversalInfo traversalInfo, int threadSubcount, bool runnable, uint laneReadIndex, uint currentPass)
{
    int waveLaneCount   = int(WaveGetLaneCount());
    uint laneIdx        = WaveGetLaneIndex();
    int endOffset       = WavePrefixSum(threadSubcount) + threadSubcount;
    int startOffset     = endOffset - threadSubcount;

    int totalLanes   = WaveActiveSum(threadSubcount);
    int totalRuns    = (totalLanes + waveLaneCount - 1) / waveLaneCount;

    // this is kind of explained in the vertex loop of this:
    // https://github.com/nvpro-samples/vk_tessellated_clusters/blob/main/shaders/render_raster_clusters_batched.mesh.glsl
    bool hasTask    = threadSubcount > 0;
    uint taskOffset = WavePrefixCountBits(hasTask);
    uint taskCount  = WaveActiveCountBits(hasTask);

    // no need for the subgroup offset since I'm using
    // as many threads as lanes in a wave

    if (hasTask)
        s_taskIDs[taskOffset] = laneIdx;
    GroupMemoryBarrier();

    int taskBase = -1;
    for (int r = 0; r < totalRuns; ++r)
    {
        int firstTaskIdx = r * waveLaneCount;
        int taskIdx      = firstTaskIdx + laneIdx;
        uint maskLe      = (1u << (laneIdx + 1u)) - 1u;
        maskLe           = laneIdx == waveLaneCount - 1 ? ~0u : maskLe; // to avoid overflow when shifting

        int relativeStart = startOffset - firstTaskIdx;

        // if not for this run, it's out of the range of this wave, so we set it to an invalid value
        uint startBits = WaveActiveBitOr(runnable && relativeStart >= 0 && relativeStart < waveLaneCount ? (1u << uint(relativeStart)) : 0);
        int task       = countbits(startBits & maskLe) + taskBase;
        uint taskID    = s_taskIDs[task];

        uint taskSubID      = taskIdx - WaveReadLaneAt(startOffset, taskID);
        uint taskSubcount   = WaveReadLaneAt(threadSubcount, taskID);
        // should be the highest task recorded this run
        taskBase            = WaveReadLaneAt(task, waveLaneCount - 1);
        bool taskValid      = taskSubID < taskSubcount;

        uint taskReadIndex  = WaveReadLaneAt(laneReadIndex, taskID);



//         dump[(32 * r + laneIdx) * 21 + 20] =  uint(runnable);
//         dump[(32 * r + laneIdx) * 21 + 0]  = uint(threadSubcount);
//         dump[(32 * r + laneIdx) * 21 + 1]  = uint(endOffset);
//         dump[(32 * r + laneIdx) * 21 + 2]  = uint(startOffset);
//         dump[(32 * r + laneIdx) * 21 + 3]  = uint(totalLanes);
//         dump[(32 * r + laneIdx) * 21 + 4]  = uint(hasTask);
//         dump[(32 * r + laneIdx) * 21 + 5]  = uint(taskOffset);
//         dump[(32 * r + laneIdx) * 21 + 6]  = uint(taskCount);
// 
//         dump[(32 * r + laneIdx) * 21 + 7]  =  uint(firstTaskIdx);
//         dump[(32 * r + laneIdx) * 21 + 8]  =  uint(taskIdx);
//         dump[(32 * r + laneIdx) * 21 + 9]  =  uint(maskLe);
//         dump[(32 * r + laneIdx) * 21 + 10] =  uint(relativeStart);
//         dump[(32 * r + laneIdx) * 21 + 11] =  uint(startBits);
//         dump[(32 * r + laneIdx) * 21 + 12] =  uint(task);
//         dump[(32 * r + laneIdx) * 21 + 13] =  uint(taskID);
//         dump[(32 * r + laneIdx) * 21 + 14] =  uint(taskSubID);
//         dump[(32 * r + laneIdx) * 21 + 15] =  uint(taskSubcount);
//         dump[(32 * r + laneIdx) * 21 + 16] =  uint(taskBase);
//         dump[(32 * r + laneIdx) * 21 + 17] =  uint(taskValid);
        
        processSubtask(traversalInfo, taskID, min(taskSubID, taskSubcount-1), taskValid, currentPass, r);
    }
}

void run(uint gtid)
{
    uint laneReadIndex = invalidLane;
    for (uint currentPass = 0; ; ++currentPass)
    {
        // meaning it's the first time in this
        if (WaveActiveAllTrue(laneReadIndex == invalidLane))
        {
            uint counter;
            if (WaveIsFirstLane())
                InterlockedAdd(counters[traversalInfoReadCounter], NUM_THREADS, counter);
            laneReadIndex = WaveReadLaneFirst(counter) + gtid;
            laneReadIndex = laneReadIndex >= sceneBuffer.maxTraversalInfo ? invalidLane : laneReadIndex;

            if (WaveActiveAllTrue(laneReadIndex == invalidLane))
                break;
        }

        bool threadRunnable = false;
        TraversalInfo traversalInfo;
        while (true)
        {
            if (laneReadIndex != invalidLane)
            {
                DeviceMemoryBarrier();

                traversalInfo  = traversalInfos[laneReadIndex];
                threadRunnable = traversalInfo.objectIdx != invalidTraversalInfo && traversalInfo.nodeIdx != invalidTraversalInfo;
            }

            if (WaveActiveAnyTrue(threadRunnable))
                break;

            // truly nothing was found
            DeviceMemoryBarrier();
            bool isEmpty = counters[traversalTaskCounter] == 0;
            if (WaveActiveAnyTrue(isEmpty))
                return;
        }

        if (WaveActiveAnyTrue(threadRunnable) == false)
            continue;

        int threadSubcount = 0;

        if (threadRunnable)
             threadSubcount = setupTask(traversalInfo, laneReadIndex, currentPass);

        processSubtasks(traversalInfo, threadSubcount, threadRunnable, laneReadIndex, currentPass);

        uint numRunnable = WaveActiveCountBits(threadRunnable);
        uint oldCount;

        if (WaveIsFirstLane())
            InterlockedAdd(counters[traversalTaskCounter], -int(numRunnable), oldCount);

        if (threadRunnable)
            laneReadIndex = invalidLane;
    }
}

[RootSignature(ROOT_SIG)]
[NumThreads(NUM_THREADS, 1, 1)]
void main(
    uint gtid : SV_GroupThreadID,
    uint dtid : SV_DispatchThreadID
)
{
        run(gtid);
}

// In depth example run for the processSubtasks loop because it was A PAIN to understand...
// T0  T1  T2  T... (till T31)
// 
// A0  B0  C0  empty
// A1      C1
// A2      C2
//         C3
// 
// threadSubcount
// T0  T1  T2
// 3   1   4
// 
// endOffsets
// T0  T1  T2 	T...
// 3   4   8 	8...
// 
// startOffsets
// T0  T1  T2 	T...
// 0   3   4 	8...
// 
// totalThreads = 8
// totalRuns    = 1 (assuming we have 32 lanes)
// 
// hasTask
// T0  T1  T2  T...
// 1 	1 	1 	0...
// 
// taskVote
// 0b...0111
// 
// taskCount = 3
// 
// taskOffset
// T0  T1  T2  T3 	T4...
// 0 	1 	2 	3   3...
// 
// s_taskIDs
// I0 	I1 	I2 	I...
// 0 	1 	2 	...(not important)
// 
// taskBase = -1
// 
// (1 iter only)
// firstTaskIdx = 0
// 
// taskIdx
// T0 	T1 	T2 	T...
// 0 	1 	2 	3...
// 
// maskLe // equivalent to gl_SubgroupLeMask
// T0 		T1 		 T2 		T...
// 0b...01 0b...011 0b...0111  0b...01111
// 
// relativeStart
// T0	T1 	T2 	T...
// 0 	3   4   8...
// 
// startBits
// T0 	T1 	 	T2 		T...
// 0b1 0b1000  0b10000 0... (not runnable)
// 
// so startBits = 0b11001
// 
// task (valid to T7 then not relevent)
// T0	T1 	T2 	T3 	T4 	T5  T6  T7  T8...
// 0 	0 	0 	1   2 	2 	2 	2 	2...
// 
// taskID
// T0	T1 	T2 	T3 	T4 	T5  T6  T7  T8...
// 0 	0 	0 	1 	2 	2 	2 	2 	2...
// 
// taskSubID
// T0	T1 	T2 	T3 	T4 	T5  T6  T7  T8...
// 0 	1 	2 	0 	0 	1 	2 	3 	4...
// 
// taskSubcount
// T0	T1 	T2 	T3 	T4 	T5  T6  T7  T8...
// 3 	3 	3 	1 	4 	4 	4 	4 	4...
// 
// taskBase = 2
// 
// taskValid
// T0  T1  T2  T3  T4  T5  T6  T7  T8...
// 1   1   1   1   1   1   1   1   0...

// so when processed in processSubtask, we will have instead of different iterations
// for each threads, we will have a homogenous subtask repartition so that they have
// the same execution path (kind of). In the end, we have these tasks processed in parallel :
// T0  T1  T2  T3  T4  T5  T6  T7  T8...
// A0  A1  A2  B0  C0  C1  C2  C3  empty/ not valid

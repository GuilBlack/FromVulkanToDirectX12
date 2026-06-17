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

struct DispatchMeshIndirectCommand
{
    uint threadGroupCountX;
    uint threadGroupCountY;
    uint threadGroupCountZ;
};

// https://www.shadertoy.com/view/XlGcRh
uint fmix(uint h)
{
    h ^= h >> 16;
    h *= 0x85ebca6bu;
    h ^= h >> 13;
    h *= 0xc2b2ae35u;
    h ^= h >> 16;
    return h;
}

float3 HashColor(uint id)
{
    uint hash = fmix(id);
    return float3((hash & 0xFF) / 255.0, ((hash >> 8) & 0xFF) / 255.0, ((hash >> 16) & 0xFF) / 255.0);
}

#define invalidTraversalInfo (~0)
#define traversalInfoReadCounter 0 // read task pointer
#define traversalTaskCounter 1 // tasks in flight counter
#define traversalInfoWriteCounter 2 // write task pointer
#define renderClusterCounter 3

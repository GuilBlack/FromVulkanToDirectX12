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
